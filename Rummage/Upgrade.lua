-- Rummage: upgrade alert. When you loot or receive gear that's an upgrade, a small popup
-- offers one-click equipping. Uses Pawn when installed; otherwise compares item level
-- against what you're wearing (respecting armor type, dual-wield and two-handers).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, wipe, max, min, format = pairs, ipairs, wipe, math.max, math.min, string.format

local U = {}
R.Upgrade = U

-- equipLoc -> candidate inventory slots. Shirts and tabards are cosmetic and ignored.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local ARMOR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10 }
local NO_ARMOR_TYPE = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
	INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local queue = {}       -- { link=, id=, target=, detail= }
local checking = {}    -- itemIDs waiting to be evaluated
local tries = {}       -- itemID -> retry count while item data loads
local frame, ticker, shownAt
local pendingCombatEquip

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
local scanTip
-- Red text in an item's tooltip = something prevents you from using it (class, skill,
-- level, proficiency). Reliable on every client, unlike IsUsableItem for gear.
local function UsableNow(bag, slot)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "RummageUpgradeScanTooltip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:ClearLines()
	if not pcall(scanTip.SetBagItem, scanTip, bag, slot) then return true end
	for i = 2, scanTip:NumLines() do
		for _, side in ipairs({ "Left", "Right" }) do
			local fs = _G["RummageUpgradeScanTooltipText" .. side .. i]
			if fs and fs:IsShown() and (fs:GetText() or "") ~= "" then
				local r, g, b = fs:GetTextColor()
				if r > 0.9 and g < 0.2 and b < 0.2 then return false end
			end
		end
	end
	return true
end

