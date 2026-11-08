#!/usr/bin/env python3
"""Rummage test runner: compiles every addon file and runs tests/cases.lua under
Lua 5.1 (lupa.lua51) against tests/wowstub.lua. Usage: python3 -I tests/run.py"""
import os
import re
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    sys.exit("lupa is required: pip install lupa")

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


def main():
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
    runner = lua.eval(
        """
        function(files, sources, cases_src, report)
          local passed, failed = 0, 0
          local T = {}
          local function new_env()
            local env = WOWSTUB()
            setmetatable(env, { __index = function(t, k)
              local v = _G[k]
              if v ~= nil then return v end
              local ok = false
              if type(k) == "string" then
                for _, pre in ipairs({"Get","Set","Is","Has","Clear","Click","Use","Pick","Show","Hide","Open","Close","Toggle","Register","Unregister","Play","Stop","Start","Cancel","Accept","Equip","Buy","Sell","Can","Do","Reset","Update","Request","Run","Pickup","Put","Cursor","Auto","Unit","Set"}) do
                  if k:sub(1, #pre) == pre and k:sub(#pre + 1, #pre + 1):match("%u") then ok = true break end
                end
              end
              if ok then
                env.__auto = env.__auto or {}
                env.__auto[k] = true
                return function() end
              end
            end })
            env._G = env
            local ns = {}
            for _, f in ipairs(files) do
              local chunk, err = loadstring(sources[f], "@" .. f)
              if not chunk then error("compile " .. f .. ": " .. tostring(err)) end
              setfenv(chunk, env)
              chunk("Rummage", ns)
            end
            return env, ns
          end
          local env_mt = {}
          local cases, loadErr = loadstring(cases_src, "@cases.lua")
          if not cases then error(loadErr) end
          local ctx = { new_env = new_env, tests = {} }
          setfenv(cases, setmetatable({ T = ctx, WOWSTUB = WOWSTUB }, { __index = _G }))
          cases()
          for _, t in ipairs(ctx.tests) do
            local ok, err = pcall(t.fn)
            if ok then passed = passed + 1; report(true, t.name, "")
            else failed = failed + 1; report(false, t.name, tostring(err)) end
          end
          return passed, failed
        end
        """
    )
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
