# Rummage vs other bag addons (2026-11-15)

Basis: Rummage 1.8.1 source (24 files, ~9k lines) read in full for the core modules
(Core, Data, Items, Search, Categories, Junk, Mover, Hooks, Integrations) and by
search for the UI; the offline suite (28 cases) run before and after. Competitor
features come from their CurseForge / Wago pages and my own knowledge of them, not
from installing them. Nothing here was checked in the game client.

## Where Rummage stands

Rummage already matches or beats the field on: list view (only Sorted has one),
search language (on par with Baganator, ahead of Bagnon/BetterBags), cross-character
browsing and tooltip counts (Baganator/Syndicator level), junk handling (Scrap-level,
plus rules, sale log, buyback and safeguards), auction/TSM/Pawn/CanIMogIt columns,
upgrade popup, themes for the big UI suites, profiles and export strings, offline tests.

## Feature matrix

✓ has it · ~ partly · – no

| Feature | Rummage 1.8.1 | Baganator | Bagnon | BetterBags | AdiBags | ArkInventory | Sorted |
|---|---|---|---|---|---|---|---|
| List / table view | ✓ | – | – | – | – | ~ | ✓ |
| Category sections | ✓ (group by) | ✓ | – | ✓ | ✓ | ✓ | ✓ |
| Search language (& \| !, ranges) | ✓ | ✓ | ~ | ✓ | ~ | ✓ | ~ |
| Alts' bags / bank / mail anywhere | ✓ | ✓ | ✓ | – | – | ✓ | ✓ |
| Guild bank view | – | ✓ | ✓ (plugin) | ✓ | – | ✓ | ✓ |
| Currencies shown | **– → ✓ 1.9.0** | ✓ | ✓ | – | – | ✓ | ✓ |
| Equipment sets | **– → ✓ 1.9.0** | ✓ | – | ✓ | ✓ | ✓ | ✓ |
| Transfer to bank | ✓ | ✓ | – | – | – | – | – |
| Transfer to mail / trade / vendor | **– → ✓ 1.9.0** (mail, trade) | ✓ | – | – | – | – | – |
| Plugin API for other addons | **– → ✓ 1.9.0** | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| Drag an item onto a category | – | – | – | ✓ | ✓ | ✓ | – |
| Sort ignoring chosen slots | – | ✓ | – | – | – | ✓ | – |
| Icon corner badges, configurable | ~ (fixed) | ✓ | ~ | ~ | ~ | ✓ | – |
| Gamepad support | – | ✓ (Forever) | – | – | – | – | – |
| Junk rules / sale log / buyback | ✓ | – | – | ~ | ~ | ~ | ✓ |
| Upgrade popup with one-click equip | ✓ | – | – | – | – | – | – |
| Offline test suite | ✓ | ~ | – | ~ | – | – | – |

## Audit findings (fixed in 1.9.0)

| # | File | Problem | Fix |
|---|---|---|---|
| A1 | `Junk.lua` SellAll | The sale runs 10 items per 0.25 s tick from a list built up front. An item moved into a listed slot mid-sale would be sold, even an epic. | Each slot is re-checked (same link, not locked) right before `UseContainerItem`; chat reports the real count and value. |
| A2 | `Junk.lua` Buyback all | `BuybackItem` is answered by the server later, so the list doesn't shrink between calls. Two log entries with one link both matched slot *b*; the second call could buy whatever shifted into *b*. | Plan first, claim each buyback slot once, buy highest index first. |
| A3 | `Junk.lua` AutoRepair | Guild repair ignored the daily withdraw limit: the repair failed silently and still printed "Repaired with guild funds". | Uses guild funds only when `GetGuildBankWithdrawMoney()` covers the cost (or is unlimited); otherwise own gold. |
| A4 | `Integrations.lua` CanIMogIt | Alt and cached-bank rows passed their bag/slot to Can I Mog It?, which reads *your current* bags there (the 1.1.0 Scrap bug, again). | Entries carry `live`; bag/slot only go out for live views. |
| A5 | `Core.lua` ImportSettings | Category import stopped at the first missing index, dropping everything after it. | Walks the present indices in order. |
| A6 | `Search.lua` | Text terms lower-cased type, subtype and slot per item per refresh. | Lower-case copies stored once in the item-info cache. |

Not changed (noted only): `#upgrade` needs Pawn (the popup's item-level fallback isn't
used by search); `#usable` checks level only, not armor/weapon proficiency; search has no
quoted phrases or parentheses; `UI.lua` is still ~2k lines.

## Features adapted in 1.9.0

1. **Transfer to mail / trade** (from Baganator). The Transfer button becomes *To Mail* /
   *To Trade* when the Send Mail tab or a trade is open, and attaches the listed items
   with `PickupContainerItem` + `ClickSendMailItemButton` / `ClickTradeButton`, one per
   0.15 s tick, re-checking each slot. Bound items are skipped; it stops when full.
   Vendor transfer was left out: selling non-junk in bulk is risky and Sell Junk covers the safe case.
2. **Tracked currencies** (Sorted, Bagnon, Baganator, ArkInventory). Up to three
   "Show on backpack" currencies in the Bags footer, cached per character.
3. **Equipment sets** (Sorted, AdiBags, ArkInventory, Baganator). `#set`, `set:name`;
   set items are never sold as junk. Uses `C_EquipmentSet` or the classic functions.
4. **Plugin API** (BetterBags, AdiBags, Baganator):

   ```lua
   Rummage:RegisterSearchKeyword("cheap", function(e) return (e.info and e.info.sell or 0) < 100 end)
   Rummage:RegisterCategory("cheap", "Cheap", "Interface\\Icons\\INV_Misc_Coin_01",
     function(e) return Rummage.Search:Matches("#cheap", e) end)
   Rummage:RegisterColumn({ key = "double", title = "x2", value = function(e) return e.count * 2 end })
   ```

   Plugin functions run under `pcall`; built-in keywords can't be overridden.

## Suggested next (not done)

| Idea | From | Why not now |
|---|---|---|
| Guild bank view (live + cached) | Baganator, Bagnon, Sorted, ArkInventory | **Added in 1.9.0** (Guild Bank window); must be checked in game. |
| Gamepad navigation | Baganator (Forever) | Forever ships gamepad support; builds on the 1.5.0 keyboard nav, but needs a controller to test. |
| Drag an item onto a sidebar category to file it there | BetterBags, AdiBags, ArkInventory | Needs item-list categories alongside the query-based ones. |
| Ignore chosen slots in sort | Baganator, ArkInventory | Only matters for the Blizzard sort button; Rummage's list is always sorted. |
| Configurable icon-corner badges in grid view | Baganator | Cosmetic; grid view is secondary to the list. |
