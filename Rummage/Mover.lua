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
Mover.bankSession = 0
R:RegisterEvent("BANKFRAME_OPENED", function() Mover.bankSession = Mover.bankSession + 1 end)
R:RegisterEvent("BANKFRAME_CLOSED", function() Mover.bankSession = Mover.bankSession + 1 end)

local function BankCheck(bags, sources)
	local needsBank = false
	for _, bag in ipairs(bags) do if API.IsBankBag(bag) then needsBank = true end end
	for _, src in ipairs(sources or {}) do if API.IsBankBag(src[1]) then needsBank = true end end
	local session = Mover.bankSession
	return function() return not needsBank or (R.Data.atBank and session == Mover.bankSession) end
end

local function IsLocked(bag, slot)
	local _, _, _, _, locked = API.GetSlotInfo(bag, slot)
	return locked
end

function Mover:Busy() return self:IsShown() or self.sendTicker ~= nil end

function Mover:Start(planner, label, onDone)
	if InCombatLockdown() then
		R:Print("Can't move items in combat.")
		return
	end
	if self:Busy() then
		R:Print("Already moving items; please wait.")
		return
	end
	if GetCursorInfo() then return R:Print("Put down the cursor item before moving items.") end
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

function Mover:Stop(msg, completed)
	self:Hide()
	self.planner = nil
	if msg then R:Print(msg) end
	if self.onDone then
		local fn = self.onDone
		self.onDone = nil
		if completed then fn() end
	end
	R:Fire("MOVER_CHANGED", false)
	R:RequestRefresh()
end

Mover:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait > 0 then return end
	if InCombatLockdown() then return self:Stop("Stopped: entered combat.") end

	if GetCursorInfo() then return self:Stop("Stopped: cursor is occupied.") end

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
	if self.steps > MAX_STEPS then return self:Stop("Stopped: move limit reached.") end

	local move, err = self.planner()
	if not move then return self:Stop(err, err == nil) end

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
	local bankValid = BankCheck(bags)
	return function()
		if not bankValid() then return nil, "Stopped: bank session ended." end
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
	local snapshot = {}
	for _, src in ipairs(sources) do
		local link, count = API.GetSlotInfo(src[1], src[2])
		snapshot[#snapshot + 1] = { src[1], src[2], src[3] or link, src[4] or count or 1 }
	end
	local bankValid = BankCheck(targets, snapshot)
	local i = 0
	return function()
		if not bankValid() then return nil, "Stopped: bank session ended." end
		while true do
			i = i + 1
			local src = snapshot[i]
			if not src then return nil end
			local link, count, _, _, locked, id = API.GetSlotInfo(src[1], src[2])
			if link and link == src[3] and (count or 1) == src[4] and not locked then
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

---------------------------------------------------------------------------
-- Transfer targets other than the bank (1.9.0): an open Send Mail tab or trade
-- window. Items are placed with PickupContainerItem + the window's own slot
-- button, one per tick, so the server can lock each one. Bound items are skipped.
---------------------------------------------------------------------------
local TARGETS = {
	mail = {
		label = "To Mail",
		open = function() return SendMailFrame and SendMailFrame:IsShown() and MailFrame and MailFrame:IsShown() end,
		max = function() return ATTACHMENTS_MAX_SEND or 12 end,
		used = function(i) return GetSendMailItem and GetSendMailItem(i) ~= nil end,
		place = function(i) if ClickSendMailItemButton then ClickSendMailItemButton(i); return true end end,
	},
	trade = {
		label = "To Trade",
		open = function() return TradeFrame and TradeFrame:IsShown() end,
		-- the last trade slot is "will not be traded"; only the first six change hands
		max = function() return math.min(6, MAX_TRADABLE_ITEMS or 6) end,
		used = function(i) return GetTradePlayerItemLink and GetTradePlayerItemLink(i) ~= nil end,
		place = function(i) if ClickTradeButton then ClickTradeButton(i); return true end end,
	},
}
Mover.targets = TARGETS

-- Footers re-check the target when these windows open/close (and when the mail
-- window switches between Inbox and Send, which fires no event).
local function TargetsChanged() R:Fire("MOVER_CHANGED", Mover:Busy()) end
local function HookShowHide(frame)
	if frame and not frame.rummageTargetHook and frame.HookScript then
		frame.rummageTargetHook = true
		frame:HookScript("OnShow", TargetsChanged)
		frame:HookScript("OnHide", TargetsChanged)
	end
end
for _, ev in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }) do
	R:RegisterEvent(ev, function()
		HookShowHide(_G.SendMailFrame)
		C_Timer.After(0, TargetsChanged)
	end)
