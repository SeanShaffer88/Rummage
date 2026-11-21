#!/usr/bin/env python3
"""Rummage test runner: compiles every addon file and runs tests/cases.lua under
Lua 5.1 (lupa.lua51 or LUA51 interpreter) against tests/wowstub.lua. Usage: python3 -I tests/run.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(HERE), "Rummage")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_files():
    files = []
    for line in read(os.path.join(ADDON, "Rummage.toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line)
    return files


def lua_string(value):
    """Quote arbitrary UTF-8 source as a Lua long string (without shell escaping)."""
    equals = ""
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[\n" + value + "]" + equals + "]"


def run_native(executable):
    files = [f for f in toc_files() if f.endswith(".lua")]
    all_files = sorted(f for f in os.listdir(ADDON) if f.endswith(".lua"))
    source_pairs = ["[ %s ]=%s" % (lua_string(f), lua_string(read(os.path.join(ADDON, f)))) for f in all_files]
    script = "assert(_VERSION == 'Lua 5.1', 'LUA51 must be a Lua 5.1 interpreter')\n"
    script += "local sources = {" + ",".join(source_pairs) + "}\n"
    script += "local files = {" + ",".join(lua_string(f) for f in files) + "}\n"
    script += """
local failures, total = 0, 0
local listed = {}; for _, f in ipairs(files) do listed[f] = true end
for name, source in pairs(sources) do
  total = total + 1
  local chunk, err = loadstring(source, "@" .. name)
  if not chunk then print("COMPILE FAIL", name, err); failures = failures + 1 end
  if not listed[name] then print("NOT IN TOC", name); failures = failures + 1 end
end
print(string.format("compile: %d files, %d problems", total, failures))
"""
    script += read(os.path.join(HERE, "wowstub.lua")) + "\n"
    script += "local runner = assert(loadstring(" + lua_string(read(os.path.join(HERE, "harness.lua"))) + "))()\n"
    script += "local cases = " + lua_string(read(os.path.join(HERE, "cases.lua"))) + "\n"
    script += """
local passed, failed = runner(files, sources, cases, function(ok, name, err)
  print((ok and "  ok   " or "  FAIL ") .. name .. (ok and "" or "\\n       " .. err))
end)
print(string.format("tests: %d passed, %d failed", passed, failed))
os.exit((failures > 0 or failed > 0) and 1 or 0)
"""
    with tempfile.TemporaryDirectory(prefix="rummage-tests-") as tmp:
        path = os.path.join(tmp, "run.lua")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(script)
        try:
            return subprocess.run([executable, path], timeout=120).returncode
        except (OSError, subprocess.TimeoutExpired) as exc:
            print("Native Lua runner failed: %s" % exc, file=sys.stderr)
            return 1


def main():
    native = os.environ.get("LUA51")
    if native:
        return run_native(native)
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        sys.exit("Install lupa or set LUA51 to an installed Lua 5.1 interpreter")
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_ = lua.eval("function(s, n) local f, e = loadstring(s, n) if f then return 'ok' end return e end")
    failures = 0
    lua_files = sorted(f for f in os.listdir(ADDON) if f.endswith(".lua"))
    for name in lua_files:
        res = compile_(read(os.path.join(ADDON, name)), "@" + name)
        if res != "ok":
            print("COMPILE FAIL", name, res)
            failures += 1
    listed = set(toc_files())
    for name in lua_files:
        if name not in listed:
            print("NOT IN TOC", name)
            failures += 1
    print("compile: %d files, %d problems" % (len(lua_files), failures))

    lua.execute(read(os.path.join(HERE, "wowstub.lua")))
    runner = lua.execute(read(os.path.join(HERE, "harness.lua")))
    sources = lua.table_from({f: read(os.path.join(ADDON, f)) for f in toc_files() if f.endswith(".lua")})
    files = lua.table_from([f for f in toc_files() if f.endswith(".lua")], )
    cases = read(os.path.join(HERE, "cases.lua"))

    def report(ok, name, err):
        print(("  ok   " if ok else "  FAIL ") + name + ("" if ok else "\n       " + err))

    passed, failed = runner(files, sources, cases, report)
    print("tests: %d passed, %d failed" % (passed, failed))
    return 1 if (failures or failed) else 0


if __name__ == "__main__":
    sys.exit(main())
