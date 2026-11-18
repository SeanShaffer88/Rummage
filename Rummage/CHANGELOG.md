# Changelog

## 1.10.1 — 2026-11-18

- **Resize the Name column.** Its flexible header now exposes the same drag handle as other resizable columns; double-click resets it to fill the remaining space.
- **Use bag items with right-click.** Register both click buttons explicitly on the secure item buttons.
- **Close auto-opened bags when leaving vendors or auction houses.** Handles the close events and modern interaction-manager hide event; manually opened bags stay open.

## 1.10.0 — 2026-11-16

Passes the offline suite (55 cases); not yet run in game.

**New**
- **Drag an item onto a category.** Drop an item (from Bags, Bank or Guild Bank) on one of your own categories in the sidebar and it belongs there from then on, whatever the category's filter says; the item itself goes back where it came from. Drop it on **+** to start a new category holding just that item. A category with added items and no filter shows only those items. Right-click a category to see its added items and remove them (one at a time or all). Built-in categories don't take items and say so. Added items are part of settings export/import.
- **Search groups and phrases.** `( )` groups terms, `!` negates a group, and `"quoted text"` keeps its spaces: `(q:rare | q:epic) ilvl>20`, `!(#junk | q:poor)`, `name:"of the bear"`. A quoted term is always plain text. Existing searches work as before.

**Changed**
- **`#upgrade` works without Pawn.** With *Judge by item level without Pawn* on, it uses the upgrade popup's rules: higher item level than what you wear in that slot, or an empty slot, for gear you can use (armor type, dual-wield and two-handers handled). Pawn still decides when installed.
- **`#usable` checks more than level.** Class, armor and weapon proficiency and profession requirements count too, read from the red text in the item's tooltip (cached per item until you level, learn a skill or change talents). *Tint items you can't use* uses the same check.

**Code**
- `UI.lua` (about 2,400 lines) is split: item rows, grid and secure buttons in `UI_Rows.lua`, the sidebar and chips in `UI_Sidebar.lua`, the footer in `UI_Footer.lua`. Shared layout constants live in `R.UIK`.

## 1.9.2 — 2026-11-16

Fixes from in-game screenshots of 1.9.1. Passes the offline suite (50 cases); not yet run in game.

- **Name column fills the window again.** Columns were measured right after the list was re-anchored, before its new width applied, so Name stayed at its 80px minimum ("Patchwork…") and the space to the right was left empty. Columns are now recomputed once the list's real width is known.
- **Settings labels stay inside their column.** "Guild vault (opens Guild Bank window)" ran past the panel edge; the auto-open entries are now *Banker* and *Guild vault*, with the detail in their tooltips, and long checkbox labels are clipped.
- **Guild Bank without a guild** says "You're not in a guild." instead of asking you to visit your guild bank.

## 1.9.1 — 2026-11-16

Fixes from the first in-game look at 1.9.0 on Forever 1.60.1.70938 (`/rum apicheck`: every guild bank API is present). Passes the offline suite (49 cases); the changes themselves are not yet run in game.