end

-- "mail", "trade" or nil: which non-bank transfer target is open right now.
function Mover:OpenTarget()
	if not R.settings.transferTargets then return nil end
	if TARGETS.mail.open() then return "mail" end
	if TARGETS.trade.open() then return "trade" end
end

local function FreeTargetSlot(t)
	for i = 1, t.max() do
		if not t.used(i) then return i end
	end
end

function Mover:SendTo(kind, entries)
	local t = TARGETS[kind]
	if not t or not t.open() then return end
	if InCombatLockdown() then return R:Print("Can't move items in combat.") end
	if self:Busy() then return R:Print("Already moving items; please wait.") end
	if GetCursorInfo() then return R:Print("Put down the cursor item before moving items.") end
	local sources = {}
	for _, e in ipairs(entries) do
		if not e.bound and not e.foreign then
			for _, s in ipairs(e.slots) do sources[#sources + 1] = { s[1], s[2], e.link } end
		end
	end
	if #sources == 0 then return R:Print("Nothing listed can be sent (bound items are skipped).") end
	local i, placed, full = 0, 0, false
	local function finish()
		if self.sendTicker then self.sendTicker:Cancel(); self.sendTicker = nil end
		local msg = format("Added %d item(s) to the %s.", placed, kind == "mail" and "mail" or "trade")
		if full then msg = msg .. " It is full; the rest stayed in your bags." end
		R:Print(msg)
		R:Fire("MOVER_CHANGED", false)
	end
	local function step()
		if not t.open() or InCombatLockdown() or GetCursorInfo() then return finish() end
		i = i + 1
		local src = sources[i]
		if not src then return finish() end
		local link, _, _, _, locked = API.GetSlotInfo(src[1], src[2])
		if link ~= src[3] or locked then return end -- moved or busy: skip it
		local idx = FreeTargetSlot(t)
		if not idx then full = true; return finish() end
		API.PickupContainerItem(src[1], src[2])
		if t.place(idx) then placed = placed + 1 end
		if GetCursorInfo() then ClearCursor() end
	end
	R:Fire("MOVER_CHANGED", true)
	self.sendTicker = C_Timer.NewTicker(0.15, step)
	step()
end

-- Copy coordinates and expected source identity before an asynchronous confirmation/move.
function Mover:SnapshotEntries(entries)
	local copies = {}
	for _, e in ipairs(entries) do
		local copy = { link = e.link, bound = e.bound, foreign = e.foreign, slots = {} }
		for _, src in ipairs(e.slots) do
			local _, count = API.GetSlotInfo(src[1], src[2])
			copy.slots[#copy.slots + 1] = { src[1], src[2], src[3] or e.link, src[4] or count or 1 }
		end
		copies[#copies + 1] = copy
	end
	return copies
end

-- Moves the given entries (all their slots) to the other side (bags <-> bank).
function Mover:TransferEntries(entries, toBank, session)
	if not R.Data.atBank or (session and session ~= self.bankSession) then return R:Print("Visit a banker first.") end
	local sources = {}
	for _, e in ipairs(self:SnapshotEntries(entries)) do
		for _, src in ipairs(e.slots) do sources[#sources + 1] = src end
	end
	local targets = toBank and others(API.BankBagList) or others(API.InvBagList)
	self:Start(self:PlanTransfer(sources, targets), "transfer")
end
