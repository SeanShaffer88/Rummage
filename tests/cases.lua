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
  local s = R.settings
  s.perViewSize = true
  -- bags layout
  s.width, s.height, s.scale = 800, 600, 1.2
  UI:SaveViewLayout(UI:ViewKey())
  assert(s.viewSizes.bags and s.viewSizes.bags.w == 800, "bags layout stored under bags")
  -- another character's cache uses the shared "all" layout (first visit keeps the current one)
  UI.charKey = "Old-TestRealm"
  assert(UI:ViewKey() == "all")
  UI:ApplyViewLayout("all")
  s.width, s.height, s.scale = 500, 350, 0.8
  UI:SaveViewLayout("all")
  UI.charKey = nil
  UI:ApplyViewLayout(UI:ViewKey())
  assert(near(f:GetWidth(), 800) and near(f:GetScale(), 1.2), "bags layout restored: " .. f:GetWidth() .. " x" .. f:GetScale())
  UI.charKey = "Old-TestRealm"
  UI:ApplyViewLayout(UI:ViewKey())
  assert(near(f:GetWidth(), 500) and near(f:GetScale(), 0.8), "all layout restored")
  UI.charKey = nil
  s.perViewSize = false
end)

test("bank is its own window with its own geometry; opening it does not hide Bags", function()
  local env, R = boot()
  local Bags, Bank = R.UI, R.BankUI
  assert(Bags ~= Bank and Bags.frame and Bank.frame and Bags.frame ~= Bank.frame, "two separate windows")
  assert(Bags.view == "bags" and Bank.view == "bank", "each window is fixed to its own view")
  Bags:Open(); Bank:Open(); env.__settle(2)
  assert(Bags.frame:IsShown() and Bank.frame:IsShown(), "both open together")
  Bank:SetView("bags")
  assert(Bank.view == "bank", "Bank window cannot switch to the bags view")
  -- independent geometry
  Bank.frame:SetSize(640, 480); Bank.frame:SetScale(1.4)
  Bank:SavePosition()
  assert(R.settings.bank and R.settings.bank.width == 640 and R.settings.bank.height == 480, "bank geometry stored apart")
  assert(R.settings.width ~= 640, "bags geometry untouched")
  Bank:ResetPosition()
  assert(R.settings.bank.width == R.defaults.width, "bank reset leaves bags alone")
  -- hiding Bags must not close the banker; hiding Bank must
  local closed = 0
  env.CloseBankFrame = function() closed = closed + 1 end
  R.Data.atBank = true
  R.settings.replaceBank = true
  Bags:Close()
  assert(closed == 0, "closing Bags must not close the bank")
  Bank:Close()
  assert(closed == 1, "closing the Bank window closes the banker")
  R.Data.atBank = false
  -- banker events open both windows, and close the ones they opened
  Bags:Close(); Bank:Close()
  env.__ev("BANKFRAME_OPENED"); env.__settle(2)
  assert(Bank.frame:IsShown() and Bags.frame:IsShown(), "banker opens Bank and Bags")
  env.__ev("BANKFRAME_CLOSED"); env.__settle(2)
  assert(not Bank.frame:IsShown() and not Bags.frame:IsShown(), "closing the banker closes both")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
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
  assert(s.viewSizes.evil == nil and s.viewSizes.bags.w == 400 and s.viewSizes.bags.h == 2400 and s.viewSizes.bags.scale == 2)
  assert(#db.savedSearches == 2 and #db.junkLog == 1 and db.contextProfiles.spec1 == "P" and db.contextProfiles.raid == nil)
  assert(db.version == 7, "version bumped")
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
  env.__buyback = { { link = "[Other]", price = 1, count = 1 }, { link = "[Rag]", price = 50, count = 1 } }
  R.Junk:Buyback(1); env.__tick(2)
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
  for _, cmd in ipairs({ "", "bank", "guild", "config", "search foo", "restack", "conflicts", "reset", "keys", "export", "apicheck",
    "inventory text", "autoprofile", "autoprofile on", "autoprofile off", "savesearch", "junklog", "buyback", "buyback all", "gold", "mail", "perf", "apicheck export", "debug report", "bogus" }) do
    env.SlashCmdList.RUMMAGE(cmd)
    env.__settle(2)
  end
  env.SlashCmdList.RUMMAGEDEBUG("report")
  assert(chatHas(env, "bank path:"), "bank path in /fdebug report")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("mail expiry: stored days-left ages and warns inside the window", function()
  local env, R = boot()
  local me = R.Data.me
  me.mailT = env.time() - 2 * 86400
  me.mail = { { l = "a", c = 1, d = 3.5 }, { l = "b", c = 1, d = 20 }, { l = "c", c = 1 } }
  local list = R.Extras:ExpiringMail(3)
  assert(#list == 1 and list[1].items == 1, "expected one expiring item, got " .. #list)
  assert(math.abs(list[1].days - 1.5) < 0.05, "days left should age to 1.5, got " .. tostring(list[1].days))
  assert(#R.Extras:ExpiringMail(0.5) == 0, "nothing should expire within half a day")
  R.settings.mailWarnDays = 3
  assert(R.Extras:MailWarnings(false) == 1)
  R.settings.mailWarnDays = 0
  assert(R.Extras:MailWarnings(false) == 0, "warning off must stay silent")
  assert(chatHas(env, "Mail on"), "warning text missing")
end)

test("gold history: one snapshot per day, deltas over 7 and 30 days", function()
  local env, R = boot()
  local me = R.Data.me
  local today = math.floor(env.time() / 86400)
  me.money = 500000
  me.goldLog = { { d = today - 40, m = 100000 }, { d = today - 8, m = 300000 } }
  env.GetMoney = function() return 500000 end
  R.Extras:RecordGold()
  R.Extras:RecordGold()
  assert(#me.goldLog == 3 and me.goldLog[3].d == today, "same-day snapshots must merge")
  local rows = R.Extras:GoldReport()
  assert(#rows >= 2 and rows[#rows]:find("All characters", 1, true), "total row missing")
  assert(rows[1]:find("+", 1, true), "positive delta expected: " .. rows[1])
  for i = 1, 100 do me.goldLog[#me.goldLog + 1] = { d = today + i, m = i } end
  R.Extras:RecordGold()
  assert(#me.goldLog <= 90, "history must be capped at 90")
  R.settings.goldHistory = false
  local n = #me.goldLog
  R.Extras:RecordGold()
  assert(#me.goldLog == n, "off must not record")
end)

test("sell hint: needs Auctionator, picks the better venue, tolerates junk", function()
  local env, R = boot()
  assert(R.Extras:SellHint("x") == nil, "no hint without Auctionator")
  env.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 9000 end } } }
  R.Integrations.active.Auctionator = true
  R.API.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 4000 end
  local h = R.Extras:SellHint("x")
  assert(h and h:find("Auction House", 1, true), "AH should win: " .. tostring(h))
  R.API.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 12000 end
  assert(R.Extras:SellHint("x"):find("Vendor", 1, true), "vendor should win")
  R.API.GetItemInfo = function() return nil end
  assert(R.Extras:SellHint("x") == nil, "no vendor price, no hint")
  env.Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("boom") end
  R.API.GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 4000 end
  assert(R.Extras:SellHint("x") == nil, "erroring price source must be tolerated")
  R.settings.sellHint = false
  assert(R.Extras:SellHint("x") == nil, "off must give no hint")
end)

test("apicheck export opens a plain-text window; perf runs", function()
  local env, R = boot()
  local shown
  R.UI.ShowTextWindow = function(_, title, text) shown = text end
  R.Extras:PrintApiCheck(true)
  assert(shown and shown:find("API check", 1, true) and not shown:find("|c", 1, true), "export text wrong")
  R.Extras:PrintPerf()
  assert(chatHas(env, "Perf:"), "perf output missing")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("columns: a dragged Name width stops flexing; reset restores flex; limits allow wide windows", function()
  local env, R = boot()
  R.UI:Toggle()
  R.UI:ComputeColumns()
  local function nameW() for _, L in ipairs(R.UI.colLayout) do if L.col.key == "name" then return L.w end end end
  local flexW = nameW()
  assert(flexW and flexW >= 80, "name should flex")
  local handle = R.UI.headerButtons.name.handle
  assert(handle:IsShown(), "Name column resize handle should be visible")
  env.__cursor = 100
  handle.scripts.OnMouseDown(handle, "LeftButton")
  env.__leftMouseDown = true
  env.__cursor = 170
  R.UI.colhead.scripts.OnUpdate(R.UI.colhead)
  env.__leftMouseDown = false
  handle.scripts.OnMouseUp(handle)
  assert(R.settings.columns.widths.name == flexW + 70, "dragging Name edge should save the width")
  R.UI:ComputeColumns()
  assert(nameW() == flexW + 70, "explicit name width must hold, got " .. tostring(nameW()))
  handle.scripts.OnMouseDown(handle, "LeftButton")
  assert(R.settings.columns.widths.name == nil, "double-click should restore flex")
  R.UI:ComputeColumns()
  assert(nameW() == flexW, "reset must restore flex")
  local _, R2 = boot(function(e)
    e.RummageDB = { version = 4, settings = { width = 3900, height = 2300, columns = { order = {}, hidden = {}, widths = { name = 5000, ilvl = 90 } } } }
  end)
  assert(R2.settings.width == 3900 and R2.settings.height == 2300, "wide window must be allowed")
  assert(R2.settings.columns.widths.name == 1200 and R2.settings.columns.widths.ilvl == 90, "column width cap is 1200")
end)

test("right-clicking a bag item uses it when the addon falls back from Blizzard templates", function()
  local env, R = boot()
  env.__failItemTemplates = true
  env.__addItem(0, 1, 777, 1, { name = "Test Potion", quality = 1 })
  R.Data:ScanInventory()
  open(env, R)
  local button = R.UI.holders[0] and R.UI.holders[0].buttons[1]
  assert(button and button.registeredClicks[2] == "RightButtonUp", "right-click is registered")
  button.scripts.OnClick(button, "RightButton")
  assert(env.__used and env.__used[1][1] == 0 and env.__used[1][2] == 1, "right-click uses the bag slot")
end)

test("auto-opened bags close after leaving merchant or auction interactions", function()
  for _, event in ipairs({ "MERCHANT_CLOSED", "AUCTION_HOUSE_CLOSED" }) do
    local env, R = boot()
    R.UI:Open()
    R.UI.autoOpened = true
    env.__ev(event)
    env.__settle(2)
    assert(not R.UI.frame:IsShown(), event .. " should close auto-opened bags")
  end
  local env, R = boot()
  R.UI:Open()
  env.__ev("MERCHANT_CLOSED")
  env.__settle(2)
  assert(R.UI.frame:IsShown(), "manually opened bags should remain open")

  env, R = boot(function(e)
    e.Enum.PlayerInteractionType = { Merchant = 1, Auctioneer = 2 }
  end)
  R.UI:Open()
  R.UI.autoOpened = true
  env.__ev("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 2)
  env.__settle(2)
  assert(not R.UI.frame:IsShown(), "leaving an auctioneer interaction should close auto-opened bags")
end)

test("settings window: every tab builds inside a scroll frame without errors", function()
  local env, R = boot()
  for _, tab in ipairs({ "general", "appearance", "items", "columns", "categories", "about" }) do
    R.Options:Show(tab)
    local page = R.Options.pages[tab]
    assert(page and page.content and page.stacker, tab .. " page not built")
    assert(page.content:GetHeight() >= 10, tab .. " content height")
  end
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

---------------------------------------------------------------------------
-- 1.9.0: audit fixes
---------------------------------------------------------------------------
test("junk sale re-checks each slot: an item swapped in mid-sale is not sold", function()
  local env, R = boot()
  env.__bags[0].size = 16
  for s = 1, 12 do env.__addItem(0, s, 100 + s, 1, { name = "Grey" .. s, quality = 0, sell = 10 }) end
  env.MerchantFrame.shown = true
  R.Data:ScanInventory()
  R.Junk:SellAll()                 -- first step sells 10
  assert(#env.__used == 10, "first step " .. #env.__used)
  env.__addItem(0, 11, 900, 1, { name = "Precious", quality = 4, sell = 99999 })
  env.__tick(2)
  for _, u in ipairs(env.__used) do assert(not (u[1] == 0 and u[2] == 11), "sold the swapped-in item") end
  assert(#env.__used == 11, "slot 12 still sold, got " .. #env.__used)
  assert(chatHas(env, "Sold 11 junk"), "reports what was really sold")
end)

test("buyback all claims each buyback slot once and buys highest index first", function()
  local env, R = boot()
  env.MerchantFrame.shown = true
  R.db.junkLog = {
    { t = 1, link = "[Rag]", count = 1, value = 5 },
    { t = 1, link = "[Rag]", count = 1, value = 5 },
    { t = 1, link = "[Rock]", count = 1, value = 5 },
  }
  env.__buyback = { { link = "[Rag]", count = 1, price = 5 }, { link = "[Other]", count = 1, price = 5 }, { link = "[Rock]", count = 1, price = 5 } }
  local calls = {}
  env.BuybackItem = function(i) calls[#calls + 1] = i end   -- server answers later: list unchanged
  R.Junk:Buyback("all")
  assert(#calls == 1 and calls[1] == 1, "only one request before acknowledgement")
  env.__tick(30); assert(#calls == 1 and not R.Buyback.operation, "no unconfirmed followup request")
  assert(#R.db.junkLog == 3, "unconfirmed requests must retain sale history")
end)

test("auto-repair uses guild funds only when the withdraw limit covers the cost", function()
  local env, R = boot()
  R.settings.autoRepair, R.settings.autoRepairGuild = true, true
  local paidByGuild
  env.CanMerchantRepair = function() return true end
  env.GetRepairAllCost = function() return 5000, true end
  env.CanGuildBankRepair = function() return true end
  env.GetMoney = function() return 100000 end
  env.RepairAllItems = function(guild) paidByGuild = guild and true or false end
  env.GetGuildBankWithdrawMoney = function() return 1000 end
  R.Junk:AutoRepair()
  assert(paidByGuild == false, "limit too low: own gold")
  env.GetGuildBankWithdrawMoney = function() return -1 end
  R.Junk:AutoRepair()
  assert(paidByGuild == true, "unlimited: guild")
end)

test("settings import keeps categories after a missing index", function()
  local env, R = boot()
  assert(R:ImportSettings("RUM1;cat1.name=A;cat1.query=linen;cat3.name=C;cat3.query=#boe"))
  assert(#R.db.categories == 2 and R.db.categories[2].name == "C", "got " .. #R.db.categories)
end)

test("Can I Mog It? gets slot coordinates only for live views", function()
  local seen = {}
  local env, R = boot(function(e)
    e.CanIMogIt = { GetTooltipText = function(_, link, bag, slot) seen[#seen + 1] = { bag, slot }; return "ok" end }
  end)
  env.__addItem(0, 1, 300, 1, { name = "Helm", equip = "INVTYPE_HEAD", class = 4 })
  R.Data:ScanInventory()
  local e = { link = env.__bags[0][1].link, id = 300, count = 1, bag = 0, slot = 1, slots = { { 0, 1 } }, vals = {} }
  R.Items:Prepare(e, R.Data.me, true, true)
  R.Columns.byKey.cimi.value(e)
  R.Items:Prepare(e, R.Data.me, false, false)
  R.Columns.byKey.cimi.value(e)
  assert(seen[1][1] == 0 and seen[1][2] == 1, "live gets bag/slot")
  assert(seen[2][1] == nil and seen[2][2] == nil, "cached gets none")
end)

---------------------------------------------------------------------------
-- 1.9.0: features adapted from other bag addons
---------------------------------------------------------------------------
local function setsEnv(e)
  e.C_EquipmentSet = {
    GetEquipmentSetIDs = function() return { 1, 2 } end,
    GetEquipmentSetInfo = function(id) return id == 1 and "Tank" or "Fishing" end,
    GetItemIDs = function(id) return id == 1 and { [1] = 400, [5] = 401 } or { [16] = 402, [1] = 400 } end,
  }
end

test("equipment sets: #set and set:name search; set items are never sold", function()
  local env, R = boot(setsEnv)
  env.__addItem(0, 1, 400, 1, { name = "Helm", quality = 0, sell = 100 })
  env.__addItem(0, 2, 402, 1, { name = "Pole", quality = 1, sell = 100 })
  env.__addItem(0, 3, 403, 1, { name = "Rag", quality = 0, sell = 100 })
  R.Data:ScanInventory()
  local function e(id) return { link = "x", id = id, count = 1, lname = "x" } end
  assert(R.Search:Matches("#set", e(400)) and not R.Search:Matches("#set", e(403)))
  assert(R.Search:Matches("set:tank", e(400)) and R.Search:Matches("set:fish", e(400)), "item in two sets")
  assert(not R.Search:Matches("set:tank", e(402)) and R.Search:Matches("set:fishing", e(402)))
  env.MerchantFrame.shown = true
  local list = R.Junk:Collect()
  assert(#list == 1 and list[1][2] == 3, "only the non-set grey sells, got " .. #list)
  assert(#R.Items:SetList() == 2)
end)

test("plugin API: keyword, category and column; plugin errors are contained", function()
  local env, R = boot()
  open(env, R)
  assert(R:GetAPIVersion() == 1)
  assert(R:RegisterSearchKeyword("cheap", function(e) return (e.info and e.info.sell or 0) < 20 end))
  assert(not R:RegisterSearchKeyword("junk", function() return true end), "built-ins are protected")
  assert(R:RegisterSearchKeyword("boom", function() error("plugin bug") end))
  env.__addItem(0, 1, 500, 1, { name = "Pebble", sell = 5 })
  env.__addItem(0, 2, 501, 1, { name = "Gem", sell = 5000 })
  env.__ev("BAG_UPDATE", 0); env.__ev("BAG_UPDATE_DELAYED"); env.__settle(4)
  local id = R:RegisterCategory("cheap", "Cheap stuff", nil, function(e) return R.Search:Matches("#cheap", e) end)
  assert(id == "plugin:cheap" and R.Categories:Get(id))
  R:RegisterColumn({ key = "plug", title = "Plug", value = function(e) return e.count * 2 end })
  assert(not R:RegisterColumn({ key = "plug", title = "Dup", value = function() end }), "duplicate key")
  env.__settle(4)
  assert(R.UI.catCounts[id] == 1, "plugin category count " .. tostring(R.UI.catCounts[id]))
  assert(R.Columns.byKey.plug and R.Columns:ValueOf("plug", R.UI.entries[1]) == 2)
  R.UI.search = "#boom"; R:RequestRefresh(); env.__settle(4)
  assert(#R.UI.entries == 0 and not env.__errors, "erroring keyword matches nothing, no error")
  R:UnregisterCategory("cheap")
  assert(not R.Categories:Get(id))
end)

test("currencies: backpack-tracked currencies are stored and shown in the footer", function()
  local env, R = boot(function(e)
    e.C_CurrencyInfo = { GetBackpackCurrencyInfo = function(i)
      if i == 1 then return { name = "Honor", quantity = 1234, iconFileID = 111, currencyTypesID = 1 } end
      if i == 2 then return { name = "Marks", quantity = 7, iconFileID = 222, currencyTypesID = 2 } end
    end }
  end)
  open(env, R)
  local cur = R.Data.me.currencies
  assert(#cur == 2 and cur[1].q == 1234 and cur[2].n == "Marks")
  local txt = R.UI.currencyText:GetText()
  assert(txt:find("1234", 1, true) and txt:find("|T222:0|t 7", 1, true), txt)
  R.settings.showCurrencies = false; R.UI:UpdateFooter()
  assert(R.UI.currencyText:GetText() == "")
  local _, R2 = boot(function(e)
    e.RummageDB = { version = 4, settings = {}, chars = { ["Alt-R"] = { containers = {}, currencies = { "bad", { n = "Ok", q = 3 }, { n = 5 } } } } }
  end)
  local c2 = R2.db.chars["Alt-R"].currencies
  assert(#c2 == 1 and c2[1].n == "Ok", "sanitizer keeps only valid entries")
end)

test("transfer to mail: Send tab open adds listed unbound items, stops when full", function()
  local env, R = boot()
  open(env, R)
  env.MailFrame = env.CreateFrame("Frame", "MailFrame"); env.MailFrame.shown = true
  env.SendMailFrame = env.CreateFrame("Frame", "SendMailFrame"); env.SendMailFrame.shown = true
  env.ATTACHMENTS_MAX_SEND = 1
  local attached = {}
  env.GetSendMailItem = function(i) if attached[i] then return "Item", 1, 1, attached[i].count end end
  env.GetSendMailItemLink = function(i) return attached[i] and attached[i].link end
  env.ClickSendMailItemButton = function(i)
    local p = env.__picked; local item = env.__bags[p[1]][p[2]]
    attached[i] = { p[1], p[2], link = item.link, count = item.count }; env.__bags[p[1]][p[2]] = nil
  end
  env.__addItem(0, 1, 600, 1, { name = "Ore" })
  env.__addItem(0, 2, 601, 1, { name = "Bar" })
  env.__addItem(0, 3, 602, 1, { name = "Gem" })
  env.__ev("BAG_UPDATE", 0); env.__ev("BAG_UPDATE_DELAYED"); env.__settle(4)
  assert(R.Mover:OpenTarget() == "mail")
  R.UI:UpdateFooter()
  assert(R.UI.btnTransfer:IsShown() and R.UI.transferTarget == "mail", "To Mail button")
  local boundE = R.UI.entries[1]
  boundE.bound = true               -- the first listed item is bound: skipped
  R.UI:DoTransfer()
  env.__tick(5)
  assert(attached[1] and not attached[2], "one attached")
  assert(not (attached[1][1] == boundE.bag and attached[1][2] == boundE.slot), "bound item skipped")
  assert(chatHas(env, "Requested 1 placement(s) in the mail; observed 1") and chatHas(env, "full"), "reports full")
  assert(not R.Mover:Busy())
  R.settings.transferTargets = false
  assert(R.Mover:OpenTarget() == nil, "setting off")
end)

---------------------------------------------------------------------------
-- 1.9.0: Guild Bank window
---------------------------------------------------------------------------
-- Fake guild vault: two tabs ("Mats": deposit, 2 withdrawals left; "Officer": no deposit).
local function guildEnv(e)
  local gb = { current = 1, queried = {}, closed = 0, cursor = false, items = { {}, {} },
    tabs = { { name = "Mats", icon = 111, view = true, dep = true, rem = 2 },
             { name = "Officer", icon = 222, view = true, dep = false, rem = 0 } } }
  e.__gb = gb
  e.GetGuildInfo = function() return "Lions", "Member", 3, nil end
  e.GetNumGuildBankTabs = function() return #gb.tabs end
  e.GetGuildBankTabInfo = function(t) local x = gb.tabs[t]; if x then return x.name, x.icon, x.view, x.dep, 5, x.rem end end
  e.GetGuildBankItemLink = function(t, s) local it = gb.items[t] and gb.items[t][s]; return it and it.link end
  e.GetGuildBankItemInfo = function(t, s)
    local it = gb.items[t] and gb.items[t][s]
    if it then return 134400, it.count, false, false, 1 end
  end
  e.QueryGuildBankTab = function(t) gb.queried[#gb.queried + 1] = t end
  e.GetCurrentGuildBankTab = function() return gb.current end
  e.SetCurrentGuildBankTab = function(t) gb.current = t end
  e.PickupGuildBankItem = function(t, s) gb.picked = { t, s } end
  e.AutoStoreGuildBankItem = function(t, s) gb.stored = { t, s } end
  e.GetGuildBankMoney = function() return 5000 end
  e.CloseGuildBankFrame = function() gb.closed = gb.closed + 1 end
  e.CursorHasItem = function() return gb.cursor end
  e.GuildBankFrame = e.CreateFrame("Frame", "GuildBankFrame")
  e.GuildBankFrame.shown = false
  gb.add = function(tab, slot, id, count, name)
    e.__items[id] = { name = name or ("Item" .. id), quality = 1 }
    gb.items[tab][slot] = { link = "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. (name or ("Item" .. id)) .. "]|h|r", count = count or 1 }
  end
  gb.add(1, 1, 700, 20, "Copper Ore")
  gb.add(1, 2, 701, 1, "Lion Banner")
  gb.add(2, 1, 700, 5, "Copper Ore")
end

-- Opens the vault and answers every tab query.
local function openVault(env)
  env.__ev("GUILDBANKFRAME_OPENED"); env.__settle(2)
  for _ = 1, 3 do env.__ev("GUILDBANKBAGSLOTS_CHANGED"); env.__settle(2) end
end

test("guild bank: opens in its own window beside Bags, each with its own geometry", function()
  local env, R = boot(guildEnv)
  local Bags, Bank, Guild = R.UI, R.BankUI, R.GuildUI
  assert(Guild and Guild.frame and Guild.frame ~= Bags.frame and Guild.frame ~= Bank.frame, "third window")
  assert(Guild.view == "guild" and env.GuildBankFrame.rummageHidden, "Blizzard's guild bank hidden")
  assert(not Bags.frame:IsShown())
  openVault(env)
  assert(Guild.frame:IsShown() and Bags.frame:IsShown(), "vault opens Guild Bank and Bags")
  assert(Guild.frame:GetRight() <= Bags.frame:GetLeft(), "Guild Bank sits left of Bags")
  -- independent geometry
  Guild.frame:SetSize(700, 450)
  Guild:SavePosition()
  assert(R.settings.guild.width == 700 and R.settings.guild.height == 450, "guild geometry stored apart")
  assert(R.settings.width ~= 700 and (not R.settings.bank or R.settings.bank.width ~= 700), "bags/bank untouched")
  Bags.frame:SetSize(820, 500); Bags:SavePosition()
  assert(R.settings.guild.width == 700 and R.settings.width == 820)
  Guild:ResetPosition()
  assert(R.settings.guild.width == R.defaults.width and R.settings.width == 820, "guild reset leaves bags alone")
  -- Bank and Guild Bank can be open together with Bags
  Bank:Open(); env.__settle(2)
  assert(Bank.frame:IsShown() and Guild.frame:IsShown() and Bags.frame:IsShown())
  Bank:Close()
  -- closing Bags keeps the vault open; leaving the vault closes what it opened
  Bags:Close()
  assert(env.__gb.closed == 0, "closing Bags must not close the vault")
  env.__ev("GUILDBANKFRAME_CLOSED"); env.__settle(2)
  assert(not Guild.frame:IsShown(), "leaving closes the Guild Bank window")
  openVault(env)
  assert(Bags.frame:IsShown(), "Bags reopened beside it")
  env.__ev("GUILDBANKFRAME_CLOSED"); env.__settle(2)
  assert(not Bags.frame:IsShown(), "Bags closes again when the visit opened it")
  openVault(env)
  Guild:Close()
  assert(env.__gb.closed == 1, "closing the Guild Bank window closes the vault")
  -- setting: don't open Bags beside it
  env.__ev("GUILDBANKFRAME_CLOSED"); env.__settle(2)
  Bags:Close()
  R.settings.guildOpenBags = false
  openVault(env)
  assert(Guild.frame:IsShown() and not Bags.frame:IsShown(), "guildOpenBags off")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("guild bank: tabs are queried one by one, scanned and cached per guild", function()
  local env, R = boot(guildEnv)
  env.__ev("GUILDBANKFRAME_OPENED"); env.__settle(2)
  assert(#env.__gb.queried == 1 and env.__gb.queried[1] == 1, "current tab queried first")
  env.__ev("GUILDBANKBAGSLOTS_CHANGED"); env.__settle(2)
  assert(env.__gb.queried[2] == 2 and R.GuildBank:IsLoaded(1) and not R.GuildBank:IsLoaded(2), "then the next")
  env.__ev("GUILDBANKBAGSLOTS_CHANGED"); env.__settle(2)
  local g = R.db.guilds["Lions-TestRealm"]
  assert(g and g.name == "Lions" and g.money == 5000 and g.numTabs == 2, "record")
  assert(g.containers[1001].name == "Mats" and g.containers[1001].slots[1].c == 20, "tab 1 scanned")
  assert(g.containers[1002].slots[1].i == 700, "tab 2 scanned")
  local Guild = R.GuildUI
  assert(Guild.bagFilter == 1001, "opens on the vault's current tab")
  R.settings.rememberCategory = false
  Guild:Close(); env.__gb.closed = 0
  env.__ev("GUILDBANKFRAME_CLOSED"); env.__settle(2)
  env.__gb.current = 2
  env.__ev("GUILDBANKFRAME_OPENED"); env.__settle(2)
  env.__ev("GUILDBANKBAGSLOTS_CHANGED"); env.__settle(2)
  env.__ev("GUILDBANKBAGSLOTS_CHANGED"); env.__settle(2)
  assert(Guild.frame:IsShown() and Guild.bagFilter == 1002, "current tab kept with rememberCategory off")
  R.settings.rememberCategory = true
  env.__gb.current = 1
  Guild:SetGuildTab(nil); env.__settle(4)
  assert(#Guild.entries == 2, "all tabs, ore combined: " .. #Guild.entries)
  -- tab selector
  Guild:SetGuildTab(2); env.__settle(4)
  assert(env.__gb.current == 2 and #Guild.entries == 1 and Guild.tabGuild.text:GetText() == "Officer", "tab 2 selected")
  -- tooltip lists the guild bank count
  local tt = env.GameTooltip
  tt.__lines = nil; tt.rummageID = nil
  R.Tooltip:Add(tt, "|cffffffff|Hitem:700::::::::60:::::|h[Copper Ore]|h|r")
  local found = false
  for _, l in ipairs(tt.__lines or {}) do if l:find("Lions", 1, true) and l:find("25", 1, true) then found = true end end
  assert(found, "guild count in tooltip")
  R.settings.tooltipGuildCounts = false; R:Fire("DATA_CHANGED")
  tt.__lines = nil; tt.rummageID = nil
  R.Tooltip:Add(tt, "|cffffffff|Hitem:700::::::::60:::::|h[Copper Ore]|h|r")
  assert(not tt.__lines, "setting off")
  -- sanitizer keeps valid records and drops garbage
  local _, R2 = boot(function(e)
    e.RummageDB = { version = 4, settings = {}, chars = {}, guilds = {
      ["Ok-R"] = { name = "Ok", containers = { [1001] = { size = 98, slots = { [1] = { l = "x", c = 1 }, [500] = { l = "y", c = 1 }, [2] = "bad" } }, [5] = { slots = {} } } },
      ["Bad-R"] = { containers = {} }, [7] = { name = "n" } } }
  end)
  local ok = R2.db.guilds["Ok-R"]
  assert(ok and not R2.db.guilds["Bad-R"] and not R2.db.guilds[7], "garbage records dropped")
  assert(ok.containers[1001].slots[1] and not ok.containers[1001].slots[500] and not ok.containers[1001].slots[2] and not ok.containers[5])
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("guild bank: dropping a cursor item from Bags deposits into a free slot of the tab", function()
  local env, R = boot(guildEnv)
  openVault(env)
  local Guild = R.GuildUI
  env.__gb.cursor = true
  Guild:SetGuildTab(1); env.__settle(2)
  Guild.list.scripts.OnReceiveDrag(Guild.list)
  assert(env.__gb.picked and env.__gb.picked[1] == 1 and env.__gb.picked[2] == 3, "first free slot of tab 1")
  -- the tab icons in the footer accept drops too
  env.__gb.picked = nil
  Guild:UpdateFooter()
  local btn = Guild.bagButtons[1]
  assert(btn and btn.bag == 1001)
  btn.scripts.OnReceiveDrag(btn)
  assert(env.__gb.picked and env.__gb.picked[2] == 3, "deposit via tab icon")
  -- no deposit rights on tab 2
  env.__gb.picked = nil
  Guild:SetGuildTab(2); env.__settle(2)
  Guild:DropCursorItem()
  assert(not env.__gb.picked and chatHas(env, "can't deposit"), "deposit refused")
  -- a full tab is reported
  Guild:SetGuildTab(1)
  for s = 1, 98 do if not env.__gb.items[1][s] then env.__gb.add(1, s, 800 + s) end end
  Guild:DropCursorItem()
  assert(not env.__gb.picked and chatHas(env, "full"), "full tab")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("guild bank: right-click and drag withdraw to the bags within the limits", function()
  local env, R = boot(guildEnv)
  openVault(env)
  local Guild = R.GuildUI
  Guild:SetGuildTab(1); env.__settle(4)
  local banner
  for _, e in ipairs(Guild.entries) do if e.id == 701 then banner = e end end
  assert(banner and banner.bag == 1001 and banner.slot == 2)
  Guild:GuildClick(banner, "RightButton")
  assert(env.__gb.stored and env.__gb.stored[1] == 1 and env.__gb.stored[2] == 2, "auto-stored into bags")
  assert(R.GuildBank:Limits(1).remaining == 1, "local withdrawal count")
  -- drag picks the item up (drop it on Bags to finish)
  Guild:GuildDrag(banner)
  assert(env.__gb.picked and env.__gb.picked[2] == 2, "drag picks up")
  -- setting: right-click picks up / does nothing
  env.__gb.stored, env.__gb.picked = nil, nil
  R.settings.guildRightClick = "cursor"
  Guild:GuildClick(banner, "RightButton")
  assert(env.__gb.picked and not env.__gb.stored)
  R.settings.guildRightClick = "none"; env.__gb.picked = nil
  Guild:GuildClick(banner, "RightButton")
  assert(not env.__gb.picked and not env.__gb.stored)
  R.settings.guildRightClick = "bags"
  -- no withdrawals left
  R.GuildBank:Limits(1).remaining = 0
  Guild:GuildClick(banner, "RightButton")
  assert(not env.__gb.stored and chatHas(env, "No withdrawals left"), "limit enforced")
  -- footer shows the limit
  R.GuildBank:Limits(1).remaining = 3
  Guild:UpdateFooter()
  assert(Guild.cachedText:GetText():find("3 withdrawals left", 1, true), Guild.cachedText:GetText())
  -- full bags
  R.GuildBank:Limits(1).remaining = 5
  for s = 1, 8 do env.__addItem(0, s, 900 + s, 1) end
  R.Data:ScanInventory()
  Guild:GuildClick(banner, "RightButton")
  assert(not env.__gb.stored and chatHas(env, "bags are full"), "full bags")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("guild bank: away from the vault the cached view is view-only", function()
  local env, R = boot(guildEnv)
  openVault(env)
  env.__ev("GUILDBANKFRAME_CLOSED"); env.__settle(2)
  local Guild = R.GuildUI
  env.SlashCmdList.RUMMAGE("guild"); env.__settle(4)
  assert(Guild.frame:IsShown() and not Guild:GuildLive(), "opened from cache")
  Guild:SetGuildTab(nil); env.__settle(4)
  assert(#Guild.entries == 2, "cached items listed")
  env.__gb.cursor = true
  Guild:GuildClick(Guild.entries[1], "RightButton")
  Guild:GuildDrag(Guild.entries[1])
  Guild:DropCursorItem()
  assert(not env.__gb.stored and not env.__gb.picked, "no item actions while away")
  Guild:UpdateFooter()
  assert(Guild.cachedText:GetText():find("Cached guild bank", 1, true), Guild.cachedText:GetText())
  assert(not Guild.btnTransfer:IsShown() and not Guild.btnRestack:IsShown(), "no footer actions")
  -- a character outside any guild still sees the cache, and the guild menu lists it
  env.GetGuildInfo = function() return nil end
  R:RequestRefresh(); env.__settle(4)
  Guild:ShowGuildMenu(Guild.charBtn)
  Guild.guildKey = "Lions-TestRealm"; R:RequestRefresh(); env.__settle(4)
  assert(#Guild.entries == 2 and Guild:Char().name == "Lions", "cached guild selectable")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

-- Cached bank (this character) and cached guild banks (own guild and an alt's guild).
local function cachedEnv(e)
  guildEnv(e)
  e.__items[710] = { name = "Bank Gem", quality = 2 }
  e.__items[720] = { name = "Wolf Pelt", quality = 1 }
  local function link(id, n) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. n .. "]|h|r" end
  e.RummageDB = { version = 4, settings = {}, chars = {
      ["Tester-TestRealm"] = { name = "Tester", realm = "TestRealm", containers = {
        [-1] = { size = 4, slots = { [1] = { l = link(700, "Copper Ore"), c = 3, i = 700 }, [2] = { l = link(710, "Bank Gem"), c = 1, i = 710 } } } } },
      ["Alt-TestRealm"] = { name = "Alt", realm = "TestRealm", guildKey = "Wolves-TestRealm", containers = {} } },
    guilds = {
      ["Lions-TestRealm"] = { name = "Lions", realm = "TestRealm", lastSeen = 900, numTabs = 1, containers = {
        [1001] = { name = "Mats", size = 98, slots = { [1] = { l = link(700, "Copper Ore"), c = 20, i = 700 } } } } },
      ["Wolves-TestRealm"] = { name = "Wolves", realm = "TestRealm", numTabs = 1, containers = {
        [1001] = { name = "Pelts", size = 98, slots = { [4] = { l = link(720, "Wolf Pelt"), c = 7, i = 720 } } } } } } }
end

test("away from the bank: Bags header buttons open the cached Bank and Guild Bank, view-only", function()
  local env, R = boot(cachedEnv)
  local Bags, Bank, Guild = R.UI, R.BankUI, R.GuildUI
  open(env, R)
  assert(Bags.tabBank:IsShown() and Bags.tabGuildToggle:IsShown(), "header buttons in Bags")
  Bags.tabBank:Click(); env.__settle(4)
  assert(Bank.frame:IsShown() and Bags.frame:IsShown() and Bags.tabBank.active, "Bank opened beside Bags")
  assert(Bank.frame:GetRight() <= Bags.frame:GetLeft(), "Bank left of Bags")
  assert(#Bank.entries == 2 and not Bank:Interactive(), "cached, non-interactive bank")
  assert(Bank.cachedText:GetText() == R.L.cachedBank, Bank.cachedText:GetText())
  Bags.tabGuildToggle:Click(); env.__settle(4)
  assert(Guild.frame:IsShown() and Bags.tabGuildToggle.active, "Guild Bank opened")
  assert(#Guild.entries == 1 and Guild:Char().name == "Lions" and not Guild:GuildLive(), "cached, non-interactive guild bank")
  assert(Guild.cachedText:GetText():find("Cached guild bank", 1, true), Guild.cachedText:GetText())
  -- drops and clicks do nothing but explain; no live API is touched
  env.__gb.cursor = true
  env.__picked = nil
  Bank.list.scripts.OnReceiveDrag(Bank.list)
  Guild.list.scripts.OnReceiveDrag(Guild.list)
  Guild:GuildClick(Guild.entries[1], "RightButton")
  Guild:SetGuildTab(1); env.__settle(4)
  assert(not env.__picked and not env.__gb.picked and not env.__gb.stored, "no moves")
  assert(#env.__gb.queried == 0 and env.__gb.current == 1, "no QueryGuildBankTab / SetCurrentGuildBankTab away")
  assert(chatHas(env, "visit a banker") and chatHas(env, "open the guild vault"), "drop hints")
  -- the alt's guild follows the character chosen in Bags
  Bags.charKey = "Alt-TestRealm"; R:RequestRefresh(); env.__settle(4)
  assert(Guild:Char().name == "Wolves" and #Guild.entries == 1 and Guild.entries[1].id == 720, "alt's guild cache")
  Bags.charKey = nil; R:RequestRefresh(); env.__settle(4)
  -- toggling again closes them
  Bags.tabGuildToggle:Click(); Bags.tabBank:Click(); env.__settle(2)
  assert(not Guild.frame:IsShown() and not Bank.frame:IsShown() and not Bags.tabBank.active and not Bags.tabGuildToggle.active)
  assert(env.__gb.closed == 0, "closing cached windows never calls CloseGuildBankFrame")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("away from the bank: no cache shows the empty state; /rum guild and /rum bank open anywhere", function()
  local env, R = boot()
  env.SlashCmdList.RUMMAGE("guild"); env.__settle(4)
  local Guild, Bank = R.GuildUI, R.BankUI
  assert(Guild.frame:IsShown() and #Guild.entries == 0, "guild window opens without a cache")
  assert(Guild.emptyText:GetText() == R.L.notInGuild and Guild:Char().name == R.L.noGuild, Guild.emptyText:GetText())
  -- guild info arriving after login: the window names the guild even with nothing cached
  env.GetGuildInfo = function() return "Bears", "Member", 3, nil end
  env.__ev("PLAYER_GUILD_UPDATE"); env.__settle(4)
  assert(Guild:Char().name == "Bears" and Guild.charBtn.text:GetText():find("Bears", 1, true), "guild name shown")
  assert(R.Data.me.guildKey == "Bears-TestRealm" and Guild.emptyText:GetText() == R.L.emptyGuild)
  env.SlashCmdList.RUMMAGE("bank"); env.__settle(4)
  assert(Bank.frame:IsShown() and Bank.emptyText:GetText() == R.L.emptyBank, Bank.emptyText:GetText())
  -- an alt without a known guild shows the empty state too
  local env2, R2 = boot(cachedEnv)
  R2.UI.charKey = "Alt-TestRealm"
  R2.db.chars["Alt-TestRealm"].guildKey = nil
  R2.GuildUI:Open(); env2.__settle(4)
  assert(#R2.GuildUI.entries == 0 and R2.GuildUI.emptyText:GetText() == R2.L.emptyGuild)
  assert(R.L.slashUsage:find("guild", 1, true), "/rum guild documented")
  assert(not env.__errors and not env2.__errors, "errors")
end)

test("key bindings toggle the right window (Bindings.xml)", function()
  local env, R = boot()
  local f = io.open("Rummage/Bindings.xml", "r") or io.open("../Rummage/Bindings.xml", "r")
  assert(f, "Bindings.xml not found")
  local xml = f:read("*a"); f:close()
  local bodies = {}
  for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do bodies[name] = body end
  local function run(name)
    local chunk = assert(loadstring(bodies[name], name))
    setfenv(chunk, env)
    chunk()
    env.__settle(2)
  end
  local Bags, Bank, Guild = R.UI, R.BankUI, R.GuildUI
  run("RUMMAGE_TOGGLE_BANK")
  assert(Bank.frame:IsShown() and not Bags.frame:IsShown(), "Toggle bank opens the Bank window, not Bags")
  run("RUMMAGE_TOGGLE_BANK")
  assert(not Bank.frame:IsShown(), "and closes it again")
  run("RUMMAGE_TOGGLE_GUILD")
  assert(Guild.frame:IsShown() and not Bags.frame:IsShown(), "Toggle guild bank")
  run("RUMMAGE_TOGGLE")
  assert(Bags.frame:IsShown(), "Toggle bags")
  for name in pairs(bodies) do
    assert(env["BINDING_NAME_" .. name], "label for " .. name)
  end
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

---------------------------------------------------------------------------
-- 1.9.1: Bank / Guild Bank dock beside Bags; columns never overflow
---------------------------------------------------------------------------
local function placeBags(R, x, top, scale)
  local f = R.UI.frame
  R.settings.scale = scale or 1
  f:SetScale(scale or 1)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", f.parent, "BOTTOMLEFT", x / (scale or 1), top / (scale or 1))
end

test("bank and guild bank open beside Bags with its height and scale", function()
  local env, R = boot(guildEnv)
  local Bags, Bank, Guild = R.UI, R.BankUI, R.GuildUI
  local rect = Bags.ScreenRect
  -- odd saved geometry, like a window scaled down and parked elsewhere
  R.settings.bank = { width = 900, height = 300, scale = 0.7, point = { "CENTER", "CENTER", 0, 0 } }
  R.settings.guild = { width = 460, height = 300, scale = 0.75, point = { "TOP", "TOP", 0, -20 } }
  Bank:ApplyPosition(); Guild:ApplyPosition()
  open(env, R)
  placeBags(R, 1230, 900, 1.05)
  Bank:Open(); env.__settle(2)
  local bl, bt, bw, bh = rect(Bags.frame)
  local kl, kt, kw, kh = rect(Bank.frame)
  assert(near(Bank.frame:GetScale(), 1.05) and near(kh, bh, 0.5) and near(kt, bt, 0.5), "same scale, height and top")
  assert(near(Bank.frame:GetWidth(), 680), "no wider than Bags: " .. Bank.frame:GetWidth())
  assert(near(kl + kw, bl - 6, 0.5), "directly left of Bags")
  -- guild bank goes beside them without covering either
  Guild:Open(); env.__settle(2)
  local gl, gt, gw = rect(Guild.frame)
  assert(gl + gw <= kl or gl >= bl + bw, "guild doesn't cover the bank or bags")
  assert(gl >= 0 and gl + gw <= 1920 and near(gt, bt, 0.5), "on screen, aligned: " .. gl)
  Guild:Close(); Bank:Close()
  -- Bags at the left edge: they open on its right
  placeBags(R, 20, 900, 1)
  Bank:Open(); env.__settle(2)
  bl, bt, bw = rect(Bags.frame)
  kl = rect(Bank.frame)
  assert(near(kl, bl + bw + 6, 0.5), "right of Bags when the left has no room")
  -- opening Bags pulls an open Bank beside it
  Bags:Close(); Bank.frame:ClearAllPoints(); Bank.frame:SetPoint("CENTER", Bank.frame.parent, "CENTER", 0, 0)
  placeBags(R, 1200, 900, 1)
  Bags:Open(); env.__settle(2)
  bl, bt = rect(Bags.frame)
  kl, kt, kw = rect(Bank.frame)
  assert(near(kl + kw, bl - 6, 0.5) and near(kt, bt, 0.5), "Bank re-docked when Bags opens")
  -- setting off: saved position is used
  Bank:Close()
  R.settings.dockBeside = false
  R.settings.bank.point = { "CENTER", "CENTER", 0, 0 }
  Bank:ApplyPosition()
  Bank:Open(); env.__settle(2)
  assert(Bank.frame:GetPoint() == "CENTER", "dockBeside off keeps the saved spot")
  -- vault opening docks too
  R.settings.dockBeside = true
  Bags:Close(); Bank:Close()
  openVault(env)
  bl = rect(Bags.frame)
  gl, gt, gw = rect(Guild.frame)
  assert(near(gl + gw, bl - 6, 0.5), "guild vault: Guild Bank beside Bags")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("columns that don't fit a narrow window are left out, never drawn past the edge", function()
  local env, R = boot()
  open(env, R)
  local UI = R.UI
  UI.frame:SetSize(460, 400); UI:Layout()
  local width = UI:ListWidth()
  local names = {}
  for _, L in ipairs(UI.colLayout) do
    names[#names + 1] = L.col.key
    if L.col.key ~= "name" then assert(L.x + L.w <= width + 2, L.col.key .. " overflows: " .. (L.x + L.w) .. " > " .. width) end
  end
  local hasName = false
  for _, k in ipairs(names) do if k == "name" then hasName = true end end
  assert(hasName, "name column kept")
  local wide = #UI.colLayout
  UI.frame:SetSize(1400, 400); UI:Layout()
  assert(#UI.colLayout >= wide, "wider window shows more columns")
  assert(UI.colhead.SetClipsChildren, "header clipped")
end)

test("categories are an icon rail; Bank and Guild Bank keep it on the edge away from Bags", function()
  local env, R = boot(guildEnv)
  local Bags, Bank, Guild = R.UI, R.BankUI, R.GuildUI
  assert(R.settings.compactSidebar == true, "icon rail by default")
  open(env, R)
  local b = Bags.catButtons[1]
  assert(b and not b.text.shown and b.count.shown and b.icon.width == 24, "icon only, count badge")
  assert(b.count:GetText() ~= nil, "count text")
  b.scripts.OnEnter(b)
  assert(env.GameTooltip:GetText() == b.cat.name, "name in the tooltip")
  assert(Bags.sidebar:GetPoint() == "TOPLEFT" and Bags:RailSide() == "LEFT", "Bags: rail on the left (layout A)")
  -- Bank docked left of Bags: rail on its left (outer) edge
  placeBags(R, 1230, 900, 1)
  Bank:Open(); env.__settle(4)
  assert(Bank:RailSide() == "LEFT" and Bank.sidebar:GetPoint() == "TOPLEFT", "bank left of Bags: rail left")
  Bank:Close()
  -- Bags at the left edge: Bank docks right, rail moves to its right edge, list on the Bags side
  placeBags(R, 20, 900, 1)
  Guild:Open(); env.__settle(4)
  assert(Guild:RailSide() == "RIGHT" and Guild.sidebar:GetPoint() == "TOPRIGHT", "guild right of Bags: rail right")
  local p, rel, rp = Guild.content:GetPoint(2)
  assert(p == "BOTTOMRIGHT" and rel == Guild.sidebar and rp == "BOTTOMLEFT", "list sits left of the rail")
  local gb = Guild.catButtons[1]
  assert(gb.bar:GetPoint() == "TOPRIGHT", "active bar on the outer edge")
  -- labelled sidebar still available
  R.settings.compactSidebar = false
  Bags:Layout(); Bags:UpdateSidebar()
  assert(Bags.catButtons[1].text.shown and Bags.addCatBtn.text:GetText() == "+ New category", "labels back")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("upgrading to DB v5 turns the icon rail on once", function()
  local _, R = boot(function(e)
    e.RummageDB = { version = 4, settings = { compactSidebar = false }, chars = {} }
  end)
  assert(R.settings.compactSidebar == true and R.db.version == 7, "migrated")
  local _, R2 = boot(function(e)
    e.RummageDB = { version = 5, settings = { compactSidebar = false }, chars = {} }
  end)
  assert(R2.settings.compactSidebar == false, "a later choice is kept")
end)

test("name column fills the window once the list's real width is known", function()
  local env, R = boot()
  open(env, R)
  local UI = R.UI
  local function nameW() for _, L in ipairs(UI.colLayout) do if L.col.key == "name" then return L.w end end end
  -- Layout ran before the list had a size: the name column falls back to its minimum
  UI.list:SetWidth(0); UI:ComputeColumns()
  local early = nameW()
  -- the list's anchors resolve to its real width: columns are recomputed, name fills it
  UI.list:SetWidth(900); env.__settle(2)
  local fixed = 0
  for _, L in ipairs(UI.colLayout) do if L.col.key ~= "name" then fixed = fixed + L.w + 4 end end
  assert(nameW() > early and nameW() >= 900 - 14 - fixed - 10, "name " .. nameW() .. " (was " .. early .. ")")
  -- the same width again does not recompute
  local v = UI.colVersion
  UI.list:SetWidth(900); env.__settle(2)
  assert(UI.colVersion == v, "no recompute for an unchanged width")
end)

---------------------------------------------------------------------------
-- 1.10.0: drag items onto categories, search grouping and quotes, #usable, #upgrade
---------------------------------------------------------------------------
local function entryFor(env, R, bag, slot, id, def)
  local link = env.__addItem(bag, slot, id, 1, def)
  local e = { link = link, id = id, count = 1, bag = bag, slot = slot, slots = {}, vals = {} }
  R.Items:Prepare(e, R.Data.me, true, true)
  return e
end

test("search: parentheses, ! on groups, quoted phrases; old syntax unchanged", function()
  local env, R = boot()
  local S = R.Search
  local cloth = entryFor(env, R, 0, 1, 501, { name = "Bolt of Linen Cloth", quality = 1, ilvl = 5, type = "Trade Goods", sub = "Cloth" })
  local band = entryFor(env, R, 0, 2, 502, { name = "Linen Bandage", quality = 1, ilvl = 8, type = "Consumable", sub = "Bandage" })
  local helm = entryFor(env, R, 0, 3, 503, { name = "Helm of the Bear", quality = 3, ilvl = 25, type = "Armor", sub = "Mail", equip = "INVTYPE_HEAD", class = 4, subclass = 3 })
  local blade = entryFor(env, R, 0, 4, 504, { name = "Epic Blade", quality = 4, ilvl = 15, type = "Weapon", sub = "Swords", equip = "INVTYPE_WEAPON", class = 2 })
  local rag = entryFor(env, R, 0, 5, 505, { name = "q:rare rag", quality = 0, ilvl = 1 })
  local function only(q, ...)
    local want = {}
    for _, e in ipairs({ ... }) do want[e] = true end
    for _, e in ipairs({ cloth, band, helm, blade, rag }) do
      local got = S:Matches(q, e)
      assert(got == (want[e] or false), q .. ": " .. e.name .. " gave " .. tostring(got))
    end
  end
  only('"linen cloth"', cloth)
  only('name:"of the bear"', helm)
  only("(q:rare | q:epic) ilvl>20", helm)
  only("(q:rare | q:epic) ilvl>10", helm, blade)
  only("!(linen | q:poor)", helm, blade)
  only('!"linen cloth" linen', band)
  only('"q:rare"', rag)                       -- quoted: literal text, not a field
  only("q:rare ilvl>20 | #junk", helm, rag)   -- unchanged OR-of-ANDs
  only("linen & cloth", cloth)
  only("(q:epic", blade)                      -- unclosed group closes at the end
  only("q:epic )", blade)                     -- stray ")" ignored
  only("((linen))", cloth, band)
end)

local function tipEnv(e)
  local orig = e.CreateFrame
  e.__red = {}
  e.CreateFrame = function(kind, name, ...)
    local f = orig(kind, name, ...)
    if name == "RummageUsableScanTooltip" then
      e.__tipScans = 0
      f.SetHyperlink = function(self, link) self.__id = tonumber(tostring(link):match("item:(%d+)")); e.__tipScans = e.__tipScans + 1 end
      f.NumLines = function() return 2 end
      e.RummageUsableScanTooltipTextLeft2 = {
        IsShown = function() return true end,
        GetText = function() return "Mail" end,
        GetTextColor = function() if e.__red[f.__id] then return 1, 0.12, 0.12 end return 1, 1, 1 end,
      }
    end
    return f
  end
end

test("#usable checks proficiency through the tooltip, cached per link", function()
  local env, R = boot(tipEnv)
  local mail = entryFor(env, R, 0, 1, 601, { name = "Mail Helm", ilvl = 20, req = 10, equip = "INVTYPE_HEAD", class = 4, subclass = 3 })
  local cloth = entryFor(env, R, 0, 2, 602, { name = "Cloth Cap", ilvl = 20, req = 10, equip = "INVTYPE_HEAD", class = 4, subclass = 1 })
  local high = entryFor(env, R, 0, 3, 603, { name = "Big Helm", ilvl = 60, req = 70, equip = "INVTYPE_HEAD", class = 4, subclass = 1 })
  env.__red[601] = true   -- "Mail" in red: can't wear mail
  assert(not R.Search:Matches("#usable", mail), "mail is not usable")
  assert(R.Search:Matches("#usable", cloth), "cloth is usable")
  assert(not R.Search:Matches("#usable", high), "level 70 item above level 60")
  local scans = env.__tipScans
  R.Search:Matches("#usable", mail); R.Search:Matches("#usable", cloth)
  assert(env.__tipScans == scans, "cached per link")
  env.__red[601] = nil
  env.__ev("SKILL_LINES_CHANGED")   -- learned mail
  assert(R.Search:Matches("#usable", mail) and env.__tipScans > scans, "re-checked after a skill change")
end)

test("#upgrade without Pawn uses the item-level rules against equipped gear", function()
  local env, R = boot(tipEnv)
  env.__items[700] = { name = "Old Helm", quality = 1, ilvl = 10, equip = "INVTYPE_HEAD", class = 4, subclass = 1 }
  env.__equipped = { [1] = "|cffffffff|Hitem:700::::::::60:::::|h[Old Helm]|h|r" }
  local better = entryFor(env, R, 0, 1, 701, { name = "New Helm", ilvl = 20, equip = "INVTYPE_HEAD", class = 4, subclass = 1 })
  local worse = entryFor(env, R, 0, 2, 702, { name = "Worse Helm", ilvl = 5, equip = "INVTYPE_HEAD", class = 4, subclass = 1 })
  local mail = entryFor(env, R, 0, 3, 703, { name = "Mail Helm", ilvl = 30, equip = "INVTYPE_HEAD", class = 4, subclass = 3 })
  local boots = entryFor(env, R, 0, 4, 704, { name = "Boots", ilvl = 3, equip = "INVTYPE_FEET", class = 4, subclass = 1 })
  local rag = entryFor(env, R, 0, 5, 705, { name = "Rag", ilvl = 30 })
  env.__red[703] = true
  assert(R.Search:Matches("#upgrade", better), "higher item level")
  assert(not R.Search:Matches("#upgrade", worse), "lower item level")
  assert(not R.Search:Matches("#upgrade", mail), "can't wear it")
  assert(R.Search:Matches("#upgrade", boots), "empty slot")
  assert(not R.Search:Matches("#upgrade", rag), "not gear")
  -- equipping something better re-evaluates
  env.__items[706] = { name = "Great Helm", quality = 1, ilvl = 50, equip = "INVTYPE_HEAD", class = 4, subclass = 1 }
  env.__equipped[1] = "|cffffffff|Hitem:706::::::::60:::::|h[Great Helm]|h|r"
  env.__ev("PLAYER_EQUIPMENT_CHANGED", 1)
  assert(not R.Search:Matches("#upgrade", better), "no longer an upgrade")
  R.settings.upgradeIlvlFallback = false
  assert(not R.Search:Matches("#upgrade", boots), "fallback off: Pawn only")
end)

test("drag an item onto a custom category adds it; built-ins refuse; + starts a category", function()
  local env, R = boot()
  open(env, R)
  local UI = R.UI
  local herb = entryFor(env, R, 0, 1, 801, { name = "Peacebloom", type = "Trade Goods" })
  local ore = entryFor(env, R, 0, 2, 802, { name = "Copper Ore", type = "Trade Goods" })
  local idx = R.Categories:AddCustom("Herbs", "")
  local cat = R.Categories:Get("custom" .. idx)
  assert(cat.filter(herb) and cat.filter(ore), "empty filter, no items: matches everything as before")
  local cleared = 0
  env.ClearCursor = function() cleared = cleared + 1 end
  env.CursorHasItem = function() return true end
  env.GetCursorInfo = function() return "item", 801, herb.link end
  assert(UI:DropOnCategory(cat))
  assert(R.db.categories[idx].items[801] and cleared == 1, "added, item returned to its slot")
  assert(cat.filter(herb) and not cat.filter(ore), "only the added item now")
  assert(chatHas(env, "Added"))
  UI:DropOnCategory(cat)
  assert(chatHas(env, "already in"))
  -- a filter and added items together: either matches
  R.db.categories[idx].query = "ore"
  assert(cat.filter(herb) and cat.filter(ore))
  -- built-in categories don't take items
  assert(UI:DropOnCategory(R.Categories:Get("trade")))
  assert(chatHas(env, "your own categories"))
  -- the sidebar button reacts to a drop
  R.Data:ScanInventory(); R:RequestRefresh(); env.__settle(4); UI.catOffset = 99; UI:UpdateSidebar()
  local btn
  for _, b in pairs(UI.catButtons) do if b.cat and b.cat.id == "custom" .. idx then btn = b end end
  assert(btn, "custom category button shown")
  R.Categories:RemoveItem(idx, 801)
  btn.scripts.OnReceiveDrag(btn)
  assert(R.db.categories[idx].items[801], "OnReceiveDrag adds")
  -- removing from the menu
  assert(R.Categories:RemoveItem(idx, 801) and R.db.categories[idx].items == nil)
  -- drop on "+": prompt, then a category holding just that item
  env.GetCursorInfo = function() return "item", 802, ore.link end
  UI.addCatBtn.scripts.OnReceiveDrag(UI.addCatBtn)
  assert(env.__popup and env.__popup.which == "RUMMAGE_NEW_CATEGORY" and tostring(env.__popup.args[1]):find("Copper Ore", 1, true))
  local dlg = { editBox = { GetText = function() return "Ores" end } }
  env.StaticPopupDialogs.RUMMAGE_NEW_CATEGORY.OnAccept(dlg)
  local n = #R.db.categories
  assert(R.db.categories[n].name == "Ores" and R.db.categories[n].query == "" and R.db.categories[n].items[802])
  assert(UI.category == "custom" .. n)
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("custom categories group into sections across configurable sidebar columns", function()
  local env, R = boot()
  open(env, R)
  R.Categories:AddCustom("Ores", "", nil, nil, "Materials")
  R.Categories:AddCustom("Herbs", "", nil, nil, "Materials")
  R.Categories:AddCustom("Potions", "", nil, nil, "Consumables")
  R:RequestRefresh()
  env.__settle(4)
  R.settings.categoryColumns = 2
  R.settings.sidebarSide = "right"
  R.UI.sidebar:SetHeight(520)
  R.UI:Layout()
  R.UI:UpdateSidebar()
  assert(R.UI:RailSide() == "RIGHT", "explicit rail side")
  assert(R.UI.sidebar:GetWidth() == 88, "two compact category bars")
  local sections, secondColumn = {}, false
  for _, b in pairs(R.UI.catHeaderButtons) do
    if b:IsShown() and b.section then sections[b.section] = true end
  end
  for _, b in pairs(R.UI.catButtons) do
    if b:IsShown() and b.cat and b.cat.custom then
      local _, _, _, x = b:GetPoint(1)
      if x and x >= 44 then secondColumn = true end
    end
  end
  assert(sections.Materials and sections.Consumables,
    "named section headers rendered")
  assert(secondColumn, "categories flow into the next bar")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("random pet and mount commands use supported collection APIs", function()
  local env, R = boot()
  local favoriteOnly, mount
  env.C_PetJournal = {
    SummonRandomPet = function(favorites) favoriteOnly = favorites end,
  }
  env.C_MountJournal = {
    SummonByID = function(id) mount = id end,
  }
  env.SlashCmdList.RUMMAGE("pet favorite")
  assert(favoriteOnly == true, "favorite pet mode")
  env.SlashCmdList.RUMMAGE("pet")
  assert(favoriteOnly == false, "all-pet mode")
  env.SlashCmdList.RUMMAGE("mount")
  assert(mount == 0, "uses the client random-mount entry")
  assert(R.L.slashUsage:find("pet", 1, true) and R.L.slashUsage:find("mount", 1, true), "commands documented")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("added category items survive sanitize and export/import", function()
  local env, R = boot(function(e)
    e.RummageDB = { version = 5, settings = {}, chars = {}, categories = {
      { name = "Mine", query = "", items = { [10] = true, [11] = true, bad = true, [12] = "x", [-3] = true } },
      { name = "Other", query = "q:rare", items = "nope" },
    } }
  end)
  local c1, c2 = R.db.categories[1], R.db.categories[2]
  assert(c1.items[10] and c1.items[11] and not c1.items.bad and not c1.items[12] and not c1.items[-3])
  assert(c2.items == nil)
  local str = R:ExportSettings()
  assert(str:find("cat1.items=10,11", 1, true), str)
  R.db.categories = {}
  assert(R:ImportSettings(str) ~= false)
  assert(R.db.categories[1].items[10] and R.db.categories[1].items[11] and R.db.categories[2].items == nil)
end)


-- 1.11.1 audit regressions.
test("window-owned entries survive another window and cross-character snapshots", function()
  local env, R = boot()
  local link = env.__addItem(0, 1, 1500, 2)
  R.Data:ScanInventory()
  local owner = R.UI
  local entries = R.Items:Build(R.Data.me, "bags", owner)
  local e, pair = entries[1], entries[1].slots[1]
  e.vals.probe = 42
  local other = { containers = { [0] = { size = 1, slots = { [1] = { l = "item:1501", i = 1501, c = 9 } } } } }
  R.Items:Build(other, "bags", R.BankUI)
  R.Items:Build(other, "bags", R.GuildUI)
  R.UI:BuildAllChars("bags")
  assert(entries[1] == e and e.link == link and e.count == 2 and e.vals.probe == 42)
  assert(e.slots[1] == pair and pair[1] == 0 and pair[2] == 1)
end)

test("sale confirmation sells only the original unchanged snapshot", function()
  local env, R = boot()
  env.MerchantFrame.shown = true
  env.__addItem(0, 1, 1510, 1, { quality = 2, sell = 10 }); R.db.junk[1510] = true
  R.Junk:SellAll()
  local sale = env.__popup.args[3]
  env.__addItem(0, 2, 1511, 1, { quality = 2, sell = 20 }); R.db.junk[1511] = true
  env.StaticPopupDialogs.RUMMAGE_SELL_CONFIRM.OnAccept(nil, sale)
  assert(#env.__used == 1 and env.__used[1][2] == 1, "new item was not confirmed")
end)

test("sale ticks recheck count favorites sets junk and vendor value", function()
  for _, kind in ipairs({ "count", "favorite", "set", "junk", "value", "combat", "session" }) do
    local env, R = boot()
    env.__bags[0].size = 12; env.MerchantFrame.shown = true
    for i = 1, 11 do env.__addItem(0, i, 1520 + i, 1, { quality = 0, sell = 10 }) end
    R.Junk:SellAll()
    assert(#env.__used == 10)
    if kind == "count" then env.__bags[0][11].count = 4
    elseif kind == "favorite" then R.db.favorites[1531] = 1
    elseif kind == "set" then R.Items.InSet = function(_, e) return e.id == 1531 end
    elseif kind == "junk" then R.db.junk[1531] = false
    elseif kind == "value" then
      local get = R.API.GetSlotInfo
      R.API.GetSlotInfo = function(b, slot)
        local l, c, t, q, lock, id, bound = get(b, slot)
        return l, c, t, q, lock, id, bound, slot == 11
      end
    elseif kind == "combat" then env.__combat = true
    elseif kind == "session" then env.__ev("MERCHANT_CLOSED"); env.__ev("MERCHANT_SHOW") end
    env.__tick(2)
    assert(#env.__used == 10 and #R.db.junkLog == 10, kind .. " sold a changed item")
  end
end)

test("sale prompt expires when the merchant session changes", function()
  local env, R = boot(); env.MerchantFrame.shown = true
  env.__addItem(0, 1, 1540, 1, { quality = 2, sell = 10 }); R.db.junk[1540] = true
  R.Junk:SellAll(); local sale = env.__popup.args[3]
  env.__ev("MERCHANT_CLOSED"); env.__ev("MERCHANT_SHOW")
  env.StaticPopupDialogs.RUMMAGE_SELL_CONFIRM.OnAccept(nil, sale)
  assert(not env.__used)
end)

local function mailTarget(env)
  env.MailFrame = env.CreateFrame("Frame", "MailFrame"); env.MailFrame:Show()
  env.SendMailFrame = env.CreateFrame("Frame", "SendMailFrame"); env.SendMailFrame:Show()
  env.GetSendMailItem = function() return nil end
  env.ClickSendMailItemButton = function() end
end

test("movers share busy state and preserve a user-owned cursor", function()
  local env, R = boot(); mailTarget(env)
  local link = env.__addItem(0, 1, 1550, 1)
  local entries = { { link = link, slots = { { 0, 1 } } } }
  local cleared = 0
  env.GetCursorInfo = function() return "item", 999 end
  env.ClearCursor = function() cleared = cleared + 1 end
  R.Mover:Start(function() end, "test"); R.Mover:SendTo("mail", entries)
  assert(not R.Mover:Busy() and cleared == 0 and not env.__picked)
  env.GetCursorInfo = function() return nil end
  R.Mover:Start(function() end, "test"); R.Mover:SendTo("mail", entries)
  assert(R.Mover:IsShown() and not R.Mover.sendTicker)
  R.Mover:Stop()
  R.Mover:SendTo("mail", entries); R.Mover:Start(function() end, "test")
  assert(R.Mover.sendTicker and not R.Mover:IsShown())
  env.GetCursorInfo = function() return "item", 999 end
  env.__tick(1)
  assert(not R.Mover:Busy() and cleared == 0)
end)

test("transfer plans reject replacement and changed stacks and bank session loss", function()
  local env, R = boot()
  local link = env.__addItem(0, 1, 1560, 2)
  env.__bags[1] = { size = 4 }
  local planner = R.Mover:PlanTransfer({ { 0, 1 } }, { 1 })
  env.__addItem(0, 1, 1561, 2)
  assert(planner() == nil, "replacement moved")
  env.__addItem(0, 1, 1560, 2)
  planner = R.Mover:PlanTransfer({ { 0, 1 } }, { 1 })
  env.__bags[0][1].count = 3
  assert(planner() == nil, "changed stack moved")
  env.__bags[-1] = { size = 4 }; R.Data.atBank = true
  planner = R.Mover:PlanTransfer({ { 0, 1 } }, { -1 })
  env.__ev("BANKFRAME_CLOSED"); R.Data.atBank = true
  local move, err = planner()
  assert(move == nil and err:find("session"))
  local done = false
  R.Mover:Start(planner, "test", function() done = true end)
  env.__update(0.1)
  assert(not R.Mover:Busy() and not done and not env.__picked)
end)

test("bank confirmation owns direction and source snapshot across window changes", function()
  local env, R = boot()
  local link = env.__addItem(0, 1, 1570, 2)
  R.Data.atBank = true; R.UI:Open(); env.__settle(2)
  R.UI.entries = { { link = link, bag = 0, slots = { { 0, 1 } } } }
  R.UI:DoTransfer()
  local transfer = env.__popup.args[3]
  assert(transfer.toBank and transfer.window == R.UI)
  R.popupUI = R.BankUI; R.UI.entries = {}; R.UI.view = "bank"
  local captured
  R.Mover.TransferEntries = function(_, entries, toBank, session) captured = { entries, toBank, session } end
  env.StaticPopupDialogs.RUMMAGE_CONFIRM_TRANSFER.OnAccept(nil, transfer)
  assert(captured[2] == true and captured[1][1].link == link and captured[1][1].slots[1][4] == 2)
end)

test("settings preserve section delimiters Unicode and explicit empty lists", function()
  local env, R = boot()
  R.db.categories = { { name = "One", query = "", section = " Équipement;=% " } }
  R.db.junkRules = { "q:poor" }
  local exported = R:ExportSettings()
  R.db.categories = {}; assert(R:ImportSettings(exported))
  assert(R.db.categories[1].section == "Équipement;=%")
  R.db.categories = {}; R.db.junkRules = {}; exported = R:ExportSettings()
  R.db.categories = { { name = "Old" } }; R.db.junkRules = { "old" }
  assert(R:ImportSettings(exported) and #R.db.categories == 0 and #R.db.junkRules == 0)
  R.db.categories = { { name = "Keep" } }; R.db.junkRules = { "keep" }
  assert(R:ImportSettings("RUM1;scale=1"))
  assert(R.db.categories[1].name == "Keep" and R.db.junkRules[1] == "keep")
  assert(R:ImportSettings("RUM1;cat1.name=Legacy;cat1.query="))
  assert(R.db.categories[1].section == "Custom")
end)

test("cached alt metadata and invalid saved anchors are repaired", function()
  local env, R = boot(function(e)
    e.RummageDB = { settings = { point = { "BAD", "CENTER", 0, 0 }, upgradePoint = { "TOP", "TOP", math.huge, 0 },
      bank = { point = { "BAD", "CENTER", 0, 0 } }, guild = { point = { "CENTER", "CENTER", 0/0, 0 } } },
      chars = { ["Broken-Realm"] = { name = {}, realm = false, class = {}, faction = {}, level = {}, lastSeen = "bad", acquired = { [1] = "bad", [2] = math.huge, [3] = 42 } } } }
  end)
  local c = R.db.chars["Broken-Realm"]
  assert(c and not c.name and not c.realm and not c.class and not c.faction and not c.level and not c.lastSeen)
  assert(c.acquired[1] == nil and c.acquired[2] == nil and c.acquired[3] == 42)
  R.Data:SortedChars(); R.Data:CountFor(c, 1); R.UI:ShowCharMenu(R.UI.frame); R.UI:BuildAllChars("bags")
  assert(not R.settings.point and not R.settings.upgradePoint)
  assert(not R.BankUI:Geo().point and not R.GuildUI:Geo().point)
  assert(R.ValidPoint({ "TOPLEFT", "BOTTOMRIGHT", -42, 99 }))
end)

test("deferred live and layout work coalesces independently for every window", function()
  local env, R = boot()
  local windows = { R.UI, R.BankUI, R.GuildUI }
  local live, layouts = {}, {}
  for i, w in ipairs(windows) do
    w.frame:Show()
    w.UpdateLiveNow = function() live[i] = (live[i] or 0) + 1 end
    w.Layout = function() layouts[i] = (layouts[i] or 0) + 1 end
    w:UpdateLive(); w:UpdateLive()
    w.frame.scripts.OnSizeChanged(w.frame)
    w.frame.scripts.OnSizeChanged(w.frame)
  end
  env.__update(0.1)
  for i = 1, 3 do assert(live[i] == 1 and layouts[i] == 1, "window " .. i .. " lost/coalesced another's job") end
end)

test("failed or unaffordable buyback preserves history", function()
  local env, R = boot(); env.MerchantFrame:Show()
  R.db.junkLog = { { t = 1, link = "[Rag]", count = 1, value = 5 } }
  env.__buyback = { { link = "[Rag]", count = 1, price = 5 } }
  local calls = 0
  env.BuybackItem = function() calls = calls + 1 end
  R.Junk:Buyback(1)
  assert(calls == 1 and #R.db.junkLog == 1)
  env.__tick(30)
  env.GetBuybackItemInfo = function() return "Rag", nil, 100, 1 end
  env.GetMoney = function() return 5 end
  R.Junk:Buyback(1); R.Junk:Buyback("all")
  assert(calls == 1 and #R.db.junkLog == 1)
end)


test("a fresh sale invalidates an older pending confirmation", function()
  local env, R = boot(); env.MerchantFrame:Show()
  env.__addItem(0, 1, 1590, 1, { quality = 2, sell = 10 }); R.db.junk[1590] = true
  R.Junk:SellAll(); local oldSale = env.__popup.args[3]
  R.settings.sellConfirmQuality = false
  R.Junk:SellAll(); env.__tick(2)
  assert(#env.__used == 1)
  env.__addItem(0, 1, 1590, 1, { quality = 2, sell = 10 })
  env.StaticPopupDialogs.RUMMAGE_SELL_CONFIRM.OnAccept(nil, oldSale)
  env.__tick(2)
  assert(#env.__used == 1, "superseded confirmation sold a new item")
end)


-- Stateful inventory adapter: real source/cursor/destination deltas, including delayed/rejected requests.
local function inventoryModel(env, R, options)
 options = options or {}
 local model = { calls = { split = 0, pickup = 0, sale = 0, clear = 0 }, queue = {} }
 local function request(fn)
  if options.delay then model.queue[#model.queue + 1] = { left = options.delay, fn = fn } else fn() end
 end
 env.GetCursorInfo = function() local h = model.held; if h then return "item", h.id, h.link end end
 env.ClearCursor = function()
  model.calls.clear = model.calls.clear + 1
  local h = model.held
  if h and h.source then
   local bag, slot = h.source[1], h.source[2]
   local s = env.__bags[bag][slot]
   if h.deferred and s and s.link == h.link then s.locked = nil; model.held = nil
   elseif s and s.link == h.link then s.count = s.count + h.count; model.held = nil
   elseif not s then env.__bags[bag][slot] = { link = h.link, id = h.id, count = h.count, quality = h.quality }; model.held = nil end
  end
 end
 R.API.SplitContainerItem = function(bag, slot, count)
  model.calls.split = model.calls.split + 1
  if options.rejectSplit then return end
  request(function()
   local s = env.__bags[bag][slot]
   if not model.held and s and s.count > count then
    if options.deferredSourceCount then s.locked = true else s.count = s.count - count end
    model.held = { link = s.link, id = s.id, count = count, quality = s.quality, source = { bag, slot }, deferred = options.deferredSourceCount }
   end
  end)
 end
 R.API.PickupContainerItem = function(bag, slot)
  model.calls.pickup = model.calls.pickup + 1
  if options.rejectPlace then return end
  request(function()
   local s = env.__bags[bag][slot]
   if model.held and not s then
    local h = model.held
    if h.deferred then
     local source = env.__bags[h.source[1]][h.source[2]]
     source.count, source.locked = source.count - h.count, nil
    end
    env.__bags[bag][slot] = { link = h.link, id = h.id, count = h.count, quality = h.quality }
    model.held = nil
   elseif model.held and s and model.held.link == s.link then
    local h = model.held
    if h.deferred then local source = env.__bags[h.source[1]][h.source[2]]; source.count, source.locked = source.count - h.count, nil end
    s.count = s.count + h.count; model.held = nil
   elseif not model.held and s then
    model.held = { link = s.link, id = s.id, count = s.count, quality = s.quality, source = { bag, slot } }
    env.__bags[bag][slot] = nil
   end
  end)
 end
 R.API.UseContainerItem = function(bag, slot)
  model.calls.sale = model.calls.sale + 1
  if not options.rejectSale then request(function()
   local item = env.__bags[bag][slot]
   if item then env.__money = env.GetMoney() + (env.__items[item.id].sell or 0) * item.count; env.__bags[bag][slot] = nil end
  end) end
 end
 function model:tick(n)
  for _ = 1, n or 1 do
   for i = #self.queue, 1, -1 do
    local q = self.queue[i]; q.left = q.left - 1
    if q.left <= 0 then table.remove(self.queue, i); q.fn() end
   end
   env.__tick(1)
  end
 end
 return model
end
local function historyHas(R, action, status, reason)
 for _, e in ipairs(R.db.actionHistory) do
  if e.action == action and e.status == status and (not reason or (e.reason or ""):find(reason, 1, true)) then return true end
 end
 return false
end
local function reserveFixture(options, size)
 local env, R = boot()
 env.__bags[0].size = size or 8
 env.__addItem(0, 1, 1700, 20, { quality = 0, sell = 3, stack = 20 })
 env.MerchantFrame:Show(); assert(R.Junk:SetKeep(1700, 7))
 return env, R, inventoryModel(env, R, options)
end

test("rule preview is read-only, search-compatible and requires exact explicit enable", function()
 local env, R = boot()
 env.__addItem(0, 1, 1710, 4, { name = "Linen Cloth", quality = 0, sell = 2 })
 env.__addItem(0, 2, 1711, 3, { name = "Linen Favorite", quality = 1, sell = 10 })
 R.db.favorites[1711] = 2; R.Data.newItems[1710] = true
 local preview = assert(R.Junk:PreviewRule("linen"))
 assert(preview.matchedStacks == 2 and preview.matchedUnits == 7 and preview.sellUnits == 4 and preview.value == 8)
 assert(#R.db.junkRules == 0 and not env.__used and env.__bags[0][1].count == 4)
 assert(R.Junk:PreviewRule("#fav").matchedUnits == 3)
 assert(R.Junk:PreviewRule("#new").matchedUnits == 4)
 assert(R.Junk:PreviewRule("#junk").matchedUnits == 4)
 assert(R.Junk:PreviewRule("#unknownkeyword").matchedUnits == 0)
 assert(not R.Junk:EnableRule({ query = "linen" }))
 preview.query = "other"; assert(not R.Junk:EnableRule(preview))
 preview = assert(R.Junk:PreviewRule("linen")); assert(R.Junk:EnableRule(preview) and R.db.junkRules[1] == "linen")
 assert(not R.Junk:EnableRule(preview), "consent is single-use")
end)

test("destructive rule drafts reject empty operands and excessive complexity", function()
 local env, R = boot()
 for _, q in ipairs({ "", "()", "(|) | linen", "(!) | linen", "linen |", "| linen", 'linen | ""', "(linen", string.rep("(", 17) .. "linen" .. string.rep(")", 17), string.rep("a", 513) }) do
  local p, err = R.Junk:PreviewRule(q); assert(not p and err and #R.db.junkRules == 0, q)
 end
 assert(R.Junk:PreviewRule('(linen | wool) !"bad cloth"'))
 R.Search.Matches = function() error("parser/plugin failure") end
 env.__addItem(0, 1, 1710, 1, { sell = 1 })
 assert(not R.Junk:PreviewRule("linen"))
end)

test("preview uses reserves protections unknown data and final buyback batch cap", function()
 local env, R = boot(); env.__bags[0].size = 20; R.settings.buybackSafe = true
 for i = 1, 15 do env.__addItem(0, i, 1720 + i, 1, { name = "Linen" .. i, quality = 0, sell = i }) end
 local preview = assert(R.Junk:PreviewRule("linen"))
 local list, total = R.Junk:Collect()
 assert(#list == 12 and preview.sellUnits == 12 and preview.value == total)
 local sum = 0; for _, row in ipairs(preview.rows) do sum = sum + row.sellCount end; assert(sum == 12)
 R.db.junk[1721] = false; env.__bags[0][2].locked = true; env.__bags[0][3].noValue = true
 R.Items.InSet = function(_, e) return e.id == 1724 end
 env.__items[1725] = nil; R.Items.Info = function(self, link) if R.ItemID(link) == 1725 then return nil end; return nil end
 preview = assert(R.Junk:PreviewRule("linen"))
 assert(preview.sellUnits == 0 and preview.excludedUnits == 15)
end)

test("keep quantities validate strictly and aggregate same-ID variants across live bags only", function()
 local env, R = boot()
 env.__addItem(0, 1, 1730, 8, { quality = 0, sell = 1 })
 env.__addItem(1, 1, 1730, 6, { quality = 0, sell = 1 })
 env.__bags[1][1].link = env.__bags[1][1].link .. "variant"
 env.__addItem(-1, 1, 1730, 100, { quality = 0, sell = 1 })
 for _, bad in ipairs({ -1, 1.5, math.huge, 1000001 }) do assert(not R.Junk:SetKeep(1730, bad)) end
 assert(not R.Junk:SetKeep(0, 1) and not R.Junk:SetKeep(1730.5, 1))
 assert(R.Junk:SetKeep(1730, 10)); local list = R.Junk:Collect()
 local count = 0; for _, it in ipairs(list) do count = count + it.sellCount end
 assert(count == 4 and #list == 1 and list[1].sellCount == 4)
 assert(R.Junk:SetKeep(1730, 0) and R.db.keepQuantities[1730] == nil)
end)

test("partial sale splits exact excess and only logs observed inventory changes", function()
 local env, R, model = reserveFixture()
 R.Junk:SellAll()
 assert(model.calls.split == 1 and model.calls.sale == 0 and env.__bags[0][1].count == 7)
 assert(historyHas(R, "Split", "Requested") and not historyHas(R, "Sale", "Observed"))
 model:tick(6)
 assert(env.__bags[0][1].count == 7 and model.calls.sale == 1 and model.held == nil and not R.Junk.ticker)
 assert(#R.db.junkLog == 1 and R.db.junkLog[1].count == 13 and R.db.junkLog[1].value == 39)
 assert(historyHas(R, "Split", "Observed") and historyHas(R, "Sale", "Observed"))
end)

test("delayed split placement and sale requests wait for actual acknowledgements", function()
 local env, R, model = reserveFixture({ delay = 2 })
 R.Junk:SellAll(); assert(model.calls.sale == 0 and #R.db.junkLog == 0 and not historyHas(R, "Split", "Observed"))
 model:tick(3); assert(#R.db.junkLog == 0)
 model:tick(12)
 assert(env.__bags[0][1].count == 7 and #R.db.junkLog == 1 and not R.Junk.ticker)
end)

test("partial sale skips unavailable space or APIs and stops on missing acknowledgements", function()
 for _, mode in ipairs({ "space", "api", "split", "place", "sale" }) do
  local opts = {}; opts[mode == "split" and "rejectSplit" or mode == "place" and "rejectPlace" or "rejectSale"] = mode ~= "space" and mode ~= "api"
  local env, R, model = reserveFixture(opts, mode == "space" and 1 or 8)
  if mode == "api" then R.API.SplitContainerItem = nil end
  R.Junk:SellAll(); model:tick(40)
  assert(not R.Junk.ticker and #R.db.junkLog == 0 and not historyHas(R, "Sale", "Observed"), mode)
  if mode == "space" or mode == "api" then assert(model.calls.split == 0 and model.calls.sale == 0 and historyHas(R, "Sale", "Skipped"))
  else assert(historyHas(R, "Sale", "Stopped"), mode) end
 end
end)

test("reserve changes and disappearing stock shrink consent without ever selling retained units", function()
 local env, R, model = reserveFixture()
 R.Junk:SellAll(); model:tick(2) -- split stack is in the bag and verified
 assert(R.Junk:SetKeep(1700, 15)); model:tick(8)
 assert(model.calls.sale == 0 and historyHas(R, "Sale", "Skipped", "Reserve Changed"))
 local e2, R2, m2 = reserveFixture()
 e2.__addItem(0, 3, 1700, 10, { quality = 0, sell = 3 })
 R2.Junk:SetKeep(1700, 27); R2.Junk:SellAll(); m2:tick(2)
 e2.__bags[0][3] = nil; R2.Junk:SetKeep(1700, 18); m2:tick(8)
 assert((e2.__bags[0][1] and e2.__bags[0][1].count or 0) + (e2.__bags[0][2] and e2.__bags[0][2].count or 0) >= 18)
end)

test("sale cursor ownership combat session and mover mutual exclusion are enforced", function()
 local env, R, model = reserveFixture()
 R.Junk:SellAll(); R.Mover:Start(function() end, "blocked")
 assert(not R.Mover:IsShown())
 env.__combat = true; model:tick(1)
 assert(model.calls.sale == 0 and model.calls.clear == 1 and env.__bags[0][1].count == 20)
 local env2, R2, model2 = reserveFixture()
 R2.Junk:SellAll(); model2.held = { id = 9999, link = "item:9999", count = 1 }
 model2:tick(1); assert(model2.calls.clear == 0 and model2.held.id == 9999 and not R2.Junk.ticker)
 local env3, R3, model3 = reserveFixture()
 R3.Junk:SellAll(); env3.__ev("MERCHANT_CLOSED"); model3:tick(1)
 assert(not R3.Junk.ticker and model3.calls.sale == 0)
end)

test("unconfirmed whole-stack sale is Requested not Observed or successful sale log", function()
 local env, R, model = reserveFixture({ rejectSale = true })
 R.Junk:SetKeep(1700, 0); R.Junk:SellAll(); model:tick(20)
 assert(model.calls.sale == 1 and #R.db.junkLog == 0 and historyHas(R, "Sale", "Requested") and not historyHas(R, "Sale", "Observed"))
 assert(historyHas(R, "Sale", "Stopped", "Unconfirmed"))
end)

test("history sanitizes bounds IDs enums and pages without exporting local records", function()
 local env, R = boot(function(e)
  e.RummageDB = { version = 5, actionHistoryNextID = 1e100, actionHistory = {
   { id = 1e100, t = 1, action = "Sale", status = "Requested", reason = string.rep("x", 500) },
   { id = 1e100, t = 2, action = "Sale", status = "Observed", native = function() end },
   { id = 1, t = math.huge, action = "Sale", status = "Observed" }, { t = 2, action = "Evil", status = "Observed" } } }
 end)
 assert(R.db.version == 7 and #R.db.actionHistory == 2)
 local ids = {}; for _, e in ipairs(R.db.actionHistory) do assert(not ids[e.id]); ids[e.id] = true; assert(not e.native and #(e.reason or "") <= 180) end
 for i = 1, 110 do R.ActionHistory:Record(i % 2 == 0 and "Sale" or "Transfer", i % 3 == 0 and "Skipped" or "Requested", { count = i, reason = "Example" }) end
 assert(#R.db.actionHistory == 100)
 local page, total, pages = R.ActionHistory:Page("All", 2, 8); assert(#page == 8 and total == 100 and pages == 13)
 page = R.ActionHistory:Page("Skipped", 1, 8); for _, e in ipairs(page) do assert(e.status == "Skipped" or e.status == "Stopped") end
 assert(not R:ExportSettings():find("actionHistory", 1, true))
 R.ActionHistory:Clear(); assert(#R.db.actionHistory == 0)
end)

test("keep and context maps round-trip atomically with legacy and future compatibility", function()
 local env, R = boot()
 R.Junk:SetKeep(1700, 12); R.db.profiles["Équipement ;=%"] = {}; assert(R.Extras:SetContextMapping("raid", "Équipement ;=%"))
 local out = R:ExportSettings(); R.db.keepQuantities = {}; R.db.contextProfiles = {}; assert(R:ImportSettings(out))
 assert(R.db.keepQuantities[1700] == 12 and R.db.contextProfiles.raid == "Équipement ;=%")
 assert(not R:ImportSettings("RUM1;scale=1.7;keep.1700=1.5")); assert(R.settings.scale ~= 1.7 and R.db.keepQuantities[1700] == 12)
 assert(R:ImportSettings("RUM1;scale=1;context.future=Future")); assert(R.db.keepQuantities[1700] == 12 and not R.db.contextProfiles.future)
 assert(R:ImportSettings("RUM1;keepQuantities.present=1;contextProfiles.present=1"))
 assert(next(R.db.keepQuantities) == nil and next(R.db.contextProfiles) == nil)
 R.db.contextProfiles.raid = "Missing Profile"; out = R:ExportSettings(); assert(R:ImportSettings(out)); assert(R.db.contextProfiles.raid == "Missing Profile")
 R.Junk:SetKeep(1700, 9); R:SaveProfile("One"); R.Junk:SetKeep(1700, 10); R:ApplyProfile("One"); assert(R.db.keepQuantities[1700] == 10)
end)

test("context mapping editor preserves precedence Unicode unavailable and combat deferral", function()
 local env, R = boot()
 R:SaveProfile("Raid Équipement"); R:SaveProfile("Spec Two")
 assert(R.Extras:SetContextMapping("raid", "Raid Équipement") and R.Extras:SetContextMapping("spec2", "Spec Two"))
 assert(not R.Extras:SetContextMapping("unknown", "Spec Two") and not R.Extras:SetContextMapping("world", "Missing"))
 env.GetSpecialization = function() return 2 end; env.IsInInstance = function() return true, "raid" end
 R.settings.autoProfile = true; env.__combat = true; assert(not R.Extras:ApplyContext())
 assert(R.db.profileName == "Spec Two")
 env.__combat = false; env.__ev("PLAYER_REGEN_ENABLED"); env.__settle(2)
 assert(R.db.profileName == "Raid Équipement" and R.settings.autoProfile)
 R:DeleteProfile("Raid Équipement"); assert(not R.db.contextProfiles.raid)
end)

test("Tools workflow invalidates drafts pages clears history and captures all nine profile callbacks", function()
 local env, R = boot()
 env.__addItem(0, 1, 1750, 2, { name = "Linen", quality = 0, sell = 1 })
 R.Tools:Show("preview"); local count = #env.__frames
 R.Tools.queryBox:SetText("linen"); R.Tools:RunPreview(); assert(R.Tools.preview)
 R.Tools.queryBox:SetText("wool"); R.Tools.queryBox.scripts.OnTextChanged(R.Tools.queryBox); assert(not R.Tools.preview)
 R.Tools:EnablePreview(); assert(#R.db.junkRules == 0)
 R.Tools.queryBox:SetText("linen"); R.Tools:RunPreview(); R.Tools:EnablePreview(); assert(#R.db.junkRules == 1)
 R.Tools:Show("keep"); R.Tools.keepID:SetText("1750"); R.Tools.keepCount:SetText("1.5"); R.Tools:SaveKeep(false); assert(not R.db.keepQuantities[1750])
 R.Tools.keepCount:SetText("1"); R.Tools:SaveKeep(false); assert(R.db.keepQuantities[1750] == 1)
 R:SaveProfile("With Spaces É"); R.Tools:Show("profiles")
 local menu
 R.Widgets.Menu = function(_, _, entries) menu = entries end
 for _, row in ipairs(R.Tools.profileRows) do
  row.button.scripts.OnClick(row.button, "LeftButton")
  local picked; for _, item in ipairs(menu) do if item.text == "With Spaces É" then picked = item end end
  assert(picked); picked.func(); assert(R.db.contextProfiles[row.key] == "With Spaces É")
 end
 for i = 1, 25 do R.ActionHistory:Record("Sale", "Requested", { reason = "History Example" }) end
 R.Tools:Show("history"); R.Tools.page = 2; R.Tools:Refresh(); assert(R.Tools.rows[1].record)
 local selected = R.Tools.rows[1].record.id; R.Tools.selectedID = selected; R.ActionHistory:Record("Transfer", "Skipped", { reason = "Changed" }); assert(R.Tools.selectedID == selected)
 for _, tab in ipairs({ "keep", "preview", "profiles", "history" }) do R.Tools:Show(tab); R.Tools.frame:Hide() end
 assert(#env.__frames == count, "reopening allocated duplicate frames")
end)

test("grid cues retain shapes and separate F J Q quantity item-level through recycling", function()
 local env, R = boot(); open(env, R)
 local link = env.__addItem(0, 1, 1760, 99, { quality = 4, sell = 1, ilvl = 60, equip = "INVTYPE_HEAD" })
 local e = { id = 1760, link = link, bag = 0, slot = 1, count = 99, icon = 1, quality = 4, fav = 2, junk = true, slots = { { 0, 1 } }, info = { equippable = true, ilvl = 60 } }
 R.settings.colorblindCues = true; R.settings.gridSize = 20
 assert(R:GridCellSize() == 48 and R.settings.gridSize == 20)
 local row = R.UI:GetGridRow(1); R.UI:SetupGridRow(row, { items = { e } }, false)
 local c = row.cells[1]
 assert(c.cues.favorite.text:GetText() == "F2" and c.cues.junk.text:GetText() == "J" and c.cues.quality.text:GetText() == "Q4")
 assert(c.fav:IsShown() and c.junk:IsShown() and c.count:GetText() == 99 and c:GetWidth() == 48)
 assert(R:GridCueText(e):find("Favorite 2", 1, true) and R:GridCueText(e):find("Epic", 1, true))
 e.fav, e.junk, e.quality = nil, false, 0; R.UI:SetupGridRow(row, { items = { e } }, false)
 assert(not c.cues.favorite:IsShown() and not c.cues.junk:IsShown() and c.cues.quality.text:GetText() == "Q0")
 R.settings.colorblindCues = false; R.UI:SetupGridRow(row, { items = { e } }, false)
 assert(R:GridCellSize() == 20 and not c.cues.quality:IsShown() and c.cues.quality.text:GetText() == "")
 R.settings.colorblindCues = true; R.settings.gridSize = 64; assert(R:GridCellSize() == 64)
end)

test("Categories help follows Add and content extent grows and shrinks", function()
 local env, R = boot(); R.Options:Show("categories")
 local p = R.Options.pages.categories.content
 assert(p.categoryHelp.points[1][2] == p.categoryAdd and p.categoryHelp.points[1][3] == "BOTTOMLEFT")
 local initial = p.categoryExtent
 for i = 1, 30 do R.db.categories[i] = { name = "Category " .. i, query = "q:poor", section = "Custom" } end
 p.categoryRebuild(); assert(p.categoryExtent > initial and p:GetHeight() >= p.categoryExtent)
 R.db.categories = {}; p.categoryRebuild(); assert(p.categoryExtent == initial)
end)

-- Append within tests/cases.lua, where test() and boot() are already local.
test("Tools typography uses separate bounded regions at fonts 6 through 24", function()
  local env, R = boot()
  env.UIParent:SetSize(1280, 720)
  for i = 1, 22 do R.db.keepQuantities[20000 + i] = i end
  for _, font in ipairs({ 6, 12, 24 }) do
    R.settings.fontSize = font; R.Widgets:UpdateFonts()
    R.Tools:Show("keep")
    local tools, layout = R.Tools, R.Tools.layout
    assert(layout.line >= font and layout.control >= font + 8, "text/control height at " .. font)
    assert(tools.status:GetHeight() >= layout.line * 3, "three status lines fit")
    assert(layout.rowTop >= layout.statusTop + layout.statusHeight + 10, "status does not overlap rows")
    assert(layout.rowTop + tools.pageSize * (layout.rowHeight + 2) + layout.control + 20 <= tools.frame:GetHeight(), "last row stays above footer")
    assert(tools.frame:GetWidth() <= 1280 and tools.frame:GetHeight() <= 720, "panel fits viewport")
    for i, row in ipairs(tools.rows) do
      local _, _, _, _, detailY = row.detail:GetPoint()
      assert(-detailY >= row.text:GetHeight() + 4, "row title/detail separated")
      assert(row.detail:GetHeight() >= font and row.text:GetWidth() < row:GetWidth(), "explicit clipping bounds")
      assert(type(row.tipTitle) == "function" and type(row.tipBody) == "function", "full row text available on hover")
      if i > tools.pageSize then assert(not row:IsShown(), "unused rows hidden") end
    end
    if font == 24 then assert(tools.pageSize == 4, "large type uses readable shorter pages") end
    local before = tools.page
    tools.next:Click()
    assert(tools.page == before + 1 and tools.rows[1].record.id == 20000 + tools.pageSize + 1, "paging uses effective page size")
    tools.previous:Click()
  end
end)

test("Tools profile paging preserves all context callbacks and clamps after viewport growth", function()
  local env, R = boot()
  R.settings.fontSize = 24; R.Widgets:UpdateFonts(); env.UIParent:SetSize(1280, 720)
  local name = string.rep("Équipement ", 8)
  R.db.profiles[name] = {}; R.db.contextProfiles.battleground = name
  R.Tools:Show("profiles")
  local tools = R.Tools
  assert(#tools.profileRows == 9 and tools.profilePageSize < 9, "nine identities, bounded visible page")
  local shown = 0
  for _, row in ipairs(tools.profileRows) do
    if row.button:IsShown() then shown = shown + 1 end
    assert(row.button.text:GetHeight() >= 24 and row.button.text:GetWidth() < row.button:GetWidth(), "profile text bounded")
    assert(type(row.button.tipTitle) == "function", "full profile name on hover")
  end
  assert(shown == tools.profilePageSize)
  tools.next:Click(); assert(tools.page == 2 and not tools.profileRows[1].button:IsShown())
  local oldFrames = #env.__frames
  env.UIParent:SetSize(1920, 1080); R.settings.fontSize = 12; R.Widgets:UpdateFonts()
  tools:Refresh(); tools:ApplyPosition()
  assert(tools.page == 1 and tools.profileRows[1].button:IsShown(), "shrunk page count clamps immediately")
  shown = 0; for _, row in ipairs(tools.profileRows) do if row.button:IsShown() then shown = shown + 1 end end
  assert(shown == 9 and #env.__frames == oldFrames, "resize reuses all nine mapping controls")
  tools:Show("keep"); assert(tools.pageSize == 8, "normal fonts retain eight rows")
end)


test("Tools tiny viewport scales a nonoverlapping logical panel", function()
  local env, R = boot()
  R.settings.fontSize = 24; R.Widgets:UpdateFonts(); env.UIParent:SetSize(600, 400)
  R.db.keepQuantities[24000] = 1
  R.Tools:Show("keep")
  local tools, l = R.Tools, R.Tools.layout
  assert(tools.pageSize >= 1)
  assert(l.rowTop + tools.pageSize * (l.rowHeight + 2) + l.control + 20 <= tools.frame:GetHeight(), "logical row/footer separation survives tiny viewport")
  assert(tools.frame:GetWidth() * tools.frame:GetScale() <= 600 and tools.frame:GetHeight() * tools.frame:GetScale() <= 400, "whole panel fits via safe scale")
  assert(tools.rows[1]:IsShown() and tools.rows[1].record.id == 24000)
end)


test("reserve oracle counts protected stock and sells exactly eighteen of thirty units", function()
 local env, R = boot(); env.MerchantFrame:Show()
 for i = 1, 3 do env.__addItem(0, i, 1770, 10, { quality = 0, sell = 2, stack = 20 }) end
 local model = inventoryModel(env, R)
 R.Junk:SetKeep(1770, 12); R.Junk:SellAll(); model:tick(15)
 local _, totals = R.Junk:Inventory(); assert(totals[1770] == 12)
 local sold = 0; for _, row in ipairs(R.db.junkLog) do sold = sold + row.count end; assert(sold == 18)
 local e2, R2 = boot(); e2.MerchantFrame:Show()
 local link = e2.__addItem(0, 1, 1771, 20, { quality = 0, sell = 2 })
 e2.__addItem(0, 2, 1771, 5, { quality = 0, sell = 2 })
 e2.__bags[0][1].link = link .. "protectedvariant"
 R2.Items.InSet = function(_, item) return item.link:find("protectedvariant", 1, true) ~= nil end
 R2.Junk:SetKeep(1771, 22); local list = R2.Junk:Collect()
 assert(#list == 1 and list[1][2] == 2 and list[1].sellCount == 3, "protected stock counts toward retained total")
end)

test("lowering a reserve never enlarges an already confirmed sale", function()
 local env, R, model = reserveFixture()
 env.__bags[0][1].quality = 2; env.__items[1700].quality = 2; R.db.junk[1700] = true
 R.Junk:SetKeep(1700, 15); R.Junk:SellAll()
 local sale = env.__popup.args[3]; assert(sale.list[1].sellCount == 5)
 R.Junk:SetKeep(1700, 0); env.StaticPopupDialogs.RUMMAGE_SELL_CONFIRM.OnAccept(nil, sale); model:tick(10)
 assert(env.__bags[0][1].count == 15 and R.db.junkLog[1].count == 5)
end)

test("partial splits stop on unexpected destinations locked acknowledgement or incompatible free slots", function()
 for _, mode in ipairs({ "destination", "locked", "family" }) do
  local env, R, model = reserveFixture()
  if mode == "family" then
   R.API.FitsBag = function() return false end
  end
  R.Junk:SellAll()
  if mode == "destination" then env.__addItem(0, 2, 9990, 1, { sell = 1 })
  elseif mode == "locked" then env.__bags[0][1].locked = true end
  model:tick(20)
  assert(model.calls.sale == 0 and #R.db.junkLog == 0 and not R.Junk.ticker, mode)
 end
end)

test("manual source moves and missing vendor money are never observed sales", function()
 for _, mode in ipairs({ "moved", "money" }) do
  local env, R, model = reserveFixture({ rejectSale = true })
  R.Junk:SetKeep(1700, 0); R.Junk:SellAll()
  if mode == "moved" then env.__bags[0][2] = env.__bags[0][1] end
  env.__bags[0][1] = nil
  model:tick(20)
  assert(#R.db.junkLog == 0 and not historyHas(R, "Sale", "Observed") and not chatHas(env, "Sold 1"), mode)
 end
end)

test("mail observation requires exact target identity and quantity", function()
 for _, mode in ipairs({ "wrong", "unknown", "right" }) do
  local env, R = boot(); mailTarget(env)
  local link = env.__addItem(0, 1, 1780, 3, { sell = 1 })
  local target
  env.GetSendMailItem = function() if target then return "Item", 1780, 1, target.count end end
  if mode ~= "unknown" then env.GetSendMailItemLink = function() return target and target.link end end
  env.ClickSendMailItemButton = function()
   env.__bags[0][1] = nil; target = { link = mode == "wrong" and "item:999" or link, count = 3 }
  end
  R.Mover:SendTo("mail", { { link = link, slots = { { 0, 1 } } } }); env.__tick(25)
  assert(historyHas(R, "Mail", "Requested"))
  assert(historyHas(R, "Mail", "Observed") == (mode == "right"), mode)
 end
end)

test("huge keep IDs reject atomically and startup drops unsafe IDs and context fields", function()
 local env, R = boot(function(e)
  e.RummageDB = { version = 5, keepQuantities = { [1e100] = 2, [2147483647] = 3 }, contextProfiles = { future = "X", raid = string.rep("x", 129), world = "Missing" } }
 end)
 assert(R.db.keepQuantities[1e100] == nil and R.db.keepQuantities[2147483647] == 3)
 assert(not R.db.contextProfiles.future and not R.db.contextProfiles.raid and R.db.contextProfiles.world == "Missing")
 local before = R.settings.scale
 assert(not R:ImportSettings("RUM1;scale=1.7;keep." .. string.rep("9", 400) .. "=2"))
 assert(R.settings.scale == before and R.db.keepQuantities[2147483647] == 3)
 R.db.profiles[string.rep("x", 129)] = {}; assert(not R.Extras:SetContextMapping("raid", string.rep("x", 129)))
 assert(R:ImportSettings(R:ExportSettings()))
end)

test("Tools history filter paging confirmed Clear and reserve Remove callbacks work", function()
 local env, R = boot()
 for i = 1, 20 do R.ActionHistory:Record("Sale", i % 2 == 0 and "Skipped" or "Requested", { reason = "Example" }) end
 R.Tools:Show("history")
 R.Tools.next.scripts.OnClick(R.Tools.next, "LeftButton"); assert(R.Tools.page == 2)
 R.Tools.previous.scripts.OnClick(R.Tools.previous, "LeftButton"); assert(R.Tools.page == 1)
 local menu; R.Widgets.Menu = function(_, _, items) menu = items end
 R.Tools.filterButton.scripts.OnClick(R.Tools.filterButton, "LeftButton")
 for _, item in ipairs(menu) do if item.text == "Skipped" then item.func() end end
 assert(R.Tools.filter == "Skipped")
 for _, row in ipairs(R.Tools.rows) do if row.record then assert(row.record.status == "Skipped") end end
 R.Tools.clearHistory.scripts.OnClick(R.Tools.clearHistory, "LeftButton")
 assert(env.__popup.which == "RUMMAGE_CLEAR_HISTORY" and #R.db.actionHistory == 20)
 env.StaticPopupDialogs.RUMMAGE_CLEAR_HISTORY.OnAccept(); assert(#R.db.actionHistory == 0)
 R.Junk:SetKeep(1780, 3); R.Tools:Show("keep"); R.Tools.keepID:SetText("1780"); R.Tools:SaveKeep(true); assert(not R.db.keepQuantities[1780])
 R.Tools:Show("profiles"); assert(R.Tools.status:GetText():find("No Profiles", 1, true))
 R.db.contextProfiles.raid = "Missing"; R.Tools:Refresh()
 for _, row in ipairs(R.Tools.profileRows) do if row.key == "raid" then assert(row.button.text:GetText():find("Unavailable", 1, true)) end end
end)

test("grid and menus remain bounded at font24 with full text preserved", function()
 local env, R = boot(); open(env, R)
 R.settings.fontSize = 24; R.Widgets:UpdateFonts(); R.settings.colorblindCues = true; R.settings.gridSize = 20
 local e = { id = 1790, link = "item:1790", bag = 0, slot = 1, count = 1000000, icon = 1, quality = 7, fav = 8, junk = true, slots = { { 0, 1 } }, info = { equippable = true, ilvl = 999 } }
 local row = R.UI:GetGridRow(1); R.UI:SetupGridRow(row, { items = { e } }, false)
 local c = row.cells[1]
 assert(c:GetWidth() >= 120 and c.cues.quality:GetHeight() >= 24 and c.cues.quality:GetWidth() >= 33)
 local _, _, _, _, ilvlY = c.ilvl:GetPoint(); assert(ilvlY > c.cues.quality:GetHeight())
 local text = string.rep("Long Profile Name ", 15); local clicked = false
 R.Widgets:Menu(R.UI.frame, { { text = text, func = function() clicked = true end } })
 local menu = env.RummageMenu; assert(menu:GetWidth() <= env.UIParent:GetWidth() - 24)
 local button
 for _, child in ipairs(menu.children) do if child.text and child.text:GetText() == text then button = child end end
 assert(button and button:GetHeight() >= 30 and button.text:GetHeight() >= 30)
 button.scripts.OnClick(button, "LeftButton"); assert(clicked and not menu:IsShown())
end)


test("Keep Save and Remove invalidate preview consent while preserving draft query", function()
 local env, R = boot()
 env.__addItem(0, 1, 2589, 20, { name = "Linen Cloth", quality = 0, sell = 13 })
 env.__addItem(0, 2, 2589, 16, { name = "Linen Cloth", quality = 0, sell = 13 })
 R.Tools:Show("preview"); R.Tools.queryBox:SetText("linen cloth"); R.Tools:RunPreview()
 assert(R.Tools.preview.sellUnits == 36)
 R.Tools:Show("keep"); R.Tools.keepID:SetText("2589"); R.Tools.keepCount:SetText("35"); R.Tools:SaveKeep(false)
 assert(not R.Tools.preview and R.Tools.queryBox:GetText() == "linen cloth" and R.Tools.enableButton.disabled)
 R.Tools:Show("preview"); R.Tools:EnablePreview(); assert(#R.db.junkRules == 0)
 R.Tools:RunPreview(); assert(R.Tools.preview.sellUnits == 1 and R.Tools.preview.retainedUnits == 35)
 R.Tools:Show("keep"); R.Tools:SaveKeep(true)
 assert(not R.Tools.preview and R.Tools.queryBox:GetText() == "linen cloth" and R.Tools.enableButton.disabled)
 R.Tools:Show("preview"); R.Tools:RunPreview(); assert(R.Tools.preview.sellUnits == 36)
end)


test("Forever locked original source count commits on split placement before selling one excess unit", function()
 local env, R = boot(); env.MerchantFrame:Show()
 env.__addItem(0, 1, 2589, 16, { name = "Linen Cloth", quality = 0, sell = 13, stack = 20 })
 env.__addItem(0, 2, 2589, 20, { name = "Linen Cloth", quality = 0, sell = 13, stack = 20 })
 local model = inventoryModel(env, R, { deferredSourceCount = true })
 R.Junk:SetKeep(2589, 35); local before = env.GetMoney(); R.Junk:SellAll()
 assert(env.__bags[0][1].count == 16 and env.__bags[0][1].locked and model.held.count == 1 and model.calls.sale == 0)
 model:tick(10)
 local _, totals = R.Junk:Inventory()
 assert(totals[2589] == 35 and env.__bags[0][1].count == 15 and not env.__bags[0][1].locked)
 assert(env.GetMoney() == before + 13 and model.calls.sale == 1 and #R.db.junkLog == 1 and R.db.junkLog[1].count == 1)
 assert(historyHas(R, "Sale", "Observed") and not R.Junk.ticker)
end)

test("Forever deferred source counts never sell on rejected placement or changed cursor", function()
 for _, mode in ipairs({ "reject", "cursor" }) do
  local env, R, model = reserveFixture({ deferredSourceCount = true, rejectPlace = mode == "reject" })
  local before = env.GetMoney(); R.Junk:SellAll()
  if mode == "cursor" then model.held = { id = 9999, link = "item:9999", count = 1 } end
  model:tick(20)
  assert(model.calls.sale == 0 and #R.db.junkLog == 0 and env.GetMoney() == before and not R.Junk.ticker)
  assert(env.__bags[0][1].count == 20)
  if mode == "reject" then assert(model.calls.clear == 1 and not model.held and not env.__bags[0][1].locked)
  else assert(model.calls.clear == 0 and model.held.id == 9999) end
 end
end)


test("large-text window chrome wraps measured controls without changing saved outer geometry", function()
 local env, R = boot(); env.MerchantFrame:Show(); R.Data.atBank = true
 local windows = { R.UI, R.BankUI, R.GuildUI }
 for _, ui in ipairs(windows) do
  ui:Open(); ui.frame:SetSize(680, 500)
  local buttons = { ui.tabBags, ui.tabBank, ui.allBtn, ui.viewBtn, ui.presetBtn, ui.btnSell, ui.btnSort, ui.btnRestack, ui.btnTransfer }
  if ui.tabGuild then buttons[#buttons + 1] = ui.tabGuild end
  if ui.tabGuildToggle then buttons[#buttons + 1] = ui.tabGuildToggle end
  for _, button in ipairs(buttons) do button.text.GetStringWidth = function(text) return #text:GetText() * R.settings.fontSize * 0.6 end end
  R.settings.fontSize = 24; R.Widgets:UpdateFonts(); ui:Layout()
  local header, footer = ui.chromeHeaderGeometry, ui.chromeFooterGeometry
  assert(header.rows == 2 and header.controlHeight >= 32 and header.searchWidth > 80)
  assert(ui:HeaderHeight() > 34 and ui:FooterHeight() >= 34 and ui.frame:GetWidth() == 680 and ui.frame:GetHeight() == 500)
  local _, relative, _, _, contentTop = ui.content:GetPoint()
  if relative == ui.sidebar then _, _, _, _, contentTop = ui.sidebar:GetPoint() end
  assert(-contentTop >= ui:HeaderHeight(), "content starts below wrapped header")
  for i, b in ipairs(footer.buttons) do
   assert(b.left >= 0 and b.right <= footer.available)
   for j, c in ipairs(footer.buttons) do if i ~= j and b.row == c.row then assert(b.right <= c.left or c.right <= b.left) end end
  end
  assert(footer.metadataY > footer.actionsHeight, "metadata is separate from actions")
  assert(ui.btnRestack.text:GetWidth() <= ui.btnRestack:GetWidth() - 12)
  ui.frame:SetWidth(400); ui:Layout()
  assert(ui.chromeHeaderGeometry.rows >= 2 and ui.chromeHeaderGeometry.searchWidth > 80)
  assert(ui.frame:GetWidth() == 400)
  R.settings.fontSize = 12; ui.frame:SetWidth(680); R.Widgets:UpdateFonts(); ui:Layout()
  assert(ui.chromeHeaderGeometry.rows == 1 and ui:HeaderHeight() == 34 and ui:FooterHeight() == 34)
  assert(ui.viewBtn:GetWidth() == 44 and ui.presetBtn:GetWidth() == 52 and ui.btnSort:GetWidth() == 46)
 end
end)

test("responsive chrome preserves view and cross-character toggle callbacks and metadata tooltips", function()
 local env, R = boot(); open(env, R)
 R.settings.fontSize = 24; R.UI:Layout()
 local before = R.settings.viewMode
 R.UI.viewBtn.scripts.OnClick(R.UI.viewBtn, "LeftButton")
 assert(R.settings.viewMode ~= before)
 before = R.settings.searchAllChars
 R.UI.allBtn.scripts.OnClick(R.UI.allBtn, "LeftButton")
 assert(R.settings.searchAllChars ~= before)
 for _, field in ipairs({ R.UI.freeText, R.UI.cachedText, R.UI.totalText, R.UI.currencyText }) do
  assert(field.tipFrame and field.tipFrame.scripts.OnEnter and field:GetHeight() >= 28)
 end
end)


test("chrome sizing measures intrinsic labels instead of feedback from clipped regions", function()
 local env, R = boot(); open(env, R); env.MerchantFrame:Show(); R.Data.atBank = true
 R.settings.fontSize = 24; R.Widgets:UpdateFonts()
 local buttons = { R.UI.tabBags, R.UI.tabBank, R.UI.tabGuildToggle, R.UI.allBtn, R.UI.viewBtn, R.UI.presetBtn, R.UI.btnSell, R.UI.btnRestack, R.UI.btnSort, R.UI.btnTransfer }
 for _, b in ipairs(buttons) do
  b.text.GetUnboundedStringWidth = false -- exercise legacy client fallback
  b.text.GetStringWidth = function(text) return math.min(text:GetWidth(), #text:GetText() * 23 * 0.6) end
 end
 -- The one unconstrained probe follows the real font's intrinsic glyph widths.
 local probe = R.Widgets.measureText
 assert(probe)
 probe.GetStringWidth = function(text) return #text:GetText() * 23 * 0.6 end
 R.UI:Layout()
 for _, b in ipairs(buttons) do assert(b:GetWidth() >= #b.text:GetText() * 23 * 0.6 + 16, b.text:GetText() .. " remains clipped") end
 assert(R.UI.chromeHeaderGeometry.rows == 2 and R.UI.chromeHeaderGeometry.searchWidth > 80)
 local source = R.UI.tabBank.text
 source.GetUnboundedStringWidth = function() return 75 end
 assert(R.Widgets:MeasureText(source) == 75)
 source.GetUnboundedStringWidth = function() error("unsupported runtime call") end
 assert(R.Widgets:MeasureText(source) == #source:GetText() * 23 * 0.6)
end)


-- Confirmed buyback fixture: three independent server evidence channels.
local function buybackFixture(options)
 options = options or {}
 local env, R = boot(); env.MerchantFrame:Show(); env.__money = 1000
 local link = env.__addItem(0, 1, 1900, 2, { name = "Recovered Cloth", sell = 5, stack = 20 }); env.__bags[0][1] = nil
 local id = R.Buyback:AddSale(link, 2, 10)
 local record = R.ActionHistory:Record("Sale", "Observed", { link = link, count = 2, value = 10, saleLedgerID = id })
 env.__buyback = { { link = link, count = 2, price = 10 } }
 local model = { requests = {}, link = link, id = id, historyID = record.id }
 function model:channel(request, kind)
  if request[kind] then return end; request[kind] = true
  local item = request.item
  if kind == "list" then for i, candidate in ipairs(env.__buyback) do if candidate == item then table.remove(env.__buyback, i); break end end
  elseif kind == "bag" then
   local count = options.wrongCount and 1 or item.count
   local recovered = options.wrongItem and "item:9999" or item.link
   for slot = 1, env.__bags[0].size do if not env.__bags[0][slot] then env.__bags[0][slot] = { link = recovered, count = count, id = 1900, quality = 1 }; break end end
  else env.__money = env.__money - (options.wrongMoney and item.price + 1 or item.price) end
 end
 function model:ack(order)
  local request = self.requests[#self.requests]
  for _, channel in ipairs(order or { "list", "bag", "money" }) do self:channel(request, channel); env.__ev("MERCHANT_UPDATE") end
 end
 env.BuybackItem = function(index)
  local request = { index = index, item = env.__buyback[index] }; model.requests[#model.requests + 1] = request
  if options.sync then model:ack() end
 end
 return env, R, model
end

test("buyback observes synchronous and every asynchronous evidence ordering exactly once", function()
 for _, order in ipairs({ { "list", "bag", "money" }, { "money", "bag", "list" }, { "bag", "list", "money" } }) do
  local env, R, m = buybackFixture()
  assert(R.Buyback:FromHistory(m.historyID)); assert(#m.requests == 1 and #R.db.junkLog == 1)
  m:channel(m.requests[1], order[1]); env.__ev("PLAYER_MONEY"); assert(#R.db.junkLog == 1)
  m:channel(m.requests[1], order[2]); env.__ev("BAG_UPDATE_DELAYED"); assert(#R.db.junkLog == 1)
  m:channel(m.requests[1], order[3]); env.__ev("MERCHANT_UPDATE")
  assert(#R.db.junkLog == 0 and not R.Buyback.operation and historyHas(R, "Buyback", "Observed"))
  env.__tick(30); assert(#m.requests == 1 and env.__money == 990)
 end
 local env, R, m = buybackFixture({ sync = true }); R.Junk:Buyback(1)
 assert(#m.requests == 1 and #R.db.junkLog == 0 and not R.Buyback.operation)
end)

test("buyback requires exact signature inventory quantity and money without burst-event timeout", function()
 for _, mode in ipairs({ "wrongCount", "wrongItem", "wrongMoney", "noop", "unrelated" }) do
  local options = {}; options[mode] = true
  local env, R, m = buybackFixture(options)
  env.__buyback[2] = { link = "item:888", count = 1, price = 2 }
  R.Junk:Buyback(1)
  if mode == "unrelated" then table.remove(env.__buyback, 2)
  elseif mode ~= "noop" then m:ack() end
  for i = 1, 40 do env.__ev("MERCHANT_UPDATE"); env.__ev("BAG_UPDATE_DELAYED"); env.__ev("PLAYER_MONEY") end
  assert(R.Buyback.operation and #R.db.junkLog == 1 and not historyHas(R, "Buyback", "Observed"), mode)
  env.__tick(26)
  assert(not R.Buyback.operation and #R.db.junkLog == 1 and historyHas(R, "Buyback", "Stopped"), mode)
 end
end)

test("buyback rejects missing signature APIs unknown price count insufficient funds and occupied cursor", function()
 for _, mode in ipairs({ "price", "count", "api", "funds", "cursor", "combat" }) do
  local env, R, m = buybackFixture()
  if mode == "price" then env.GetBuybackItemInfo = function() return "Cloth", 1, nil, 2 end
  elseif mode == "count" then env.GetBuybackItemInfo = function() return "Cloth", 1, 10, nil end
  elseif mode == "api" then env.GetBuybackItemInfo = nil
  elseif mode == "funds" then env.__money = 1
  elseif mode == "cursor" then env.GetCursorInfo = function() return "item", 9999 end
  else env.__combat = true end
  assert(not R.Buyback:Availability(m.historyID)); R.Buyback:FromHistory(m.historyID)
  assert(#m.requests == 0 and #R.db.junkLog == 1 and not R.Buyback.operation, mode)
 end
end)

test("buyback duplicate signatures serialize all and re-resolve shifting indices", function()
 local env, R, m = buybackFixture({ sync = true })
 local other = env.__addItem(0, 1, 1901, 1, { name = "Other", sell = 9 }); env.__bags[0][1] = nil
 R.Buyback:AddSale(other, 1, 9); R.Buyback:AddSale(m.link, 2, 10)
 env.__buyback = { { link = m.link, count = 1, price = 5 }, { link = m.link, count = 2, price = 10 }, { link = other, count = 1, price = 9 }, { link = m.link, count = 2, price = 10 } }
 R.Junk:Buyback("all")
 assert(#m.requests == 3 and m.requests[1].index == 4 and #R.db.junkLog == 0 and #env.__buyback == 1)
 assert(env.__buyback[1].count == 1 and env.__money == 971)
end)

test("buyback pending rejects repeat clicks and stops on session combat cursor API or ledger loss", function()
 for _, mode in ipairs({ "session", "combat", "cursor", "api", "ledger" }) do
  local env, R, m = buybackFixture(); R.Buyback:FromHistory(m.historyID)
  local op = R.Buyback.operation
  assert(not R.Buyback:FromHistory(m.historyID)); R.Junk:Buyback("all"); assert(#m.requests == 1)
  if mode == "session" then env.__ev("MERCHANT_CLOSED"); env.__ev("MERCHANT_SHOW")
  elseif mode == "combat" then env.__combat = true
  elseif mode == "cursor" then env.GetCursorInfo = function() return "item", 9999 end
  elseif mode == "api" then env.GetBuybackItemInfo = nil
  else R.db.junkLog = { { id = "sale:1:999", link = "item:123", count = 1, value = 1 } }; m:ack() end
  env.__tick(2); R.Buyback:Check(op, true)
  assert(not R.Buyback.operation and op.ticker.cancelled and #m.requests == 1 and not historyHas(R, "Buyback", "Observed"), mode)
  if mode == "ledger" then assert(R.db.junkLog[1].id == "sale:1:999") end
 end
end)

test("buyback removes stable ledger identity despite reorder and history clear", function()
 local env, R, m = buybackFixture()
 R.Buyback:FromHistory(m.historyID)
 local extra = R.Buyback:AddSale("item:777", 1, 3)
 R.ActionHistory:Clear(); m:ack()
 assert(#R.db.junkLog == 1 and R.db.junkLog[1].id == extra and historyHas(R, "Buyback", "Observed"))
end)

test("ledger and history sanitizer retains stable links but disables corrupt or duplicate claims", function()
 for _, corrupt in ipairs({ "bad", { false, 123, "bad" } }) do
  local env, R = boot(function(e) e.RummageDB = { junkLog = { { id = "sale:1:1", t = 1, link = "item:1", count = 1, value = 2 } }, actionHistory = corrupt } end)
  assert(#R.db.junkLog == 1 and #R.db.actionHistory == 0)
 end
 local env, R = boot(function(e)
  e.RummageDB = { junkLog = { { id = "sale:1:1", t = 1, link = "item:1", count = 1, value = 2 }, { id = "sale:1:1", t = 2, link = "item:2", count = 1, value = 3 } },
   actionHistory = { { id = 1, t = 1, action = "Sale", status = "Observed", link = "item:1", count = 1, value = 2, saleLedgerID = "sale:1:1" } } }
 end)
 assert(R.db.junkLog[1].id ~= R.db.junkLog[2].id and R.db.actionHistory[1].ledgerInvalid and not R.Buyback:Availability(R.db.actionHistory[1].id))
 local e2, R2, m = buybackFixture()
 R2.ActionHistory:Record("Sale", "Observed", { link = m.link, count = 2, value = 10 })
 R2.ActionHistory:Record("Sale", "Observed", { link = m.link, count = 2, value = 10 })
 assert(not R2.Buyback:Availability(R2.db.actionHistory[1].id))
 assert(R2.Buyback:Availability(m.historyID)) -- the new linked sale remains unique
end)

test("history Buy Back captures record identity Pending and large-font trailing width", function()
 local env, R, m = buybackFixture(); R.settings.fontSize = 24; R.Widgets:UpdateFonts(); env.UIParent:SetSize(1280, 720)
 R.Tools:Show("history"); local row
 for _, r in ipairs(R.Tools.rows) do if r.record and r.record.id == m.historyID then row = r end end
 assert(row and row.buyBack:IsShown() and not row.buyBack.disabled)
 assert(row.text:GetWidth() + row.buyBack:GetWidth() + 10 < row:GetWidth() and row.buyBack:GetHeight() >= 36)
 local click = row.buyBack.scripts.OnClick
 R.ActionHistory:Record("Transfer", "Skipped", { reason = "New Row" }); click()
 assert(#m.requests == 1 and R.Buyback.operation.current.id == m.id)
 R.Tools:Refresh(); local pending
 for _, r in ipairs(R.Tools.rows) do if r.record and r.record.id == m.historyID then pending = r end end
 assert(pending.buyBack.disabled and pending.buyBack.text:GetText() == "Pending")
 click(); assert(#m.requests == 1); m:ack(); R.Tools:Refresh()
 assert(not R.Buyback.operation)
 for _, r in ipairs(R.Tools.rows) do if r.record and r.record.id == m.historyID then assert(r.buyBack.disabled and r.buyBack.tipBody:find("Already Bought", 1, true)) end end
end)


test("buyback notification reentrancy cannot issue a cancelled or superseded request", function()
 local env, R, m = buybackFixture()
 R:Listen("ACTION_HISTORY_CHANGED", function()
  local row = R.db.actionHistory[1]
  if row and row.action == "Buyback" and row.status == "Requested" then R.Buyback:Stop("Cancelled By Listener") end
 end)
 R.Buyback:FromHistory(m.historyID)
 assert(#m.requests == 0 and not R.Buyback.operation and #R.db.junkLog == 1)
 local e2, R2, m2 = buybackFixture()
 local newSale = R2.Buyback:AddSale(m2.link, 2, 10)
 e2.__buyback[2] = { link = m2.link, count = 2, price = 10 }
 local replaced = false
 R2:Listen("ACTION_HISTORY_CHANGED", function()
  local row = R2.db.actionHistory[1]
  if not replaced and row and row.action == "Buyback" and row.status == "Observed" then
   replaced = true; R2.Buyback:Stop("Replaced"); R2.Buyback:Start({ newSale })
  end
 end)
 R2.Buyback:Start({ m2.id, newSale }); local old = R2.Buyback.operation
 m2:ack(); assert(replaced and #m2.requests == 2)
 R2.Buyback:Check(old, true); assert(#m2.requests == 2)
end)

test("history buyback availability updates immediately on combat and cursor boundaries", function()
 local env, R, m = buybackFixture(); R.Tools:Show("history")
 local function button()
  for _, row in ipairs(R.Tools.rows) do if row.record and row.record.id == m.historyID then return row.buyBack end end
 end
 assert(not button().disabled)
 env.__combat = true; env.__ev("PLAYER_REGEN_DISABLED"); assert(button().disabled and button().tipBody:find("Combat", 1, true))
 env.__combat = false; env.__ev("PLAYER_REGEN_ENABLED"); assert(not button().disabled)
 env.GetCursorInfo = function() return "item", 9999 end; env.__ev("CURSOR_CHANGED"); assert(button().disabled)
 env.GetCursorInfo = function() return nil end; env.__ev("CURSOR_CHANGED"); assert(not button().disabled)
end)

local function bankModel(options, merge)
 local env, R = boot(); env.__bags[-1] = { size = 4 }
 local link = env.__addItem(0, 1, 1910, 5, { name = "Bank Ore", stack = 20, sell = 1 })
 if merge then env.__addItem(-1, 1, 1910, 3, { name = "Bank Ore", stack = 20, sell = 1 }) end
 env.__ev("BANKFRAME_OPENED")
 local model = inventoryModel(env, R, options)
 function model:frames(n) for i = 1, n do self:tick(1); env.__update(0.2) end end
 return env, R, model, link
end

test("bank transfers verify empty placement and exact partial-stack merge after acknowledgement", function()
 for _, merge in ipairs({ false, true }) do
  local env, R, model, link = bankModel(nil, merge)
  local done = false
  R.Mover:Start(R.Mover:PlanTransfer({ { 0, 1 } }, { -1 }), "bank", function() done = true end)
  model:frames(4)
  assert(done and not R.Mover:Busy() and not env.__bags[0][1] and env.__bags[-1][1].link == link)
  assert(env.__bags[-1][1].count == (merge and 8 or 5) and historyHas(R, "Transfer", "Observed"))
 end
end)

test("bank session and combat interruption precede queued acknowledgement and never resume old work", function()
 for _, mode in ipairs({ "close", "combat", "cursor", "noack", "replaced", "count", "locked" }) do
  local env, R, model = bankModel({ rejectPlace = mode == "noack" })
  local done = false
  local planner = R.Mover:PlanTransfer({ { 0, 1 } }, { -1 })
  if mode == "replaced" then env.__addItem(0, 1, 9999, 5)
  elseif mode == "count" then env.__bags[0][1].count = 6
  elseif mode == "locked" then env.__bags[0][1].locked = true end
  R.Mover:Start(planner, "bank", function() done = true end)
  model:frames(1)
  if mode == "close" then env.__ev("BANKFRAME_CLOSED"); env.__ev("BANKFRAME_OPENED")
  elseif mode == "combat" then env.__combat = true
  elseif mode == "cursor" then model.held = { link = "item:9999", id = 9999, count = 1 } end
  model:frames(25)
  assert(not R.Mover:Busy() and not historyHas(R, "Transfer", "Observed"), mode)
  if mode == "close" or mode == "combat" or mode == "cursor" or mode == "noack" then assert(not done, mode) end
 end
end)

local function targetModel(kind, options)
 options = options or {}
 local env, R = boot(); env.__bags[0].size = 8
 local links = {}
 for slot = 1, 3 do links[slot] = env.__addItem(0, slot, 1920 + slot, 2, { name = "Target" .. slot }) end
 local target, pending, calls = {}, {}, {}
 if kind == "mail" then
  mailTarget(env); env.ATTACHMENTS_MAX_SEND = options.full and 1 or 12
  env.GetSendMailItem = function(i) local e = target[i]; if e then return "Item", 1, 1, e.count end end
  env.GetSendMailItemLink = function(i) return target[i] and target[i].link end
  if options.missing then env.GetSendMailItemLink = nil end
 else
  env.TradeFrame = env.CreateFrame("Frame", "TradeFrame"); env.TradeFrame:Show(); env.MAX_TRADABLE_ITEMS = 7
  env.GetTradePlayerItemLink = function(i) return target[i] and target[i].link end
  env.GetTradePlayerItemInfo = function(i) local e = target[i]; if e then return "Item", 1, e.count end end
  if options.missing then env.GetTradePlayerItemInfo = nil end
 end
 if options.full then for i = 1, kind == "mail" and 1 or 6 do target[i] = { link = "item:888", count = 1 } end end
 local function place(i)
  calls[#calls + 1] = i
  local source = env.__picked; local item = env.__bags[source[1]][source[2]]
  pending[#pending + 1] = function()
   env.__bags[source[1]][source[2]] = nil
   target[i] = { link = options.wrong and "item:999" or item.link, count = item.count }
  end
  if not options.delay and not options.noack then table.remove(pending, 1)() end
 end
 if kind == "mail" then env.ClickSendMailItemButton = place else env.ClickTradeButton = place end
 local entries = {}; for i = 1, 3 do entries[i] = { link = links[i], slots = { { 0, i } } } end
 return env, R, entries, target, pending, calls
end

test("mail and trade serialize exact attachment observation and trade excludes the seventh slot", function()
 for _, kind in ipairs({ "mail", "trade" }) do
  local env, R, entries, target, pending, calls = targetModel(kind, { delay = true })
  R.Mover:SendTo(kind, entries); assert(#calls == 1)
  for step = 1, 3 do table.remove(pending, 1)(); env.__tick(1) end
  env.__tick(2)
  assert(#calls == 3 and not R.Mover:Busy() and historyHas(R, kind == "mail" and "Mail" or "Trade", "Observed"))
  for _, i in ipairs(calls) do assert(i <= (kind == "mail" and 12 or 6)) end
  local e2, R2, list, _, _, attempts = targetModel(kind, { full = true })
  R2.Mover:SendTo(kind, list); assert(#attempts == 0 and not R2.Mover:Busy())
 end
end)

test("mail and trade session target and source changes stop before old acknowledgement", function()
 for _, kind in ipairs({ "mail", "trade" }) do
  for _, mode in ipairs({ "close", "combat", "cursor", "wrong", "missing", "noack", "bound", "count" }) do
   local opts = { delay = true }; opts[mode] = true
   local env, R, entries, target, pending, calls = targetModel(kind, opts)
   R.Mover:SendTo(kind, entries)
   if mode == "close" then
    if kind == "mail" then env.SendMailFrame:Hide(); env.SendMailFrame:Show() else env.TradeFrame:Hide(); env.TradeFrame:Show() end
   elseif mode == "combat" then env.__combat = true
   elseif mode == "cursor" then env.GetCursorInfo = function() return "item", 9999 end
   elseif mode == "bound" then env.__bags[0][2].bound = true
   elseif mode == "count" then env.__bags[0][2].count = 3 end
   if mode ~= "noack" then table.remove(pending, 1)() end
   env.__tick(30)
   assert(not R.Mover:Busy(), kind .. mode)
   if mode == "close" or mode == "combat" or mode == "cursor" or mode == "wrong" or mode == "missing" or mode == "noack" then
    assert(#calls == 1 and not historyHas(R, kind == "mail" and "Mail" or "Trade", "Observed"), kind .. mode)
   else assert(#calls <= 2, kind .. mode) end
  end
 end
end)


test("bank delayed acknowledgement does not complete or advance while source remains locked", function()
 local env, R, model, link = bankModel()
 local held, waiting
 env.GetCursorInfo = function() if held then return "item", held.item.id, held.item.link end end
 R.API.PickupContainerItem = function(bag, slot)
  if not held then
   held = { bag = bag, slot = slot, item = env.__bags[bag][slot] }; held.item.locked = true
  else waiting = { source = held, bag = bag, slot = slot }; held = nil end
 end
 local done = false
 R.Mover:Start(R.Mover:PlanTransfer({ { 0, 1 } }, { -1 }), "bank", function() done = true end)
 model:frames(2)
 assert(waiting and not done and not historyHas(R, "Transfer", "Observed") and R.Mover:Busy())
 local request = waiting; request.source.item.locked = nil
 env.__bags[request.bag][request.slot] = request.source.item; env.__bags[request.source.bag][request.source.slot] = nil
 model:frames(3)
 assert(done and not R.Mover:Busy() and env.__bags[-1][1].link == link and historyHas(R, "Transfer", "Observed"))
end)

test("buyback ledger linkage survives startup without legacy ambiguity", function()
 local env, R = boot(function(e)
  e.RummageDB = { junkLog = { { id = "sale:1:99", t = 1, link = "item:1900", count = 2, value = 10 } },
   actionHistory = { { id = 999, t = 1, action = "Sale", status = "Observed", link = "item:1900", count = 2, value = 10, saleLedgerID = "sale:1:99" } } }
 end)
 env.MerchantFrame:Show(); env.__buyback = { { link = "item:1900", count = 2, price = 10 } }
 local id = R.db.actionHistory[1].id
 assert(R.db.actionHistory[1].saleLedgerID == "sale:1:99" and R.Buyback:Availability(id))
 R.Buyback:FromHistory(id); env.__tick(2)
 assert(#R.db.junkLog == 0 and historyHas(R, "Buyback", "Observed"))
end)

test("buyback re-resolves merchant candidate after Requested listeners shift or replace its index", function()
 for _, replace in ipairs({ false, true }) do
  local env, R, m = buybackFixture()
  R:Listen("ACTION_HISTORY_CHANGED", function()
   local row = R.db.actionHistory[1]
   if row and row.action == "Buyback" and row.status == "Requested" then
    if replace then env.__buyback[1] = { link = "item:999", count = 1, price = 1 }
    else table.insert(env.__buyback, 1, { link = "item:999", count = 1, price = 1 }) end
   end
  end)
  R.Buyback:FromHistory(m.historyID)
  if replace then assert(#m.requests == 0 and not R.Buyback.operation)
  else assert(#m.requests == 1 and m.requests[1].index == 2 and m.requests[1].item.link == m.link) end
 end
end)


test("unknown merchant list size cannot confirm buyback despite inventory and money deltas", function()
 for _, size in ipairs({ false, -1, 0.5, math.huge, 101 }) do
  local env, R, m = buybackFixture(); R.Buyback:FromHistory(m.historyID)
  env.GetNumBuybackItems = function() return size ~= false and size or nil end
  m:ack(); env.__tick(2)
  assert(#R.db.junkLog == 1 and not historyHas(R, "Buyback", "Observed") and not R.Buyback.operation, tostring(size))
 end
end)


-- Append once to tests/cases.lua; uses its existing test/boot helpers.

-- Append once to tests/cases.lua; uses its existing test/boot helpers.
test("rule diagnostics reports every OR overlap once and keeps manual classification separate from protection", function()
 local env, R = boot()
 env.__addItem(0, 1, 2100, 5, { name = "Linen Cloth", quality = 0, sell = 2 })
 R.db.junkRules = { "linen", "type:miscellaneous | linen" }
 local before = #R.db.junkRules
 local result = assert(R.RuleDiagnostics:AnalyzeRules())
 assert(result.matchedUnits == 5 and result.overlapUnits == 5 and result.overlapPairs["1:2"] == 5 and result.sellUnits == 5)
 assert(#result.rows[1].matches == 2 and result.rows[1].detail:find("No Priority Winner", 1, true))
 R.db.junk[2100] = false
 result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.rows[1].source == "Manual Keep" and not result.rows[1].junk and result.sellUnits == 0)
 R.db.junk[2100] = true; R.db.favorites[2100] = 2
 result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.rows[1].junk and result.rows[1].source == "Manual Junk" and result.sellUnits == 0)
 R.settings.protectFavorites = false
 result = assert(R.RuleDiagnostics:AnalyzeRules("linen")); assert(result.sellUnits == 5 and result.draft.sellUnits == 0)
 assert(result.rows[1].detail:find("Draft Preview Excludes Favorites", 1, true) and #R.db.junkRules == before and not env.__used)
 R.Items.InSet = function() return true end
 result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.sellUnits == 0 and result.rows[1].detail:find("Equipment", 1, true))
end)

test("rule diagnostics uses one canonical Scrap decision and exposes fallback errors unknown data and cap effects", function()
 local env, R = boot()
 env.__addItem(0, 1, 2101, 3, { name = "Stone", quality = 0, sell = 1 })
 R.settings.useScrap = true
 local calls = 0
 env.Scrap = { IsJunk = function() calls = calls + 1; return false end }
 local result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.rows[1].source == "Scrap" and not result.rows[1].junk and result.sellUnits == 0)
 env.Scrap.IsJunk = function() error("unavailable") end
 result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.rows[1].junk and result.rows[1].detail:find("Plugin Error", 1, true))
 R.Items.Info = function() return nil end
 result = assert(R.RuleDiagnostics:AnalyzeRules()); assert(result.sellUnits == 0 and result.rows[1].detail:find("Unknown Item Data", 1, true))
 assert(not R.RuleDiagnostics:AnalyzeRules("(|) | stone"))
 local e2, R2 = boot(); e2.__bags[0].size = 15; R2.settings.buybackSafe = true; R2.db.junkRules = { "cloth", "cloth" }
 for i = 1, 15 do e2.__addItem(0, i, 2110 + i, 1, { name = "Cloth" .. i, quality = 0, sell = i }) end
 result = assert(R2.RuleDiagnostics:AnalyzeRules()); assert(result.overlapUnits == 15 and result.sellUnits == 12)
 local capped = 0; for _, row in ipairs(result.rows) do if row.detail:find("Batch Limit", 1, true) then capped = capped + 1 end end
 assert(capped == 3)
end)

test("vendor summary uses private deduplicated facts independent of history and raw wallet changes", function()
 local env, R = boot(); env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
 env.__addItem(0, 1, 2120, 5, { quality = 0, sell = 5 }); env.__addItem(0, 2, 2120, 4, { quality = 0, sell = 5 }); R.Junk:SetKeep(2120, 3)
 local V, token = R.VendorSession, R.VendorSession:Token()
 V:Record("Sale", "Candidate", { session = token, itemID = 2120 })
 V:Record("Sale", "Requested", { session = token, operationID = "one", itemID = 2120 })
 local full = { session = token, operationID = "one", saleLedgerID = "sale:2:1", itemID = 2120, count = 2, value = 10, slotsFreed = 1 }
 assert(V:Record("Sale", "Observed", full)); assert(not V:Record("Sale", "Observed", full))
 local partial = { session = token, operationID = "two", saleLedgerID = "sale:2:2", itemID = 2120, count = 1, value = 5, slotsFreed = 0 }
 V:Record("Split", "Observed", { session = token, operationID = "two", itemID = 2120, slotsConsumed = 1 })
 V:Record("Sale", "Observed", partial)
 R.ActionHistory:Clear(); for i = 1, 110 do R.ActionHistory:Record("Sale", "Requested", { count = 999, value = 999, reason = "Not A Private Fact" }) end
 env.__money = env.GetMoney() + 9999
 local result = V:Summary(); assert(result.observedStacks == 2 and result.observedUnits == 3 and result.gross == 15 and result.retained == 3 and result.slotsFreed == 1 and result.stagingSlots == 0)
 assert(V:Record("Buyback", "Observed", { session = token, operationID = "back", saleLedgerID = "sale:2:1", itemID = 2120, count = 2, value = 10 }))
 assert(not V:Record("Buyback", "Observed", { session = token, operationID = "duplicate", saleLedgerID = "sale:2:1", itemID = 2120, count = 2, value = 10 }))
 result = V:Summary(); assert(result.gross == 15 and result.buybackCost == 10 and result.net == 5)
end)

test("vendor close seals epochs and fully retained candidates remain counted once", function()
 local env, R = boot(); env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
 env.__addItem(0, 1, 2130, 5, { quality = 0, sell = 1 }); R.Junk:SetKeep(2130, 10)
 local V, old = R.VendorSession, R.VendorSession:Token()
 V:Record("Sale", "Candidate", { session = old, itemID = 2130 }); V:Record("Sale", "Candidate", { session = old, itemID = 2130 })
 assert(V:Summary().retained == 5 and V:Summary().gross == 0 and V:Summary().summary:find("No Observed Sales", 1, true))
 V:Record("Split", "Observed", { session = old, operationID = "stage", itemID = 2130, slotsConsumed = 1 })
 V:Record("Sale", "Stopped", { session = old, operationID = "stage", itemID = 2130 })
 assert(V:Summary().stagingSlots == 1 and V:Summary().stopped == 1)
 env.__ev("MERCHANT_CLOSED"); assert(not V:Summary().active and V:Summary().retained == 5)
 env.__ev("MERCHANT_SHOW"); assert(V:Token() ~= old)
 assert(not V:Record("Sale", "Observed", { session = old, operationID = "late", saleLedgerID = "sale:2:3", itemID = 2130, count = 1, value = 1, slotsFreed = 1 }))
 assert(V:Summary().observedStacks == 0)
 V:Record("Buyback", "Observed", { session = V:Token(), operationID = "oldBuyback", saleLedgerID = "sale:1:99", itemID = 2130, count = 1, value = 20 })
 local result = V:Summary(); assert(result.net == -20 and result.rows[4].detail:sub(1, 1) == "-")
end)

test("vendor retained quantity is Unknown when live quantity capture is unavailable", function()
 local env, R = boot(); env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
 R.VendorSession:Record("Sale", "Candidate", { session = R.VendorSession:Token(), itemID = 2140 })
 local original = R.API.GetNumSlots
 R.API.GetNumSlots = function(bag) if bag == 0 then return nil end; return original(bag) end
 local result = R.VendorSession:Summary(); assert(result.retained == nil and result.rows[5].detail == "Unknown")
end)

test("Planning has four paged native views with bounded typography and no reopening allocations", function()
 local env, R = boot(); env.UIParent:SetSize(1280, 720)
 for i = 1, 20 do R.Restock:SetTarget(2200 + i, i) end
 R.Planning:Show("restock"); local count = #env.__frames
 for _, font in ipairs({ 6, 12, 24 }) do
  R.settings.fontSize = font; R.Widgets:UpdateFonts()
  for _, tab in ipairs({ "restock", "rules", "vendor", "forecast" }) do
   R.Planning:Show(tab); local P, g = R.Planning, R.Planning.layout
   assert(P.status:GetHeight() >= g.line * 3 and g.rowTop >= g.statusTop + g.statusHeight + 10)
   assert(g.rowTop + P.pageSize * (g.rowHeight + 2) + g.control + 18 <= P.frame:GetHeight())
   for _, row in ipairs(P.rows) do local _, _, _, _, y = row.detail:GetPoint(); assert(-y >= row.text:GetHeight() + 4) end
   assert(P.frame:GetWidth() <= 1280 and P.frame:GetHeight() <= 720 and P.frame:GetScale() <= 1)
  end
 end
 assert(#env.__frames == count)
 R.Planning:Show("restock"); assert(R.Planning.pageSize < 8)
 R.Planning.next:Click(); assert(R.Planning.page == 2); R.Planning.previous:Click(); assert(R.Planning.page == 1)
end)

test("Planning restock executes only captured confirmation and draft/query changes invalidate views", function()
 local env, R = boot(); R.Planning:Show("restock")
 local P = R.Planning
 P.restockID:SetText("2300"); P.restockCount:SetText("1.5"); P:SaveTarget(false); assert(not R.db.restockTargets[2300])
 P.restockCount:SetText("5"); P:SaveTarget(false); assert(R.db.restockTargets[2300] == 5 and not P.preview)
 local token = { executable = true, moves = { {} }, rows = {}, forecast = { known = true, netCarriedSlots = -1 } }
 local oldPreview, oldExecute = R.Restock.Preview, R.Restock.Execute
 R.Restock.Preview = function() return token end
 local executed
 R.Restock.Execute = function(_, preview) executed = preview; return true end
 P:Run(); P:ConfirmExecute(); assert(not executed and env.__popup.which == "RUMMAGE_CONFIRM_RESTOCK")
 env.StaticPopupDialogs.RUMMAGE_CONFIRM_RESTOCK.OnAccept(nil, env.__popup.args[3]); assert(executed == token and not P.preview)
 R.Restock.Preview, R.Restock.Execute = oldPreview, oldExecute
 P:SaveTarget(true); assert(not R.db.restockTargets[2300])
 P:Show("rules"); P.queryBox:SetText("(|) | cloth"); P:Run(); assert(not P.result and P.status:GetText() ~= "")
 P:Show("forecast"); P.queryBox:SetText(""); P:Run(); assert(P.result)
 P.queryBox:SetText("cloth"); P.queryBox.scripts.OnTextChanged(P.queryBox); assert(not P.result)
 local menu; R.Widgets.Menu = function(_, _, entries) menu = entries end
 P:ChooseForecast(P.kindButton)
 for _, entry in ipairs(menu) do if entry.text == "From Bank" then entry.func() end end
 assert(P.forecastKind == "fromBank" and not P.result)
end)


test("vendor summary consumes real observed sale and buyback facts before history notification side effects", function()
 local env, R = boot(); env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
 local link = env.__addItem(0, 1, 2400, 20, { name = "Session Cloth", quality = 0, sell = 3, stack = 20 })
 R.Junk:SetKeep(2400, 7)
 local model = inventoryModel(env, R, { deferredSourceCount = true })
 local cleared = false
 R:Listen("ACTION_HISTORY_CHANGED", function()
  local row = R.db.actionHistory[1]
  if not cleared and row and row.action == "Sale" and row.status == "Observed" then cleared = true; R.ActionHistory:Clear() end
 end)
 R.Junk:SellAll(); model:tick(12)
 local result = R.VendorSession:Summary()
 assert(cleared and result.observedStacks == 1 and result.observedUnits == 13 and result.gross == 39 and result.slotsFreed == 0 and result.stagingSlots == 0 and result.retained == 7)
 env.__buyback = { { link = link, count = 13, price = 39 } }
 R.Junk:Buyback(1); env.__tick(3)
 result = R.VendorSession:Summary(); assert(result.gross == 39 and result.buybackCost == 39 and result.net == 0)
 local token = result.session
 env.__ev("MERCHANT_CLOSED"); env.__ev("MERCHANT_SHOW")
 assert(R.VendorSession:Summary().gross == 0 and not R.VendorSession:Record("Sale", "Observed", { session = token, operationID = "stale", saleLedgerID = "sale:2:999", itemID = 2400, count = 1, value = 3, slotsFreed = 1 }))
end)


local function restockFixture(options)
 local env, R = boot()
 R.API.BankBagList = { -1 }; env.__bags[-1] = { size = 4 }
 env.__addItem(0, 1, 2000, 7, { name = "Restock Cloth", stack = 15, sell = 2 })
 env.__addItem(-1, 1, 2000, 50, { name = "Restock Cloth", stack = 15, sell = 2 })
 env.__ev("BANKFRAME_OPENED"); R.Restock:SetTarget(2000, 20)
 local model = inventoryModel(env, R, options)
 function model:frames(n) for i = 1, n do self:tick(1); env.__update(0.25) end end
 return env, R, model
end

test("restock oracle withdraws exact thirteen using existing capacity eight and one new slot five", function()
 for _, deferred in ipairs({ false, true }) do
  local env, R, model = restockFixture({ deferredSourceCount = deferred })
  local preview = R.Restock:Preview()
  assert(preview.executable and preview.rows[1].plannedWithdraw == 13 and #preview.moves == 2)
  assert(preview.moves[1].count == 8 and preview.moves[2].count == 5 and preview.forecast.netCarriedSlots == -1)
  assert(R.Restock:Execute(preview)); model:frames(12)
  local totals = R.InventoryPlan:Totals(R.InventoryPlan:Capture(R.API.InvBagList, false))
  assert(totals[2000] == 20 and env.__bags[-1][1].count == 37 and not R.Restock.operation and not R.Mover:Busy())
  assert(historyHas(R, "Transfer", "Observed", "Restock") and env.__bags[0][1].count == 15 and env.__bags[0][2].count == 5)
 end
end)

test("restock consent rejects modified superseded configuration session and source snapshots", function()
 for _, mode in ipairs({ "modified", "latest", "target", "session", "source", "count", "locked", "destination" }) do
  local env, R, model = restockFixture()
  local preview = R.Restock:Preview()
  if mode == "modified" then preview.moves[1].count = 99
  elseif mode == "latest" then R.Restock:Preview()
  elseif mode == "target" then R.Restock:SetTarget(2000, 30)
  elseif mode == "session" then env.__ev("BANKFRAME_CLOSED"); env.__ev("BANKFRAME_OPENED")
  elseif mode == "source" then env.__addItem(-1, 1, 9999, 50)
  elseif mode == "count" then env.__bags[-1][1].count = 49
  elseif mode == "locked" then env.__bags[-1][1].locked = true
  else env.__bags[0][1].count = 8 end
  assert(not R.Restock:Execute(preview), mode); model:frames(3)
  assert(model.calls.pickup == 0 and model.calls.split == 0)
 end
end)

test("restock shrinks current deficit but never expands original consent after outside changes", function()
 local env, R, model = restockFixture()
 local preview = R.Restock:Preview(); local added = false
 R:Listen("ACTION_HISTORY_CHANGED", function()
  local e = R.db.actionHistory[1]
  if not added and e and e.action == "Transfer" and e.status == "Observed" then added = true; env.__addItem(0, 3, 2000, 2, { stack = 15 }) end
 end)
 assert(R.Restock:Execute(preview)); model:frames(15)
 local totals = R.InventoryPlan:Totals(R.InventoryPlan:Capture(R.API.InvBagList, false))
 assert(added and totals[2000] == 20 and env.__bags[-1][1].count == 39, "only eleven were still needed")
 local e2, R2, m2 = restockFixture(); local p2 = R2.Restock:Preview(); assert(R2.Restock:Execute(p2)); R2.Restock:SetTarget(2000, 30); m2:frames(3)
 assert(m2.calls.split == 0 and not R2.Restock.operation)
end)

test("restock blocks unknown carried stack family bank capacity unsupported splits and met targets", function()
 for _, mode in ipairs({ "carried", "stack", "family", "bank", "split", "met", "closed", "full" }) do
  local env, R, model = restockFixture()
  if mode == "carried" then local get = R.API.GetSlotInfo; R.API.GetSlotInfo = function(bag, slot) if bag == 0 and slot == 2 then error("Unknown Slot") end; return get(bag, slot) end
  elseif mode == "stack" then local info = R.API.GetItemInfo; R.API.GetItemInfo = function(link) local a,b,c,d,e,f,g,_,i,j,k,l,m,n = info(link); return a,b,c,d,e,f,g,nil,i,j,k,l,m,n end
   env.__addItem(0, 1, 2001, 7, { stack = 15 }); env.__addItem(-1, 1, 2001, 50, { stack = 15 }); R.Restock:SetTarget(2000, 0); R.Restock:SetTarget(2001, 20)
  elseif mode == "family" then R.API.GetItemFamily = function() return nil end
  elseif mode == "bank" then env.__bags[-1].size = 0
  elseif mode == "split" then R.API.SplitContainerItem = nil
  elseif mode == "met" then R.Restock:SetTarget(2000, 7)
  elseif mode == "closed" then env.__ev("BANKFRAME_CLOSED")
  else env.__bags[0].size = 1; env.__bags[0][1].count = 15; R.Restock:SetTarget(2000, 30) end
  local p = R.Restock:Preview(); assert(not p.executable, mode)
  assert(not R.Restock:Execute(p) and model.calls.pickup == 0 and model.calls.split == 0)
  if mode == "carried" then assert(not p.rows[1].carriedKnown and p.rows[1].reason:find("Unknown", 1, true)) end
 end
end)

test("restock exact link variants prefer compatible special slots and reserve each destination once", function()
 local env, R, model = restockFixture()
 env.__bags[0].size = 1; env.__bags[1] = { size = 2 }
 env.__addItem(-1, 2, 2000, 6, { stack = 15 }); env.__bags[-1][2].link = env.__bags[-1][2].link .. "variant"
 R.API.GetNumFreeSlots = function(bag) return 2, bag == 1 and 8 or 0 end
 R.API.GetItemFamily = function() return 8 end
 R.Restock:SetTarget(2000, 25)
 local p = R.Restock:Preview(); assert(#p.moves >= 2)
 assert(p.moves[1].to[1] == 0 and p.moves[1].count == 8)
 local occupied = {}; for _, m in ipairs(p.moves) do if not m.destLink then local key = m.to[1] .. ":" .. m.to[2]; assert(not occupied[key]); occupied[key] = true end end
 assert(R.Restock:Execute(p)); model:frames(20)
 assert(R.InventoryPlan:Totals(R.InventoryPlan:Capture(R.API.InvBagList, false))[2000] == 25)
end)

test("restock metadata replacement interruption and rejected acknowledgement release singleton ownership", function()
 for _, mode in ipairs({ "familyBefore", "familyDuring", "combat", "close", "cursor", "cancel", "reject" }) do
  local env, R, model = restockFixture({ rejectPlace = mode == "reject" })
  local preview = R.Restock:Preview()
  if mode == "familyBefore" then R.API.GetNumFreeSlots = function() return 0, 64 end; assert(not R.Restock:Execute(preview))
  else
   assert(R.Restock:Execute(preview)); model:frames(1)
   if mode == "familyDuring" then R.API.GetNumFreeSlots = function() return 0, 64 end
   elseif mode == "combat" then env.__combat = true
   elseif mode == "close" then env.__ev("BANKFRAME_CLOSED"); env.__ev("BANKFRAME_OPENED")
   elseif mode == "cursor" then model.held = { id = 9999, link = "item:9999", count = 1 }
   elseif mode == "cancel" then R.Restock:Cancel() end
  end
  model:frames(25)
  assert(not R.Restock.operation and not R.Mover:Busy() and not historyHas(R, "Transfer", "Observed"), mode)
  if mode == "cursor" then assert(model.held.id == 9999 and model.calls.clear == 0) end
 end
end)

test("restock request listeners cannot replace source or approved deficit before native pickup", function()
 local env, R, model = restockFixture(); local p = R.Restock:Preview()
 R:Listen("ACTION_HISTORY_CHANGED", function()
  local e = R.db.actionHistory[1]
  if e and e.action == "Transfer" and e.status == "Requested" then env.__bags[-1][1].count = 49 end
 end)
 assert(R.Restock:Execute(p)); model:frames(3)
 assert(model.calls.split == 0 and model.calls.pickup == 0 and not R.Restock.operation)
end)

test("restock targets migrate sanitize round-trip explicit empties atomically and stay outside profiles", function()
 local env, R = boot(function(e) e.RummageDB = { version = 6, restockTargets = { [1] = 7, [2] = 0, [3] = -1, [4] = 1.5, [1e100] = 9 } } end)
 assert(R.db.version == 7 and R.db.restockTargets[1] == 7 and R.db.restockTargets[2] == nil and R.db.restockTargets[1e100] == nil)
 assert(not R.Restock:SetTarget(1, 1.5) and not R.Restock:SetTarget(0, 1))
 R.Restock:SetTarget(2589, 35); local out = R:ExportSettings(); R.db.restockTargets = {}; assert(R:ImportSettings(out)); assert(R.db.restockTargets[2589] == 35)
 assert(R:ImportSettings("RUM1;scale=1") and R.db.restockTargets[2589] == 35)
 assert(not R:ImportSettings("RUM1;scale=1.8;restock.2589=1.5") and R.settings.scale == 1 and R.db.restockTargets[2589] == 35)
 assert(R:ImportSettings("RUM1;restockTargets.present=1") and next(R.db.restockTargets) == nil)
 R.Restock:SetTarget(1, 2); R:SaveProfile("Targets"); R.Restock:SetTarget(1, 3); R:ApplyProfile("Targets"); assert(R.db.restockTargets[1] == 3)
end)

test("forecast uses enabled junk plan not a hypothetical query rule and handles full partial blocked sales", function()
 local env, R = boot(); env.__addItem(0, 1, 2010, 10, { name = "Cloth", quality = 1, sell = 1, stack = 20 })
 local no = assert(R.InventoryPlan:Forecast("sale", "cloth")); assert(no.netCarriedSlots == 0 and #no.rows == 0)
 R.db.junk[2010] = true; local full = R.InventoryPlan:Forecast("sale", "cloth"); assert(full.netCarriedSlots == 1)
 R.Junk:SetKeep(2010, 7); local partial = R.InventoryPlan:Forecast("sale", "cloth"); assert(partial.netCarriedSlots == 0 and partial.temporarySlotsNeeded == 1 and partial.blockedMoves == 0)
 env.__bags[0].size = 1; local blocked = R.InventoryPlan:Forecast("sale", "cloth"); assert(blocked.netCarriedSlots == 0 and blocked.blockedMoves == 1)
 assert(env.__bags[0][1].count == 10 and not env.__picked and not env.__split and not env.__used)
end)

test("slot allocator forecasts signed carried effects for disjoint bags and marks overlaps unsupported", function()
 local env, R = boot(); env.__addItem(0, 1, 2020, 5, { stack = 20, sell = 1 }); env.__bags[0].size = 1; env.__bags[1] = { size = 1 }
 local from = R.InventoryPlan:Capture({ 0 }, false); local to = R.InventoryPlan:Capture({ 1 }, false)
 local empty = R.InventoryPlan:Allocate(from, to, { [2020] = 5 }); assert(empty.netCarriedSlots == 0)
 env.__addItem(1, 1, 2020, 3, { stack = 20, sell = 1 }); to = R.InventoryPlan:Capture({ 1 }, false)
 local merge = R.InventoryPlan:Allocate(from, to, { [2020] = 5 }); assert(merge.netCarriedSlots == 1 and #merge.moves == 1)
 local overlap = R.InventoryPlan:Allocate(from, from, { [2020] = 5 }); assert(not overlap.known and #overlap.moves == 0)
 local own = R.InventoryPlan:Destination(from.slots[1], from.slots); assert(own == nil)
 local partial = R.InventoryPlan:Allocate(from, to, { [2020] = 2 }); assert(partial.netCarriedSlots == 0)
end)

test("forecast bank signed slots and unknown quantities are conditional with no inventory mutation", function()
 local env, R, model = restockFixture()
 local bank = assert(R.InventoryPlan:Forecast("fromBank", "restock")); assert(bank.netCarriedSlots < 0)
 local bags = assert(R.InventoryPlan:Forecast("toBank", "restock")); assert(bags.netCarriedSlots == 1)
 assert(model.calls.pickup == 0 and model.calls.split == 0 and env.__bags[-1][1].count == 50)
 env.__ev("BANKFRAME_CLOSED"); assert(not R.InventoryPlan:Forecast("fromBank", "").known)
 local original = R.API.GetSlotInfo; R.API.GetSlotInfo = function(bag, slot) if bag == 0 and slot == 2 then error("Unknown") end; return original(bag, slot) end
 assert(not R.InventoryPlan:Forecast("sale", "").known)
end)

test("vendor private summary listener closing and reopening cannot issue old-batch followups", function()
 local env, R = boot(); env.__bags[0].size = 4
 env.__addItem(0, 1, 2030, 1, { quality = 0, sell = 3 }); env.__addItem(0, 2, 2031, 1, { quality = 0, sell = 4 })
 env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
 local interrupted = false
 R:Listen("VENDOR_SUMMARY_CHANGED", function()
  if not interrupted and R.VendorSession:Summary().observedStacks == 1 then
   interrupted = true; env.__ev("MERCHANT_CLOSED"); env.__ev("MERCHANT_SHOW")
  end
 end)
 R.Junk:SellAll(); env.__tick(5)
 assert(interrupted and #env.__used == 1 and R.VendorSession:Summary().observedStacks == 0 and env.__bags[0][2])
end)

test("Planning shows numeric bank lower bounds and unavailable bank quantities as Unknown", function()
 local env, R = boot(); R.Planning:Show("restock")
 local row = { itemID = 2420, target = 10, carried = 0, carriedKnown = false, remainingDeficit = 10, deficitKnown = false, availableBank = 3, bankKnown = false, availableBankLowerBound = true, plannedWithdraw = 0, reason = "Unknown Container" }
 R.Planning.preview = { rows = { row }, moves = {}, executable = false, forecast = { known = false } }
 R.Planning:Refresh()
 assert(R.Planning.rows[1].text:GetText():find("Carried Unknown", 1, true))
 assert(R.Planning.rows[1].detail:GetText():find("At Least 3 (Unknown Total)", 1, true) and not R.Planning.rows[1].detail:GetText():find("true", 1, true))
 row.availableBank = nil; R.Planning:Refresh()
 assert(R.Planning.rows[1].detail:GetText():find("Bank Unknown", 1, true) and not R.Planning.rows[1].detail:GetText():find("At Least", 1, true))
end)


test("requested vendor notifications revalidate whole sale and split eligibility before native APIs", function()
 for _, partial in ipairs({ false, true }) do
  local env, R = boot(); env.__addItem(0, 1, 2040, 20, { quality = 0, sell = 2, stack = 20 })
  env.MerchantFrame:Show(); env.__ev("MERCHANT_SHOW")
  if partial then R.Junk:SetKeep(2040, 7) end
  local model = inventoryModel(env, R)
  local changed = false
  R:Listen("VENDOR_SUMMARY_CHANGED", function()
   if not changed and R.Junk.saleState then changed = true; R.Junk:SetKeep(2040, 20) end
  end)
  R:Listen("ACTION_HISTORY_CHANGED", function()
   local e = R.db.actionHistory[1]
   if partial and e and e.action == "Split" and e.status == "Requested" then R.Junk:SetKeep(2040, 20) end
  end)
  R.Junk:SellAll(); model:tick(5)
  assert(model.calls.sale == 0 and model.calls.split == 0 and env.__bags[0][1].count == 20)
 end
 local env, R, model = reserveFixture()
 R:Listen("ACTION_HISTORY_CHANGED", function()
  local e = R.db.actionHistory[1]
  if e and e.action == "Split" and e.status == "Requested" and e.reason == "Place Split Stack In Empty Bag Slot" then env.__bags[0][1].count = 30 end
 end)
 R.Junk:SellAll(); model:tick(5)
 assert(model.calls.pickup == 0 and model.calls.sale == 0, "changed source must be rejected before placement")
end)

test("restock before-placement carried growth kills exact deficit validation without over-target withdrawal", function()
 local env, R, model = restockFixture(); local preview = R.Restock:Preview()
 assert(R.Restock:Execute(preview)); model:frames(1)
 env.__addItem(0, 3, 2000, 10, { stack = 15 })
 model:frames(5)
 local totals = R.InventoryPlan:Totals(R.InventoryPlan:Capture(R.API.InvBagList, false))
 assert(totals[2000] == 17 and env.__bags[-1][1].count == 50 and not R.Restock.operation)
end)

test("forecast visible snapshots invalidate on keep rule protection or selection refresh", function()
 local env, R = boot(); env.__addItem(0, 1, 2050, 10, { quality = 0, sell = 1, stack = 20 })
 R.Planning:Show("forecast"); R.Planning:Run(); assert(R.Planning.result)
 R.Junk:SetKeep(2050, 7); assert(not R.Planning.result)
 R.Planning:Run(); assert(R.Planning.result)
 R.settings.protectFavorites = not R.settings.protectFavorites; R:RequestRefresh(); assert(not R.Planning.result)
end)

test("controller navigation: D-pad, A/B/X/Y and shoulders; off without a controller, in search or combat", function()
  local env, R = boot(function(e)
    e.__pad = true
    e.C_GamePad = { IsEnabled = function() return e.__pad end }
  end)
  env.__addItem(0, 1, 210, 1, { name = "A", quality = 1 })
  env.__addItem(0, 2, 211, 1, { name = "B", quality = 1 })
  env.__addItem(0, 3, 212, 1, { name = "C", quality = 1 })
  R.Data:ScanInventory()
  open(env, R)
  local UI, f = R.UI, R.UI.frame
  assert(f.gamepad == true, "controller buttons captured while shown")
  local press = f.scripts.OnGamePadButtonDown
  assert(press, "OnGamePadButtonDown set")
  press(f, "PADDDOWN")
  assert(UI.selected == UI:NavEntries()[1], "D-pad down selects")
  assert(f.propagate == false, "consumed")
  assert(env.GameTooltip:IsShown(), "tooltip follows the selection")
  UI.list:SetHeight(400)  -- the stub doesn't resolve anchors: give the list a height
  press(f, "PADRSHOULDER")
  assert(UI.selected == UI:NavEntries()[3], "shoulder pages (clamped at the end)")
  press(f, "PADLSHOULDER")
  assert(UI.selected == UI:NavEntries()[1], "left shoulder pages back")
  press(f, "PADDDOWN"); press(f, "PADDDOWN")
  press(f, "PAD1")
  assert(env.__used and #env.__used == 1, "A uses the item")
  local favBefore = R.db.favorites[UI.selected.id]
  press(f, "PAD3")
  assert(R.db.favorites[UI.selected.id] ~= favBefore, "X cycles favorite")
  local junkBefore = R.Junk:IsJunk(UI.selected)
  press(f, "PAD4")
  assert(R.Junk:IsJunk(UI.selected) ~= junkBefore, "Y toggles junk")
  -- left/right change category in the list view
  local cat = UI.category
  press(f, "PADDRIGHT"); env.__settle(2)
  assert(UI.category ~= cat, "right goes to the next category")
  press(f, "PADDLEFT"); env.__settle(2)
  assert(UI.category == cat, "left comes back")
  -- unhandled buttons pass through to the game
  press(f, "PADLSTICK")
  assert(f.propagate == true, "unmapped button propagates")
  -- search focus, combat and no controller all yield
  UI.searchBox:SetFocus()
  assert(UI:HandlePadButton("PADDDOWN") == false); UI.searchBox:ClearFocus()
  env.__combat = true; assert(UI:HandlePadButton("PADDDOWN") == false); env.__combat = false
  env.__pad = false; assert(UI:HandlePadButton("PADDDOWN") == false); env.__pad = true
  R.settings.gamepadNav = false; assert(UI:HandlePadButton("PADDDOWN") == false); R.settings.gamepadNav = true
  -- B clears the selection, then closes
  UI:HandlePadButton("PADDDOWN")
  press(f, "PAD2")
  assert(UI.selected == nil and f:IsShown(), "B clears first")
  press(f, "PAD2")
  assert(not f:IsShown() and f.gamepad == false, "B closes and releases the controller")
  -- combat releases capture
  open(env, R)
  env.__ev("PLAYER_REGEN_DISABLED")
  assert(f.gamepad == false, "released in combat")
  assert(not env.__errors, "errors: " .. tostring(env.__errors and env.__errors[1]))
end)

test("controller input goes to the window used last; grid D-pad moves by one", function()
  local env, R = boot(function(e) e.C_GamePad = { IsEnabled = function() return true end } end)
  env.__addItem(0, 1, 220, 1, { name = "A" }); env.__addItem(0, 2, 221, 1, { name = "B" })
  R.Data:ScanInventory()
  open(env, R)
  env.SlashCmdList.RUMMAGE("bank"); env.__settle(4)
  assert(R.gamepadUI == R.BankUI, "last shown window")
  assert(R.UI:HandlePadButton("PADDDOWN") == false, "Bags yields to the Bank window")
  R.UI.frame.scripts.OnMouseDown(R.UI.frame)
  assert(R.gamepadUI == R.UI, "click marks Bags")
  assert(R.UI:HandlePadButton("PADDDOWN") == true, "clicking Bags takes the controller")
  R.settings.viewMode = "grid"; R:RequestRefresh(); env.__settle(4)
  local list = R.UI:NavEntries()
  R.UI:SelectEntry(list[1])
  R.UI:HandlePadButton("PADDRIGHT")
  assert(R.UI.selected == list[2], "grid right moves by one")
end)
