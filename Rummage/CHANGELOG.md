# Changelog

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
