# Rummage — Features

The full feature list for Rummage 1.3.0 for WoW Forever
(Interface 16001). For the short version see `README.md`; for
store-listing copy see `DESCRIPTION.md`.

Prepared 2026-10-24 from the shipped 1.3.0 README and CHANGELOG.
Rummage is by Malikor, GPLv3 or later.

## The window

- **One window for bags, keyring and bank**, with Bags / Bank tabs.
- **List view** (a configurable table) or **grid view** (icons with
  item level, count, favorite, junk, upgrade and quest badges).
- Sort by any column; favorites and/or new items pinned on top.
- Show, hide, reorder and resize columns (drag a header edge;
  right-click a header to toggle).
- Group by category, type, quality or bag, with collapsible group
  headers. Identical stacks can combine into one row.
- Movable, resizable, scalable, lockable; opacity control.

## Finding things

- **Category sidebar** — All, Favorites, New, Equipment,
  Consumables, Trade Goods, Recipes, Quest Items, Bags & Ammo,
  Keys, Miscellaneous, Junk — with live counts, plus sub-filter
  chips per category (e.g. Cloth / Leather / Herb).
- **Custom categories** built from search queries.
- Click a bag icon to show only that bag. The last selected
  category is remembered, even across sessions.
- The search box remembers your **last 10 searches** (1.3.0).
- **Search all characters** (1.3.0): the "All" button beside the
  tabs makes searches run across every character's cached bags and
  bank, with an optional Owner column. Results are view-only in
  this mode.
- **Sort presets** (1.3.0): named combinations of sort, grouping
  and view settings, saved from the Preset button.
- The footer shows the **vendor value of the current view**
  (1.3.0), with the junk portion broken out.

### Search syntax (combine freely)

| Example | Meaning |
|---|---|
| `linen` | name, type, subtype or slot contains "linen" |
| `ilvl>20`, `ilvl:10-20`, `lvl<=30` | item level / required level |
| `q:rare`, `q>=uncommon` | quality (poor, common, uncommon, rare, epic, legendary) |
| `type:armor`, `sub:cloth`, `slot:head` | item type / subtype / equip slot |
| `count>5`, `bag:2` | stack size / bag number |
| `value>1g`, `ah>50s`, `tsm>2g`, `pawn>5` | vendor, Auctionator, TSM value; Pawn upgrade % |
| `#fav #new #junk #upgrade #boe #bop #bound #gear #consumable #quest #trade #recipe #key #usable` | keywords |
| `a b` / `a & b` | AND |
| `a \| b` | OR |
| `!term` | NOT |

## Items

- **Favorites** with 8 raid-marker icons (star column, or Alt+click).
- New-item highlighting and a "time since acquired" column.
- Required-level tint for gear you can't use yet; quest-starter
  badges; cooldown swipes and locked-item dimming.

## Upgrade popup

- When you loot or receive gear that's an upgrade, a small movable
  popup offers one-click **Equip**. Pawn decides when installed;
  otherwise item level for your armor type (dual-wield and
  two-handers handled).
- Gear you can't use is skipped; rings and trinkets go into your
  weaker slot. Clicking during combat equips as soon as combat
  ends. Auto-hides after a configurable time (pauses while
  hovered); right-click the X to never suggest that item again.

## Characters & bank

- Cached bags, bank, equipped items, mailbox and gold for every
  character. Browse any character from the name button; forget old
  characters from there.
- Gold tooltip with every character and the account total.
- Item tooltips show counts on all characters (bags / bank /
  equipped / mail).
- Supports both classic bank bags (with slot purchase) and modern
  bank tabs.

## Junk, merchants, moving items

- Grey items are junk by default; mark or unmark anything (coin
  column or Alt+right-click).
- **Auto-junk rules** (1.3.0): up to 8 search queries — anything
  matching counts as junk. Favorites are never junk by rule;
  manual marks always win.
- One-click **Sell Junk** or auto-sell; favorites are never sold;
  optional buyback-safe mode (max 12).
- Auto-repair (guild funds first, if available).
- **Restack** partial stacks; Blizzard sort when the client
  provides it.
- **Transfer**: moves everything currently listed (after search
  and filters) between bags and bank. **Empty a bag** by
  right-clicking its icon. Drop the cursor item onto empty list
  space to put it in a free slot. Low-bag-space warning.

## Blizzard integration

- Replaces the Blizzard bags (including one-bag mode) and bank
  window. Your **Open All Bags** keybind (and optionally Backpack /
  Bag 1–5 keys) opens Rummage via override bindings, so your saved
  keybinds are never changed.
- Dedicated keybinds: toggle bags, toggle bank, focus search.
- Per-context auto-open: merchant, mailbox, auction house, trade,
  bank.
- Minimap button (LibDBIcon if present), LibDataBroker launcher,
  and an addon-compartment entry (1.3.0).

## Profiles & sharing (1.3.0)

- Save your whole setup as named **profiles**; optionally
  per-character, so each character re-applies its profile at login.
- **Export / import** the whole setup (settings, columns, custom
  categories, auto-junk rules) as one text string — About tab in
  settings, or `/rum export` / `/rum import`.

## Conflict protection

- On login Rummage detects other bag addons and the ElvUI / NDui
  bag modules, warns in chat, and offers **Disable & Reload**.
  Syndicator and BagSync are not bag replacements and are left
  alone.

## Themes

Forever (Blizzard) by default; ElvUI, EllesmereUI, GW2 UI, Tukui
and NDui themes read the installed suite's live colors and fonts;
Minimal Dark, Parchment and Classic Tooltip extras. **Auto** picks
the matching theme when a suite is installed. Fonts: theme
default, built-in WoW fonts, or any LibSharedMedia font, with an
optional class-colored accent.

## Integrations (all optional, auto-detected)

Auctionator (price columns, `ah>` search), TradeSkillMaster (any
custom price source, `tsm>` search), Pawn (upgrade arrow and %,
`pawn>` search), Can I Mog It? (transmog status), Scrap (junk
list), Syndicator (tooltip counts step aside).

## Commands

`/rum` toggle bags · `/rum bank` · `/rum search <text>` ·
`/rum config` · `/rum restack` · `/rum sell` · `/rum conflicts` ·
`/rum keys` · `/rum upgrade` · `/rum export` · `/rum import` ·
`/rum reset`. Diagnostics: `/fdebug` overlay and `/fdebug report`.

**Status note:** 1.3.0 is built but not yet verified in game;
1.2.1 is the version verified live (Forever beta build
1.60.1.70450, compatibility pass — behavior unchanged from 1.2.0).
