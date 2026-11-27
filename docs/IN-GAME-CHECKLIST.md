# In-game test checklist (1.14.0)

Nothing from 1.9.0 to 1.14.0 has been run in the game; the offline suite can't show server
replies, taint, secure buttons or real layout. This list puts the checks that can lose,
sell or misplace items first. `docs/FOREVER-MANUAL-CHECKLIST.md` keeps the detailed
pass/fail table for buyback, bank, mail and trade edge cases.

Mark each line ✅ pass, ❌ fail (write what happened) or ⏭ skipped.

## 0. Before you start

- [ ] Back up `WTF/Account/<account>/SavedVariables/Rummage.lua` (and the per-character file if present).
- [ ] Note the client build: `/run print(GetBuildInfo())`.
- [ ] `/rum apicheck` and keep the output. Anything listed as missing explains later failures.
- [ ] `/console scriptErrors 1` (or BugSack) so Lua errors show.
- [ ] Use a character with a few vendor greys, some cheap stackables (cloth, food) and one
      item you don't mind losing. Keep anything valuable in the bank while testing sales.

## 1. Selling and buyback (can sell the wrong item)

- [ ] At a vendor, **Sell Junk**: only greys and items your junk rules match are sold; chat
      total matches the gold you gained.
- [ ] During a sale, move an item into a slot that was just emptied: it is **not** sold.
- [ ] An item in an equipment set (`#set`) is never sold, even if grey or rule-matched.
- [ ] **Keep Quantities** (`/rum tools`): keep 5 of a 20-stack, sell. Exactly 15 go; the 5 stay
      (needs one free bag slot for the split).
- [ ] `/rum buyback 1`: the last sold item comes back and the gold leaves.
- [ ] `/rum history` → **Buy Back** on an Observed sale row: returns that exact stack; the
      button can't be pressed twice while Pending.
- [ ] Close the vendor mid-sale: selling stops; reopening doesn't resume it.
- [ ] Auto-repair with guild funds when the guild limit is too low: uses your own gold and
      says so.

## 2. Moving items to the bank, mail and trade

- [ ] At a banker, Bags and Bank open side by side. Drag items both ways.
- [ ] Footer **To Bank** / **From Bank** moves the listed items (after search/filters) and
      merges into partial stacks.
- [ ] Close the bank mid-transfer: it stops, nothing ends up on the cursor.
- [ ] **Bank Restock** (`/rum plan` → Restock): set a target (e.g. 20 food), **Save Target**, **Preview**, **Execute**.
      Exactly the missing amount comes from the bank; a stack is split if needed.
- [ ] Change your bags after Preview, then Execute: it refuses and asks for a new preview.
- [ ] Mail: open Send Mail, footer button reads **To Mail**, attaches listed items, skips
      bound ones, stops when 12 slots are full.
- [ ] Trade: button reads **To Trade**, uses only the first six slots.

## 3. Guild bank

- [ ] At the vault, the Guild Bank window opens beside Bags with tabs; Blizzard's frame is hidden.
- [ ] Drop an item from Bags onto the window or a tab icon: it's deposited.
- [ ] Right-click and drag withdraw within the daily limit; the footer counts down.
- [ ] Tabs you can't view show "(no access)".
- [ ] Away from the vault, the Guild Bank (Bags header **Guild**, `/rum guild`) shows the
      saved contents, view-only, with their age.

## 4. Window, sidebar and categories

- [ ] Bank (`/rum bank`) away from a banker shows the saved bank, view-only.
- [ ] Name column fills the spare width; resize it by dragging, double-click resets.
- [ ] Right-click an item uses it (potion, hearthstone outside combat).
- [ ] Icon rail: counts as badges, names in tooltips. Try *Category columns* 1, 2 and 3 (Appearance)
      and left/right/auto placement.
- [ ] Drag an item onto your own category: added, item returns to its slot. Onto a built-in:
      refused. Onto **+**: prompts for a name.
- [ ] Right-click a custom category: added items listed, removing works.
- [ ] Category sections group custom categories with the same section name.
- [ ] Open bags at a vendor/AH, walk away: auto-opened bags close; manually opened stay.
- [ ] In combat, open/close bags and scroll: no "blocked action" errors.

## 5. Search

- [ ] `(q:rare | q:epic) ilvl>20`, `!(#junk | q:poor)`, `name:"linen cloth"` give sensible results.
- [ ] `#usable` hides gear your class can't wear (e.g. plate on a mage).
- [ ] `#upgrade` without Pawn: shows higher-item-level gear for empty or weaker slots.
- [ ] `#set` / `set:<name>` match equipment-set items.

## 6. Tools and Planning windows

- [ ] `/rum tools`: rule preview lists planned items and value; nothing is sold until enabled.
- [ ] `/rum plan`: Rules view explains overlaps; Vendor shows the session summary; Forecast
      shows bag-space effects without moving anything.
- [ ] At font sizes 8, 12 and 18 (Settings → Appearance → Font size), controls stay inside their
      windows and buttons aren't clipped.

## 7. Controller (1.14.0, needs a gamepad)

- [ ] With the controller enabled, open Bags: D-pad down selects the first item and its
      tooltip shows; your character doesn't jump or cast on those buttons.
- [ ] Shoulders page through a long list; left/right change category (list view) or
      move by one (grid view).
- [ ] **A** uses a potion or food; **X** cycles the favorite marker; **Y** marks junk.
- [ ] **B** clears the selection, a second **B** closes the window.
- [ ] With the window open, buttons Rummage doesn't use (jump, abilities) still work.
- [ ] Bags and Bank open: input goes to the one opened or clicked last.
- [ ] Enter combat with the window open: buttons go back to the game, no "blocked action" error.
- [ ] Type in the search box: the D-pad doesn't move the selection.

## 8. Other

- [ ] Footer shows up to three tracked currencies.
- [ ] `/rum pet`, `/rum pet favorite`, `/rum mount` summon something.
- [ ] Context profiles (Settings → General → *Context Profiles...*): set one for a spec or instance type, switch, settings change.
- [ ] Settings export → import on another character keeps categories, sections and restock targets.

## Report back

Paste failures (what you did, what happened, any Lua error text) and the `/rum apicheck`
output. Restore the SavedVariables backup if anything got into a bad state.
