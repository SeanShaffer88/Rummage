-- Rummage: item info cache and list entries.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, wipe, pcall = pairs, ipairs, wipe, pcall

local Items = {}
R.Items = Items

-- Item info is cached per link. The cache is bounded so a very long session
-- (thousands of distinct links seen via alts/bank) can't grow it without limit.
local infoCache, infoCount = {}, 0
local INFO_CACHE_MAX = 5000

-- Items whose data isn't loaded yet: itemID -> true. Only their arrival triggers a refresh.
local pendingIDs, pendingCount = {}, 0
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local BIND_TEXT = { [1] = "BoP", [2] = "BoE", [3] = "BoU", [4] = "Quest" }

function Items:Info(link)
	if not link then return nil end
	local inf = infoCache[link]
	if inf then return inf end
	local name, _, quality, ilvl, reqLevel, itype, subType, maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType =
		API.GetItemInfo(link)
	if not name then
		local id = R.ItemID(link)
		if id and not pendingIDs[id] then
			pendingIDs[id] = true
			pendingCount = pendingCount + 1
			-- Mainline: GetItemInfo also queues a load, but requesting explicitly guarantees
			-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT for this ID.
			if RequestLoad then pcall(RequestLoad, id) end
		end
		return nil
	end
	if API.GetDetailedItemLevelInfo then
		local ok, eff = pcall(API.GetDetailedItemLevelInfo, link)
		if ok and eff and eff > 0 then ilvl = eff end
	end
	if not classID and API.GetItemInfoInstant then
		local _, _, _, _, _, c, sc = API.GetItemInfoInstant(link)
		classID, subclassID = c, sc
	end
	inf = {
		name = name,
		lname = name:lower(),
		quality = quality or 1,
		ilvl = ilvl or 0,
		req = reqLevel or 0,
		type = itype or "",
		sub = subType or "",
		stack = maxStack or 1,
		equipLoc = equipLoc or "",
		icon = icon,
		sell = sellPrice or 0,
		class = classID,
		subclass = subclassID,
		bindType = bindType,
	}
	inf.slotName = (inf.equipLoc ~= "" and _G[inf.equipLoc]) or ""
	inf.equippable = inf.equipLoc ~= "" and inf.equipLoc ~= "INVTYPE_BAG" and inf.equipLoc ~= "INVTYPE_QUIVER"
		and inf.equipLoc ~= "INVTYPE_NON_EQUIP" and inf.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
	if infoCount >= INFO_CACHE_MAX then wipe(infoCache); infoCount = 0 end
	infoCache[link] = inf
	infoCount = infoCount + 1
	return inf
end

-- Item data arrived. Ignore IDs we never asked about (other addons' requests), and
-- coalesce bursts (a fresh login can deliver hundreds) into one refresh.
local refreshTimer = false
local function OnItemData(_, itemID, success)
	itemID = tonumber(itemID)
	if not itemID or not pendingIDs[itemID] then return end
	pendingIDs[itemID] = nil
	pendingCount = pendingCount - 1
	if success == false then return end
	if refreshTimer then return end
	refreshTimer = true
	C_Timer.After(0.25, function()
		refreshTimer = false
		R:RequestRefresh()
	end)
end
R:RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemData)
R:RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemData)

function Items:PendingCount() return pendingCount end
function Items:CacheCount() return infoCount end

---------------------------------------------------------------------------
-- Entry pool. Each refresh used to allocate ~4 tables per item (entry, slot list,
-- slot pairs, value cache). Entries, their slot lists and {bag,slot} pairs are now
-- recycled between refreshes; only the first refresh allocates.
---------------------------------------------------------------------------
local entryPool, pairPool = {}, {}
local live = {}       -- entries handed out by the last Build (returned on next Build)
local out = {}        -- reused result array
local combineMap = {}

local function AcquirePair(bag, slot)
	local p = pairPool[#pairPool]
	if p then pairPool[#pairPool] = nil else p = {} end
	p[1], p[2] = bag, slot
	return p
end

local function ReleaseAll()
	for i = 1, #live do
		local e = live[i]
		local sl = e.slots
		for j = 1, #sl do pairPool[#pairPool + 1] = sl[j]; sl[j] = nil end
		wipe(e.vals)
		e.info, e.fav, e.new, e.acquired, e.junk = nil, nil, nil, nil, nil
		entryPool[#entryPool + 1] = e
		live[i] = nil
	end
end

local function AcquireEntry()
	local e = entryPool[#entryPool]
	if e then entryPool[#entryPool] = nil
	else e = { slots = {}, vals = {} } end
	live[#live + 1] = e
	return e
end

-- Builds entries for a character record and a view ("bags" or "bank").
-- The returned array and its entries are only valid until the next Build call.
function Items:Build(char, view)
	ReleaseAll()
	wipe(out)
	local bags = (view == "bank") and API.BankBagList or API.InvBagList
	local combine = R.settings.combineStacks
	if combine then wipe(combineMap) end
	for _, bag in ipairs(bags) do
		local rec = char.containers and char.containers[bag]
		if rec then
			local slots = rec.slots
			for slot = 1, rec.size or 0 do
				local s = slots[slot]
				if s then
					local e = combine and combineMap[s.l]
					if e then
						e.count = e.count + s.c
						e.slots[#e.slots + 1] = AcquirePair(bag, slot)
					else
						e = AcquireEntry()
						e.link, e.id, e.count, e.bag, e.slot = s.l, s.i, s.c, bag, slot
						e.icon, e.q, e.bound = s.t, s.q, s.b
						e.slots[1] = AcquirePair(bag, slot)
						if combine then combineMap[s.l] = e end
						out[#out + 1] = e
					end
				end
			end
		end
	end
	return out
end

function Items:PoolStats() return #entryPool, #live, #pairPool end

function Items:Prepare(e, char, isMe, isLive)
	local inf = self:Info(e.link)
	e.info = inf
	e.name = inf and inf.name or (e.link:match("%[(.-)%]") or "?")
	e.lname = inf and inf.lname or e.name:lower()
	e.quality = (inf and inf.quality) or e.q or 1
	e.icon = e.icon or (inf and inf.icon) or 134400
	e.fav = R.db.favorites[e.id]
	e.new = isMe and R.Data.newItems[e.id] or nil
	e.acquired = char.acquired and char.acquired[e.id]
	e.junk = R.Junk:IsJunk(e, isLive)
end

function Items:BindText(e)
	if e.bound then return "|cffff9a9aBound|r" end
	local bt = e.info and e.info.bindType
	if bt == 2 then return "|cff7fd17fBoE|r" end
	return BIND_TEXT[bt] or ""
end

function Items:IsKey(e)
	return (API.KEYRING and e.bag == API.KEYRING) or (e.info and e.info.class == 13)
end
