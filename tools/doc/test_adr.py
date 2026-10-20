"""Tests of tools/doc/adr.py: python -m unittest tools/doc/test_adr.py"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import adr  # noqa: E402

OLD = """# Decision log (ADR)

Preamble.

---

## ADR-0001 — Language choice — *Accepted*

**Context**: a.

## ADR-0046 — Circuit breaker — *Accepted*

b.

## ADR-0046b — Duo autonomy — *Accepted by the owner*

### Sub-title
c.

---

## ADR-0164 — Same title — *Accepted*

d.

## ADR-0164 — Same title — *Accepted*

e.
"""


class Adr(unittest.TestCase):
    def test_slug_and_title(self):
        h = "## ADR-0473 — Login screen: café menu in 3 tones — *Accepted* (TASK 521)"
        self.assertEqual(adr.title_of(h), "Login screen: café menu in 3 tones")
        self.assertEqual(adr.slug(adr.title_of(h)), "login-screen-cafe-menu-in-3-tones")

    def test_split_keeps_every_block_verbatim_and_index_lists_them(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "old.md"
            src.write_text(OLD, encoding="utf-8")
            out = Path(d) / "adr"
            names = adr.split(src, out)
            self.assertEqual(len(names), 5)
            self.assertIn("0046b-duo-autonomy.md", names)
            self.assertIn("0164-same-title-2.md", names)
            self.assertEqual((out / "0046b-duo-autonomy.md").read_text(encoding="utf-8"),
                             "## ADR-0046b — Duo autonomy — *Accepted by the owner*\n\n### Sub-title\nc.\n")
            # every body line of the old file is in exactly one ADR file
            body = "".join((out / n).read_text(encoding="utf-8") for n in names)
            for line in OLD.splitlines()[6:]:
                if line.strip() not in ("", "---"):
                    self.assertIn(line, body)
            index = adr.render_index(out)
            self.assertIn("- [ADR-0001](adr/0001-language-choice.md) — Language choice — *Accepted*", index)
            self.assertEqual(index.count("\n- [ADR-"), 5)
            self.assertNotIn("\n## ADR-", index)
            self.assertIn("BUDGET:", index.splitlines()[1])
            self.assertEqual(len(adr.headers(out)), 5)

    def test_index_check_then_write(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "docs" / "adr").mkdir(parents=True)
            (root / "docs" / "adr" / "0001-x.md").write_text("## ADR-0001 — X — *Accepted* (TASK 001)\n", encoding="utf-8")
            adr.ADR_DIR, adr.INDEX = root / "docs" / "adr", root / "docs" / "DECISIONS.md"
            self.assertEqual(adr.main(["index", "--check"]), 1)
            self.assertFalse(adr.INDEX.exists())
            self.assertEqual(adr.main(["index"]), 0)
            self.assertEqual(adr.main(["index", "--check"]), 0)
            self.assertIn("(TASK 001)", adr.INDEX.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
