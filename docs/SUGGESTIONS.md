# Rummage — 20 suggestions (2026-11-08)

Basis: read of the 19 addon files (~7k lines; `UI.lua` is 2.3k), `Compat.lua`, `Mover.lua`, `AUDIT.md`, TOC. Build checked: Forever 1.60.1.70862 (interface 16001), code review only.

Status key: Done / Partial / Skipped, with reason. Nothing was verified in the game client.

## Compatibility / reliability
1. **`/rum apicheck`** — report which container/bank/tooltip APIs exist on the live client (`C_Container.*`, `Enum.BagIndex.CharacterBankTab_N`, `TooltipUtil`), giving real evidence for "Unverified".
   - **Status:** Done — `/rum apicheck` (Extras.lua); tested with a faked client. Real output on Forever not yet seen.
2. **Secret-safe tooltip reads** — Forever enforces Midnight-style secret values; wrap `TooltipUtil` / tooltip-data reads in `pcall` + `issecretvalue` guards so an item tooltip can never throw.
   - **Status:** Done — pcall + issecretvalue/canaccessvalue guards in Tooltip.lua and the upgrade scan tooltip. Unverified in a real restricted context.
3. **Commit the test harness** — `AUDIT.md` cites a 33-step mock suite, combat-lockdown suite and allocation profiler, but none is in the repo. Add `tests/` (Lua 5.1 + stub).
   - **Status:** Done — `tests/` (21 cases, Lua 5.1 + fake client) and `tests/README.md`. Fake client only; no real taint or lockdown.
4. **Local gate script + `.luacheckrc`** — luacheck, compile-all, TOC lint (interface / X-Build / version consistency).
   - **Status:** Partial — `tools/check.py` (compile, TOC lint, headers, tests) and `.luacheckrc`. luacheck could not be installed here, so the rc file is unrun.
5. **Bank-tab verification** — confirm the modern bank-tab path on Forever; add a visible "bank layout: tabs/bags" line to `/fdebug report`.
   - **Status:** Done — `/fdebug report` prints the resolved bank path and bag ids. Which path Forever actually takes still needs a live look.
6. **Stale-data indicators** — per-character "last seen" time and a dim state for old cached bags/bank/mail.
   - **Status:** Done — char menu shows last-seen age; stale (default 14 days, setting) is dimmed and marked.

## Window / UX
7. **Shift-snap on the scale grips** — snap to 75/100/125/150%.
   - **Status:** Done — Shift-drag snaps to 75/100/125/150%.
8. **Per-view window size and scale** — separate geometry for Bags, Bank and All-characters views.
   - **Status:** Done — setting `Remember window size and scale per view` (Bags / Bank / All characters).
9. **Keyboard navigation** — arrow keys / Enter (use) / Space (favorite) in the list.
   - **Status:** Done — arrows/Page/Home/End select, Enter uses, Space cycles favorite. Unverified: keyboard capture/propagation on the live client.
10. **Colorblind-safe quality cues** — text or shape markers alongside quality colors.
   - **Status:** Done — optional `[Rare]`-style text tag before item names. Grid cells keep colour only.
11. **Pending-layout badge** — show when a change waits for combat to end.
   - **Status:** Done — `Layout pending` badge, cleared (and applied) on combat end.
12. **Scale shown live** — small percent readout beside the cursor while dragging a grip.
   - **Status:** Done — percent readout above the footer while a grip is held (placed in the window, not at the cursor).

## Features
13. **Junk-sale log + buyback shortcut** — list what was sold and offer one-click buyback.
   - **Status:** Partial — log (30 entries) + `/rum junklog`, `/rum buyback [n]` matching by link. Unverified: Forever's buyback API; no on-screen button.
14. **Sell safeguards** — confirm above a value threshold or for uncommon-and-better items.
   - **Status:** Done — confirm for Uncommon+ (on) and above a gold threshold (off by default); also applies to auto-sell.
15. **Saved searches as sidebar chips** — pin frequent queries (beyond custom categories).
   - **Status:** Done — up to 8 chips above `+ New category`; save via history menu or `/rum savesearch`; right-click removes.
16. **Drag-to-split in list view** — stack-split without leaving the table.
   - **Status:** Partial — Shift-drag splits half on the plain item buttons only. The secure Blizzard buttons already split on Shift-click and cannot be changed safely.
17. **Inventory export** — copy all characters' items as CSV/text.
   - **Status:** Done — `/rum inventory [csv|text]` copy window, all characters, escaped CSV.
18. **Auto-profile by context** — per spec / zone, reusing the 1.3.0 profiles.
   - **Status:** Partial — spec1-4 and dungeon/raid/battleground/arena/world mapped via `/rum autoprofile`; out of combat only; no config UI for the map. Unverified: spec API on Forever.
19. **Upgrade popup stat diff** — show what changes versus the equipped item.
   - **Status:** Done — top 4 stat deltas vs the equipped item when the client provides item stats; blank otherwise.

## Engineering
20. **Split `UI.lua`** into header / list / grid / footer modules; makes combat-deferred layout code testable.
   - **Status:** Done — `UI_Window.lua`, `UI_Menus.lua`, `UI_Input.lua` split out (not header/list/grid/footer as proposed; those still share locals in `UI.lua`, which is now ~2.0k lines).

## Second list (2026-11-08, after in-game verification)

| Item | Status | Notes |
|---|---|---|
| In-game verification | Done | 1.5.0 verified live by SEAN on Forever 1.60.1.70862 (keyboard capture, buyback, spec detection included) |
| Release | Done | cut by SEAN |
| Real luacheck in CI | Skipped | SEAN: skip for now |
| `apicheck` export | Done | `/rum apicheck export` |
| CI release workflow | Done | `.github/workflows/{ci,release}.yml`, `tools/package.sh` |
| Finish partials (#13, #16, #18) | Partial | `/rum buyback all` added; the secure-button split and a config UI for the auto-profile map stay as they were (`/rum autoprofile set` exists) |
| Mail view and expiry | Done | days-left stored; login warning, `/rum mail` |
| Gold over time | Done | `/rum gold` |
| Bag-space warning | Already true | `lowSpaceWarn` (default 3) |
| Reagent category rules | Already true | built-in categories, custom categories from searches |
| Vendor vs auction hint | Done | tooltip line with Auctionator |
| Compare tooltip for non-upgrades | Skipped | the game's own comparison tooltip already covers it |
| CSV export | Already true | `/rum inventory csv` |
| Performance budget | Done | `/rum perf` |
