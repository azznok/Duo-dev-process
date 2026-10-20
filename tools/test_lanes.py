"""Tests of tools/lanes.py: python -m unittest tools/test_lanes.py"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lanes  # noqa: E402

HEAD = "# Backlog test\n\n"


def backlog(text, name="M7-test.md"):
    d = Path(tempfile.mkdtemp())
    (d / "docs" / "backlog").mkdir(parents=True)
    (d / "docs" / "backlog" / name).write_text(HEAD + text, encoding="utf-8")
    lanes.ROOT = d
    return lanes.analyse(lanes.read("M7"))


def entry(i, lane=None, zones=None, prerequisites="", done=False, boxes="- [ ] a\n"):
    t = f"## M7-{i:02d}{' ✅' if done else ''} — entry {i}\n\n"
    t += f"**Prerequisites**: {prerequisites or '—'}. **Domains**: code.\n"
    if lane:
        t += f"**Lane**: {lane}. **Zones**: {zones}.\n"
    return t + boxes + "\n"


def states(r):
    return {k: v["state"] for k, v in r.items()}


class Lanes(unittest.TestCase):
    def test_duplicate_title_is_an_error(self):
        _r, e = backlog(entry(1) + entry(2) + entry(1))
        self.assertEqual(e, ["M7-01 : duplicate title"])

    def test_distinct_titles_no_error(self):
        _r, e = backlog(entry(1) + entry(2))
        self.assertEqual(e, [])

    def test_no_label_means_single_lane(self):
        r, e = backlog(entry(1) + entry(2))
        self.assertEqual(e, [])
        self.assertEqual(list(r), ["single"])
        self.assertEqual(r["single"]["state"], "ready")

    def test_prerequisite_done_in_another_milestone(self):
        d = Path(tempfile.mkdtemp())
        (d / "docs" / "backlog").mkdir(parents=True)
        (d / "docs" / "backlog" / "M6-before.md").write_text(HEAD + "## M6-01 ✅ — done\n\n- [x] a\n", encoding="utf-8")
        (d / "docs" / "backlog" / "M7-test.md").write_text(HEAD + entry(1, "sim", "src/sim", "M6-01"), encoding="utf-8")
        lanes.ROOT = d
        alone, _ = lanes.analyse(lanes.read("M7"))
        self.assertEqual(alone["sim"]["state"], "waiting")
        elsewhere = {e["id"] for e in lanes.read(r"M\d+") if e["done"]}
        r, e = lanes.analyse(lanes.read("M7"), elsewhere)
        self.assertEqual(e, [])
        self.assertEqual(r["sim"]["state"], "ready")

    def test_two_disjoint_lanes_ready(self):
        r, e = backlog(entry(1, "sim", "src/sim") + entry(2, "art", "tools/image, `src/ui`"))
        self.assertEqual(e, [])
        self.assertEqual(states(r), {"sim": "ready", "art": "ready"})
        self.assertEqual(r["art"]["zones"], ["src/ui", "tools/image"])

    def test_bold_colon_inside_label(self):
        r, e = backlog("## M7-01 — x\n\n**Lane:** sim. **Zones:** src/sim.\n- [ ] a\n")
        self.assertEqual(e, [])
        self.assertEqual(r["sim"]["zones"], ["src/sim"])

    def test_owner_decision_blocks_the_entry(self):
        r, e = backlog(entry(1, "art", "tools/image", prerequisites="owner decision (pause)")
                       + entry(2, "ui", "src/ui/hud"))
        self.assertEqual(e, [])
        self.assertEqual(states(r), {"art": "waiting", "ui": "ready"})

    def test_pause_blocks_even_inside_the_lane(self):
        r, _ = backlog(entry(1, "art", "tools/image", prerequisites="pause"))
        self.assertEqual(r["art"]["state"], "waiting")

    def test_shared_zone_refused(self):
        r, e = backlog(entry(1, "sim", "src/sim") + entry(2, "net", "src/sim/net"))
        self.assertEqual(len(e), 1)
        self.assertIn("share the zone", e[0])

    def test_open_entry_without_lane_refused(self):
        r, e = backlog(entry(1, "sim", "src/sim") + entry(2))
        self.assertEqual(e, ["M7-02 : no lane"])

    def test_open_entry_without_zones_refused(self):
        r, e = backlog("## M7-01 — x\n\n**Lane**: sim.\n- [ ] a\n")
        self.assertEqual(e, ["M7-01 : no zones"])

    def test_prerequisite_in_another_lane_waits(self):
        r, e = backlog(entry(1, "sim", "src/sim") + entry(2, "render", "src/render", "M7-01"))
        self.assertEqual(r["render"]["state"], "waiting")
        r, e = backlog(entry(1, "sim", "src/sim", done=True) + entry(2, "render", "src/render", "M7-01"))
        self.assertEqual(r["sim"]["state"], "done")
        self.assertEqual(r["sim"]["ready"], [])
        self.assertEqual(r["render"]["state"], "ready")

    def test_prerequisite_in_the_same_lane_ready(self):
        r, e = backlog(entry(1, "sim", "src/sim") + entry(2, "sim", "src/sim", "M7-01"))
        self.assertEqual(r["sim"]["ready"], ["M7-01", "M7-02"])

    def test_range_of_prerequisites(self):
        self.assertEqual(lanes.ids_of("M4-03, M4-15 to M4-18 (x)"), ["M4-03", "M4-15", "M4-16", "M4-17", "M4-18"])

    def test_done_by_ticked_boxes(self):
        r, e = backlog(entry(1, "sim", "src/sim", boxes="- [x] a\n- [x] b\n") + entry(2, "art", "tools/image"))
        self.assertEqual(r["sim"]["state"], "done")
        self.assertEqual(r["art"]["state"], "ready")

    def test_end_of_milestone_after_the_others(self):
        end = "## End of M7\n\n**Prerequisites**: M7-00 to M7-01.\n- [ ] build\n"
        r, e = backlog(entry(1, "sim", "src/sim") + end)
        self.assertEqual(r["end"]["state"], "waiting")
        r, e = backlog(entry(1, "sim", "src/sim", done=True) + end)
        self.assertEqual(states(r), {"sim": "done", "end": "ready"})
        self.assertEqual(r["end"]["ready"], ["END"])
        r, e = backlog(entry(1, "sim", "src/sim", done=True) + end.replace("- [ ]", "- [x]"))
        self.assertEqual(r["end"]["state"], "done")

    def test_milestone_files_with_a_letter(self):
        r, e = backlog(entry(1, "sim", "src/sim"), name="M7a-systems.md")
        self.assertIn("sim", r)

    def test_read_from_a_branch(self):
        # --ref main: the merged backlog counts, not the working copy of a coder mid-task.
        backlog(entry(1))
        d = lanes.ROOT
        g = lambda *a: subprocess.run(["git", "-C", str(d), *a], capture_output=True, text=True)  # noqa: E731
        g("init", "-q"); g("add", "-A"); g("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "x")
        f = d / "docs" / "backlog" / "M7-test.md"
        f.write_text(HEAD + entry(1, "sim", "src/sim") + entry(2, "art", "tools/image"), encoding="utf-8")
        self.assertEqual(set(lanes.analyse(lanes.read("M7"))[0]), {"sim", "art"})
        self.assertEqual(list(lanes.analyse(lanes.read("M7", "HEAD"))[0]), ["single"])

    def test_cli_json_shape(self):
        backlog(entry(1, "sim", "src/sim") + entry(2, "art", "tools/image"))
        d = lanes.ROOT
        (d / "tools").mkdir()
        (d / "tools" / "lanes.py").write_text(Path(lanes.__file__).read_text(encoding="utf-8"), encoding="utf-8")
        out = subprocess.run([sys.executable, str(d / "tools" / "lanes.py"), "--milestone", "M7", "--json"],
                             capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(out.returncode, 0, out.stderr)
        j = json.loads(out.stdout)
        self.assertEqual(j["errors"], [])
        self.assertEqual(j["lanes"]["sim"]["state"], "ready")
        self.assertEqual(j["lanes"]["sim"]["entries"], ["M7-01"])
        self.assertEqual(j["lanes"]["art"]["ready"], ["M7-02"])
        txt = subprocess.run([sys.executable, str(d / "tools" / "lanes.py"), "--milestone", "M7"],
                             capture_output=True, text=True, encoding="utf-8").stdout
        self.assertIn("LANES M7 : 2 ready, 0 error(s)", txt)


if __name__ == "__main__":
    unittest.main()
