# -*- coding: utf-8 -*-
# Tests of agg_logs.py and --loop on synthetic logs: python -m unittest tools/costs/test_agg_logs.py
import contextlib
import io
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import agg_logs  # noqa: E402
import loop  # noqa: E402


def log(d, name, cost, dur=60000, sid=None):
    j = dict(type="result", session_id=sid or name, total_cost_usd=cost, duration_ms=dur, usage={})
    (d / name).write_text(json.dumps(j) + "\n", encoding="utf-8")


def harness(d, lines):
    (d / "harness-261001.log").write_text("\n".join(lines) + "\n", encoding="utf-8")


def task(n, title, dom, *logs):
    out = ["[01/10 00:00:00] reviewer : TASK: %d — %s" % (n, title),
           "[01/10 00:00:01] coder : domains %s -> MCP none" % dom]
    out += ["[01/10 00:00:02] coder : m (new session) -> %s" % j for j in logs]
    return out


def compute(d, history=None):
    tasks = loop.read_tasks(d)
    rows, _, _ = agg_logs.calls(d)
    rejected, bugs = loop.analyse(tasks, rows, history)
    return tasks, rejected, bugs


class Loop(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.d = self.root / "logs"
        self.d.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_rejection_then_correction(self):
        harness(self.d, task(200, "[M] a", "code", "261001-000100-coder.log")
                + task(201, "[M, correction of 200] b", "code", "261001-000200-coder.log")
                + task(202, "[M] c", "ui", "261001-000300-coder.log"))
        for n in ("261001-000100-coder.log", "261001-000200-coder.log", "261001-000300-coder.log"):
            log(self.d, n, 1.0)
        t, rejected, bugs = compute(self.d)
        self.assertEqual(rejected, {200})
        self.assertEqual(bugs, {200})
        self.assertTrue(t[201]["correction"] and not t[200]["correction"])

    def test_bug_after_acceptance(self):
        harness(self.d, task(210, "[M] a", "code", "261001-000100-coder.log")
                + task(211, "[M] b", "code", "261001-000200-coder.log")
                + task(212, "[BENCH KO 210] c", "code", "261001-000300-coder.log"))
        t, rejected, bugs = compute(self.d)
        self.assertEqual(rejected, set())
        self.assertEqual(bugs, {210})

    def test_plain_fix_in_a_title_is_not_a_correction(self):
        harness(self.d, task(270, "[M] fix the camera jitter", "code") + task(271, "[M] next", "code"))
        t, rejected, bugs = compute(self.d)
        self.assertFalse(t[270]["correction"])
        self.assertEqual(bugs, set())

    def test_target_without_number_and_correction_of_correction(self):
        harness(self.d, task(220, "[M] a", "code") + task(221, "[correction] b", "code")
                + task(222, "[CORRECTION, fixes 221] c", "code"))
        t, rejected, bugs = compute(self.d)
        self.assertEqual(t[221]["targets"], (220,))
        self.assertEqual(bugs, {220})

    def test_cost_is_coder_plus_judging_pass(self):
        harness(self.d, task(230, "[M] a", "code", "261001-000100-coder.log", "261001-000200-coder.log"))
        log(self.d, "261001-000100-coder.log", 2.0, 120000)
        log(self.d, "261001-000200-coder.log", 3.0, 60000)
        log(self.d, "261001-000300-reviewer-231.log", 0.5, 30000)
        log(self.d, "261001-000250-reviewer-230.log", 9.0)
        t, _, _ = compute(self.d)
        self.assertEqual(t[230]["judge"], 231)
        self.assertAlmostEqual(t[230]["cost"], 5.5)
        self.assertAlmostEqual(t[230]["dur"], 3.5)
        self.assertTrue(t[230]["known"])

    def test_two_duos_judging_pass_is_the_next_of_the_same_folder(self):
        # Shared counter: duo A writes 300 and 302, duo B writes 301. A's pass 302 judges 300.
        b = self.root / "b-logs"
        b.mkdir()
        harness(self.d, task(300, "[M] a", "code", "261001-000100-coder.log") + task(302, "[M] c", "code"))
        harness(b, task(301, "[M] b", "ui", "261001-000150-coder.log"))
        log(self.d, "261001-000100-coder.log", 1.0)
        log(b, "261001-000150-coder.log", 7.0)
        log(b, "261001-000200-reviewer-303.log", 4.0)
        log(self.d, "261001-000300-reviewer-302.log", 0.5)
        tasks = loop.read_all([self.d, b])
        rows, _, _ = agg_logs.calls([self.d, b])
        loop.analyse(tasks, rows)
        self.assertEqual(tasks[300]["judge"], 302)
        self.assertAlmostEqual(tasks[300]["cost"], 1.5)
        self.assertEqual(tasks[301]["judge"], 303)
        self.assertAlmostEqual(tasks[301]["cost"], 11.0)

    def test_domain_is_the_first(self):
        harness(self.d, task(240, "[M] a", "gameplay,ui,code"))
        self.assertEqual(loop.read_tasks(self.d)[240]["dom"], "gameplay")

    def test_missing_log_does_not_crash(self):
        harness(self.d, task(250, "[M] a", "code", "261001-000100-coder.log")
                + task(251, "[M] b", "code", "261001-000200-coder.log"))
        log(self.d, "261001-000200-coder.log", 4.0)
        t, _, _ = compute(self.d)
        self.assertFalse(t[250]["known"])
        self.assertTrue(t[251]["known"])
        lines = loop.table([t[250], t[251]], set(), set())
        self.assertIn("+1 unknown", lines[-1])

    def history(self, files):
        h = self.root / "pipeline" / "history"
        h.mkdir(parents=True, exist_ok=True)
        for name, text in files.items():
            (h / name).write_text(text, encoding="utf-8")
        return h

    def test_fixes_nnn_in_the_report_and_rejection_by_verdict(self):
        harness(self.d, task(280, "[M] a", "code") + task(281, "[M] b", "code")
                + task(282, "[M, correction] c", "code") + task(283, "[M, correction] d", "code"))
        h = self.history({
            "281-review.md": "VERDICT: ACCEPT\n", "282-review.md": "VERDICT: REJECT\n",
            "283-review.md": "VERDICT: ACCEPT\n", "284-review.md": "VERDICT: ACCEPT\n",
            "284-judged-report.md": "ADR (fixes 280 and 281).\n"})
        tasks, rejected, bugs = compute(self.d, h)
        self.assertEqual(tasks[282]["targets"], (281,))
        self.assertEqual(tasks[283]["targets"], (280, 281))
        self.assertEqual(rejected, {281})
        self.assertEqual(bugs, {280, 281})

    def test_history_next_to_the_log_folder_by_default(self):
        harness(self.d, task(290, "[M] a", "code") + task(291, "[M] b", "code"))
        self.history({"291-review.md": "VERDICT: REJECT\n"})
        _, rejected, _ = compute(self.d)
        self.assertEqual(rejected, {290})

    def test_verdict_line_of_the_journal(self):
        harness(self.d, task(260, "[M] a", "code") + task(261, "[M] b", "code")
                + ["[01/10 00:00:03] reviewer : verdict REJECT on task/260-m1-01 (gate : 0 KO)"])
        t, rejected, _ = compute(self.d)
        self.assertEqual(t[260]["verdict"], "REJECT")
        self.assertEqual(rejected, {260})

    def test_main_prints(self):
        harness(self.d, task(260, "[M] a", "code", "261001-000100-coder.log"))
        log(self.d, "261001-000100-coder.log", 1.0)
        self.assertEqual(loop.main(["--loop", "--tasks", "260-260"], self.d), 0)

    def summary(self, *argv):
        raw = io.BytesIO()
        out = io.TextIOWrapper(raw, encoding="utf-8", write_through=True)
        with contextlib.redirect_stdout(out):
            code = agg_logs.main(list(argv))
        return code, raw.getvalue().decode("utf-8")

    def test_given_logs_folder_for_the_summary(self):
        log(self.d, "261001-000100-coder.log", 1.5)
        log(self.d, "261001-000200-mediator-B.log", 0.25)
        log(self.d, "261001-000300-judge-012.log", 0.75)
        code, text = self.summary("--logs", str(self.d))
        self.assertEqual(code, 0)
        self.assertIn("CODER : 1 calls, 1.50 $", text)
        self.assertIn("MEDIATOR : 1 calls, 0.25 $", text)
        self.assertIn("JUDGE : 1 calls, 0.75 $", text)

    def test_several_logs_folders(self):
        b = self.root / "b-logs"
        b.mkdir()
        log(self.d, "261001-000100-coder.log", 1.0)
        log(b, "261001-000200-coder.log", 2.0)
        code, text = self.summary("--logs", str(self.d), "--logs", str(b))
        self.assertIn("CODER : 2 calls, 3.00 $", text)

    def test_empty_logs_folder_names_the_folder(self):
        code, text = self.summary("--logs", str(self.d))
        self.assertEqual(code, 0)
        self.assertIn("no claude log in %s" % self.d, text)

    def test_given_logs_folder_for_the_loop(self):
        harness(self.d, task(260, "[M] a", "code", "261001-000100-coder.log"))
        log(self.d, "261001-000100-coder.log", 1.0)
        code, _ = self.summary("--loop", "--tasks", "260-260", "--logs", str(self.d))
        self.assertEqual(code, 0)

    def test_default_folders_come_from_duos_txt(self):
        (self.root / "config").mkdir()
        (self.root / "config" / "duos.txt").write_text(
            "# name folder build load\nA   .        target    yes\nB   game-b   target-b  no\n", encoding="utf-8")
        got = agg_logs.duo_log_folders(self.root)
        self.assertEqual(got, [self.root / "logs", self.root.parent / "game-b" / "logs"])
        self.assertEqual(agg_logs.duo_log_folders(self.root / "nowhere"), [self.root / "nowhere" / "logs"])
        self.assertEqual(agg_logs.log_folders(["--logs", "x"]), [pathlib.Path("x")])


if __name__ == "__main__":
    unittest.main()
