# Changelog

## 1.7.1 — 2026-11-08

Fix from in-game screenshots of 1.6.0: settings tabs ran past the bottom of the settings window (General lost its last rows, Columns overlapped its footer, About spilled out). Passes the offline suite (27 cases); not yet run in game.

- **Settings tabs scroll.** Every tab is a scroll frame with mouse-wheel scrolling and a thin scroll bar that appears when needed. Tabs that place widgets outside the normal flow (the column list) grow to fit.
- **About lists every command** (`buyback`, `junklog`, `gold`, `mail`, `perf`, `inventory`, `apicheck export`).

## 1.7.0 — 2026-11-08

Wider windows and easier column resizing. (Docs and version bump for this release shipped late, in 1.7.1.)

- **Wider window.** Maximum width is now 4000 and height 2400 (was 2000 x 1600), and the saved-size limits match. A new left-edge handle joins the right-edge and bottom-edge ones; the side handles are 8 px wide instead of 5.
- **Resizable Name column.** Name fills the free space until you drag its header edge; then it keeps that width. Double-click the edge to hand it back to flex.
- **Easier column handles.** Header resize handles are 10 px wide, sit above neighbouring headers, light up gold on hover, and show a tooltip. Double-click a handle to reset that column. Column width cap raised from 600 to 1200.

## 1.6.0 — 2026-11-08

1.5.0 was verified in game on Forever 1.60.1.70862 (keyboard capture, buyback and spec detection included). This release adds the items left on the suggestion list; the new code passes the offline suite (25 cases) and is not yet run in game.

- **`/rum apicheck export`** opens the API report in the copy window, plain text, ready to paste into a bug report.
- **Mail expiry warning.** The mailbox is only readable at a mailbox, so Rummage now stores each item's days left when it last saw the mail and ages it. At login, any character whose cached mail expires within N days (Settings > Safety, default 3, 0 = off) gets a chat line. `/rum mail` checks on demand.
- **Gold history.** One snapshot per character per day (90 kept). `/rum gold` lists each character's gold with 7-day and 30-day change, plus the account total. Switch off with `Keep daily gold history`.
- **Tooltip sell hint** (needs Auctionator): vendor price against auction price per unit, and which is higher. Raw prices; the auction cut is not modelled. Setting `Tooltip hint: vendor or auction house`.
- **`/rum buyback all`** buys back every logged sale still in the merchant's buyback list.
- **`/rum perf`:** window refresh time, inventory scan time, addon memory, cached character count.
- **Release tooling:** `tools/package.sh` builds the zip and `SHA256SUMS.txt`; `.github/workflows/ci.yml` runs the gate on every push and PR; `release.yml` builds and publishes a release when a `v*` tag matching the TOC version is pushed.
- **Already present, no change:** low-space warning, `/rum autoprofile set`, CSV export, reagent categories.

## 1.5.0 — 2026-11-08

Items marked *Unverified* depend on client behaviour I could not test; they are written defensively (existence checks + `pcall`) and degrade to doing nothing.

