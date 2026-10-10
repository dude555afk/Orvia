#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = ''.join(chr(x) for x in (107, 101, 108, 105, 118, 111))
OLD_OWNER = ''.join(chr(x) for x in (67, 104, 101, 118, 101, 121, 51, 51, 57))
LEGAL = {'LICENSE','LICENSE.md','LICENSE.txt','NOTICE','NOTICE.md','NOTICE.txt','COPYING','COPYING.md','COPYING.txt'}
SKIP_PREFIXES = ('dependencies/', '.git/')

def is_legal(path):
    p = Path(path)
    return p.name in LEGAL or any(part.lower() in {'licenses','legal'} for part in p.parts)

files = subprocess.check_output(['git','ls-files','-z'], cwd=ROOT).decode().split('\0')
bad = []
for rel in filter(None, files):
    if rel.startswith(SKIP_PREFIXES) or is_legal(rel):
        continue
    if FORBIDDEN in rel.lower():
        bad.append(f'path: {rel}')
        continue
    path = ROOT / rel
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    for i, line in enumerate(text.splitlines(), 1):
        low = line.lower()
        if rel.startswith('lib/') and rel.endswith('.dart'):
            if 'assets/app_icon' in low or 'assets/icon_mac.png' in low:
                bad.append(f'legacy in-app brand icon: {rel}:{i}: {line.strip()}')
        if FORBIDDEN in low or OLD_OWNER.lower() in low:
            if 'copyright' in low or 'spdx' in low:
                continue
            bad.append(f'{rel}:{i}: {line.strip()}')

if bad:
    print('Orvia identity guard failed:')
    print('\n'.join(bad))
    sys.exit(1)
print('Orvia identity guard passed.')
