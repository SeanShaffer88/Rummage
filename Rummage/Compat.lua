-- Rummage: API compatibility layer (C_Container / legacy globals).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

local API = {}
R.API = API

local C = C_Container
local function pick(a, b) return a or b end

API.GetNumSlots = pick(C and C.GetContainerNumSlots, _G.GetContainerNumSlots)
API.GetNumFreeSlots = pick(C and C.GetContainerNumFreeSlots, _G.GetContainerNumFreeSlots)
API.PickupContainerItem = pick(C and C.PickupContainerItem, _G.PickupContainerItem)
API.SplitContainerItem = pick(C and C.SplitContainerItem, _G.SplitContainerItem)
API.UseContainerItem = pick(C and C.UseContainerItem, _G.UseContainerItem)
API.GetContainerItemCooldown = pick(C and C.GetContainerItemCooldown, _G.GetContainerItemCooldown)
API.ContainerIDToInventoryID = pick(C and C.ContainerIDToInventoryID, _G.ContainerIDToInventoryID)
API.SortBags = pick(C and C.SortBags, _G.SortBags)
API.SortBankBags = pick(C and C.SortBankBags, _G.SortBankBags)
API.PickupBagFromSlot = pick(C and C.PickupBagFromSlot, _G.PickupBagFromSlot)
API.PutItemInBag = pick(C and C.PutItemInBag, _G.PutItemInBag)
API.PutItemInBackpack = pick(C and C.PutItemInBackpack, _G.PutItemInBackpack)
API.GetContainerItemQuestInfo = pick(C and C.GetContainerItemQuestInfo, _G.GetContainerItemQuestInfo)
API.GetAddOnMemoryUsage = pick(C_AddOns and C_AddOns.GetAddOnMemoryUsage, _G.GetAddOnMemoryUsage)
API.UpdateAddOnMemoryUsage = pick(C_AddOns and C_AddOns.UpdateAddOnMemoryUsage, _G.UpdateAddOnMemoryUsage)

API.GetItemInfo = pick(C_Item and C_Item.GetItemInfo, _G.GetItemInfo)
API.GetItemInfoInstant = pick(C_Item and C_Item.GetItemInfoInstant, _G.GetItemInfoInstant)
API.IsEquippableItem = pick(C_Item and C_Item.IsEquippableItem, _G.IsEquippableItem)
API.GetDetailedItemLevelInfo = pick(C_Item and C_Item.GetDetailedItemLevelInfo, _G.GetDetailedItemLevelInfo)
API.GetItemFamily = pick(C_Item and C_Item.GetItemFamily, _G.GetItemFamily)
API.IsAddOnLoaded = pick(C_AddOns and C_AddOns.IsAddOnLoaded, _G.IsAddOnLoaded)

-- Returns link, count, icon, quality, locked, itemID, isBound(nil if unknown), noValue
if C and C.GetContainerItemInfo then
	function API.GetSlotInfo(bag, slot)
		local i = C.GetContainerItemInfo(bag, slot)
		if not i then return end
		return i.hyperlink, i.stackCount, i.iconFileID, i.quality, i.isLocked, i.itemID, i.isBound, i.hasNoValue
	end
else
	function API.GetSlotInfo(bag, slot)
		local icon, count, locked, quality, _, _, link, _, noValue, itemID = _G.GetContainerItemInfo(bag, slot)
		return link, count, icon, quality, locked, itemID, nil, noValue
	end
end

---------------------------------------------------------------------------
-- Container IDs
---------------------------------------------------------------------------
API.BACKPACK = _G.BACKPACK_CONTAINER or 0
API.BANK = _G.BANK_CONTAINER or -1
API.KEYRING = _G.KEYRING_CONTAINER          -- -2 on clients that have a keyring
API.REAGENTBANK = _G.REAGENTBANK_CONTAINER  -- nil on clients without one
API.NUM_BAGS = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4
API.NUM_BANKBAGS = _G.NUM_BANKBAGSLOTS or 6
API.FIRST_BANKBAG = API.NUM_BAGS + 1
API.LAST_BANKBAG = API.NUM_BAGS + API.NUM_BANKBAGS

