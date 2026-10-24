# Rummage 1.1.0 — Audit & Optimization Report

Target: WoW Forever beta (Mainline UI tree, Lua 5.1, `## Interface: 16001`).
Method: line-by-line review, then every file loaded and exercised under a real Lua 5.1 VM against a mocked WoW API (33-step gameplay scenario, combat-lockdown suite, modern bank-tab client suite, corrupted-SavedVariables suite) and an allocation profiler with the GC stopped.

## 1. Critical bugs (fixed)

| # | Area | Problem | Fix |
|---|---|---|---|
| C1 | Options | Every theme change / "Reset all settings" rebuilt all option pages. WoW frames can never be freed, so each rebuild permanently leaked ~150 widgets and grew the global button registry. | Pages are built once; `O:Rebuild()` now refreshes colors/labels/values in place. |
| C2 | Junk / Scrap | For alts and the cached bank, Scrap was asked about *your live* bag/slot coordinates, producing wrong junk marks. | Scrap only receives coordinates for live (interactive) views. |
| C3 | SavedVariables | Defaults were only filled when `nil`; wrong-typed or legacy values (e.g. `scale="x"`, numbers in `columns.order`, malformed slot records) would throw during layout. | Full sanitizer: type-checks every setting, clamps numeric ranges, validates enums, de-duplicates column order, validates every character/container/slot/mail record, favorites (1-8), junk overrides (boolean), categories. DB schema version → 2. |
| C4 | Mover | Transfers stored references to entry `{bag,slot}` tables; with entry pooling these are recycled mid-transfer. | Values are copied when the transfer starts. |

## 2. API compatibility & deprecations

- Every container/item/addon call goes through `Compat.lua`, preferring `C_Container`, `C_Item`, `C_AddOns` and falling back to legacy globals only when the namespace function is absent. Newly shimmed this pass: `PickupBagFromSlot`, `PutItemInBag`, `PutItemInBackpack`, `GetContainerItemQuestInfo`, `GetAddOnMemoryUsage`, `UpdateAddOnMemoryUsage`.
- Tooltips: `TooltipUtil.GetDisplayedItem` + `TooltipDataProcessor` on Mainline; `OnTooltipSetItem` only when the script exists.
- Bank: both legacy bank bags (`-1`, `5..N`) and Mainline bank tabs (`Enum.BagIndex.CharacterBankTab_N`) are supported.
- `C_Spell` is not used (the addon reads no spell data), so no spell shims are required.
- **Async item data:** missing items are now requested explicitly with `C_Item.RequestLoadItemDataByID`, tracked in a pending set, and only *those* IDs arriving (`GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT`) trigger one coalesced refresh. Previously any addon's item loads caused Rummage refreshes. All item-info consumers nil-check and render a link-derived fallback name until data arrives.

## 3. Combat lockdown & taint review

| Action | Protection |
|---|---|
| Creating Blizzard item-button templates | Skipped in combat (returns nil; row is non-interactive until combat ends). |
| Re-anchoring item buttons | If the client marks them protected, Refresh/Render are deferred and replayed on `PLAYER_REGEN_ENABLED`; lock/cooldown state still updates in place. |
| `SetOverrideBinding` / `ClearOverrideBindings` | Deferred until `PLAYER_REGEN_ENABLED`. |
| Item moving (restack / transfer / empty bag) | Refuses to start in combat; stops if combat begins. |
| Blizzard functions | Only `hooksecurefunc` / `HookScript`; no global function is replaced. |
| Blizzard bag frames | Hidden from their own `OnShow` (non-protected frames). |
| `BankFrame` | Re-parented to a hidden frame + legacy events unregistered. Residual low risk: the UI panel manager still counts it as an open panel while you're at a banker (cosmetic positioning of other panels only). |

## 4. Garbage collection & memory

Measured with the GC stopped, 180 occupied slots, Lua 5.1 VM:

