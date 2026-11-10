# Rummage

**List-view bag & bank replacement for WoW Forever — by Malikor.**

Store-listing copy prepared 2026-10-24 from the shipped 1.3.0
README and CHANGELOG.

---

Your bags are a database. Why are you reading them as a grid of
icons? Rummage puts every item you own into one sortable table:
full item names, item level, required level, type, vendor value,
auction prices, Pawn upgrades and more. Filter by category in one
click, search with a real query language, browse any character's
bags and bank from anywhere, and sell junk in one click.

## Why you'll like it

- **Find anything instantly.** A category sidebar with live
  counts, custom categories built from searches, and a query
  language that understands `ilvl>20`, `q>=uncommon`, `ah>50s`,
  `#fav`, AND / OR / NOT — plus your last 10 searches, one click
  away.
- **Every character, one search.** Rummage caches bags, bank,
  equipped items, mailbox and gold for all your characters. Hit
  **All** and search across all of them, with an Owner column
  showing whose item it is. Tooltips show counts on every
  character too.
- **Junk handles itself.** Greys are junk by default; add up to 8
  auto-junk rules written in the same search language and anything
  matching counts as junk — favorites never do, and your manual
  marks always win. One click sells it all, with an optional
  buyback-safe mode.
- **Upgrades announce themselves.** Loot something better than
  what you're wearing and a small popup offers one-click Equip —
  Pawn-powered when installed, sensible item-level logic
  otherwise, queued politely until combat ends.
- **Set it up once, take it anywhere.** Named profiles (optionally
  per-character), sort presets, and one-text-string export/import
  of your whole setup — settings, columns, custom categories and
  junk rules included.
- **Plays well with others.** Optional integrations for
  Auctionator, TradeSkillMaster, Pawn, Can I Mog It?, Scrap and
  Syndicator; themes that match ElvUI, EllesmereUI, GW2 UI, Tukui
  or NDui; and login-time detection of conflicting bag addons with
  a one-click Disable & Reload offer.

## How to use it

1. Extract the `Rummage` folder into
   `World of Warcraft\_classic_beta_\Interface\AddOns\` and
   `/reload`.
2. Open your bags as usual — Rummage replaces the Blizzard bags
   and bank, and your Open All Bags keybind keeps working.
3. Type in the search box to filter; click column headers to
   sort; `/rum config` opens settings, `/rum export` copies your
   setup as text.

Good to know: item changes that happen during combat are applied
when combat ends; guild bank and equipment sets are not shown
(WoW Forever has neither); and cross-character search results are
view-only, so an action can never touch another character's cached
items.

Rummage is by Malikor, GPLv3 or later. It brings together the
feature sets of Sorted and its plugins in a single addon, plus
Baganator/Syndicator-style cross-character tracking. 1.5.0 added keyboard navigation, saved searches, a junk-sale log with buyback, sell confirmations, inventory export, auto-profiles by spec/zone, an upgrade stat diff and `/rum apicheck`. 1.6.0 adds mail-expiry warnings, gold history and a sell hint.

**Status note:** 1.5.0 was verified in game on Forever 1.60.1.70862. 1.6.0 added mail-expiry warnings, gold history, a vendor-or-AH tooltip hint, `/rum perf` and `/rum buyback all`; 1.7.0 allows much wider windows and resizable columns (Name included); 1.7.1 makes settings tabs scroll; 1.8.0 opens the Bank in its own window so items can be dragged between Bags and Bank; it passes the offline test suite (`tests/`) and is not yet run in game.