local function EquippedIlvl(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then return nil end
	local inf = R.Items:Info(link)
	return inf and inf.ilvl or 0, inf
end

local function PlayerArmorType()
	local best = 0
	for _, slot in ipairs(ARMOR_SLOTS) do
		local _, inf = EquippedIlvl(slot)
		if inf and inf.class == 4 and inf.subclass and inf.subclass >= 1 and inf.subclass <= 4 then
			best = max(best, inf.subclass)
		end
	end
	return best
end

-- Returns isUpgrade, targetSlot, detailText (nil, "retry" when item data isn't loaded yet).
function U:Evaluate(link, bag, slot)
	local inf = R.Items:Info(link)
	if not inf then return nil, "retry" end
	if not inf.equippable or (inf.class ~= 2 and inf.class ~= 4) then return false end
	local slots = SLOTS[inf.equipLoc]
	if not slots then return false end
	if not UsableNow(bag, slot) then return false end
	if inf.class == 4 and not NO_ARMOR_TYPE[inf.equipLoc] and inf.subclass and inf.subclass >= 1 and inf.subclass <= 4 then
		local armor = PlayerArmorType()
		if armor > 0 and inf.subclass < armor then return false end
	end
	if inf.equipLoc == "INVTYPE_WEAPON" and not (CanDualWield and CanDualWield()) then slots = SLOTS.INVTYPE_WEAPONMAINHAND end

	-- target = the weaker (or empty) of the candidate slots
	local target, targetIlvl
	for _, s in ipairs(slots) do
		local il = EquippedIlvl(s)
		if not il then target, targetIlvl = s, nil; break end
		if not target or il < targetIlvl then target, targetIlvl = s, il end
	end
	-- two-hander vs main hand + off hand, and one-hander replacing a two-hander
	if inf.equipLoc == "INVTYPE_2HWEAPON" then
		local mh, oh = EquippedIlvl(16), EquippedIlvl(17)
		if mh and oh then targetIlvl = (mh + oh) / 2 elseif oh and not mh then targetIlvl = oh end
	elseif target == 17 then
		local _, mhInf = EquippedIlvl(16)
		if mhInf and mhInf.equipLoc == "INVTYPE_2HWEAPON" then return false end -- would unequip the 2H
	end

	-- Pawn decides when present
	if R.Integrations:PawnAvailable() then
		local pct = R.Integrations:PawnUpgrade({ link = link, info = inf })
		if pct == nil then return false end
		return true, target, pct > 0 and format("|cff40ff40+%.0f%%|r upgrade (Pawn)", pct * 100) or "|cff40ff40Upgrade|r (Pawn)"
	end
	if not R.settings.upgradeIlvlFallback then return false end
	if not targetIlvl then
		return true, target, "|cff40ff40Empty slot|r · item level " .. inf.ilvl
	end
	if inf.ilvl > targetIlvl then
		return true, target, format("Item level %d → |cff40ff40%d|r", targetIlvl, inf.ilvl)
	end
	return false
end

-- Finds a live bag slot holding this link (or itemID).
function U:Locate(link, id)
	for _, bag in ipairs(API.InvBagList) do
		if not (API.KEYRING and bag == API.KEYRING) then
			for slot = 1, API.GetNumSlots(bag) or 0 do
				local l, _, _, _, _, itemID = API.GetSlotInfo(bag, slot)
				if l and ((link and l == link) or (not link and (itemID or R.ItemID(l)) == id)) then return bag, slot, l end
			end
		end
	end
end

local function InQueue(link)
	for _, q in ipairs(queue) do if q.link == link then return true end end
	return false
end

function U:Check()
	for id in pairs(checking) do
		checking[id] = nil
		if not R.db.upgradeIgnore[id] then
			local bag, slot, link = self:Locate(nil, id)
			if bag and not InQueue(link) then
				local ok, target, detail = self:Evaluate(link, bag, slot)
				if ok == nil and target == "retry" then
					tries[id] = (tries[id] or 0) + 1
					if tries[id] <= 5 then
						C_Timer.After(1, function() checking[id] = true; U:Check() end)
					end
				elseif ok then
					tries[id] = nil
					queue[#queue + 1] = { link = link, id = id, target = target, detail = detail }
				else
					tries[id] = nil
				end
			end
		end
	end
	if #queue > 0 and not (frame and frame:IsShown()) then self:ShowNext(true) end
end

---------------------------------------------------------------------------
-- Popup
---------------------------------------------------------------------------
local function SavePoint()
	local p, _, rp, x, y = frame:GetPoint()
	R.settings.upgradePoint = { p, rp, x, y }
end

function U:ApplyPoint()
	frame:ClearAllPoints()
	local p = R.settings.upgradePoint
	if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 220) end
end

local function Create()
	local W = R.Widgets
	frame = CreateFrame("Frame", "RummageUpgradePopup", UIParent, API.Backdrop)
	frame:SetSize(290, 62)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint() end)
	frame:Hide()

	local icon = CreateFrame("Button", nil, frame)
	icon:SetSize(40, 40)
	icon:SetPoint("LEFT", 10, 0)
	icon.border = icon:CreateTexture(nil, "BACKGROUND")
	icon.border:SetAllPoints()
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetPoint("TOPLEFT", 2, -2)
	icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
	icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetScript("OnEnter", function(self)
		local q = queue[1]
		if not q then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local bag, slot = U:Locate(q.link)
		if bag then GameTooltip:SetBagItem(bag, slot) else GameTooltip:SetHyperlink(q.link) end
		if IsShiftKeyDown() and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.icon = icon

	frame.title = W:Text(frame, "tiny")
	frame.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
	frame.name = W:Text(frame, "normal")
	frame.name:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)
	frame.name:SetPoint("RIGHT", -74, 0)
	frame.name:SetJustifyH("LEFT")
	frame.detail = W:Text(frame, "small")
	frame.detail:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
	frame.detail:SetPoint("RIGHT", -74, 0)
	frame.detail:SetJustifyH("LEFT")

	frame.equip = W:Button(frame, "Equip", 58, 22, function() U:EquipCurrent() end)
	frame.equip:SetPoint("RIGHT", -10, -6)
	W:SetTooltip(frame.equip, "Equip", "Equips this item in the right slot. Bind-on-equip items still ask for confirmation.")
	frame.close = W:Button(frame, "X", 18, 18, function(_, mouse)
		if mouse == "RightButton" and queue[1] then
			R.db.upgradeIgnore[queue[1].id] = true
			R:Print("Won't suggest " .. queue[1].link .. " again.")
		end
		U:ShowNext()
	end)
	frame.close:SetPoint("TOPRIGHT", -6, -6)
	W:SetTooltip(frame.close, "Dismiss", "Right-click: never suggest this item again.")

	-- countdown bar (updated by a 0.1s ticker only while visible; no per-frame OnUpdate)
	frame.bar = frame:CreateTexture(nil, "OVERLAY")
	frame.bar:SetPoint("BOTTOMLEFT", 3, 3)
	frame.bar:SetHeight(2)
	frame:SetScript("OnHide", function()
		if ticker then ticker:Cancel(); ticker = nil end
	end)
end

local function Tick()
	local dur = R.settings.upgradeDuration
	if dur <= 0 then frame.bar:Hide(); return end
	local left = dur - (GetTime() - shownAt)
	if left <= 0 then return U:ShowNext() end
	-- pause the countdown while the mouse is over the popup
	if frame:IsMouseOver() then shownAt = shownAt + 0.1 end
	frame.bar:Show()
	frame.bar:SetWidth(max(1, (frame:GetWidth() - 6) * min(1, left / dur)))
end

-- Shows the next queued upgrade (removing the current one unless `keep`).
function U:ShowNext(keep)
	if not keep and #queue > 0 then table.remove(queue, 1) end
	-- drop entries that left the bags meanwhile
	while queue[1] and not self:Locate(queue[1].link) do table.remove(queue, 1) end
	local q = queue[1]
	if not q then
		if frame then frame:Hide() end
		return
	end
	if not frame then Create() end
	local W = R.Widgets
	W:Backdrop(frame, "main")
	local skin = W:Skin()
	local inf = R.Items:Info(q.link)
	local r, g, b, hex = R.QualityColor(inf and inf.quality or 1)
	frame.icon.tex:SetTexture(inf and inf.icon or 134400)
	frame.icon.border:SetColorTexture(r, g, b, 1)
	frame.title:SetText(#queue > 1 and format("UPGRADE  ·  1 of %d", #queue) or "UPGRADE")
	frame.title:SetTextColor(skin.accent[1], skin.accent[2], skin.accent[3])
	frame.name:SetText(hex .. (inf and inf.name or q.link) .. "|r")
	frame.detail:SetText(q.detail or "")
	frame.bar:SetColorTexture(skin.accent[1], skin.accent[2], skin.accent[3], 0.8)
	local inCombat = InCombatLockdown()
	frame.equip:SetLabel((q == pendingCombatEquip) and "Queued" or (inCombat and "After" or "Equip"))
	self:ApplyPoint()
	local wasShown = frame:IsShown()
	frame:Show()
	shownAt = GetTime()
	if not ticker then ticker = C_Timer.NewTicker(0.1, Tick) end
	if not wasShown and R.settings.upgradeSound and SOUNDKIT then
		PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.IG_BACKPACK_OPEN)
	end
end

function U:EquipCurrent()
	local q = queue[1]
	if not q then return end
	if InCombatLockdown() then
		-- Gear can't be swapped in combat: remember the click and equip as soon as combat ends.
		pendingCombatEquip = q
		frame.equip:SetLabel("Queued")
		R:Print("Will equip " .. q.link .. " when combat ends.")
		return
	end
	local bag, slot = self:Locate(q.link)
	if not bag then
		R:Print("That item is no longer in your bags.")
		return self:ShowNext()
	end
	ClearCursor()
	API.PickupContainerItem(bag, slot)
	if q.target and EquipCursorItem then
		EquipCursorItem(q.target)
	else
		local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
		ClearCursor()
		if equip then equip(q.link, q.target) end
	end
	if GetCursorInfo() then ClearCursor() end
	if pendingCombatEquip == q then pendingCombatEquip = nil end
	self:ShowNext()
end

function U:Test()
	-- Shows the popup for the first equippable item in your bags (for positioning/preview).
	for _, bag in ipairs(API.InvBagList) do
		for slot = 1, API.GetNumSlots(bag) or 0 do
			local link = API.GetSlotInfo(bag, slot)
			local inf = link and R.Items:Info(link)
			if inf and inf.equippable and SLOTS[inf.equipLoc] then
				table.insert(queue, 1, { link = link, id = R.ItemID(link), target = SLOTS[inf.equipLoc][1], detail = "Preview — drag to move" })
				return self:ShowNext(true)
			end
		end
	end
	R:Print("No equippable item in your bags to preview.")
end

function U:ResetPosition()
	R.settings.upgradePoint = nil
	if frame then self:ApplyPoint() end
end

---------------------------------------------------------------------------
function U:Init()
	R:Listen("ITEM_ACQUIRED", function(_, id)
		if not R.settings.upgradePopup then return end
		checking[id] = true
		R:Defer("upgradecheck", function() U:Check() end)
	end)
	-- hide/advance when the shown item leaves the bags (equipped manually, sold, banked)
	R:Listen("DATA_CHANGED", function()
		if frame and frame:IsShown() and queue[1] and not U:Locate(queue[1].link) then
			R:Defer("upgradeadvance", function() U:ShowNext() end)
		end
	end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pendingCombatEquip and queue[1] == pendingCombatEquip then
			pendingCombatEquip = nil
			U:EquipCurrent()
		elseif frame and frame:IsShown() then
			frame.equip:SetLabel("Equip")
		end
	end)
	R:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if frame and frame:IsShown() and queue[1] ~= pendingCombatEquip then frame.equip:SetLabel("After") end
	end)
end