| Operation | Before | After |
|---|---|---|
| Full refresh | 212 KB | **6.3 KB** |
| Render visible rows | 16.4 KB | **6.2 KB** |
| Bag update (scan + totals) | 28.8 KB | **13.6 KB** (remainder = tables returned by `C_Container.GetContainerItemInfo`, unavoidable) |
| Lock/cooldown update | 4.9 KB | **0** |
| Tooltip counts (per tooltip refresh) | 0.6 KB | **0** |

Changes:
- **Entry pooling:** entries, slot lists and `{bag,slot}` pairs are recycled between refreshes (`Items.lua`).
- **Scratch tables:** search/category/subfilter/final arrays and category counts are module-level and wiped, never reallocated.
- **Display pooling:** group headers, groups and grid rows are pooled.
- **Scans reuse slot tables:** unchanged slots are updated in place; tooltip-based bind detection runs only for items new to a slot.
- **Double-buffered totals** for new-item detection.
- **Memoized:** sort comparator, category objects, group labels, money strings, tooltip lines (until data changes), character list.
- **Bounded caches:** item info (5,000 links), compiled searches (300), money strings (2,000).
- Hot-path globals cached as file-level upvalues (`pairs`, `ipairs`, `wipe`, `math.floor`, `table.sort`, `InCombatLockdown`, …).

## 5. Frame engine & render loop

OnUpdate audit — every handler is either hidden when idle or only exists during a drag:

| Handler | Behavior |
|---|---|
| Core scheduler | Shown only while jobs are queued; runs once, hides itself. |
| Mover | Shown only while moving items; accumulator-throttled (`wait`) and lock-aware. |
| Column resize | Script attached on mouse-down, removed on mouse-up. |
| Minimap drag | Script attached on drag start, removed on drag stop. |
| Debug overlay | Exists only while `/fdebug` is on. |

Redraw changes:
- Refresh no longer re-anchors anything unless geometry inputs changed (`LayoutIfChanged`); header arrows update only when the sort changes.
- Row cells are re-anchored only when the column layout version changes.
- Item buttons are diffed between renders: unchanged buttons are untouched, moved ones re-anchored, departed ones hidden — no Hide/Show churn on Blizzard templates.
- Window resize: `OnSizeChanged` coalesced to one layout per frame.
- `ITEM_LOCK_CHANGED` / `BAG_UPDATE_COOLDOWN` (fires every GCD) coalesced to one pass per frame.
- Refresh rate-limited to ~12/s; options sliders coalesce re-skins per frame.

Timing (Lua 5.1, 180 items): refresh 1.68 → 1.39 ms, render 0.35 → 0.18 ms.

## 6. Events & state

- `ADDON_LOADED` unregisters after Rummage's own load; `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD` are one-shot (`R:RegisterEventOnce`).
- Event handler lists are copy-on-write, so handlers can unregister themselves mid-dispatch safely.
- Unknown events on this client are ignored instead of erroring.
- `COMBAT_LOG_EVENT_UNFILTERED` is not used.

## 7. Lua 5.1 compliance

No `goto`, no `//`, no bitwise operators (uses `bit.band`), no `_ENV`, no integer-division or 5.3 syntax. Verified by compiling every file with Lua 5.1 `loadstring` and running the full suites on a Lua 5.1 VM.

## 8. Diagnostics

`/fdebug` (or `/rum debug`) toggles an overlay; `/fdebug report` prints to chat; `/fdebug reset` clears counters. Shows addon memory (sampled every 5 s — `UpdateAddOnMemoryUsage` is expensive), Lua heap growth per second, frame time avg/max and hitches > 50 ms, top events/s and internal messages/s, profiled timings for Refresh / Render / ScanBag, pool and cache sizes, pending item loads, and CPU time when `scriptProfile` is enabled. Counters cost one boolean check when off.

## 9. Not verifiable outside the client

The mock cannot prove Blizzard-template behavior. Verify in game: item clicks/drags/selling through the list, the bank window replacement, and the keybind takeover.
