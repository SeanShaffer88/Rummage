-- Rummage: guild bank scanning, per-guild cache, deposit and withdraw (Guild Bank window).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, type, wipe, pcall, tonumber, time = pairs, type, wipe, pcall, tonumber, time

local GB = {}
R.GuildBank = GB

GB.atBank = false     -- the guild vault is open right now
GB.key = nil          -- "Guild-Realm" of the open vault
GB.loaded = {}        -- [tab] = true once the server answered that tab's query this visit
GB.queue = {}         -- tabs still to query (one at a time; each answer queries the next)
GB.pending = nil      -- tab queried and waiting for GUILDBANKBAGSLOTS_CHANGED
GB.limits = {}        -- [tab] = { viewable, deposit, remaining } (live only; -1/nil = unlimited)

-- Every guild bank API is optional: missing ones make the guild window view-only.
local function Call(name, ...)
	local f = _G[name]
	if type(f) ~= "function" then return nil end
	local ok, a, b, c, d, e, f2, g = pcall(f, ...)
	if ok then return a, b, c, d, e, f2, g end
end
GB.Call = Call

function GB:Available()
	return type(_G.GetGuildBankItemLink) == "function" and type(_G.GetGuildBankItemInfo) == "function"
		and type(_G.GetNumGuildBankTabs) == "function"
end

-- "Guild-Realm", guild name, realm for the player's guild, or nil.
function GB:Key()
	local name, _, _, realm = Call("GetGuildInfo", "player")
	if type(name) ~= "string" or name == "" or R.IsSecret(name) then return nil end
	if type(realm) ~= "string" or realm == "" then realm = GetRealmName() end
	return name .. "-" .. realm, name, realm
end

