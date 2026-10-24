-- Rummage: inventory scanning and per-character cache (bags, bank, equipped, mail, money).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, next, type, wipe, time = pairs, ipairs, next, type, wipe, time
local GetTime, GetInventoryItemLink = GetTime, GetInventoryItemLink

local Data = {}
R.Data = Data

Data.atBank = false
Data.newItems = {}
Data.dirty = {}

---------------------------------------------------------------------------
-- Soulbound detection via a hidden tooltip (only when the API doesn't say)
---------------------------------------------------------------------------
local scanTip
local boundStrings

local function IsBoundLine(t)
	if not boundStrings then
		boundStrings = {}
		for _, k in ipairs({ "ITEM_SOULBOUND", "ITEM_BIND_QUEST", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND",
			"ITEM_ACCOUNTBOUND_UNTIL_EQUIP" }) do
			if _G[k] then boundStrings[_G[k]] = true end
		end
	end
	return boundStrings[t]
end

local function BoundFromTooltip(bag, slot)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "RummageScanTooltip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:ClearLines()
	local ok
	if bag == API.BANK and not API.BankTabs and BankButtonIDToInvSlotID then
		ok = pcall(scanTip.SetInventoryItem, scanTip, "player", BankButtonIDToInvSlotID(slot))
	else
		ok = pcall(scanTip.SetBagItem, scanTip, bag, slot)
	end
	if not ok then return false end
	for i = 2, math.min(scanTip:NumLines(), 6) do
		local fs = _G["RummageScanTooltipTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and IsBoundLine(t) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Character record
---------------------------------------------------------------------------
function Data:Init()
	local chars = R.db.chars
	local c = chars[R.charKey] or {}
	chars[R.charKey] = c
	c.name = UnitName("player")
	c.realm = GetRealmName()
	c.class = select(2, UnitClass("player"))
	c.faction = UnitFactionGroup("player")
	c.level = UnitLevel("player")
	c.containers = c.containers or {}
	c.equipped = c.equipped or {}
	c.mail = c.mail or {}
	c.acquired = c.acquired or {}
	c.money = GetMoney()
	c.lastSeen = time()
	self.me = c
	self.baselineUntil = GetTime() + 5

	R:RegisterEvent("BAG_UPDATE", function(_, bag) if bag then Data:MarkDirty(bag) end end)
	R:RegisterEvent("BAG_UPDATE_DELAYED", function() Data:Flush() end)
	R:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() Data:MarkDirty(API.BANK) end)
	R:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function() Data:ScanBank() end)
	R:RegisterEvent("PLAYERREAGENTBANKSLOTS_CHANGED", function()
		if API.REAGENTBANK then Data:MarkDirty(API.REAGENTBANK) end
	end)
	R:RegisterEvent("BAG_CONTAINER_UPDATE", function() Data:ScanInventory() end)
	R:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() Data:ScanEquipped(); Data:MarkDirty("equip") end)
	R:RegisterEvent("PLAYER_MONEY", function() Data.me.money = GetMoney(); R:Fire("MONEY_CHANGED") end)
	R:RegisterEvent("PLAYER_LEVEL_UP", function(_, lvl) Data.me.level = lvl or UnitLevel("player") end)
	R:RegisterEvent("MAIL_INBOX_UPDATE", function() Data:ScanMail() end)
	R:RegisterEvent("ITEM_LOCK_CHANGED", function() R:Fire("LOCKS_CHANGED") end)
	R:RegisterEvent("BAG_UPDATE_COOLDOWN", function() R:Fire("COOLDOWNS_CHANGED") end)
	R:RegisterEvent("PLAYER_LOGOUT", function() Data.me.lastSeen = time() end)
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
function Data:ScanBag(bag)
	local me = self.me
	if not me then return end
	if API.IsBankBag(bag) and not self.atBank then return end

	local t0 = R:ProfileStart()
	local size = API.GetNumSlots(bag) or 0
	-- Reuse the container record and every unchanged slot table: a BAG_UPDATE usually
	-- changes one or two slots, so this keeps scans nearly allocation-free.
	local rec = me.containers[bag]
	if not rec then rec = { slots = {} }; me.containers[bag] = rec end
	local slots = rec.slots
	rec.size = size
	rec.link, rec.icon = API.GetBagItem(bag)

	local free = 0
	for slot = 1, size do
		local link, count, icon, quality, _, itemID, isBound = API.GetSlotInfo(bag, slot)
		if link then
			local s = slots[slot]
			local same = s and s.l == link
			if not s then s = {}; slots[slot] = s end
			s.c = count or 1
			s.t = icon
			s.q = quality
			if not same then
				s.l = link
				s.i = itemID or R.ItemID(link)
				s.b = nil
			end
			if isBound ~= nil then
				s.b = isBound and true or false
			elseif s.b == nil then
				-- tooltip scan only for items new to this slot (expensive; never per refresh)
				s.b = BoundFromTooltip(bag, slot)
			end
		else
			slots[slot] = nil
			free = free + 1
		end
	end
	for slot in pairs(slots) do
		if slot > size then slots[slot] = nil end
	end
	rec.free = free
	if bag ~= API.BACKPACK and bag ~= API.BANK and API.GetNumFreeSlots then
		local _, family = API.GetNumFreeSlots(bag)
		rec.family = family
	end
	R:ProfileEnd("Data:ScanBag", t0)
