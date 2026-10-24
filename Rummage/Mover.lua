-- Rummage: sequential item mover (restack, transfer bags<->bank, empty a bag).
-- Each step re-reads live bag state, so it never works from stale data.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local Mover = CreateFrame("Frame")
Mover:Hide()
R.Mover = Mover

local MAX_STEPS = 400
local LOCK_TIMEOUT = 3

local function IsLocked(bag, slot)
	local _, _, _, _, locked = API.GetSlotInfo(bag, slot)
	return locked
end

function Mover:Busy() return self:IsShown() end

function Mover:Start(planner, label, onDone)
	if InCombatLockdown() then
		R:Print("Can't move items in combat.")
		return
	end
	if self:IsShown() then
		R:Print("Already moving items; please wait.")
		return
	end
	self.planner = planner
	self.label = label
	self.onDone = onDone
	self.steps = 0
	self.wait = 0
	self.last = nil
	self.lockTime = 0
	self:Show()
	R:Fire("MOVER_CHANGED", true)
end

function Mover:Stop(msg)
	self:Hide()
	self.planner = nil
	if msg then R:Print(msg) end
	if self.onDone then
		local fn = self.onDone
		self.onDone = nil
		fn()
	end
	R:Fire("MOVER_CHANGED", false)
	R:RequestRefresh()
end

Mover:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait > 0 then return end
	if InCombatLockdown() then return self:Stop("Stopped: entered combat.") end

	if GetCursorInfo() then
		ClearCursor()
		self.wait = 0.1
		return
	end

	local last = self.last
	if last then
		if IsLocked(last.from[1], last.from[2]) or IsLocked(last.to[1], last.to[2]) then
			self.lockTime = self.lockTime + elapsed
			if self.lockTime > LOCK_TIMEOUT then return self:Stop("Stopped: server did not respond.") end
			return
		end
	end
	self.lockTime = 0

	self.steps = self.steps + 1
	if self.steps > MAX_STEPS then return self:Stop() end

	local move, err = self.planner()
	if not move then return self:Stop(err) end

	if move.amount then
		API.SplitContainerItem(move.from[1], move.from[2], move.amount)
	else
		API.PickupContainerItem(move.from[1], move.from[2])
	end
	API.PickupContainerItem(move.to[1], move.to[2])
	if GetCursorInfo() then ClearCursor() end
	self.last = move
	self.wait = 0.05
end)

---------------------------------------------------------------------------
-- Planners
---------------------------------------------------------------------------
local function maxStack(link)
	local inf = R.Items:Info(link)
	return inf and inf.stack or 1
end

-- Merge partial stacks of the same item within the given bags.
function Mover:PlanRestack(bags)
	return function()
		local partial = {}
		for _, bag in ipairs(bags) do
			for slot = 1, API.GetNumSlots(bag) or 0 do
				local link, count = API.GetSlotInfo(bag, slot)
				if link then
					local max = maxStack(link)
					count = count or 1
					if max > 1 and count < max then
						local list = partial[link]
						if not list then list = {}; partial[link] = list end
						list[#list + 1] = { bag, slot, count, max }
					end
				end
			end
		end
		for _, list in pairs(partial) do
			if #list > 1 then
				table.sort(list, function(a, b) return a[3] > b[3] end)
				local dst, src = list[1], list[#list]
				local room = dst[4] - dst[3]
				local amount = math.min(room, src[3])
				return { from = { src[1], src[2] }, to = { dst[1], dst[2] }, amount = (amount < src[3]) and amount or nil }
			end
		end
		return nil
	end
end

-- Finds a destination for link/id/count among target bags: a partial stack with room, else a free slot.
function Mover:FindTarget(targets, link, id, count)
	local max = maxStack(link)
	if max > 1 then
		for _, bag in ipairs(targets) do
			for slot = 1, API.GetNumSlots(bag) or 0 do
				local l, c, _, _, locked = API.GetSlotInfo(bag, slot)
				if l == link and not locked and (c or 1) + count <= max then return { bag, slot } end
			end
		end
	end
	-- prefer special bags the item fits in, then normal bags
	local normal
	for _, bag in ipairs(targets) do
		local size = API.GetNumSlots(bag) or 0
		if size > 0 and not (API.KEYRING and bag == API.KEYRING) then
			local family = 0
			if bag ~= API.BACKPACK and bag ~= API.BANK and API.GetNumFreeSlots then
				local _, f = API.GetNumFreeSlots(bag)
				family = f or 0
			end
			if API.FitsBag(id, family) then
				for slot = 1, size do
					if not API.GetSlotInfo(bag, slot) then
						if family ~= 0 then return { bag, slot } end
						normal = normal or { bag, slot }
						break
					end
				end
			end
		end
	end
	return normal
end

-- Moves every given source slot into the target bags.
function Mover:PlanTransfer(sources, targets)
	local i = 0
	return function()
		while true do
			i = i + 1
			local src = sources[i]
			if not src then return nil end
			local link, count, _, _, _, id = API.GetSlotInfo(src[1], src[2])
			if link then
				id = id or R.ItemID(link)
				local dst = Mover:FindTarget(targets, link, id, count or 1)
				if not dst then return nil, "Not enough free space." end
				return { from = { src[1], src[2] }, to = dst }
			end
		end
	end
end

local function others(list, except)
	local out = {}
	for _, b in ipairs(list) do
		if b ~= except and not (API.KEYRING and b == API.KEYRING) then out[#out + 1] = b end
	end
	return out
end

function Mover:Restack(view)
	local bags = (view == "bank") and API.BankBagList or API.InvBagList
	if view == "bank" and not R.Data.atBank then return R:Print("Visit a banker first.") end
	self:Start(self:PlanRestack(others(bags)), "restack", function() R:Print("Stacks combined.") end)
end

-- Empties one bag: at the bank, into the other side; otherwise into the other bags of the same side.
function Mover:EmptyBag(bag)
	local sources = {}
	for slot = 1, API.GetNumSlots(bag) or 0 do sources[#sources + 1] = { bag, slot } end
	local targets
	local isBank = API.IsBankBag(bag)
	if R.Data.atBank then
		targets = isBank and others(API.InvBagList) or others(API.BankBagList)
	else
		if isBank then return R:Print("Visit a banker first.") end
		targets = others(API.InvBagList, bag)
	end
	self:Start(self:PlanTransfer(sources, targets), "empty")
end

-- Moves the given entries (all their slots) to the other side (bags <-> bank).
function Mover:TransferEntries(entries, toBank)
	if not R.Data.atBank then return R:Print("Visit a banker first.") end
	local sources = {}
	-- Copy the {bag, slot} values: entry tables are pooled and recycled on the next
	-- refresh, which happens while this transfer is still running.
	for _, e in ipairs(entries) do
		for _, s in ipairs(e.slots) do sources[#sources + 1] = { s[1], s[2] } end
	end
	local targets = toBank and others(API.BankBagList) or others(API.InvBagList)
	self:Start(self:PlanTransfer(sources, targets), "transfer")
end