- New: **`/rum apicheck`** — lists which container, item, tooltip, secret-value and buyback APIs this client provides, required vs optional.
- Hardened: **secret-value safety** — tooltip item reads (counts, upgrade scan tooltip) go through `pcall` and `issecretvalue` / `canaccessvalue` guards and quietly skip when data is unreadable.
- New: **Shift-snap on the scale grips** (75 / 100 / 125 / 150 %) and a **live percent readout** while a grip is held.
- New: **Pending-layout badge** — a scale or layout change that has to wait for combat shows "Layout pending" and is applied when combat ends.
- New: **Per-view window size and scale** (General settings) — Bags, Bank and other-character views each remember their own geometry.
- New: **Keyboard navigation** — arrows, Page Up/Down, Home/End select a row; Enter uses the item; Space cycles its favorite marker. Off while typing in search and in combat; every other key is passed through. *Unverified* on Forever (`SetPropagateKeyboardInput`).
- New: **Colourblind-safe quality tags** — optional `[Rare]` / `[Epic]` text before item names (Appearance).
- New: **Stale-data cues** — other characters' menu entries show how long ago they were seen; data older than N days (default 14, 0 = off) is dimmed and marked "(stale)".
- New: **Junk-sale log and buyback shortcut** — `/rum junklog`, `/rum buyback [n]` (matches the logged link against the merchant's buyback list). *Unverified* on Forever's buyback API.
- New: **Sell safeguards** — a confirmation when a junk sale includes an Uncommon-or-better item (on by default) or is worth more than a gold threshold (off by default).
- New: **Saved searches** — "Save current search" in the history menu or `/rum savesearch`; up to 8 appear as chips above "+ New category"; right-click removes.
- New: **Inventory export** — `/rum inventory [csv|text]` opens a copy window with every cached character's bags, bank, equipped and mail.
- New: **Auto-profile by context** — `/rum autoprofile on|off|set <spec1-4|dungeon|raid|battleground|arena|world> <profile>|clear <context>` re-applies saved profiles on spec or zone-type change, out of combat only. *Unverified* (spec API names on Forever).
- New: **Upgrade popup stat diff** — "+12 Strength, -3 Stamina" versus the item you would replace, when the client provides item stats.
- New: **Shift-drag splits a stack** on the plain (non-secure) item buttons. The secure Blizzard buttons already split on Shift-click.
- New: **`/fdebug report` prints the bank path** (character bank tabs or legacy bank bags, with bag ids).
- Saved data upgraded to v4 (saved searches, junk log, context profiles, per-view sizes; existing data untouched).
- Under the hood: `UI.lua` is split into `UI.lua`, `UI_Window.lua` (scale/geometry), `UI_Menus.lua` (menus, popups, copy window) and `UI_Input.lua` (keyboard); the `UI` table is shared through `R.UI`. New `tests/` (Lua 5.1 + fake client) and `tools/check.py` gate script.

## 1.4.0 — 2026-11-08

- New: **Scale grips in both bottom corners.** Drag either bottom corner to scale the whole window — frame, rows, grid icons, buttons and text — together (0.5 – 2.0). The opposite bottom corner and the top edge stay where they are. Refused while the window is locked or in combat; releasing saves the scale and position, and the Scale setting follows.
- Changed: the old bottom-right size grip is now the right-edge (width) and bottom-edge (height) drag handles, so resizing the window still works. The footer moved right to clear the new left grip.
- Compatibility: reviewed against Forever beta build 1.60.1.70862 (interface remains 16001). Container, item and bank access still goes through `Compat.lua`; no code changes were needed for the new build. Not tested in the client.
## 1.3.0 — 2026-10-20

- New: **Profiles** — save the whole setup under a name (General settings) and re-apply it anywhere; optionally per-character, re-applied automatically at login.
- New: **Settings export / import** — one text string carries settings, column layout, custom categories and auto-junk rules (About tab, or `/rum export` / `/rum import`).
- New: **Auto-junk rules** — up to 8 search queries; anything matching counts as junk for display, totals and selling. Favorites are never junk by rule, and manual marks always win (Items & Junk settings).
- New: **Cross-character search** — the "All" button beside the tabs searches every character's cached bags and bank while you type; an Owner column (Columns tab) shows whose item it is. Results are view-only in this mode, so item actions can never touch another character's cached coordinates.
- New: **Search history** — the last 10 searches are kept under the arrow button at the right end of the search box.
- New: **Sort presets** — save named combinations of sort, grouping and view settings from the Preset button in the header.
- New: **Footer view totals** — the footer now shows the vendor value of everything currently listed, with the junk portion broken out.
- New: **Addon compartment entry** — Rummage now appears in the addon compartment (left-click bags, right-click settings).
- Saved data upgraded to v3 (profiles, search history, rules and presets added; existing data is untouched).
- Under the hood: the window chrome, minimap tooltip, settings tabs and slash usage now read from a single string table, so translations can be supplied as a `RummageLocales` global.

## 1.2.1 — 2026-10-20

Compatibility pass for Forever Beta build 1.60.1.70450. Behavior is unchanged.

- Verified against build 1.60.1.70450 (interface remains 16001). All container, item and bank access already goes through the `Compat.lua` shim layer, and nothing in the 70425 or 70450 builds changes those APIs — no code changes were needed for the new build.
- `/fdebug report` now prints the client version and build first, to make issue reports useful.

## 1.2.0 — 2026-10-15

- New: **Upgrade popup** — when you loot or receive gear that beats what you're wearing, a small movable popup offers one-click **Equip**
  - Uses Pawn when installed; otherwise compares item level, respecting armor type, dual-wield and two-handers
  - Skips gear you can't use (class, level, proficiency)
  - Picks the right slot (weaker ring/trinket, empty slots first)
  - Clicking in combat queues the swap for when combat ends
  - Queues multiple upgrades; auto-hides after a configurable time (pauses while hovered); right-click X to never suggest an item again
  - `/rum upgrade` previews the popup so you can move it
- New: **Remember last selected category** option (on by default), persists across sessions; replaces "Reset category when opened" (setting migrated automatically)

## 1.1.0 — 2026-10-15

Performance & hardening pass (see AUDIT.md).

- Fixed: options window leaked every widget on each theme change / reset
- Fixed: Scrap junk checks for alts and the cached bank used your live bag slots
- Fixed: corrupted or legacy SavedVariables could throw; full sanitizer with type checks and clamping
- Async item data: explicit `C_Item.RequestLoadItemDataByID`, refresh only when requested items arrive
- Garbage per refresh cut from 212 KB to 6 KB (entry/display pooling, scratch tables, memoization)
- No re-anchoring on refresh unless geometry changed; item buttons diffed instead of hidden/shown
- Lock/cooldown updates coalesced per frame; resize and option-slider updates coalesced
- Startup events unregister after use
- Remaining bare globals shimmed through C_Container / C_AddOns
- New: `/fdebug` (or `/rum debug`) diagnostics overlay — memory, frame time, event rates, timings

## 1.0.0 — 2026-10-15

First release.

- List view and grid view for bags, keyring and bank in one window
- Sortable, reorderable, resizable columns: favorite, icon, name, quantity, item level, required level, type, subtype, slot, binding, vendor value, age, bag, junk
- Category sidebar with live counts, sub-filter chips, custom categories from search queries
- Search language: text, fields with comparisons/ranges, keywords, AND / OR / NOT
- Grouping (category, type, quality, bag) with collapsible headers; stack combining
- Favorites (8 markers), new-item tracking, acquisition age, unusable tint, quest badges, cooldowns
- Cached bags, bank, equipped, mail and gold for all characters; character browser; cross-character tooltip counts
- Classic bank bags (incl. slot purchase) and modern bank tabs
- Junk marking (own rules or Scrap), one-click / automatic selling, favorite protection, buyback-safe mode, auto-repair
- Restack, Blizzard sort, transfer filtered items bags ⇄ bank, empty a bag, drop-to-free-slot
- Replaces Blizzard bags (incl. one-bag mode) and bank; per-context auto-open
- Open All Bags / bag keys routed to Rummage via override bindings; dedicated keybinds
- Conflicting bag addon detection with Disable & Reload
- Themes: Forever (default, native Blizzard frame art), ElvUI (live colors), EllesmereUI, GW2 UI, Tukui, NDui, Minimal Dark, Parchment, Classic Tooltip; Auto theme; LibSharedMedia fonts; class accent
- Integrations: Auctionator, TradeSkillMaster, Pawn (arrow + upgrade %), Can I Mog It?, Scrap, Syndicator, LibDataBroker, LibDBIcon
- Minimap button, settings window, Blizzard AddOns settings entry, slash commands