end

function Data:ScanInventory()
	for _, bag in ipairs(API.InvBagList) do self:ScanBag(bag) end
	self:UpdateTotals()
	R:Fire("DATA_CHANGED")
end

function Data:ScanBank()
	if not self.atBank then return end
	for _, bag in ipairs(API.BankBagList) do self:ScanBag(bag) end
	if not API.BankTabs and GetNumBankSlots then
		self.me.bankBags = GetNumBankSlots()
	end
	self:UpdateTotals()
	R:Fire("DATA_CHANGED")
end

function Data:ScanEquipped()
	local eq = {}
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if link then eq[slot] = { l = link, c = 1, i = R.ItemID(link) } end
	end
	self.me.equipped = eq
end

function Data:ScanMail()
	if not GetInboxNumItems then return end
	local mail = {}
	local maxAttach = ATTACHMENTS_MAX_RECEIVE or 16
	for i = 1, GetInboxNumItems() do
		for a = 1, maxAttach do
			local link = GetInboxItemLink(i, a)
			if link then
				local _, _, _, count = GetInboxItem(i, a)
				mail[#mail + 1] = { l = link, c = count or 1, i = R.ItemID(link) }
			end
		end
	end
	self.me.mail = mail
	R:Fire("DATA_CHANGED")
end

function Data:MarkDirty(bag)
	self.dirty[bag] = true
	R:Defer("dataflush", function() Data:Flush() end)
end

function Data:Flush()
	if not next(self.dirty) then return end
	for bag in pairs(self.dirty) do
		if type(bag) == "number" then self:ScanBag(bag) end
	end
	wipe(self.dirty)
	self:UpdateTotals()
	R:Fire("DATA_CHANGED")
end

---------------------------------------------------------------------------
-- New items / acquisition time
---------------------------------------------------------------------------
-- Two tables are swapped between calls instead of allocating a new one per bag update.
local totalsA, totalsB = {}, {}
function Data:CountAll()
	local t = (self.totals == totalsA) and totalsB or totalsA
	wipe(t)
	for _, rec in pairs(self.me.containers) do
		for _, s in pairs(rec.slots) do
			if s.i then t[s.i] = (t[s.i] or 0) + s.c end
		end
	end
	for _, s in pairs(self.me.equipped) do
		if s.i then t[s.i] = (t[s.i] or 0) + 1 end
	end
	return t
end

function Data:UpdateTotals()
	local now = self:CountAll()
	local prev = self.totals
	local flag = prev and GetTime() > (self.baselineUntil or 0)
	if flag then
		local acquired = self.me.acquired
		for id, n in pairs(now) do
			if n > (prev[id] or 0) then
				self.newItems[id] = true
				acquired[id] = time()
				R:Fire("ITEM_ACQUIRED", id) -- listeners must only queue work (see Upgrade.lua)
			end
		end
	end
	for id in pairs(self.me.acquired) do
		if not now[id] then self.me.acquired[id] = nil end
	end
	self.totals = now
end

function Data:ClearNew(itemID)
	if itemID then
		self.newItems[itemID] = nil
	else
		wipe(self.newItems)
	end
end

---------------------------------------------------------------------------
-- Counting across characters (tooltips)
---------------------------------------------------------------------------
local countCache = {}
local sortedChars
R:Listen("DATA_CHANGED", function() wipe(countCache); sortedChars = nil end)

-- returns bags, bank, equipped, mail counts of itemID for character record c
function Data:CountFor(c, itemID)
	local key = (c.name or "?") .. (c.realm or "") .. ":" .. itemID
	local hit = countCache[key]
	if hit then return hit[1], hit[2], hit[3], hit[4] end
	local bags, bank, eq, mail = 0, 0, 0, 0
	for bag, rec in pairs(c.containers or {}) do
		local isBank = API.IsBankBag(bag)
		for _, s in pairs(rec.slots) do
			if s.i == itemID then
				if isBank then bank = bank + s.c else bags = bags + s.c end
			end
		end
	end
	for _, s in pairs(c.equipped or {}) do
		if s.i == itemID then eq = eq + 1 end
	end
	for _, s in ipairs(c.mail or {}) do
		if s.i == itemID then mail = mail + s.c end
	end
	countCache[key] = { bags, bank, eq, mail }
	return bags, bank, eq, mail
end

-- Cached until DATA_CHANGED (character list rarely changes; tooltips call this often).
function Data:SortedChars()
	if sortedChars then return sortedChars end
	local list = {}
	for key, c in pairs(R.db.chars) do
		list[#list + 1] = { key = key, c = c }
	end
	local myRealm = GetRealmName()
	table.sort(list, function(a, b)
		if a.key == R.charKey then return true end
		if b.key == R.charKey then return false end
		local ar, br = a.c.realm == myRealm, b.c.realm == myRealm
		if ar ~= br then return ar end
		return a.key < b.key
	end)
	sortedChars = list
	return list
end

function Data:FreeSlots(c, bags)
	local free, total = 0, 0
	for _, bag in ipairs(bags) do
		local rec = c.containers[bag]
		if rec and not (API.KEYRING and bag == API.KEYRING) then
			total = total + (rec.size or 0)
			local used = 0
			for _ in pairs(rec.slots) do used = used + 1 end
			free = free + (rec.size or 0) - used
		end
	end
	return free, total
end