-- The cached record for `key` (default: the player's guild). Shaped like a character
-- record (name, realm, money, lastSeen, containers[GUILD_BASE + tab]) so the window
-- pipeline (Items:Build, footer, bag bar) works on it unchanged.
function GB:Record(key, create)
	local db = R.db and R.db.guilds
	if not db then return nil end
	local name, realm
	if not key then key, name, realm = self:Key() end
	-- guild info can be unavailable (early login, API missing): fall back to the stored one
	if not key and not create then key = R.Data.me and R.Data.me.guildKey end
	if not key then return nil end
	local g = db[key]
	if not g and create then
		if not name then name = key:match("^(.-)%-[^%-]*$") or key; realm = key:match("%-([^%-]*)$") end
		g = { name = name, realm = realm, faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
			containers = {}, money = 0, numTabs = 0 }
		db[key] = g
	end
	return g
end

function GB:IsLive(g)
	return self.atBank and g ~= nil and g == self:Record(self.key)
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
-- Tab names/icons, permissions and withdrawals left. Cheap (one call per tab).
function GB:ScanTabs()
	local g = self:Record(self.key, true)
	if not g then return end
	local n = tonumber(Call("GetNumGuildBankTabs")) or 0
	n = math.min(n, API.MAX_GUILD_TABS)
	g.numTabs = n
	for tab = 1, API.MAX_GUILD_TABS do
		local bag = API.GUILD_BASE + tab
		if tab > n then
			g.containers[bag] = nil
			self.limits[tab] = nil
		else
			local name, icon, viewable, canDeposit, _, remaining = Call("GetGuildBankTabInfo", tab)
			local rec = g.containers[bag]
			if not rec then rec = { slots = {}, size = 0 }; g.containers[bag] = rec end
			rec.name = (type(name) == "string" and name ~= "") and name or ("Tab " .. tab)
			if icon ~= nil and not R.IsSecret(icon) then rec.icon = icon end
			-- Unknown permissions (older clients without the extra returns) count as allowed.
			if viewable == nil then viewable = true end
			if canDeposit == nil then canDeposit = true end
			self.limits[tab] = { viewable = viewable and true or false, deposit = canDeposit and true or false,
				remaining = tonumber(remaining) }
			if not viewable then
				rec.size = 0
				wipe(rec.slots)
			end
		end
	end
	local money = Call("GetGuildBankMoney")
	if type(money) == "number" then g.money = money end
	g.lastSeen = time()
end

function GB:ScanTab(tab)
	local g = self:Record(self.key)
	local lim = self.limits[tab]
	if not g or not lim or not lim.viewable then return end
	local rec = g.containers[API.GUILD_BASE + tab]
	if not rec then return end
	local slots = rec.slots
	for slot = 1, API.GUILD_SLOTS do
		local link = Call("GetGuildBankItemLink", tab, slot)
		if type(link) == "string" and not R.IsSecret(link) then
			local icon, count, _, _, quality = Call("GetGuildBankItemInfo", tab, slot)
			local s = slots[slot]
			if not s then s = {}; slots[slot] = s end
			if s.l ~= link then s.l = link; s.i = R.ItemID(link) end
			s.c = tonumber(count) or 1
			s.t = icon
			s.q = tonumber(quality)
		else
			slots[slot] = nil
		end
	end
	for slot in pairs(slots) do
		if type(slot) ~= "number" or slot > API.GUILD_SLOTS then slots[slot] = nil end
	end
	rec.size = API.GUILD_SLOTS
	rec.scanned = time()
end

-- Tabs are queried one at a time; the answer (GUILDBANKBAGSLOTS_CHANGED) marks that
-- tab loaded and queries the next. Unloaded tabs are never scanned, so a tab whose
-- data hasn't arrived yet keeps its cached contents instead of being wiped.
function GB:QueryNext()
	self.pending = nil
	while #self.queue > 0 do
		local tab = table.remove(self.queue, 1)
		local lim = self.limits[tab]
		if lim and lim.viewable and not self.loaded[tab] then
			self.pending = tab
			Call("QueryGuildBankTab", tab)
			return tab
		end
	end
end

function GB:QueueTab(tab, front)
	for i = #self.queue, 1, -1 do if self.queue[i] == tab then table.remove(self.queue, i) end end
	if front then table.insert(self.queue, 1, tab) else self.queue[#self.queue + 1] = tab end
	if not self.pending then self:QueryNext() end
end

function GB:OnSlotsChanged()
	if not self.atBank then return end
	local answered = self.pending
	if answered then self.loaded[answered] = true end
	self:ScanTabs()
	for tab in pairs(self.loaded) do self:ScanTab(tab) end
	if answered then self:QueryNext() end
	R:Fire("DATA_CHANGED")
end

function GB:OnOpened()
	if self.atBank then return end
	local key = self:Key()
	if not key then return end
	self.atBank, self.key = true, key
	if R.Data.me then R.Data.me.guildKey = key end
	R.Data.atGuildBank = true
	wipe(self.loaded); wipe(self.queue); wipe(self.limits)
	self.pending = nil
	self:ScanTabs()
	local g = self:Record(key)
	local cur = tonumber(Call("GetCurrentGuildBankTab")) or 1
	if g and g.numTabs > 0 then
		if cur < 1 or cur > g.numTabs then cur = 1 end
		self.queue[1] = cur
		for tab = 1, g.numTabs do
			if tab ~= cur then self.queue[#self.queue + 1] = tab end
		end
	end
	self:QueryNext()
	R:Fire("DATA_CHANGED")
end

function GB:OnClosed()
	if not self.atBank then return false end
	local g = self:Record(self.key)
	if g then g.lastSeen = time() end
	self.atBank = false
	R.Data.atGuildBank = false
	wipe(self.loaded); wipe(self.queue); wipe(self.limits)
	self.pending = nil
	R:Fire("DATA_CHANGED")
	return true
end

function GB:IsLoaded(tab) return self.loaded[tab] and true or false end
function GB:Limits(tab) return self.limits[tab] end

-- Shows `tab` in Blizzard's (hidden) guild bank too: deposits and withdrawals act on it.
function GB:SelectTab(tab)
	if not self.atBank or not tab then return end
	if tonumber(Call("GetCurrentGuildBankTab")) ~= tab then Call("SetCurrentGuildBankTab", tab) end
	if not self.loaded[tab] then self:QueueTab(tab, true) end
end

---------------------------------------------------------------------------
-- Moving items
---------------------------------------------------------------------------
local function SlotEmpty(tab, slot)
	if Call("GetGuildBankItemLink", tab, slot) then return false end
	return Call("GetGuildBankItemInfo", tab, slot) == nil
end

-- Puts the cursor item into the first free slot of `tab` (default: the current tab,
-- else the first tab that accepts deposits). Returns the slot used, or nil.
function GB:Deposit(tab)
	if not self.atBank or not (CursorHasItem and CursorHasItem()) then return nil end
	if not tab then
		local cur = tonumber(Call("GetCurrentGuildBankTab"))
		local lim = cur and self.limits[cur]
		if lim and lim.viewable and lim.deposit then tab = cur end
		if not tab then
			for t = 1, API.MAX_GUILD_TABS do
				local l = self.limits[t]
				if l and l.viewable and l.deposit and self.loaded[t] then tab = t; break end
			end
		end
	end
	local lim = tab and self.limits[tab]
	if not lim or not lim.viewable or not lim.deposit then
		R:Print("You can't deposit items in this guild bank tab.")
		return nil
	end
	if not self.loaded[tab] then
		self:SelectTab(tab)
		R:Print("That guild bank tab is still loading; try again in a moment.")
		return nil
	end
	for slot = 1, API.GUILD_SLOTS do
		if SlotEmpty(tab, slot) then
			self:SelectTab(tab)
			Call("PickupGuildBankItem", tab, slot)
			return slot
		end
	end
	R:Print("That guild bank tab is full.")
	return nil
end

function GB:CanWithdraw(tab)
	if not self.atBank then return false, "The guild bank is closed (cached view only)." end
	local lim = self.limits[tab]
	if not lim or not lim.viewable or not self.loaded[tab] then return false, "That guild bank tab isn't available." end
	if lim.remaining == 0 then return false, "No withdrawals left today from this guild bank tab." end
	return true
end

-- mode "cursor": pick the item up (drop it on Bags or a bag slot); "bags": straight into the bags.
function GB:Withdraw(tab, slot, mode)
	local ok, why = self:CanWithdraw(tab)
	if not ok then R:Print(why); return false end
	if not Call("GetGuildBankItemLink", tab, slot) then return false end
	self:SelectTab(tab)
	if mode == "bags" then
		local free = R.Data:FreeSlots(R.Data.me, API.InvBagList)
		if free <= 0 then R:Print("Your bags are full."); return false end
		if type(_G.AutoStoreGuildBankItem) ~= "function" then
			Call("PickupGuildBankItem", tab, slot)
			return true
		end
		Call("AutoStoreGuildBankItem", tab, slot)
		-- the server updates the count later; don't let a quick second click overdraw it
		local lim = self.limits[tab]
		if lim.remaining and lim.remaining > 0 then lim.remaining = lim.remaining - 1 end
	else
		Call("PickupGuildBankItem", tab, slot)
	end
	return true
end

---------------------------------------------------------------------------
-- Tooltip counts
---------------------------------------------------------------------------
function GB:CountFor(g, itemID)
	local n = 0
	for bag, rec in pairs(g.containers or {}) do
		if API.IsGuildBag(bag) and type(rec.slots) == "table" then
			for _, s in pairs(rec.slots) do
				if s.i == itemID then n = n + (s.c or 1) end
			end
		end
	end
	return n
end

-- { {key=, g=}, ... } sorted by key (own guild first).
function GB:SortedGuilds()
	local list = {}
	local mine = self:Key()
	for key, g in pairs(R.db and R.db.guilds or {}) do list[#list + 1] = { key = key, g = g } end
	table.sort(list, function(a, b)
		if a.key == mine then return true end
		if b.key == mine then return false end
		return a.key < b.key
	end)
	return list
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Remembers this character's guild so its cache shows when browsing the character elsewhere.
function GB:UpdateCharGuild()
	local me = R.Data.me
	if not me then return end
	local before = me.guildKey
	local key = self:Key()
	if key then me.guildKey = key
	elseif _G.IsInGuild and Call("IsInGuild") == false then me.guildKey = nil end
	-- guild info often arrives after login: redraw the Guild Bank window when it does
	if me.guildKey ~= before or key then R:RequestRefresh() end
end

function GB:Init()
	self:UpdateCharGuild()
	R:RegisterEvent("PLAYER_GUILD_UPDATE", function() GB:UpdateCharGuild() end)
	R:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function() GB:OnSlotsChanged() end)
	R:RegisterEvent("GUILDBANK_UPDATE_TABS", function()
		if GB.atBank then GB:ScanTabs(); R:Fire("DATA_CHANGED") end
	end)
	R:RegisterEvent("GUILDBANK_UPDATE_MONEY", function()
		if GB.atBank then GB:ScanTabs(); R:Fire("MONEY_CHANGED") end
	end)
	R:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY", function()
		if GB.atBank then GB:ScanTabs() end
	end)
end
