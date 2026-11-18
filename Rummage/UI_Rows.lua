-- Rummage: item rows, grid cells and the secure item buttons behind them.
-- Split out of UI.lua in 1.10.0; shares the UI table through R.UIParts.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API
R.UIParts[#R.UIParts + 1] = function(UI)
local W = R.Widgets

local pairs, ipairs, type, wipe, tostring = pairs, ipairs, type, wipe, tostring
local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local InCombatLockdown = InCombatLockdown
local K = R.UIK
local SCROLL_W, FAV_ICON, COIN_ICON, UPGRADE_ICON = K.SCROLL_W, K.FAV_ICON, K.COIN_ICON, K.UPGRADE_ICON

---------------------------------------------------------------------------
-- Secure item buttons (one per bag/slot, re-anchored to whatever row shows it)
---------------------------------------------------------------------------
local function StripButton(btn)
	for _, r in ipairs({ btn:GetRegions() }) do r:SetAlpha(0) end
	for _, c in ipairs({ btn:GetChildren() }) do c:SetAlpha(0) end
end

local function FallbackButtonScripts(btn)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	local function bs(self) return self:GetParent():GetID(), self:GetID() end
	btn:SetScript("OnClick", function(self, button)
		local bag, slot = bs(self)
		local link = API.GetSlotInfo(bag, slot)
		if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
		if button == "RightButton" then API.UseContainerItem(bag, slot) else API.PickupContainerItem(bag, slot) end
	end)
	btn:SetScript("OnDragStart", function(self)
		local bag, slot = bs(self)
		-- 1.5.0: Shift-drag splits a stack in half onto the cursor (fallback buttons only;
		-- the secure Blizzard template already splits on Shift-click).
		if IsShiftKeyDown and IsShiftKeyDown() and API.SplitContainerItem then
			local _, count = API.GetSlotInfo(bag, slot)
			if count and count > 1 then return API.SplitContainerItem(bag, slot, math.floor(count / 2)) end
		end
		API.PickupContainerItem(bag, slot)
	end)
	btn:SetScript("OnReceiveDrag", function(self) API.PickupContainerItem(bs(self)) end)
	btn:SetScript("OnEnter", function(self)
		local bag, slot = bs(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if bag == API.BANK and BankButtonIDToInvSlotID then
			GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
		else
			GameTooltip:SetBagItem(bag, slot)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:GetItemButton(bag, slot)
	local holder = self.holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, self.list)
		holder:SetID(bag)
		holder:SetSize(1, 1)
		holder:SetPoint("TOPLEFT")
		holder.buttons = {}
		-- modern item-button mixins query their parent container for these
		holder.GetBagID = function(h) return h:GetID() end
		holder.IsCombinedBagContainer = function() return false end
		holder.IsBagOpen = function() return true end
		self.holders[bag] = holder
	end
	local btn = holder.buttons[slot]
	if btn then return btn end
	if InCombatLockdown() then return nil end

	local tmpl = (bag == API.BANK) and "BankItemButtonGenericTemplate" or "ContainerFrameItemButtonTemplate"
	local name = "RummageItem" .. (bag < 0 and ("N" .. -bag) or bag) .. "_" .. slot
	local ok
	ok, btn = pcall(CreateFrame, "ItemButton", name, holder, tmpl)
	if not ok or not btn then ok, btn = pcall(CreateFrame, "Button", name, holder, tmpl) end
	if not ok or not btn then
		btn = CreateFrame("Button", name, holder)
		FallbackButtonScripts(btn)
	end
	btn:SetID(slot)
	if btn.SetBagID then pcall(btn.SetBagID, btn, bag) end
-- Some client templates register only left clicks; item use depends on the right
-- click reaching the template's OnClick handler too.
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	StripButton(btn)
	btn:HookScript("OnEnter", function(self)
		if self.rummageRow then UI:Highlight(self.rummageRow, true) end
		local e = self.rummageEntry
		if e and e.new then
			R.Data:ClearNew(e.id)
			e.new = nil
		end
	end)
	btn:HookScript("OnLeave", function(self)
		if self.rummageRow then UI:Highlight(self.rummageRow, false) end
	end)
	btn:HookScript("OnClick", function(self, button)
		if IsAltKeyDown() and self.rummageEntry then
			if GetCursorInfo() then ClearCursor() end
			if button == "RightButton" then R.Junk:Toggle(self.rummageEntry)
			else UI:CycleFavorite(self.rummageEntry) end
		end
	end)
	if btn:IsProtected() then self.protectedButtons = true end
	btn:Hide()
	holder.buttons[slot] = btn
	return btn
end

-- Item buttons are diffed between renders: a button that stays on the same row is not
-- touched at all; only buttons that moved are re-anchored and only buttons that left the
-- view are hidden. Avoids Hide/Show churn on Blizzard templates (their OnShow/OnHide do work).
UI.keepButtons = {}

function UI:BeginButtons()
	wipe(self.keepButtons)
end

function UI:EndButtons()
	local keep, shown = self.keepButtons, self.shownButtons
	for btn in pairs(shown) do
		if not keep[btn] then
			btn:Hide()
			btn:ClearAllPoints()
			btn.rummageRow, btn.rummageEntry, btn.rummageLevel = nil, nil, nil
		end
	end
	-- swap the two sets instead of copying
	self.shownButtons, self.keepButtons = keep, shown
end

function UI:AttachButton(target, e, level)
	local btn = self:GetItemButton(e.bag, e.slot)
	if not btn then return end
	if btn.rummageRow ~= target or not btn:IsShown() then
		btn:ClearAllPoints()
		btn:SetAllPoints(target)
		btn.rummageRow = target
		btn:Show()
	end
	if btn.rummageLevel ~= level then
		btn:SetFrameLevel(level)
		btn.rummageLevel = level
	end
	btn.rummageEntry = e
	self.keepButtons[btn] = true
end

-- Hides every item button (used when switching to a non-interactive view).
function UI:ReleaseButtons()
	self:BeginButtons()
	self:EndButtons()
end

---------------------------------------------------------------------------
-- Rows (list view)
---------------------------------------------------------------------------
function UI:Highlight(row, on)
	if row and row.hl then row.hl:SetShown(on) end
end

local function RowOnEnter(row)
	UI:Highlight(row, true)
	local e = row.entry
	if e and not row.interactive then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(e.link)
		if e.count > 1 then GameTooltip:AddLine("Count: " .. e.count, 1, 1, 1) end
		UI:AddGuildHint(GameTooltip, e)
		GameTooltip:Show()
	end
end

local function RowOnLeave(row)
	UI:Highlight(row, false)
	GameTooltip:Hide()
end

local function RowOnMouseUp(row, button)
	local d = row.display
	if d and d.header then
		R.settings.collapsed[d.key] = not R.settings.collapsed[d.key] or nil
		UI:Layout()
		return
	end
	local e = row.entry
	if UI.kind == "guild" then return UI:GuildClick(e, button) end
	if e and not row.interactive and button == "LeftButton" and IsModifiedClick and HandleModifiedItemClick then
		HandleModifiedItemClick(e.link)
	end
end

function UI:GetListRow(i)
	local row = self.rows[i]
	if row then return row end
	local rh = self:RowHeight()
	row = CreateFrame("Frame", nil, self.list)
	row:SetHeight(rh)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * rh)
	row:SetPoint("RIGHT", self.list, "RIGHT", -SCROLL_W - 2, 0)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.hl = row:CreateTexture(nil, "BORDER")
	row.hl:SetAllPoints()
	row.hl:Hide()
	row.newBar = row:CreateTexture(nil, "ARTWORK")
	row.newBar:SetPoint("TOPLEFT")
	row.newBar:SetPoint("BOTTOMLEFT")
	row.newBar:SetWidth(2)
	row.headerText = W:Text(row, "normal")
	row.headerText:SetPoint("LEFT", 22, 0)
	row.headerArrow = row:CreateTexture(nil, "ARTWORK")
	row.headerArrow:SetSize(12, 12)
	row.headerArrow:SetPoint("LEFT", 6, 0)
	row.cells = {}
	row:EnableMouse(true)
	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", RowOnLeave)
	row:SetScript("OnMouseUp", RowOnMouseUp)
	if self.kind == "guild" then
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnDragStart", function(r) UI:GuildDrag(r.entry) end)
		row:SetScript("OnReceiveDrag", function() UI:DropCursorItem() end)
	end
	self.rows[i] = row
	return row
end

function UI:CycleFavorite(e, clear)
	local favs = R.db.favorites
	if clear then favs[e.id] = nil
	else
		local cur = favs[e.id]
		if not cur then favs[e.id] = 1
		elseif cur >= 8 then favs[e.id] = nil
		else favs[e.id] = cur + 1 end
	end
	R:RequestRefresh()
end

local function MakeToggleCell(row, kind)
	local b = CreateFrame("Button", nil, row)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetSize(14, 14)
	b.tex:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self)
		UI:Highlight(row, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if kind == "fav" then
			GameTooltip:SetText("Favorite")
			GameTooltip:AddLine("Left-click: cycle marker (8 icons)\nRight-click: clear\nAlt+click item: cycle", 1, 1, 1)
		else
			GameTooltip:SetText("Junk")
			GameTooltip:AddLine("Click: mark / unmark as junk\nAlt+right-click item: toggle", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() UI:Highlight(row, false); GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		local e = row.entry
		if not e then return end
		if kind == "fav" then UI:CycleFavorite(e, button == "RightButton")
		else R.Junk:Toggle(e) end
	end)
	return b
end

local function MakeIconCell(row)
	local c = CreateFrame("Frame", nil, row)
	c.tex = c:CreateTexture(nil, "ARTWORK")
	c.tex:SetPoint("TOPLEFT", 1, -1)
	c.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.border = c:CreateTexture(nil, "BACKGROUND")
	c.border:SetAllPoints()
	c.upgrade = c:CreateTexture(nil, "OVERLAY")
	c.upgrade:SetTexture(UPGRADE_ICON)
	c.upgrade:SetSize(10, 10)
	c.upgrade:SetPoint("TOPLEFT", -2, 2)
	c.quest = c:CreateTexture(nil, "OVERLAY")
	c.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	c.quest:SetSize(12, 12)
	c.quest:SetPoint("RIGHT", 4, 0)
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, c, "CooldownFrameTemplate")
	if ok and cd then
		cd:SetAllPoints(c.tex)
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
		c.cooldown = cd
	end
	return c
