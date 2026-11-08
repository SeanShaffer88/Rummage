# Rummage tests

Offline tests: every addon file is loaded under **Lua 5.1** (via `lupa.lua51`) against a
small fake WoW client (`wowstub.lua`) — a stub, not a game emulator.

    pip install lupa
    python3 -I tests/run.py        # compile all files + run tests/cases.lua
    python3 -I tools/check.py      # full gate: TOC lint, headers, luacheck (if installed), tests

What is covered: compile of every file and TOC membership; addon boot and window open;
scale-grip math (both corners, fixed edges, clamp, Shift snap, readout, lock/combat);
pending-layout badge; per-view layouts; SavedVariables sanitizing and v3→v4 migration;
settings export/import and profile round-trips; junk sale safeguards, log and buyback;
stale data; saved searches; keyboard navigation (including search focus and combat);
`/rum apicheck`, inventory CSV, auto-profile, tooltip secret-value guard, upgrade stat diff,
and every slash command running without a Lua error.

What is **not** covered: real client behaviour. The stub fakes geometry for UIParent-anchored
frames only, has no taint, no real combat lockdown on protected buttons, and no real secret
values (tests simulate `issecretvalue`). Items marked *Unverified* in `Rummage/CHANGELOG.md`
need a live check on Forever 1.60.1.70862.

Adding a test: append `test("name", function() local env, R = boot() ... end)` to
`cases.lua`. `env.__combat`, `env.__cursor`, `env.__shift`, `env.__now`, `env.__bags`,
`env.__addItem(bag, slot, id, count, def)` and `env.__settle(n)` drive the fake client.
