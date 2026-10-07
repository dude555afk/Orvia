#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LEGAL = {'LICENSE','LICENSE.md','LICENSE.txt','NOTICE','NOTICE.md','NOTICE.txt','COPYING','COPYING.md','COPYING.txt'}
SKIP_PREFIXES = ('dependencies/', '.git/')
BINARY_EXTS = {'.png','.jpg','.jpeg','.gif','.webp','.ico','.icns','.ttf','.otf','.woff','.woff2','.zip','.gz','.xz','.tar','.so','.dll','.dylib','.a','.jar','.apk','.bin','.pdf'}

def tracked_files():
    out = subprocess.check_output(['git','ls-files','-z'], cwd=ROOT)
    return [p for p in out.decode().split('\0') if p]

def is_legal(path):
    p = Path(path)
    return p.name in LEGAL or any(part.lower() in {'licenses','legal'} for part in p.parts)

def is_first_party(path):
    return not path.startswith(SKIP_PREFIXES) and not is_legal(path)

def rename_path(path):
    return path.replace('Kelivo','Orvia').replace('kelivo','orvia').replace('KELIVO','ORVIA')

# Rename tracked first-party files and directories by moving each file.
for old in sorted(tracked_files(), key=lambda p: p.count('/'), reverse=True):
    if not is_first_party(old):
        continue
    new = rename_path(old)
    if new == old:
        continue
    target = ROOT / new
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(['git','mv',old,new], cwd=ROOT)

replacements = [
    ('https://github.com/Chevey339/ish-arm64.git', 'https://github.com/OpenMinis/ish-arm64.git'),
    ('Chevey339/ish-arm64', 'OpenMinis/ish-arm64'),
    ('https://github.com/Chevey339/kelivo', 'https://github.com/dude555afk/Orvia'),
    ('https://github.com/Chevey339/orvia', 'https://github.com/dude555afk/Orvia'),
    ('package:Kelivo/', 'package:orvia/'),
    ('name: Kelivo', 'name: orvia'),
    ('com.psyche.kelivo', 'com.dude555afk.orvia'),
    ('psyche.kelivo', 'com.dude555afk.orvia'),
    ('@kelivo/fetch', '@orvia/fetch'),
    ('kelivo_fetch', 'orvia_fetch'),
    ('KelivoFetch', 'OrviaFetch'),
    ('KELIVO', 'ORVIA'),
    ('Kelivo', 'Orvia'),
    ('kelivo', 'orvia'),
]

for rel in tracked_files():
    rel = rename_path(rel)
    if not is_first_party(rel) or rel in {'README.md','tool/orvia_identity_migration.py','.github/workflows/orvia-identity-migration.yml'}:
        continue
    path = ROOT / rel
    if not path.exists() or path.suffix.lower() in BINARY_EXTS:
        continue
    try:
        raw = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    out = []
    changed = False
    for line in raw.splitlines(keepends=True):
        if re.search(r'copyright|spdx', line, re.I):
            out.append(line)
            continue
        new_line = line
        for old, new in replacements:
            new_line = new_line.replace(old, new)
        low = new_line.lower()
        if any(token in low for token in ('github.com/sponsors/','buymeacoffee.com/','patreon.com/','afdian.com/')):
            changed = True
            continue
        changed = changed or new_line != line
        out.append(new_line)
    if changed:
        path.write_text(''.join(out), encoding='utf-8')

# Root Dart package follows normal lowercase package naming.
pubspec = ROOT / 'pubspec.yaml'
text = pubspec.read_text(encoding='utf-8')
text = re.sub(r'(?m)^name:\s*\S+\s*$', 'name: orvia', text, count=1)
pubspec.write_text(text, encoding='utf-8')

# Product/project docs should describe Orvia directly.
for rel in ('PRODUCT.md','AGENTS.md'):
    path = ROOT / rel
    if not path.exists():
        continue
    text = path.read_text(encoding='utf-8')
    text = text.replace('package:Orvia/', 'package:orvia/').replace('Package name is `Orvia`', 'Package name is `orvia`')
    path.write_text(text, encoding='utf-8')

# Remove the one-shot migration files before the final commit.
for rel in ('tool/orvia_identity_migration.py','.github/workflows/orvia-identity-migration.yml'):
    path = ROOT / rel
    if path.exists():
        subprocess.check_call(['git','rm','-f',rel], cwd=ROOT)