end

local function SetCooldown(cd, e, live)
	if not cd then return end
	if not live then cd:Hide(); return end
	local start, duration, enable = API.GetContainerItemCooldown(e.bag, e.slot)
	if CooldownFrame_Set then
		CooldownFrame_Set(cd, start or 0, duration or 0, enable)
	elseif cd.SetCooldown and start and duration and duration > 0 then
		cd:SetCooldown(start, duration)
		cd:Show()
	else
		cd:Hide()
	end
end

function UI:SetupHeaderRow(row, d)
	row.display = d
	row.entry = nil
	row.interactive = false
	for _, cell in pairs(row.cells) do cell:Hide() end
	row.colVersion = nil -- cells were hidden; force re-anchor when this row shows an item again
	local skin = W:Skin()
	local p = skin.panel
	row.bg:SetColorTexture(p[1], p[2], p[3], (p[4] or 0.05) * 2.5)
	row.hl:SetColorTexture(unpack(skin.hover))
	row.newBar:Hide()
	row.headerText:Show()
	row.headerText:SetText(d.label .. "  |cff888888(" .. d.count .. ")|r")
	row.headerArrow:Show()
	row.headerArrow:SetTexture(d.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
end

function UI:SetupItemRow(row, e, index, interactive)
	row.display = e
	row.entry = e
	row.interactive = interactive
	row.headerText:Hide()
	row.headerArrow:Hide()
	local skin = W:Skin()
	local alt = index % 2 == 0
	-- background/highlight colors only change with the theme or row parity
	if row.skinRef ~= skin or row.alt ~= alt then
		row.skinRef, row.alt = skin, alt
		if alt then row.bg:SetColorTexture(unpack(skin.rowAlt)) else row.bg:SetColorTexture(0, 0, 0, 0) end
		row.hl:SetColorTexture(unpack(skin.hover))
		row.newBar:SetColorTexture(0.25, 1, 0.25, 0.9)
	end
	row.newBar:SetShown(e.new and true or false)

	local locked = false
	if interactive then
		local _, _, _, _, l = API.GetSlotInfo(e.bag, e.slot)
		locked = l
	end

	-- Cells are re-anchored only when the column layout changed (colVersion), not every
	-- render. Previously every visible cell got ClearAllPoints/SetPoint on each redraw.
	local relayout = row.colVersion ~= self.colVersion
	if relayout then
		for _, cell in pairs(row.cells) do cell:Hide() end
		row.colVersion = self.colVersion
	end
	local rh = self:RowHeight()
	local layout = self.colLayout
	local Columns = R.Columns
	for li = 1, #layout do
		local L = layout[li]
		local col = L.col
		local key = col.key
		local kind = col.kind
		local cell = row.cells[key]
		if not cell then
			if kind == "fav" or kind == "junk" then cell = MakeToggleCell(row, kind)
			elseif kind == "icon" then cell = MakeIconCell(row)
			else
				cell = W:Text(row, "normal")
			end
			row.cells[key] = cell
			relayout = true
			row.colVersion = nil
		end
		if relayout then
			cell:ClearAllPoints()
			if kind == "icon" then
				local sz = rh - 4
				cell:SetSize(sz, sz)
				cell:SetPoint("LEFT", row, "LEFT", L.x + 1, 0)
			elseif kind == "fav" or kind == "junk" then
				cell:SetSize(L.w, rh)
				cell:SetPoint("LEFT", row, "LEFT", L.x, 0)
				cell:SetFrameLevel(row:GetFrameLevel() + 8)
			else
				cell:SetPoint("LEFT", row, "LEFT", L.x, 0)
				cell:SetWidth(L.w)
				cell:SetJustifyH(col.align)
			end
			cell:Show()
		end
		if kind == "icon" then
			cell.tex:SetTexture(e.icon)
			cell.tex:SetDesaturated(locked and true or false)
			UI:TintUnusable(cell.tex, e)
			cell.quest:SetShown(UI:QuestStarter(e, interactive))
			local r, g, b = R.QualityColor(e.quality)
			if e.quality and e.quality >= 2 then cell.border:SetColorTexture(r, g, b, 0.9) else cell.border:SetColorTexture(0, 0, 0, 0.6) end
			cell.upgrade:SetShown(R.Integrations:UpgradeBadge(e))
			SetCooldown(cell.cooldown, e, interactive)
		elseif kind == "fav" or kind == "junk" then
			if kind == "fav" then
				if e.fav then
					cell.tex:SetTexture(FAV_ICON .. e.fav)
					cell.tex:SetAlpha(1)
				else
					cell.tex:SetTexture(FAV_ICON .. "1")
					cell.tex:SetAlpha(0.12)
				end
				cell.tex:SetDesaturated(not e.fav)
			else
				cell.tex:SetTexture(COIN_ICON)
				cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				cell.tex:SetAlpha(e.junk and 1 or 0.12)
				cell.tex:SetDesaturated(not e.junk)
			end
		else
			local v = Columns:ValueOf(key, e)
			local t
			if col.text then t = col.text(e, v) else t = (v ~= nil) and tostring(v) or "" end
			cell:SetText(t or "")
			local tc = (key == "name" or key == "count") and skin.text or skin.dim
			cell:SetTextColor(tc[1], tc[2], tc[3])
			cell:SetAlpha(locked and 0.5 or 1)
		end
	end
	if row.colVersion == nil then row.colVersion = self.colVersion end
end

---------------------------------------------------------------------------
-- Grid view
---------------------------------------------------------------------------
local function MakeGridCell(parent)
	local c = CreateFrame("Frame", nil, parent)
	c:EnableMouse(true)
	c.border = c:CreateTexture(nil, "BACKGROUND")
	c.border:SetAllPoints()
	c.tex = c:CreateTexture(nil, "ARTWORK")
	c.tex:SetPoint("TOPLEFT", 1, -1)
	c.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.hl = c:CreateTexture(nil, "HIGHLIGHT")
	c.hl:SetAllPoints(c.tex)
	c.hl:SetColorTexture(1, 1, 1, 0.15)
	c.count = W:Text(c, "tiny")
	c.count:SetPoint("BOTTOMRIGHT", -2, 2)
	c.fav = c:CreateTexture(nil, "OVERLAY")
	c.fav:SetSize(12, 12)
	c.fav:SetPoint("TOPRIGHT", -1, -1)
	c.junk = c:CreateTexture(nil, "OVERLAY")
	c.junk:SetTexture(COIN_ICON)
	c.junk:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.junk:SetSize(11, 11)
	c.junk:SetPoint("LEFT", 2, 0)
	c.ilvl = W:Text(c, "tiny")
	c.ilvl:SetPoint("BOTTOMLEFT", 2, 2)
	c.quest = c:CreateTexture(nil, "OVERLAY")
	c.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	c.quest:SetSize(14, 14)
	c.quest:SetPoint("TOP", 0, -1)
	c.upgrade = c:CreateTexture(nil, "OVERLAY")
	c.upgrade:SetTexture(UPGRADE_ICON)
	c.upgrade:SetSize(13, 13)
	c.upgrade:SetPoint("TOPLEFT", 1, -1)
	c.new = c:CreateTexture(nil, "OVERLAY")
	c.new:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	c.new:SetBlendMode("ADD")
	c.new:SetVertexColor(0.3, 1, 0.3)
	c.new:SetPoint("CENTER")
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, c, "CooldownFrameTemplate")
	if ok and cd then
		cd:SetAllPoints(c.tex)
		c.cooldown = cd
	end
	c:SetScript("OnEnter", function(self)
		local e = self.entry
		if e and not self.interactive then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(e.link)
			UI:AddGuildHint(GameTooltip, e)
			GameTooltip:Show()
		end
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if UI.kind == "guild" then
		c:RegisterForDrag("LeftButton")
		c:SetScript("OnMouseUp", function(self, button) UI:GuildClick(self.entry, button) end)
		c:SetScript("OnDragStart", function(self) UI:GuildDrag(self.entry) end)
		c:SetScript("OnReceiveDrag", function() UI:DropCursorItem() end)
	end
	return c
end

function UI:GetGridRow(i)
	local row = self.gridRows[i]
	if row then return row end
	row = CreateFrame("Frame", nil, self.list)
	row.cells = {}
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.headerText = W:Text(row, "normal")
	row.headerText:SetPoint("LEFT", 22, 0)
	row.headerArrow = row:CreateTexture(nil, "ARTWORK")
	row.headerArrow:SetSize(12, 12)
	row.headerArrow:SetPoint("LEFT", 6, 0)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", function(self)
		local d = self.display
		if d and d.header then
			R.settings.collapsed[d.key] = not R.settings.collapsed[d.key] or nil
			UI:Layout()
		end
	end)
	self.gridRows[i] = row
	return row
