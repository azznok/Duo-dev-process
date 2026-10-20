"""Tests of tools/doc/concurrent_appends.py: python -m unittest tools/doc/test_concurrent_appends.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import concurrent_appends as ca  # noqa: E402

ADDITIONS = """## M5-29

a.
<<<<<<< HEAD
## M5-30

b.
||||||| base
=======
## M5-31

c.
>>>>>>> main

## End of M5
"""

EDIT = """<<<<<<< HEAD
- [x] 1/2
||||||| base
- [ ] 1/2
=======
- [ ] 1/2 (moved)
>>>>>>> main
"""


class ConcurrentAppends(unittest.TestCase):
    def test_keeps_both_additions_ours_first(self):
        got = ca.resolve(ADDITIONS)
        self.assertEqual(got, "## M5-29\n\na.\n## M5-30\n\nb.\n\n## M5-31\n\nc.\n\n## End of M5\n")

    def test_refuses_an_edit_of_existing_lines(self):
        self.assertIsNone(ca.resolve(EDIT))

    def test_refuses_two_way_style_without_base(self):
        self.assertIsNone(ca.resolve("<<<<<<< HEAD\na\n=======\nb\n>>>>>>> main\n"))

    def test_refuses_a_file_without_conflict(self):
        self.assertIsNone(ca.resolve("nothing\n"))

    def test_keeps_crlf(self):
        got = ca.resolve(ADDITIONS.replace("\n", "\r\n"))
        self.assertIn("b.\r\n\r\n## M5-31", got)
        self.assertNotIn("\n\n", got.replace("\r\n", "|"))


if __name__ == "__main__":
    unittest.main()
