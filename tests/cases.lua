-- Rummage test cases. Each test builds a fresh fake client and loads every addon file.
local function test(name, fn) T.tests[#T.tests + 1] = { name = name, fn = fn } end

local function boot(setup)
  local env, ns = T.new_env()
  if setup then setup(env) end
  local ev
  for _, f in ipairs(env.__frames) do if f.events and f.events.ADDON_LOADED then ev = f end end
  assert(ev, "no event frame registered ADDON_LOADED")
  env.__ev = function(name, ...) ev.scripts.OnEvent(ev, name, ...) end
  env.__ev("ADDON_LOADED", "Rummage")
  env.__ev("PLAYER_LOGIN")
  env.__ev("PLAYER_ENTERING_WORLD")
  env.__settle(3)
  return env, ns.R
end

test("addon loads, logs in and opens the window", function()
  local env, R = boot()
  assert(R.UI and R.UI.frame, "no main frame")
  R.UI:Open("bags")
  env.__settle(4)
  assert(R.UI.frame:IsShown())
  assert(not env.__errors, "scheduler errors: " .. tostring(env.__errors and env.__errors[1]))
end)

local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.001) end
local function chatHas(env, needle)
  for _, m in ipairs(env.__chat) do if tostring(m):find(needle, 1, true) then return true end end
  return false
end
local function open(env, R)
  R.UI:Open("bags"); env.__settle(4)
end

---------------------------------------------------------------------------
-- Scale grips
---------------------------------------------------------------------------
test("pure scale helpers: clamp, ratio, snap", function()
  local env, R = boot()
  local UI = R.UI
  assert(near(UI.ScaleFromCursor("RIGHT", 1160 + 1020, 1160, 680), 1.5))
  assert(near(UI.ScaleFromCursor("LEFT", 1000, 1500, 500), 1))
  assert(UI.ScaleFromCursor("RIGHT", 99999, 0, 680) == 2, "upper clamp")
  assert(UI.ScaleFromCursor("RIGHT", -99999, 0, 680) == 0.5, "lower clamp")
  assert(UI.ScaleFromCursor("RIGHT", 10, 0, 0) == nil, "zero width")
  assert(UI.SnapScale(0.8) == 0.75 and UI.SnapScale(1.1) == 1 and UI.SnapScale(1.2) == 1.25 and UI.SnapScale(1.9) == 1.5)
end)

test("right grip keeps the left edge and top fixed", function()
  local env, R = boot()
  open(env, R)
  local UI, f = R.UI, R.UI.frame
  local l0, t0 = f:GetLeft() * f:GetScale(), f:GetTop() * f:GetScale()
  local g = UI.gripR
  g.scripts.OnMouseDown(g, "LeftButton")
  assert(g.sizing and UI.scaleReadout.shown, "readout shown while dragging")
  env.__cursor = l0 + 1.5 * f:GetWidth()
  g.scripts.OnUpdate(g)
  assert(near(f:GetScale(), 1.5, 0.002), "scale " .. f:GetScale())
  assert(near(f:GetLeft() * f:GetScale(), l0, 0.01) and near(f:GetTop() * f:GetScale(), t0, 0.01))
  assert(UI.scaleReadout:GetText() == "150%", UI.scaleReadout:GetText())
  g.scripts.OnMouseUp(g)
  assert(not g.sizing and not UI.scaleReadout.shown and not g.scripts.OnUpdate, "OnUpdate removed")
  assert(R.settings.scale == 1.5 and R.settings.point, "saved")
end)

test("left grip keeps the right edge fixed; Shift snaps", function()
  local env, R = boot()
  open(env, R)
  local UI, f = R.UI, R.UI.frame
  local w = f:GetWidth()
  local r0 = f:GetRight() * f:GetScale()
  local g = UI.gripL
  g.scripts.OnMouseDown(g, "LeftButton")
  env.__shift = true
  env.__cursor = r0 - 1.18 * w   -- raw 1.18 -> snaps to 1.25
  g.scripts.OnUpdate(g)
  assert(near(f:GetScale(), 1.25, 0.002), "scale " .. f:GetScale())
  assert(near(f:GetRight() * f:GetScale(), r0, 0.05), "right edge moved")
  g.scripts.OnMouseUp(g)
  env.__shift = false
end)

