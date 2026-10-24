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

-- Collects sellable junk in the player's bags: list of {bag, slot, value}
function Junk:Collect()
	local list, total = {}, 0
	for _, bag in ipairs(API.InvBagList) do
		if not (API.KEYRING and bag == API.KEYRING) then
			for slot = 1, API.GetNumSlots(bag) or 0 do
				local link, count, _, quality, locked, itemID, _, noValue = API.GetSlotInfo(bag, slot)
				if link and not locked then
					local inf = R.Items:Info(link)
					local e = { id = itemID or R.ItemID(link), bag = bag, slot = slot, quality = inf and inf.quality or quality,
						link = link, count = count or 1, info = inf, name = inf and inf.name, lname = inf and inf.lname }
					local protected = R.settings.protectFavorites and R.db.favorites[e.id]
					if inf and inf.sell > 0 and not noValue and not protected and self:IsJunk(e) then
						local v = inf.sell * (count or 1)
						list[#list + 1] = { bag, slot, v }
						total = total + v
					end
				end
			end
		end
	end
	if R.settings.buybackSafe and #list > 12 then
		table.sort(list, function(a, b) return a[3] > b[3] end)
		for i = #list, 13, -1 do total = total - list[i][3]; list[i] = nil end
	end
	return list, total
end

function Junk:AutoRepair()
	if not R.settings.autoRepair or not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	if R.settings.autoRepairGuild and CanGuildBankRepair and CanGuildBankRepair() then
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

function Junk:SellAll()
	if not MerchantOpen() then
		R:Print("Open a merchant to sell junk.")
		return
	end
	if self.ticker then return end
	local list, total = self:Collect()
	if #list == 0 then
		R:Print("No junk to sell.")
		return
	end
	local i = 0
	local sold = 0
	local function step()
		if not MerchantOpen() then
			self.ticker:Cancel(); self.ticker = nil
			return
		end
		for _ = 1, 10 do
			i = i + 1
			local it = list[i]
			if not it then
				self.ticker:Cancel(); self.ticker = nil
				R:Print(format("Sold %d junk item(s) for %s.", sold, R.FormatMoney(total)))
				return
			end
			API.UseContainerItem(it[1], it[2])
			sold = sold + 1
		end
	end
	self.ticker = C_Timer.NewTicker(0.25, step)
	step()
end

R:RegisterEvent("MERCHANT_SHOW", function()
	Junk:AutoRepair()
	if R.settings.autoSellJunk then
		C_Timer.After(0.2, function() Junk:SellAll() end)
	end
	R:Fire("MERCHANT_CHANGED")
end)
R:RegisterEvent("MERCHANT_CLOSED", function() R:Fire("MERCHANT_CHANGED") end)