end

function UI:SetupGridRow(row, d, interactive)
	local size = R.settings.gridSize
	row.display = d
	local skin = W:Skin()
	if d.header then
		for _, c in ipairs(row.cells) do c:Hide() end
		local p = skin.panel
		row.bg:SetColorTexture(p[1], p[2], p[3], (p[4] or 0.05) * 2.5)
		row.bg:Show()
		row.headerText:Show()
		row.headerText:SetText(d.label .. "  |cff888888(" .. d.count .. ")|r")
		row.headerArrow:Show()
		row.headerArrow:SetTexture(d.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		row:EnableMouse(true)
		return
	end
	row:EnableMouse(false)
	row.bg:Hide()
	row.headerText:Hide()
	row.headerArrow:Hide()
	for i, e in ipairs(d.items) do
		local c = row.cells[i]
		if not c then
			c = MakeGridCell(row)
			row.cells[i] = c
		end
		c:ClearAllPoints()
		c:SetSize(size, size)
		c:SetPoint("TOPLEFT", (i - 1) * (size + 2), 0)
		c.entry = e
		c.interactive = interactive
		c.tex:SetTexture(e.icon)
		local locked = false
		if interactive then
			local _, _, _, _, l = API.GetSlotInfo(e.bag, e.slot)
			locked = l
		end
		c.tex:SetDesaturated(locked and true or false)
		UI:TintUnusable(c.tex, e)
		c.quest:SetShown(UI:QuestStarter(e, interactive))
		local il = R.settings.gridItemLevel and e.info and e.info.equippable and e.info.ilvl or 0
		if il > 1 then
			local qr, qg, qb = R.QualityColor(e.quality)
			c.ilvl:SetText(il)
			c.ilvl:SetTextColor(qr, qg, qb)
		else
			c.ilvl:SetText("")
		end
		local r, g, b = R.QualityColor(e.quality)
		if e.quality and e.quality >= 2 then c.border:SetColorTexture(r, g, b, 1) else c.border:SetColorTexture(0.2, 0.2, 0.2, 1) end
		c.count:SetText(e.count > 1 and e.count or "")
		c.fav:SetShown(e.fav ~= nil)
		if e.fav then c.fav:SetTexture(FAV_ICON .. e.fav) end
		c.junk:SetShown(e.junk and true or false)
		c.upgrade:SetShown(R.Integrations:UpgradeBadge(e))
		c.new:SetSize(size * 1.7, size * 1.7)
		c.new:SetShown(e.new and true or false)
		SetCooldown(c.cooldown, e, interactive)
		c:Show()
	end
	for i = #d.items + 1, #row.cells do row.cells[i]:Hide() end
end


-- Lightweight update of lock/cooldown state without resorting (safe in combat).
-- ITEM_LOCK_CHANGED and BAG_UPDATE_COOLDOWN can fire many times per frame (every GCD
-- triggers BAG_UPDATE_COOLDOWN), so requests are coalesced to one pass per frame.
local function DoUpdateLive() UI:UpdateLiveNow() end
function UI:UpdateLive()
	if not self.frame or not self.frame:IsShown() then return end
	R:Defer("live", DoUpdateLive)
end

function UI:UpdateLiveNow()
	if not self.frame or not self.frame:IsShown() then return end
	if not self:Interactive() or self.searchAllActive then return end
	local grid = R.settings.viewMode == "grid"
	local pool = grid and self.gridRows or self.rows
	for _, row in ipairs(pool) do
		if row:IsShown() then
			if grid then
				for _, c in ipairs(row.cells) do
					if c:IsShown() and c.entry then
						local _, _, _, _, l = API.GetSlotInfo(c.entry.bag, c.entry.slot)
						c.tex:SetDesaturated(l and true or false)
						SetCooldown(c.cooldown, c.entry, true)
					end
				end
			elseif row.entry then
				local _, _, _, _, l = API.GetSlotInfo(row.entry.bag, row.entry.slot)
				local icon = row.cells.icon
				if icon and icon:IsShown() then
					icon.tex:SetDesaturated(l and true or false)
					SetCooldown(icon.cooldown, row.entry, true)
				end
			end
		end
	end
end

end