test("grips respect lock, and combat blocks/queues", function()
  local env, R = boot()
  open(env, R)
  local UI, f = R.UI, R.UI.frame
  R.settings.locked = true
  UI:BeginScale(UI.gripR)
  assert(not UI.gripR.sizing, "locked must not start")
  R.settings.locked = false
  env.__combat = true
  UI:BeginScale(UI.gripR)
  assert(not UI.gripR.sizing, "combat must not start")
  env.__combat = false
  UI:BeginScale(UI.gripR)
  assert(UI.gripR.sizing)
  env.__combat = true      -- combat begins mid-drag
  UI.gripR.scripts.OnUpdate(UI.gripR)
  assert(not UI.gripR.sizing and UI.pendingCombat, "ended and flagged pending")
  assert(UI.pendingBadge and UI.pendingBadge.shown, "badge visible")
  env.__combat = false
  env.__ev("PLAYER_REGEN_ENABLED")
  assert(not UI.pendingCombat and not UI.pendingBadge.shown, "badge cleared after combat")
end)

test("per-view layouts are remembered when enabled", function()
  local env, R = boot()
  open(env, R)
  local UI, f = R.UI, R.UI.frame
  R.settings.perViewSize = true
  f:SetSize(800, 600); f:SetScale(1.2)
  R.settings.scale = 1.2
  UI:SavePosition()          -- stores under "bags"
  UI:SetView("bank")         -- first visit: starts from the current layout
  env.__settle(2)
  f:SetSize(500, 350); R.settings.scale = 0.8; f:SetScale(0.8)
  UI:SavePosition()
  UI:SetView("bags")
  env.__settle(2)
  assert(near(f:GetWidth(), 800) and near(f:GetScale(), 1.2), "bags layout restored")
  UI:SetView("bank")
  env.__settle(2)
  assert(near(f:GetWidth(), 500) and near(f:GetScale(), 0.8), "bank layout restored")
  R.settings.perViewSize = false
end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
test("sanitizer repairs garbage and migrates a v3 database", function()
  local env, R = boot(function(e)
    e.RummageDB = {
      version = 3,
      settings = { scale = 99, staleDays = -5, sellConfirmValue = "x", viewSizes = { bags = { w = 1, h = 99999, scale = 9 }, evil = 5 },
        keyboardNav = "yes", columns = { order = { "name", "name", 5 } } },
      savedSearches = { "a", 5, "", "b" },
      junkLog = { { t = 1, link = "x", value = 5 }, "junk" },
      contextProfiles = { spec1 = "P", [3] = "x", raid = 7 },
    }
  end)
  local s, db = R.settings, R.db
  assert(s.scale == 2 and s.staleDays == 0 and s.sellConfirmValue == 0, "clamped / defaulted")
  assert(s.keyboardNav == true, "type repaired")
  assert(s.viewSizes.evil == nil and s.viewSizes.bags.w == 400 and s.viewSizes.bags.h == 2000 and s.viewSizes.bags.scale == 2)
  assert(#db.savedSearches == 2 and #db.junkLog == 1 and db.contextProfiles.spec1 == "P" and db.contextProfiles.raid == nil)
  assert(db.version == 4, "version bumped")
  local n = 0
  for _, k in ipairs(s.columns.order) do if k == "name" then n = n + 1 end; assert(type(k) == "string") end
  assert(n <= 1, "column order deduped")
end)

test("settings export/import round-trips the 1.5.0 keys", function()
  local env, R = boot()
  R.settings.colorblindCues = true
  R.settings.staleDays = 30
  R.settings.sellConfirmValue = 50000
  R.settings.autoProfile = true
  local str = R:ExportSettings()
  assert(str:find("colorblindCues=1", 1, true) and str:find("staleDays=30", 1, true))
  R.settings.colorblindCues = false; R.settings.staleDays = 14; R.settings.sellConfirmValue = 0; R.settings.autoProfile = false
  local ok, err = R:ImportSettings(str)
  assert(ok, tostring(err))
  assert(R.settings.colorblindCues == true and R.settings.staleDays == 30 and R.settings.sellConfirmValue == 50000 and R.settings.autoProfile == true)
  local bad = R:ImportSettings("RUM1;staleDays=abc")
  assert(not bad, "bad number rejected")
end)

test("profiles carry the new settings; auto-profile keeps itself on", function()
  local env, R = boot()
  R.settings.colorblindCues = true
  R:SaveProfile("Alt")
  R.settings.colorblindCues = false
  R.settings.autoProfile = true
  R.db.profileName = nil
  R.db.contextProfiles.world = "Alt"
  assert(R.Extras:ApplyContext(), "context applied")
  assert(R.settings.colorblindCues == true and R.settings.autoProfile == true)
  env.__combat = true
  R.db.profileName = "other"
  assert(R.Extras:ApplyContext() == false and R.Extras.waiting, "deferred in combat")
  env.__combat = false
  env.__instanceType = "raid"; env.__inInstance = true
  R.db.contextProfiles.raid = "Alt"
  assert(R.Extras:ContextKeys()[1] == "raid")
end)

---------------------------------------------------------------------------
-- Junk safeguards, log, buyback
---------------------------------------------------------------------------
test("junk sale: plain greys sell without a prompt and are logged", function()
  local env, R = boot()
  env.__addItem(0, 1, 100, 1, { name = "Rag", quality = 0, sell = 50 })
  env.__addItem(0, 2, 101, 3, { name = "Rock", quality = 0, sell = 10 })
  env.MerchantFrame.shown = true
  env.__ev("BAG_UPDATE_DELAYED"); env.__settle(3)
  R.Data:ScanInventory()
  local list, total = R.Junk:Collect()
  assert(#list == 2 and total == 80, "collected " .. #list .. " total " .. total)
  R.Junk:SellAll()
  env.__tick(3)
  assert(#env.__used == 2, "sold " .. tostring(env.__used and #env.__used))
  assert(not env.__popup, "no prompt for greys")
  assert(#R.db.junkLog == 2 and R.db.junkLog[1].value > 0)
end)

test("junk sale: Uncommon item or high value asks first", function()
  local env, R = boot()
  env.__addItem(0, 1, 100, 1, { name = "Green", quality = 2, sell = 500 })
  env.MerchantFrame.shown = true
  R.Data:ScanInventory()
  R.db.junk[100] = true
  R.Junk:SellAll()
  assert(env.__popup and env.__popup.which == "RUMMAGE_SELL_CONFIRM", "prompt for quality")
  assert(not env.__used, "nothing sold yet")
  R.settings.sellConfirmQuality = false
  env.__popup = nil
  R.Junk:SellAll()
  assert(not env.__popup, "quality prompt off")
  env.__tick(3)   -- finish that sale
  env.__addItem(0, 1, 100, 1, { name = "Green", quality = 2, sell = 500 })
  R.Data:ScanInventory()
  R.settings.sellConfirmValue = 100
  R.Junk:SellAll()
  assert(env.__popup, "value prompt")
  assert(R.Junk:NeedsConfirm({ { 0, 0, 5, 0 } }, 100) == false and R.Junk:NeedsConfirm({ { 0, 0, 5, 0 } }, 101) == true)
  local before = env.__used and #env.__used or 0
  R.Junk:SellAll(true)   -- confirmed path
  env.__tick(2)
  assert(#env.__used == before + 1, "confirmed sale went through")
end)

test("buyback matches by link, guards a missing API", function()
  local env, R = boot()
  env.MerchantFrame.shown = true
  table.insert(R.db.junkLog, 1, { t = env.__now, link = "[Rag]", count = 1, value = 50 })
  env.__buyback = { { link = "[Other]" }, { link = "[Rag]" } }
  R.Junk:Buyback(1)
  assert(env.__bought and env.__bought[1].link == "[Rag]" and #R.db.junkLog == 0)
  local saved = env.BuybackItem
  env.BuybackItem = nil
  R.Junk:Buyback(1)
  assert(chatHas(env, "not available"), "reports missing API")
  env.BuybackItem = saved
end)

---------------------------------------------------------------------------
-- UI features
---------------------------------------------------------------------------
test("stale characters are detected and dimmed", function()
  local env, R = boot()
  open(env, R)
  assert(R.IsStale({ lastSeen = env.__now - 20 * 86400 }) == true)
  assert(R.IsStale({ lastSeen = env.__now - 2 * 86400 }) == false)
  R.settings.staleDays = 0
  assert(R.IsStale({ lastSeen = 1 }) == false, "0 disables")
  R.settings.staleDays = 14
  R.db.chars["Old-TestRealm"] = { name = "Old", realm = "TestRealm", class = "MAGE", lastSeen = env.__now - 40 * 86400,
    containers = {}, equipped = {}, mail = {}, acquired = {}, money = 0 }
  R.UI.charKey = "Old-TestRealm"
  R.UI:UpdateFooter()
  assert(R.UI.cachedText:GetText():find("stale", 1, true), R.UI.cachedText:GetText())
  assert(R.UI.list:GetAlpha() < 1)
end)

test("colourblind cue adds a text tag", function()
  local env, R = boot()
  assert(R.QualityTag(4) == "")
  R.settings.colorblindCues = true
  assert(R.QualityTag(4) == "[Epic]" and R.QualityTag(1) == "")
end)

test("saved searches: save, dedupe, cap, chip click, remove", function()
  local env, R = boot()
  open(env, R)
  local UI = R.UI
  UI.search = ""
  assert(UI:SaveCurrentSearch() == false, "empty search not saved")
  UI.search = "potion"
  assert(UI:SaveCurrentSearch() == true and UI:SaveCurrentSearch() == false)
  env.__settle(2)
  local b = UI.savedButtons[1]
  assert(b and b.shown, "chip shown")
  for i = 1, 10 do UI.search = "q" .. i; UI:SaveCurrentSearch() end
  assert(#R.db.savedSearches == 8, "capped at 8")
  UI.savedButtons[1].scripts.OnClick(UI.savedButtons[1], "RightButton")
  assert(#R.db.savedSearches == 7)
end)

test("keyboard navigation selects, wraps ends, uses items, yields to search and combat", function()
  local env, R = boot()
  env.__addItem(0, 1, 200, 1, { name = "A", quality = 1 })
  env.__addItem(0, 2, 201, 1, { name = "B", quality = 1 })
  env.__addItem(0, 3, 202, 1, { name = "C", quality = 1 })
  R.Data:ScanInventory()
  open(env, R)
  local UI = R.UI
  assert(#UI:NavEntries() == 3, "entries " .. #UI:NavEntries())
  assert(UI:HandleNavKey("DOWN") == true and UI.selected == UI:NavEntries()[1])
  UI:HandleNavKey("DOWN"); UI:HandleNavKey("DOWN"); UI:HandleNavKey("DOWN")
  assert(UI.selected == UI:NavEntries()[3], "clamped at the end")
  UI:HandleNavKey("HOME")
  assert(UI.selected == UI:NavEntries()[1])
  assert(UI:HandleNavKey("ENTER") == true and env.__used and #env.__used == 1, "enter uses the item")
  local favBefore = R.db.favorites[UI.selected.id]
  assert(UI:HandleNavKey("SPACE") == true and R.db.favorites[UI.selected.id] ~= favBefore, "space cycles favorite")
  assert(UI:HandleNavKey("A") == false, "unrelated key passes through")
  UI.searchBox:SetFocus()
  assert(UI:HandleNavKey("DOWN") == false, "search box focused")
  UI.searchBox:ClearFocus()
  env.__combat = true
  assert(UI:HandleNavKey("DOWN") == false, "combat")
  env.__combat = false
  R.settings.keyboardNav = false
  assert(UI:HandleNavKey("DOWN") == false, "setting off")
  R.settings.keyboardNav = true
  local f = UI.frame
  env.__ev("PLAYER_REGEN_DISABLED")
  assert(f.keyboard == false, "keyboard released in combat")
  env.__ev("PLAYER_REGEN_ENABLED")
  assert(f.keyboard == true, "keyboard restored")
end)

---------------------------------------------------------------------------
-- Extras, tooltip, upgrade
---------------------------------------------------------------------------
test("apicheck reports required and optional APIs", function()
  local env, R = boot()
  local res, missing = R.Extras:ApiCheck()
  assert(#res > 8 and missing == 0, "missing " .. missing)
  env.C_Timer = nil
  local _, m2 = R.Extras:ApiCheck()
  assert(m2 >= 1, "a removed required API is flagged")
  env.SlashCmdList.RUMMAGE("apicheck")
  assert(chatHas(env, "API check"))
end)

test("inventory export: CSV is escaped and covers every character", function()
  local env, R = boot()
  env.__addItem(0, 1, 300, 5, { name = 'Odd, "Name"', quality = 1 })
  R.Data:ScanInventory()
  R.db.chars["Alt-TestRealm"] = { name = "Alt", realm = "TestRealm", class = "MAGE", lastSeen = 1,
    containers = { [0] = { size = 4, slots = { [2] = { l = "|Hitem:7::|h[Silk]|h", c = 20, i = 7 } } } },
    equipped = {}, mail = { { l = "|Hitem:8::|h[Cloth]|h", c = 2, i = 8 } }, acquired = {}, money = 0 }
  local csv = R.Extras:InventoryCSV()
  assert(csv:find("character,realm,location", 1, true))
  assert(csv:find('"Odd, ""Name"""', 1, true), "quoted field")
  assert(csv:find("Alt,TestRealm,bags,0,2,Silk,20,7", 1, true), csv)
  assert(csv:find("mail", 1, true))
  assert(R.Extras:InventoryText():find("20x Silk", 1, true))
  R.UI:Open("bags")
  env.SlashCmdList.RUMMAGE("inventory")
  assert(R.UI.textWindow and R.UI.textWindow.shown, "copy window opened")
end)

test("tooltip counts skip secret values and survive API errors", function()
  local env, R = boot()
  env.__addItem(0, 1, 400, 2, { name = "Thing", quality = 1 })
  R.Data:ScanInventory()
  local tt = env.__newObject("GameTooltip")
  local link = "|Hitem:400::|h[Thing]|h"
  env.issecretvalue = function(v) return v == "SECRET" end
  R.Tooltip:Add(tt, "SECRET")
  assert(not tt.__lines, "secret link ignored")
  env.issecretvalue = nil
  R.Tooltip:Add(tt, link)
end)

test("upgrade stat diff lists changes, tolerates missing API", function()
  local env, R = boot()
  env.C_Item.GetItemStats = function(link)
    if link == "new" then return { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 5 } end
    return { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_AGILITY_SHORT = 4 }
  end
  env.ITEM_MOD_STRENGTH_SHORT = "Strength"
  local s = R.Upgrade.StatDiff("new", "old")
  assert(s:find("+12", 1, true) and s:find("Strength", 1, true) and s:find("-4", 1, true), s)
  env.C_Item.GetItemStats = nil
  assert(R.Upgrade.StatDiff("new", "old") == "")
end)

test("every documented slash command runs without errors", function()
  local env, R = boot()
  for _, cmd in ipairs({ "", "bank", "config", "search foo", "restack", "conflicts", "reset", "keys", "export", "apicheck",
    "inventory text", "autoprofile", "autoprofile on", "autoprofile off", "savesearch", "junklog", "buyback", "debug report", "bogus" }) do
    env.SlashCmdList.RUMMAGE(cmd)
    env.__settle(2)
  end
  env.SlashCmdList.RUMMAGEDEBUG("report")
  assert(chatHas(env, "bank path:"), "bank path in /fdebug report")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)
