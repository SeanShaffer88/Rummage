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
	-- lower-cased once here so text searches don't lower() per item per refresh
	inf.ltype, inf.lsub, inf.lslot = inf.type:lower(), inf.sub:lower(), inf.slotName:lower()
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
		e.info, e.fav, e.new, e.acquired, e.junk, e.live = nil, nil, nil, nil, nil, nil
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

-- Builds entries for a character (or guild) record and a view ("bags", "bank" or "guild").
-- The returned array and its entries are only valid until the next Build call.
function Items:Build(char, view)
	ReleaseAll()
	wipe(out)
	local bags = (view == "guild" and API.GuildBagList) or ((view == "bank") and API.BankBagList) or API.InvBagList
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
	-- live = bag/slot are real locations in the player's current bags (integrations
	-- that inspect a slot, like Can I Mog It? and Scrap, must not get cached ones)
	e.live = isLive ~= false or nil
	e.junk = R.Junk:IsJunk(e, isLive)
end

function Items:BindText(e)
	if e.bound then return "|cffff9a9aBound|r" end
	local bt = e.info and e.info.bindType
	if bt == 2 then return "|cff7fd17fBoE|r" end
	return BIND_TEXT[bt] or ""
end

---------------------------------------------------------------------------
-- Equipment sets (1.9.0). itemID -> "set a, set b" (lower-case), rebuilt lazily
-- after EQUIPMENT_SETS_CHANGED. Mainline C_EquipmentSet first, then the classic
-- GetEquipmentSetInfo / GetEquipmentSetItemIDs pair; nothing when neither exists.
---------------------------------------------------------------------------
local setByID, setNames, setsDirty = {}, {}, true

local function AddSetItems(name, ids)
	if type(name) ~= "string" or type(ids) ~= "table" then return end
	setNames[#setNames + 1] = name
	local lname = name:lower()
	for _, id in pairs(ids) do
		if type(id) == "number" and id > 0 then
			local cur = setByID[id]
			if not cur then setByID[id] = lname
			elseif not (", " .. cur .. ","):find(", " .. lname .. ",", 1, true) then setByID[id] = cur .. ", " .. lname end
		end
	end
end

function Items:RebuildSets()
	wipe(setByID); wipe(setNames)
	setsDirty = false
	local C = _G.C_EquipmentSet
	if C and C.GetEquipmentSetIDs and C.GetEquipmentSetInfo and C.GetItemIDs then
		local ok, ids = pcall(C.GetEquipmentSetIDs)
		if ok and type(ids) == "table" then
			for _, setID in ipairs(ids) do
				local okN, name = pcall(C.GetEquipmentSetInfo, setID)
				local okI, items = pcall(C.GetItemIDs, setID)
				if okN and okI then AddSetItems(name, items) end
			end
		end
	elseif _G.GetNumEquipmentSets and _G.GetEquipmentSetInfo and _G.GetEquipmentSetItemIDs then
		local okC, n = pcall(_G.GetNumEquipmentSets)
		for i = 1, (okC and tonumber(n)) or 0 do
			local okN, name = pcall(_G.GetEquipmentSetInfo, i)
			if okN and name then
				local okI, items = pcall(_G.GetEquipmentSetItemIDs, name)
				if okI then AddSetItems(name, items) end
			end
		end
	end
end

-- Lower-case, comma-separated names of the sets that use this item, or nil.
function Items:SetNames(e)
	if setsDirty then self:RebuildSets() end
	return e and e.id and setByID[e.id] or nil
end

function Items:InSet(e) return self:SetNames(e) ~= nil end

function Items:SetList()
	if setsDirty then self:RebuildSets() end
	return setNames
end

R:RegisterEvent("EQUIPMENT_SETS_CHANGED", function()
	setsDirty = true
	R:RequestRefresh()
end)

---------------------------------------------------------------------------
-- Usable by this character (1.10.0). Level is checked first; then the item's tooltip
-- is scanned once per link for red text (class, armor/weapon proficiency, profession,
-- level), the same signal the upgrade popup uses. Unknown (data not loaded, tooltip
-- unavailable) counts as usable and is not cached, so it is checked again later.
---------------------------------------------------------------------------
local usableCache, usableCount = {}, 0
local usableTip

local function TipUsable(link)
	if not usableTip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", "RummageUsableScanTooltip", nil, "GameTooltipTemplate")
		if not ok or not tip then return nil end
		usableTip = tip
	end
	usableTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	usableTip:ClearLines()
	if not pcall(usableTip.SetHyperlink, usableTip, link) then return nil end
	local n = usableTip:NumLines() or 0
	if n < 2 then return nil end
	for i = 2, n do
		for _, side in ipairs({ "Left", "Right" }) do
			local fs = _G["RummageUsableScanTooltipText" .. side .. i]
			if fs and fs:IsShown() then
				local txt = fs:GetText()
				if not R.IsSecret(txt) and (txt or "") ~= "" then
					local r, g, b = fs:GetTextColor()
					if not (R.IsSecret(r) or R.IsSecret(g) or R.IsSecret(b)) and r > 0.9 and g < 0.2 and b < 0.2 then
						return false
					end
				end
			end
		end
	end
	return true
end

function Items:Usable(e)
	local inf = e and e.info
	if inf and (inf.req or 0) > (UnitLevel("player") or 0) then return false end
	local link = e and e.link
	if not link then return true end
	local v = usableCache[link]
	if v == nil then
		v = TipUsable(link)
		if v == nil then return true end
		if usableCount >= INFO_CACHE_MAX then wipe(usableCache); usableCount = 0 end
		usableCache[link] = v
		usableCount = usableCount + 1
	end
	return v
end

function Items:ResetUsable()
	wipe(usableCache); usableCount = 0
end

for _, ev in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "CHARACTER_POINTS_CHANGED" }) do
	R:RegisterEvent(ev, function() Items:ResetUsable(); R:RequestRefresh() end)
end

function Items:IsKey(e)
	return (API.KEYRING and e.bag == API.KEYRING) or (e.info and e.info.class == 13)
end
