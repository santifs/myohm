#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check the Git publication candidate without printing secret values.

Includes tracked files (even if ignored) and nonignored new files. This is a
fast hygiene guard, not a replacement for Gitleaks history/archive scanning.
"""
from pathlib import Path
import re
import subprocess
import sys

PATTERNS = [
    ('private key', r'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    ('GitHub token', r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'),
    ('AWS key', r'(?:AKIA|ASIA)[0-9A-Z]{16}'),
    ('JWT', r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
]
PRIVATE_SUFFIXES = {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.mobileprovision'}
PRIVATE_PARTS = {'.private-review', 'xcuserdata', 'measurements', 'exports', '.idea', '.cursor'}
# Optional list of names that must never be published (one per line), kept outside version control.
NAMES_FILE = Path('.private-review/forbidden-names.txt')


def forbidden_names(root):
    path = root / NAMES_FILE
    if not path.exists():
        return None
    names = [n.strip() for n in path.read_text(encoding='utf-8').splitlines() if n.strip()]
    return re.compile('|'.join(re.escape(n) for n in names), re.IGNORECASE) if names else None


def check(root):
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=root
    ).decode().split('\0')
    issues = []
    count = 0
    names_pattern = forbidden_names(root)
    for name in sorted(set(names) - {''}):
        rel = Path(name)
        path = root / rel
        if path.is_symlink():
            issues.append(f'{rel}: symlink requires publication review')
            continue
        if not path.is_file():
            continue  # tracked deletion
        count += 1
        if ((path.name.startswith('.env') and path.name != '.env.example')
                or path.suffix.lower() in PRIVATE_SUFFIXES
                or PRIVATE_PARTS.intersection(rel.parts)
                or path.name in {'local.properties', 'label.conf', '.DS_Store'}
                or {'supabase', '.temp'} <= set(rel.parts)):
            issues.append(f'{rel}: private/local file in publication candidate')
        try:
            text = path.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            continue  # Binary and archive inspection belongs to the full release audit.
        if path.suffix in {'.kicad_sch', '.kicad_pcb', '.kicad_mod', '.kicad_sym'} or path.name.endswith('lib-table'):
            if re.search(r'(?:/Users/|/home/|[A-Z]:\\)', text):
                issues.append(f'{rel}: machine-specific CAD path')
        for label, pattern in PATTERNS:
            if re.search(pattern, text):
                issues.append(f'{rel}: potential {label}')
        if names_pattern and names_pattern.search(text):
            issues.append(f'{rel}: forbidden name')
    return count, issues


if __name__ == '__main__':
    count, issues = check(Path(__file__).resolve().parents[1])
    print(f'Scanned {count} publication files; {len(issues)} issues. Heuristic check, not a legal/provenance audit.')
    for issue in issues:
        print(issue)
    sys.exit(bool(issues))
