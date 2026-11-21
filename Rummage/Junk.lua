-- Rummage: junk detection (own rules or Scrap) and one-click selling.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local Junk = {}
R.Junk = Junk

local function ScrapAvailable()
	return R.settings.useScrap and type(_G.Scrap) == "table" and type(_G.Scrap.IsJunk) == "function"
end
Junk.ScrapAvailable = ScrapAvailable

-- Auto-junk rules: user-written search queries (Items & Junk tab). An item
-- matching any rule counts as junk. Favorites are never junk by rule, and a
-- manual mark (db.junk) always wins because IsJunk checks it first.
function Junk:RuleMatch(e)
	local rules = R.db.junkRules
	if not rules or #rules == 0 or not e.lname then return false end
	if e.id and R.db.favorites[e.id] then return false end
	for i = 1, #rules do
		local q = rules[i]
		if q ~= "" and R.Search:Matches(q, e) then return true end
	end
	return false
end

-- isLive=false for cached data (alts / bank away from the banker): Scrap inspects the
-- given bag/slot in *your current* bags, so it must only receive real live locations.
function Junk:IsJunk(e, isLive)
	local override = R.db.junk[e.id]
	if override ~= nil then return override end
	if self:RuleMatch(e) then return true end
	if ScrapAvailable() then
		local bag, slot
		if isLive ~= false then bag, slot = e.bag, e.slot end
		local ok, res = pcall(_G.Scrap.IsJunk, _G.Scrap, e.id, bag, slot)
		if ok then return res and true or false end
	end
	return (e.quality or 1) == 0
end

function Junk:Toggle(e)
	if ScrapAvailable() and type(_G.Scrap.ToggleJunk) == "function" and R.db.junk[e.id] == nil then
		pcall(_G.Scrap.ToggleJunk, _G.Scrap, e.id)
	else
		local isJunk = self:IsJunk(e)
		local wanted = not isJunk
		local default = (e.quality or 1) == 0
		if ScrapAvailable() then
			local ok, res = pcall(_G.Scrap.IsJunk, _G.Scrap, e.id, e.bag, e.slot)
			if ok then default = res and true or false end
		end
		if wanted == default then R.db.junk[e.id] = nil else R.db.junk[e.id] = wanted end
	end
	R:RequestRefresh()
end

local function MerchantOpen()
	return MerchantFrame and MerchantFrame:IsShown()
end
Junk.MerchantOpen = MerchantOpen

-- Inventory-only planner shared by preview and execution; reserves count every variant.
local previews = setmetatable({}, { __mode = "k" })
local function integer(v, maximum)
 return type(v) == "number" and v == v and v >= 0 and v <= maximum and v == math.floor(v)
end
function Junk:SetKeep(id, quantity)
 id, quantity = tonumber(id), tonumber(quantity)
 if not integer(id, 2147483647) or id == 0 or not integer(quantity, 1000000) then return false, "Use A Positive Item ID And A Whole Keep Quantity (0 To Remove)" end
 local n = 0; for _ in pairs(R.db.keepQuantities) do n = n + 1 end
 if quantity > 0 and not R.db.keepQuantities[id] and n >= 500 then return false, "Keep List Is Full (500 Items)" end
 R.db.keepQuantities[id] = quantity > 0 and quantity or nil
 R:RequestRefresh()
 return true
