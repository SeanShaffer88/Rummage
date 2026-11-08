# Rummage — 20 suggestions (2026-11-08)

Basis: read of the 19 addon files (~7k lines; `UI.lua` is 2.3k), `Compat.lua`, `Mover.lua`, `AUDIT.md`, TOC. Build checked: Forever 1.60.1.70862 (interface 16001), code review only.

## Compatibility / reliability
1. **`/rum apicheck`** — report which container/bank/tooltip APIs exist on the live client (`C_Container.*`, `Enum.BagIndex.CharacterBankTab_N`, `TooltipUtil`), giving real evidence for "Unverified".
2. **Secret-safe tooltip reads** — Forever enforces Midnight-style secret values; wrap `TooltipUtil` / tooltip-data reads in `pcall` + `issecretvalue` guards so an item tooltip can never throw.
3. **Commit the test harness** — `AUDIT.md` cites a 33-step mock suite, combat-lockdown suite and allocation profiler, but none is in the repo. Add `tests/` (Lua 5.1 + stub).
4. **Local gate script + `.luacheckrc`** — luacheck, compile-all, TOC lint (interface / X-Build / version consistency).
5. **Bank-tab verification** — confirm the modern bank-tab path on Forever; add a visible "bank layout: tabs/bags" line to `/fdebug report`.
6. **Stale-data indicators** — per-character "last seen" time and a dim state for old cached bags/bank/mail.

## Window / UX
7. **Shift-snap on the scale grips** — snap to 75/100/125/150%.
8. **Per-view window size and scale** — separate geometry for Bags, Bank and All-characters views.
9. **Keyboard navigation** — arrow keys / Enter (use) / Space (favorite) in the list.
10. **Colorblind-safe quality cues** — text or shape markers alongside quality colors.
11. **Pending-layout badge** — show when a change waits for combat to end.
12. **Scale shown live** — small percent readout beside the cursor while dragging a grip.

## Features
13. **Junk-sale log + buyback shortcut** — list what was sold and offer one-click buyback.
14. **Sell safeguards** — confirm above a value threshold or for uncommon-and-better items.
15. **Saved searches as sidebar chips** — pin frequent queries (beyond custom categories).
16. **Drag-to-split in list view** — stack-split without leaving the table.
17. **Inventory export** — copy all characters' items as CSV/text.
18. **Auto-profile by context** — per spec / zone, reusing the 1.3.0 profiles.
19. **Upgrade popup stat diff** — show what changes versus the equipped item.

## Engineering
20. **Split `UI.lua`** into header / list / grid / footer modules; makes combat-deferred layout code testable.