API.InvBagList = {}
for b = API.BACKPACK, API.NUM_BAGS do API.InvBagList[#API.InvBagList + 1] = b end
if API.KEYRING then API.InvBagList[#API.InvBagList + 1] = API.KEYRING end

-- Modern clients use bank *tabs* (Enum.BagIndex.CharacterBankTab_N) instead of bank bags.
local BI = Enum and Enum.BagIndex
API.BankTabs = BI and BI.CharacterBankTab_1 ~= nil or false

API.BankBagList = {}
if API.BankTabs then
	for i = 1, 8 do
		local id = BI["CharacterBankTab_" .. i]
		if id then API.BankBagList[#API.BankBagList + 1] = id end
	end
else
	API.BankBagList[1] = API.BANK
	for b = API.FIRST_BANKBAG, API.LAST_BANKBAG do API.BankBagList[#API.BankBagList + 1] = b end
	if API.REAGENTBANK then API.BankBagList[#API.BankBagList + 1] = API.REAGENTBANK end
end

local bankSet = {}
for i, b in ipairs(API.BankBagList) do bankSet[b] = i end

function API.IsBankBag(bag)
	return bankSet[bag] ~= nil
end

function API.BankIndex(bag) return bankSet[bag] end

-- Bags that are equipped items (have an inventory slot): bags 1..N and legacy bank bags.
function API.IsEquippedBag(bag)
	if bag >= 1 and bag <= API.NUM_BAGS then return true end
	return not API.BankTabs and bag >= API.FIRST_BANKBAG and bag <= API.LAST_BANKBAG
end

function API.IsLegacyBankBag(bag)
	return not API.BankTabs and bag >= API.FIRST_BANKBAG and bag <= API.LAST_BANKBAG
end

-- Inventory slot ID for an equipped bag (bags 1-N and bank bags).
function API.BagInvID(bag)
	if not API.IsEquippedBag(bag) or not API.ContainerIDToInventoryID then return nil end
	local ok, inv = pcall(API.ContainerIDToInventoryID, bag)
	return ok and inv or nil
end

function API.GetBagItem(bag)
	local inv = API.BagInvID(bag)
	if inv then
		return GetInventoryItemLink("player", inv), GetInventoryItemTexture("player", inv), inv
	end
end

function API.BagLabel(bag)
	if bag == API.BACKPACK then return "Backpack" end
	if bag == API.BANK then return "Bank" end
	if API.KEYRING and bag == API.KEYRING then return "Keyring" end
	if API.REAGENTBANK and bag == API.REAGENTBANK then return "Reagent Bank" end
	if API.BankTabs and API.IsBankBag(bag) then return "Bank Tab " .. API.BankIndex(bag) end
	if API.IsLegacyBankBag(bag) then return "Bank Bag " .. (bag - API.NUM_BAGS) end
	return "Bag " .. bag
end

function API.BagShort(bag)
	if bag == API.BACKPACK then return "B0" end
	if bag == API.BANK then return "Bank" end
	if API.KEYRING and bag == API.KEYRING then return "Key" end
	if API.REAGENTBANK and bag == API.REAGENTBANK then return "Rgt" end
	if API.BankTabs and API.IsBankBag(bag) then return "T" .. API.BankIndex(bag) end
	if API.IsLegacyBankBag(bag) then return "BB" .. (bag - API.NUM_BAGS) end
	return "B" .. bag
end

-- Can an item go into a bag of the given family? (special bags: quivers, soul, herb...)
function API.FitsBag(itemID, bagFamily)
	if not bagFamily or bagFamily == 0 then return true end
	local fam = API.GetItemFamily and API.GetItemFamily(itemID) or 0
	if not fam or fam == 0 then return false end
	return bit.band(fam, bagFamily) ~= 0
end

function API.SetResizeBounds(frame, minW, minH, maxW, maxH)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(minW, minH, maxW, maxH)
	else
		if frame.SetMinResize then frame:SetMinResize(minW, minH) end
		if frame.SetMaxResize and maxW then frame:SetMaxResize(maxW, maxH) end
	end
end

API.Backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
