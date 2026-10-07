#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_PREFIXES = ("dependencies/", "ios/sandbox/")
EXCLUDED_FILES = {"LICENSE", "android/app/src/main/jniLibs/NOTICE", "ios/sandbox/NOTICE"}
SUFFIXES = {".dart",".kt",".kts",".java",".swift",".m",".mm",".h",".c",".cc",".cpp",".xml",".plist",".strings",".yaml",".yml",".json",".md",".txt",".sh",".py",".ps1",".cmake",".gradle",".properties"}
CJK = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
hits=[]
for p in ROOT.rglob("*"):
    if not p.is_file(): continue
    rel=p.relative_to(ROOT).as_posix()
    if rel in EXCLUDED_FILES or rel.startswith(EXCLUDED_PREFIXES): continue
    if p.suffix.lower() not in SUFFIXES: continue
    try: text=p.read_text(encoding="utf-8")
    except UnicodeDecodeError: continue
    for n,line in enumerate(text.splitlines(),1):
        if CJK.search(line): hits.append(f"{rel}:{n}: {line.strip()}")
if hits:
    print("First-party CJK text found:")
    print("\n".join(hits))
    sys.exit(1)
print("No first-party CJK text found.")
