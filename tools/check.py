#!/usr/bin/env python3
"""Rummage local gate: compile-all, TOC lint, file headers, tests, optional luacheck.
Usage: python3 -I tools/check.py        (exit code 0 = clean)
Needs: python3, lupa (pip install lupa). luacheck is run only when installed."""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Rummage")
problems = []


def fail(msg):
    problems.append(msg)
    print("FAIL", msg)


def ok(msg):
    print("ok  ", msg)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_lint():
    toc = read(os.path.join(ADDON, "Rummage.toc"))
    meta = dict(re.findall(r"^##\s*([\w-]+):\s*(.*)$", toc, re.M))
    if meta.get("Interface") != "16001":
        fail("TOC Interface is %r, expected 16001" % meta.get("Interface"))
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", meta.get("X-Build", "")):
        fail("TOC X-Build missing or malformed: %r" % meta.get("X-Build"))
    if meta.get("Author") != "Malikor":
        fail("TOC Author must be Malikor")
    if meta.get("X-License") != "GPL-3.0-or-later":
        fail("TOC X-License must be GPL-3.0-or-later")
    log = read(os.path.join(ADDON, "CHANGELOG.md"))
    m = re.search(r"^## (\d+\.\d+\.\d+)", log, re.M)
    if not m or m.group(1) != meta.get("Version"):
        fail("TOC Version %r != newest CHANGELOG entry %r" % (meta.get("Version"), m and m.group(1)))
    files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    seen = set()
    for f in files:
        if f in seen:
            fail("TOC lists %s twice" % f)
        seen.add(f)
        if not os.path.exists(os.path.join(ADDON, f)):
            fail("TOC lists missing file %s" % f)
    for f in sorted(os.listdir(ADDON)):
        if f.endswith(".lua") and f not in seen:
            fail("%s is not in the TOC" % f)
    for doc in ("README.md", "FEATURES.md", "DESCRIPTION.md"):
        if not os.path.exists(os.path.join(ADDON, doc)):
            fail("missing " + doc)
    ok("TOC lint (%d files, version %s, build %s)" % (len(files), meta.get("Version"), meta.get("X-Build")))


def headers():
    for f in sorted(os.listdir(ADDON)):
        if f.endswith(".lua"):
            head = "".join(read(os.path.join(ADDON, f)).splitlines(True)[:12])
            if not re.search(r"Copyright \(C\) 2026 Malikor\..*(GPL|GNU)", head, re.S):
                fail("%s: GPLv3/Malikor header missing in first lines" % f)
    ok("file headers")


def luacheck():
    exe = shutil.which("luacheck")
    if not exe:
        print("skip luacheck (not installed)")
        return
    r = subprocess.run([exe, ADDON, "--config", os.path.join(ROOT, ".luacheckrc"), "--no-color"],
                       capture_output=True, text=True)
    print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "")
    if r.returncode not in (0,):
        fail("luacheck reported issues")


def main():
    toc_lint()
    headers()
    luacheck()
    r = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tests", "run.py")])
    if r.returncode != 0:
        fail("tests/run.py failed")
    print()
    print("GATE:", "FAILED (%d)" % len(problems) if problems else "clean")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