- **Categories as an icon rail.** The sidebar shows category icons only, larger, with the item count as a badge and the name in the tooltip; the selected category is highlighted in the accent colour. Saved searches become numbered stubs (the search is in the tooltip) and "+ New category" a "+" button. On by default and switched on once for existing settings (database v5); *Categories as icons only (names on hover)* in Appearance brings the labels back.
- **Bank and Guild Bank rail on the outer edge.** Docked beside Bags, they keep their icon rail on the side away from Bags, so the item lists face each other where you drag items. Bags keeps its rail on the left.
- **Bank and Guild Bank open beside Bags.** They now open right next to the Bags window wherever it is (left if there's room, else right, never on top of each other), with the same height and scale as Bags and no wider than it. Opening Bags pulls an already-open Bank or Guild Bank beside it. Setting: *Open Bank and Guild Bank beside Bags* (General); off keeps the old behaviour (where you last left them).
- **No more overlapping text in Bags.** The search hint is clipped to the search box (it ran over the Preset button once the Bank/Guild buttons made the box narrower), column headers are clipped to the list, and columns that don't fit a narrow window are left out instead of being drawn over the scrollbar and the window edge.
- **Guild Bank names your guild** before its bank is cached, instead of "No guild": guild info arrives after login and the window now redraws when it does.

## 1.9.0 — 2026-11-15

Audit against the other bag addons (Baganator, Bagnon, BetterBags, AdiBags, ArkInventory, Sorted, Combuctor, LiteBag); report in `docs/COMPARISON.md`. Passes the offline suite (45 cases); not yet run in game.

**Fixes**
- **Junk sale re-checks each slot.** Selling runs over several ticks; an item moved into a slot after the junk list was built could be sold. Each slot is now checked against the listed item right before selling, and the chat total reports what was really sold (and says so when the merchant closed early).
- **`/rum buyback all` buys each item once.** Buyback is answered by the server later, so two log entries with the same link could both hit the same buyback slot and then buy whatever shifted into it. The plan is now made first, each slot is claimed once, and the highest slot is bought first.
- **Guild repair honours the withdraw limit.** When the guild's daily limit doesn't cover the cost, auto-repair now uses your own gold instead of failing and printing "Repaired with guild funds".
- **Can I Mog It? on alts and the cached bank** no longer receives the current character's bag/slot (same class of bug as the 1.1.0 Scrap fix).
- **Settings import** no longer drops every custom category after a gap in the numbering.
- **Search** no longer lower-cases type/subtype/slot per item per refresh (precomputed once per item).
- **"Toggle bank" key binding** opened the Bags window instead of the Bank window since 1.8.0.

**New**
- **Transfer to mail or trade.** With the Send Mail tab or a trade window open, the footer's Transfer button reads *To Mail* / *To Trade* and adds the listed items (after search and filters) until the window is full. Bound items are skipped. Setting: *Transfer to an open mail or trade window*.
- **Tracked currencies.** Up to three currencies marked *Show on backpack* appear in the Bags footer, cached per character so alts show theirs. Setting: *Show tracked currencies in the footer*.
- **Equipment sets.** `#set` matches items in any equipment set and `set:name` items in a matching set. Items in an equipment set are never sold as junk. *Unverified*: which equipment-set API Forever provides (`/rum apicheck` lists it).
- **Plugin API** on the global `Rummage` table: `RegisterSearchKeyword`, `RegisterCategory` / `UnregisterCategory`, `RegisterColumn`, `GetAPIVersion`. Plugin functions run under `pcall`; built-in keywords can't be replaced.
- `/rum apicheck` also reports the equipment-set, currency, mail/trade and guild-withdraw APIs.

**Guild Bank window** (the largest gap in `docs/COMPARISON.md`). *Unverified in game*: whether Forever provides the guild bank APIs at all (`/rum apicheck` lists each one; without them the window stays empty and Blizzard's frame is untouched).
- **Its own window, like the Bank.** Opening the guild vault opens the Guild Bank window and, if it was closed, Bags beside it (Guild Bank defaults to the left of Bags). Items can be dragged between Bags, Guild Bank and Bank. Blizzard's guild bank frame is hidden. Closing the Guild Bank window closes the vault; closing Bags doesn't. Leaving the vault closes the Guild Bank window, and Bags too if the visit opened it.
- **Own geometry.** Position, size, scale and per-view layout are stored under `guild` in the saved settings; `/rum reset` and *Reset Guild Bank window position* reset it.
- **Tabs.** A tab selector in the header (each tab with its icon and used/total slots, or *All tabs*), and the footer shows one icon per tab: click to show only that tab, click again for all. Selecting a tab also selects it in the vault. Tabs you can't view are marked *(no access)*.
- **Deposit.** Drop an item from Bags anywhere on the Guild Bank window (or on a tab icon) and it goes into the first free slot of that tab, or of the vault's current tab while showing all tabs. Tabs without deposit rights, full tabs and tabs still loading are reported in chat.
- **Withdraw.** Click or drag an item to pick it up, then drop it on Bags or a bag slot. Right-click withdraws straight into the bags (configurable). The daily withdrawal limit of each tab is respected (and counted down locally until the server answers), and full bags are reported.
- **Cached per guild.** Every tab is queried once per visit, one at a time, and stored per guild in `RummageDB.guilds` (sanitized at load). Away from the vault the window shows the cache, view-only, with its age in the footer. The guild button lists every cached guild; the X next to one forgets it.
- **Tooltips** list the count in each cached guild bank under the character counts.
- **Settings** (General tab, *Guild bank*): replace Blizzard's guild bank, open automatically at the vault, also open Bags beside it, open on the current tab or all tabs, right-click action (withdraw to bags / pick up / nothing), withdrawals left in the footer, guild counts in tooltips.
- `/rum guild` (or `/rum gbank`), a key binding and Ctrl-click on the minimap button toggle the Guild Bank window.

**Bank and Guild Bank anywhere.**
- The Bags header has **Bank** and **Guild** buttons that open those windows beside Bags (and light up while open). Away from a banker or the guild vault they show the cached contents, view-only, with a *Cached bank* / *Cached guild bank* footer note. Nothing is queried or moved while away; dropping an item on a cached window prints a hint instead.
- With nothing cached (or no guild) the Guild Bank window says so, like the Bank window does.
- Each character remembers its guild, so browsing an alt in Bags shows that alt's guild bank in the Guild Bank window.

## 1.8.1 — 2026-11-10

- **Fix:** opening a window in combat raised ADDON_ACTION_BLOCKED (`SetPropagateKeyboardInput`). Keyboard calls are now skipped in combat; navigation stays off there as before.

## 1.8.0 — 2026-11-09

The Bank is now its own window, so items can be dragged from Bags to Bank and back. Passes the offline suite (28 cases); not yet run in game.

- **Separate Bank window.** Visiting a banker opens the Bank window and, if it was closed, the Bags window beside it (Bank defaults to the left of Bags). Drag an item from one window onto empty space in the other, or right-click it to move it across as before. `/rum bank` and Shift-click on the minimap button toggle the Bank window.
- **Independent geometry.** Each window keeps its own position, size, scale and per-view layouts (the Bank window's live under `bank` in the saved settings). Scale grips, edge handles and column resizing work in both. `/rum reset` and the settings button reset both.
- **One tab per window.** Bags shows "Bags", Bank shows "Bank". Browsing another character or cross-character search still works in each.
- **Closing.** Closing the Bank window closes the banker; closing Bags leaves the bank open. Leaving the banker closes the Bank window, and Bags too if the visit opened it.
- **Keyboard navigation** follows the mouse while both windows are open.
- **Internals.** The window code is built once per window (`UI_Boot.lua`); popups act on the window that raised them.

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
