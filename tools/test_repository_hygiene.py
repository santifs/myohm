#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression checks for publication boundaries; fixtures never contain real keys."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from check_repository import check


class PublicationHygieneTests(unittest.TestCase):
    def test_ignored_private_files_are_excluded_but_tracked_ones_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            (root / '.gitignore').write_text('.env\n.private-review/\n')
            (root / '.env').write_text('EXAMPLE=local-only\n')
            (root / '.private-review').mkdir()
            (root / '.private-review' / 'notes.txt').write_text('private\n')
            self.assertEqual(check(root)[1], [])
            subprocess.run(['git', 'add', '-f', '.env'], cwd=root, check=True)
            self.assertTrue(any('.env:' in issue for issue in check(root)[1]))

    def test_new_files_are_scanned_and_secret_values_are_never_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            fixture = 'gh' + 'p_' + 'A' * 36
            (root / 'accidental.txt').write_text(fixture)
            issues = check(root)[1]
            self.assertTrue(any('GitHub token' in issue for issue in issues))
            self.assertNotIn(fixture, '\n'.join(issues))


if __name__ == '__main__':
    unittest.main()