end
function Junk:Inventory()
 local entries, totals = {}, {}
 for _, bag in ipairs(API.InvBagList) do
  if bag ~= API.KEYRING then
   for slot = 1, API.GetNumSlots(bag) or 0 do
    local link, count, icon, quality, locked, id, bound, noValue = API.GetSlotInfo(bag, slot)
    if link then
     id, count = id or R.ItemID(link), count or 1
     local inf = R.Items:Info(link)
     local name = inf and inf.name or link:match("%[(.-)%]") or link
     local e = { id = id, bag = bag, slot = slot, link = link, count = count, icon = icon, bound = bound,
      info = inf, quality = inf and inf.quality or quality, locked = locked, noValue = noValue,
      name = name, lname = name:lower() }
     e.q = e.quality
     R.Items:Prepare(e, R.Data.me, true, true)
     entries[#entries + 1] = e
     if id then totals[id] = (totals[id] or 0) + count end
    end
   end
  end
 end
 return entries, totals
end
function Junk:Eligibility(e, query)
 if not e.info then return "Unknown Item Data" end
 if e.locked then return "Item Is Locked" end
 if e.noValue or e.info.sell <= 0 then return "No Vendor Value" end
 if (R.settings.protectFavorites or query) and R.db.favorites[e.id] then return "Favorite Is Protected" end
 if R.Items:InSet(e) then return "Equipment Set Is Protected" end
 if query then
  if R.db.junk[e.id] == false then return "Manual Keep Override" end
 else
  if not self:IsJunk(e) then return "Not Junk" end
 end
end
function Junk:Plan(query)
 local entries, totals = self:Inventory()
 local budgets = {}
 for id, total in pairs(totals) do budgets[id] = math.max(0, total - (R.db.keepQuantities[id] or 0)) end
 local result = { query = query, rows = {}, matchedStacks = 0, matchedUnits = 0, sellUnits = 0, value = 0, retainedUnits = 0, excludedUnits = 0 }
 local list = {}
 for _, e in ipairs(entries) do
  if not query or R.Search:Matches(query, e) then
   local reason = self:Eligibility(e, query)
   local amount = not reason and math.min(e.count, budgets[e.id] or 0) or 0
   if not reason and amount == 0 then reason = "Keep Quantity Reserved" end
   if amount > 0 then
    budgets[e.id] = budgets[e.id] - amount
    local it = { e.bag, e.slot, e.info.sell * amount, e.quality or 0, e.link, e.count,
     id = e.id, sellCount = amount, unitValue = e.info.sell }
    list[#list + 1] = it
   end
   result.rows[#result.rows + 1] = { id = e.id, link = e.link, count = e.count, sellCount = amount,
    reason = reason or (amount < e.count and "Keep Quantity Reserved; Split Required" or "Eligible"), value = e.info and e.info.sell * amount or nil }
   if amount > 0 then list[#list].previewRow = result.rows[#result.rows] end
   result.matchedStacks, result.matchedUnits = result.matchedStacks + 1, result.matchedUnits + e.count
   result.sellUnits, result.value = result.sellUnits + amount, result.value + (e.info and e.info.sell * amount or 0)
   if reason == "Keep Quantity Reserved" or (not reason and amount < e.count) then
    result.retainedUnits = result.retainedUnits + e.count - amount
   elseif reason then result.excludedUnits = result.excludedUnits + e.count end
  end
 end
 if R.settings.buybackSafe and #list > 12 then
  table.sort(list, function(a, b) return a[3] > b[3] end)
  while #list > 12 do
   local dropped = list[#list]
   local row = dropped.previewRow
   result.sellUnits, result.value = result.sellUnits - row.sellCount, result.value - (row.value or 0)
   row.sellCount, row.value, row.reason = 0, 0, "Buyback-Safe Batch Limit"
   list[#list] = nil
  end
 end
 local value = 0; for _, it in ipairs(list) do value = value + it[3] end
 return list, value, result
end
function Junk:Collect() return self:Plan() end
function Junk:PreviewRule(query)
 if type(query) ~= "string" then return nil, "Enter A Search Query" end
 query = query:match("^%s*(.-)%s*$")
 if #query == 0 or #query > 512 or not query:find("[%w\128-\255]") then return nil, "Enter A Meaningful Query (Maximum 512 Characters)" end
 if query:find("%(%s*%)") or query:find('"%s*"') then return nil, "Empty Groups Or Quoted Terms Are Not Allowed" end
 local depth, quoted = 0, false
 for i = 1, #query do
  local c = query:sub(i, i)
  if c == '"' then quoted = not quoted
  elseif not quoted and c == "(" then depth = depth + 1; if depth > 16 then return nil, "Query Nesting Is Limited To 16" end
  elseif not quoted and c == ")" then depth = depth - 1; if depth < 0 then return nil, "Unmatched Parenthesis" end end
 end
 if depth ~= 0 or quoted then return nil, "Close Every Group And Quoted Term" end
 if not R.Search:ValidateQuery(query) then return nil, "Every Group And Alternative Must Contain A Search Term" end
 local ok, _, _, preview = pcall(self.Plan, self, query)
 if not ok then return nil, "The Search Could Not Be Evaluated" end
 previews[preview] = query
 return preview
end
function Junk:EnableRule(preview)
 if type(preview) ~= "table" or previews[preview] ~= preview.query then return false, "Preview This Exact Query First" end
 if #R.db.junkRules >= 8 then return false, "Eight Rules Are Already Enabled" end
 R.db.junkRules[#R.db.junkRules + 1] = preview.query
 previews[preview] = nil
 R:RequestRefresh()
 return true
end

function Junk:AutoRepair()
	if not R.settings.autoRepair or not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	-- Guild repair only when the guild will actually pay: the daily withdraw limit
	-- (-1 = unlimited) must cover the cost, otherwise fall back to own gold.
	local guildFunds = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
	local guildCovers = guildFunds == nil or guildFunds == -1 or guildFunds >= cost
	if R.settings.autoRepairGuild and CanGuildBankRepair and CanGuildBankRepair() and guildCovers then
		RepairAllItems(true)
		R:Print("Repaired with guild funds for " .. R.FormatMoney(cost) .. ".")
	elseif GetMoney() >= cost then
		RepairAllItems()
		R:Print("Repaired for " .. R.FormatMoney(cost) .. ".")
	end
end

function Junk:TotalValue()
	local _, total = self:Collect()
	return total
end

-- True when the sale should be confirmed first (1.5.0 safeguards): it includes an
-- Uncommon-or-better item, or its total value is above the configured threshold.
function Junk:NeedsConfirm(list, total)
	local st = R.settings
	if st.sellConfirmQuality then
		for i = 1, #list do
			if (list[i][4] or 0) >= 2 then return true end
		end
	end
	local limit = st.sellConfirmValue or 0
	return limit > 0 and total > limit
end

local function LogSale(it)
	local log = R.db.junkLog
	table.insert(log, 1, { t = time(), link = it[5] or "", count = it[6] or 1, value = it[3] or 0 })
	for i = #log, 31, -1 do log[i] = nil end
end

local merchantSession = 0

local function History(status, it, reason)
 return R.ActionHistory:Record("Sale", status, { itemID = it and it.id, link = it and it[5],
  count = it and (it.sellCount or it[6]), value = it and it[3], reason = reason,
  from = it and (it[1] .. ":" .. it[2]), to = "Merchant" })
end
local function CursorMatches(it)
 local kind, id, link = GetCursorInfo()
 return kind == "item" and id == it.id and (not link or link == it[5])
end
local function FreeSplitSlot(it)
 if not API.GetNumFreeSlots or not API.FitsBag then return end
 for _, bag in ipairs(API.InvBagList) do
  if bag ~= API.KEYRING then
   local _, family = API.GetNumFreeSlots(bag)
   if API.FitsBag(it.id, family or 0) then
    for slot = 1, API.GetNumSlots(bag) or 0 do if not API.GetSlotInfo(bag, slot) then return { bag, slot } end end
   end
  end
 end
end
function Junk:SaleAllowance(it)
 local entries, totals = self:Inventory()
 for _, e in ipairs(entries) do
  if e.bag == it[1] and e.slot == it[2] then
   if e.link ~= it[5] or e.count ~= it[6] then return 0, "Source Stack Changed" end
   local reason = self:Eligibility(e)
   if reason then return 0, reason end
   local budget = math.max(0, (totals[e.id] or 0) - (R.db.keepQuantities[e.id] or 0))
   return math.min(it.sellCount or it[6], budget), budget == 0 and "Keep Quantity Reserved" or nil
  end
 end
 return 0, "Source Item Moved"
end
function Junk:SellAll(confirmed)
 if not MerchantOpen() then R:Print("Open a merchant to sell junk."); return end
 if self.ticker or InCombatLockdown() or R.Mover:Busy() then return end
 if GetCursorInfo() then History("Stopped", nil, "Cursor Is Occupied"); R:Print("Put Down The Cursor Item Before Selling."); return end
 if confirmed == true then confirmed = self.pendingSale end
 local list, total
 if type(confirmed) == "table" then
  if confirmed ~= self.pendingSale or confirmed.session ~= merchantSession then return end
  list, total = confirmed.list, confirmed.total; self.pendingSale = nil
 else self.pendingSale = nil; list, total = self:Collect() end
 if #list == 0 then History("Skipped", nil, "No Sellable Excess Junk"); R:Print("No junk to sell."); return end
 if not confirmed and self:NeedsConfirm(list, total) then
  self.pendingSale = { list = list, total = total, session = merchantSession }
  StaticPopup_Show("RUMMAGE_SELL_CONFIRM", #list, R.FormatMoney(total), self.pendingSale); return
 end
 local session, i, sold, soldValue = merchantSession, 0, 0, 0
 local state = { phase = "Next", waits = 0 }
 self.saleState = state
 local function finish(reason)
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
  if state.ownedCursor and state.item and CursorMatches(state.item) then ClearCursor() end
  self.saleState, self.CancelSale = nil, nil
  if reason then History("Stopped", state.item, reason) end
  if sold > 0 then R:Print(format("Sold %d junk item(s) for %s (observed inventory change)%s.", sold, R.FormatMoney(soldValue), reason and "; stopped: " .. reason or "")) end
  if reason and sold == 0 then R:Print("Sale Stopped: " .. reason) end
  R:Fire("MOVER_CHANGED", false)
 end
 self.CancelSale = function() finish("Cancelled By Player") end
 local function observeSale(it)
  local _, totals = self:Inventory()
  local money = GetMoney and GetMoney()
  if API.GetSlotInfo(it[1], it[2]) == nil and (totals[it.id] or 0) == state.beforeTotal - it[6] then
   if type(money) ~= "number" or type(state.beforeMoney) ~= "number" or money ~= state.beforeMoney + it.unitValue * it[6] then return end
   LogSale({ it[1], it[2], it.unitValue * it[6], it[4], it[5], it[6] })
   sold, soldValue = sold + 1, soldValue + it.unitValue * it[6]
   History("Observed", it, "Expected Inventory Decrease And Vendor Money Gain Verified")
   state.phase, state.item, state.waits = "Next", nil, 0
   return true
  end
 end
 local function step()
  if not MerchantOpen() or session ~= merchantSession then return finish("Merchant Session Ended") end
  if InCombatLockdown() then return finish("Entered Combat") end
  if state.phase == "Cursor" then
   local it = state.item
   local link, count, _, _, sourceLocked = API.GetSlotInfo(it[1], it[2])
   if GetCursorInfo() and not CursorMatches(it) then return finish("Cursor Identity Changed") end
   if CursorMatches(it) and not sourceLocked and link == it[5] and count == it[6] - state.amount then
    if API.GetSlotInfo(state.destination[1], state.destination[2]) then return finish("Split Destination Changed") end
    state.ownedCursor = true
    R.ActionHistory:Record("Split", "Requested", { itemID = it.id, link = it[5], count = state.amount, reason = "Place Split Stack In Empty Bag Slot" })
    API.PickupContainerItem(state.destination[1], state.destination[2])
    state.phase, state.waits = "Placement", 0
   else state.waits = state.waits + 1; if state.waits > 12 then return finish("Split Was Not Acknowledged") end end
   return
  elseif state.phase == "Placement" then
   local it = state.item
   local link, count, _, _, locked = API.GetSlotInfo(state.destination[1], state.destination[2])
   local source, remainder, _, _, sourceLocked = API.GetSlotInfo(it[1], it[2])
   if GetCursorInfo() and not CursorMatches(it) then return finish("Cursor Identity Changed") end
   if not GetCursorInfo() and not sourceLocked and source == it[5] and remainder == it[6] - state.amount and link == it[5] and count == state.amount and not locked then
    R.ActionHistory:Record("Split", "Observed", { itemID = it.id, link = it[5], count = state.amount, reason = "Source And Destination Quantities Verified" })
    state.ownedCursor = nil
    state.item = { state.destination[1], state.destination[2], it.unitValue * state.amount, it[4], it[5], state.amount,
     id = it.id, sellCount = state.amount, unitValue = it.unitValue, split = true }
    state.phase, state.waits = "Validate", 0
   else state.waits = state.waits + 1; if state.waits > 12 then return finish("Split Placement Was Not Acknowledged") end end
   return
  elseif state.phase == "Sale" then
   if GetCursorInfo() then return finish("Cursor Is Occupied") end
   if not observeSale(state.item) then state.waits = state.waits + 1; if state.waits > 12 then return finish("Sale Remains Unconfirmed") end; return end
  elseif GetCursorInfo() then return finish("Cursor Is Occupied") end
  for _ = 1, 10 do
   if state.phase == "Next" then
    i = i + 1; state.item = list[i]
    if not state.item then return finish() end
    state.phase = "Validate"
   end
   local it = state.item
   local amount, reason = self:SaleAllowance(it)
   if amount == 0 then History("Skipped", it, reason); state.phase, state.item = "Next", nil
   elseif amount < it[6] then
    local destination = not it.split and API.SplitContainerItem and FreeSplitSlot(it)
    if not destination then
     History("Skipped", it, it.split and "Reserve Changed After Split" or "Partial Stack Needs A Free Bag Slot And Split API")
     state.phase, state.item = "Next", nil
    else
     state.amount, state.destination, state.waits = amount, destination, 0
     R.ActionHistory:Record("Split", "Requested", { itemID = it.id, link = it[5], count = amount, reason = "Split Exact Approved Excess" })
     API.SplitContainerItem(it[1], it[2], amount)
     state.ownedCursor = CursorMatches(it) or nil
     state.phase = "Cursor"; return
    end
   else
    it.sellCount = it[6]
    History("Requested", it, "Vendor Sale Requested; Awaiting Inventory Change")
    local _, totals = self:Inventory()
    state.beforeTotal, state.beforeMoney = totals[it.id] or 0, GetMoney and GetMoney()
    API.UseContainerItem(it[1], it[2])
    state.phase, state.waits = "Sale", 0
    if not observeSale(it) then return end
   end
  end
 end
 self.ticker = C_Timer.NewTicker(0.25, step)
 R:Fire("MOVER_CHANGED", true)
 step()
end

-- Buyback shortcut. Matches the logged item link against the merchant's buyback
-- list instead of trusting a slot number. UNVERIFIED on Forever 1.60.1: needs the
-- classic GetNumBuybackItems / GetBuybackItemLink / BuybackItem trio, guarded here.
function Junk:Buyback(n)
	if not MerchantOpen() then R:Print("Open a merchant to buy items back."); return end
	if not (GetNumBuybackItems and GetBuybackItemLink and BuybackItem) then
		R:Print("Buyback API not available on this client.")
		return
	end
	local log = R.db.junkLog
	if type(n) == "string" and n:lower() == "all" then
		-- Plan first, then buy. BuybackItem is answered by the server later, so the
		-- list does not shrink between calls: each buyback index is claimed once, and
		-- indices are bought highest first so earlier ones cannot shift underneath.
		local claimed, picks = {}, {}
		local numBuyback = GetNumBuybackItems() or 0
		for i = 1, #log do
			for b = 1, numBuyback do
				if not claimed[b] and GetBuybackItemLink(b) == log[i].link then
					claimed[b] = true
					picks[#picks + 1] = { index = b, log = i }
					break
				end
			end
		end
		table.sort(picks, function(a, b) return a.index > b.index end)
		local confirmedHits, requested, budget = {}, 0, GetMoney()
		for _, pick in ipairs(picks) do
			local price = GetBuybackItemInfo and select(3, GetBuybackItemInfo(pick.index))
			if not price or price <= budget then
				local before = GetNumBuybackItems() or 0
				R.ActionHistory:Record("Buyback", "Requested", { link = log[pick.log].link, count = log[pick.log].count, reason = "Merchant Buyback Requested" })
				BuybackItem(pick.index)
				requested = requested + 1
				if price then budget = budget - price end
				if (GetNumBuybackItems() or 0) < before then
					confirmedHits[#confirmedHits + 1] = pick.log
					R.ActionHistory:Record("Buyback", "Observed", { link = log[pick.log].link, count = log[pick.log].count, reason = "Buyback List Decreased" })
				end
			else R.ActionHistory:Record("Buyback", "Skipped", { link = log[pick.log].link, reason = "Insufficient Funds" }) end
		end
		table.sort(confirmedHits, function(a, b) return a > b end)
		for _, i in ipairs(confirmedHits) do table.remove(log, i) end
		R:Print(requested > 0 and ("Requested buyback of " .. requested .. " item(s). Unconfirmed sales remain in the log.") or "No matching affordable items in buyback.")
		return
	end
	n = tonumber(n) or 1
	local want = log[n]
	if not want then R:Print("No such sale in the log (/rum junklog)."); return end
	for i = 1, GetNumBuybackItems() or 0 do
		if GetBuybackItemLink(i) == want.link then
			local price = GetBuybackItemInfo and select(3, GetBuybackItemInfo(i))
			if price and price > GetMoney() then R.ActionHistory:Record("Buyback", "Skipped", { link = want.link, reason = "Insufficient Funds" }); R:Print("Not enough money to buy that item back."); return end
			local before = GetNumBuybackItems() or 0
			R.ActionHistory:Record("Buyback", "Requested", { link = want.link, count = want.count, reason = "Merchant Buyback Requested" })
			BuybackItem(i)
			if (GetNumBuybackItems() or 0) < before then
				R.ActionHistory:Record("Buyback", "Observed", { link = want.link, count = want.count, reason = "Buyback List Decreased" })
				table.remove(log, n)
				R:Print("Bought back " .. want.link .. ".")
			else R:Print("Requested buyback of " .. want.link .. ". Sale remains in the log until confirmed.") end
			return
		end
	end
	R:Print("That item is no longer in the merchant's buyback list.")
end

function Junk:PrintLog()
	local log = R.db.junkLog
	if #log == 0 then R:Print("Junk-sale log is empty."); return end
	for i = 1, math.min(#log, 10) do
		local e = log[i]
		R:Print(format("%d. %s x%d  %s  (%s ago)", i, e.link, e.count or 1, R.FormatMoney(e.value or 0), R.FormatAge(e.t)))
	end
end

R:RegisterEvent("MERCHANT_SHOW", function()
	merchantSession = merchantSession + 1
	Junk.pendingSale = nil
	Junk:AutoRepair()
	if R.settings.autoSellJunk then
		C_Timer.After(0.2, function() Junk:SellAll() end)
	end
	R:Fire("MERCHANT_CHANGED")
end)
R:RegisterEvent("MERCHANT_CLOSED", function() merchantSession = merchantSession + 1; Junk.pendingSale = nil; R:Fire("MERCHANT_CHANGED") end)
