-- Rummage: category sidebar (icon rail), saved searches, subtype chips and header tabs.
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
local CHIPS_H, SIDEBAR_W, SIDEBAR_COMPACT_W = K.CHIPS_H, K.SIDEBAR_W, K.SIDEBAR_COMPACT_W

---------------------------------------------------------------------------
-- Sidebar & chips
---------------------------------------------------------------------------
-- Saved searches (1.5.0): chips above the "+ New category" button. Left-click
-- runs the search, right-click removes it. Returns the height they occupy.
UI.savedButtons = {}
function UI:UpdateSavedSearches(compact)
	for _, b in ipairs(self.savedButtons) do b:Hide() end
	local saved = R.db and R.db.savedSearches or {}
	if #saved == 0 then return 0 end
	for i, q in ipairs(saved) do
		local b = self.savedButtons[i]
		if not b then
			b = W:Button(self.sidebar, "", SIDEBAR_W - 8, 18, function(btn, button)
				if button == "RightButton" then
					table.remove(R.db.savedSearches, btn.index)
					UI:UpdateSidebar()
				else
					UI.searchBox:SetText(btn.query)
				end
			end)
			if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
			self.savedButtons[i] = b
		end
		b.index, b.query = i, q
		-- icon rail: numbered stubs (the search is in the tooltip)
		b:SetWidth((self.sidebar:GetWidth() or SIDEBAR_W) - 8)
		b:SetLabel(compact and ("|cffd9a441*|r" .. i) or ("|cffd9a441*|r " .. q))
		b:ClearAllPoints()
		b:SetPoint("BOTTOM", self.sidebar, "BOTTOM", 0, 26 + (#saved - i) * 20)
		W:SetTooltip(b, "Saved search", "Click to run: " .. q .. "\nRight-click to remove.")
		b:Show()
	end
	return #saved * 20 + 4
end

function UI:SaveCurrentSearch()
	local q = self.search and self.search:match("^%s*(.-)%s*$")
	if not q or q == "" then R:Print("Type a search first."); return false end
	local saved = R.db.savedSearches
	for _, v in ipairs(saved) do if v == q then return false end end
	if #saved >= 8 then R:Print("Saved searches are full (8). Right-click one to remove it."); return false end
	saved[#saved + 1] = q
	self:UpdateSidebar()
	return true
end

local function SidebarRows(cats)
	local rows, groups, bySection = {}, {}, {}
	for _, cat in ipairs(cats) do
		if cat.custom then
			local section = cat.section or "Custom"
			local key = section:lower()
			local group = bySection[key]
			if not group then
				group = { name = section, cats = {} }
				bySection[key] = group
				groups[#groups + 1] = group
			end
			group.cats[#group.cats + 1] = cat
		else
			rows[#rows + 1] = { cat = cat }
		end
	end
	for _, group in ipairs(groups) do
		rows[#rows + 1] = { section = group.name }
		for _, cat in ipairs(group.cats) do rows[#rows + 1] = { cat = cat } end
	end
	return rows
end

function UI:UpdateSidebar()
	if not R.settings.showSidebar then return end
	local compact = R.settings.compactSidebar
	local cats = self.catList or R.Categories:List()
	if R.settings.hideEmptyCategories and self.catCounts then
		local filtered = {}
		for _, c in ipairs(cats) do
			if c.id == "all" or c.id == self.category or (self.catCounts[c.id] or 0) > 0 then filtered[#filtered + 1] = c end
		end
		cats = filtered
	end
	for _, b in pairs(self.catButtons) do b:Hide() end
	self.catHeaderButtons = self.catHeaderButtons or {}
	for _, b in pairs(self.catHeaderButtons) do b:Hide() end
	local width = compact and SIDEBAR_COMPACT_W or SIDEBAR_W
	local bh = compact and 34 or 22
	local savedH = self:UpdateSavedSearches(compact)
	local avail = (self.sidebar:GetHeight() or 300) - 30 - savedH
	local outer = self:RailSide()
	local columns = math.max(1, math.min(3, math.floor(tonumber(R.settings.categoryColumns) or 1)))
	local maxPerColumn = math.max(1, math.floor(avail / bh))
	local maxVisible = maxPerColumn * columns
	local rows = SidebarRows(cats)
	local maxOff = math.max(0, #rows - maxVisible)
	self.catOffset = math.min(self.catOffset or 0, maxOff)
	local skin = W:Skin()
	for i = 1, math.min(maxVisible, #rows - self.catOffset) do
		local row = rows[i + self.catOffset]
		if not row then break end
		local column = math.floor((i - 1) / maxPerColumn)
		local rowIndex = (i - 1) % maxPerColumn
		local x, y = 2 + column * width, -3 - rowIndex * bh
		if row.section then
			local b = self.catHeaderButtons[i]
			if not b then
				b = CreateFrame("Frame", nil, self.sidebar)
				b:EnableMouse(true)
				b.text = W:Text(b, "small")
				b.text:SetPoint("CENTER")
				b.text:SetJustifyH("CENTER")
				W:SetTooltip(b, "Category section", function() return b.section end)
				self.catHeaderButtons[i] = b
			end
			b.section = row.section
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.sidebar, "TOPLEFT", x, y)
			b:SetSize(width - 4, bh - 2)
			b.text:SetText(compact and row.section:sub(1, 1):upper() or row.section)
			b.text:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])
			b:Show()
		else
			local c = row.cat
		local b = self.catButtons[i]
		if not b then
			b = CreateFrame("Button", nil, self.sidebar)
			b:SetHeight(bh - 2)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints()
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.07)
			b.bar = b:CreateTexture(nil, "ARTWORK")
			b.bar:SetPoint("TOPLEFT")
			b.bar:SetPoint("BOTTOMLEFT")
			b.bar:SetWidth(2)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetSize(16, 16)
			b.icon:SetPoint("LEFT", 6, 0)
			b.text = W:Text(b, "small")
			b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
			b.text:SetPoint("RIGHT", -28, 0)
			b.text:SetJustifyH("LEFT")
			b.count = W:Text(b, "small")
			b.count:SetPoint("RIGHT", -6, 0)
			b:SetScript("OnClick", function(self, button)
				if CursorHasItem and CursorHasItem() then return UI:DropOnCategory(self.cat) end
				if button == "RightButton" then
					if self.cat.custom then UI:ShowCategoryMenu(self, self.cat) end
					return
				end
				UI:SetCategory(self.cat.id)
				UI.subfilter = nil
				UI.offset = 0
				R:RequestRefresh()
			end)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.cat.name)
				if (self.n or 0) > 0 then GameTooltip:AddLine(self.n .. (self.n == 1 and " item" or " items"), 1, 1, 1) end
				if self.cat.custom then
					local def = R.db.categories[self.cat.custom]
					local q = def and def.query or ""
					local added = R.Categories:ItemCount(self.cat.custom)
					if q ~= "" or added == 0 then GameTooltip:AddLine("Filter: " .. q, 1, 1, 1, true) end
					if added > 0 then GameTooltip:AddLine(added .. (added == 1 and " added item" or " added items"), 1, 1, 1) end
					GameTooltip:AddLine("Drop an item here to add it.", 0.7, 0.7, 0.7)
					GameTooltip:AddLine("Right-click to edit, move or delete.", 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			b:SetScript("OnReceiveDrag", function(self) UI:DropOnCategory(self.cat) end)
			self.catButtons[i] = b
		end
		b.cat = c
		b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.sidebar, "TOPLEFT", x, y)
		b:SetWidth(width - 4)
		b:SetHeight(bh - 2)
		-- icon rail: a large centred icon, the count as a corner badge, the accent bar on
		-- the rail's outer edge; the name is in the tooltip. Labelled: icon, name, count.
		b.icon:ClearAllPoints(); b.count:ClearAllPoints(); b.bar:ClearAllPoints()
		if compact then
			b.icon:SetSize(24, 24)
			b.icon:SetPoint("CENTER")
			b.count:SetPoint("BOTTOMRIGHT", -1, 1)
		else
			b.icon:SetSize(16, 16)
			b.icon:SetPoint("LEFT", 6, 0)
			b.count:SetPoint("RIGHT", -6, 0)
		end
		local barSide = (compact and outer == "RIGHT") and "RIGHT" or "LEFT"
		b.bar:SetPoint("TOP" .. barSide)
		b.bar:SetPoint("BOTTOM" .. barSide)
		b.icon:SetTexture(c.icon)
		if c.id ~= "fav" then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
		b.text:SetText(c.name)
		b.text:SetShown(not compact)
		local n = self.catCounts and self.catCounts[c.id] or 0
		b.n = n
		b.count:SetText(n > 0 and n or "")
		b.count:Show()
		local active = self.category == c.id
		b.bar:SetColorTexture(skin.accent[1], skin.accent[2], skin.accent[3], 1)
		b.bar:SetShown(active)
		if compact and active then
			b.bg:SetColorTexture(skin.accent[1], skin.accent[2], skin.accent[3], 0.18)
		else
			b.bg:SetColorTexture(1, 1, 1, active and 0.08 or 0)
		end
		local tc = active and skin.accent or (n > 0 and skin.text or skin.dim)
		b.text:SetTextColor(tc[1], tc[2], tc[3])
		b.count:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])
		b.icon:SetDesaturated(n == 0 and not active)
		b:Show()
		end
	end
end

function UI:UpdateChips()
	for _, b in ipairs(self.chipButtons) do b:Hide() end
	local subs = self.subList or {}
	local show = #subs > 0
	if self.chips:IsShown() ~= show then
		self.chips:SetShown(show)
	end
	if not show then return end
	local x = 0
	local maxW = self.chips:GetWidth() or 400
	local function chip(i, label, value, count)
		local b = self.chipButtons[i]
		if not b then
			b = W:Button(self.chips, "", 40, CHIPS_H - 4, function(btn)
				UI.subfilter = btn.value
				UI.offset = 0
				R:RequestRefresh()
			end)
			self.chipButtons[i] = b
		end
		b.value = value
		b:SetLabel(count and (label .. " |cff888888" .. count .. "|r") or label)
		b:FitText(14)
		if x + b:GetWidth() > maxW then return false end
		b:ClearAllPoints()
		b:SetPoint("LEFT", self.chips, "LEFT", x, 0)
		b:SetActive(UI.subfilter == value)
		b:Show()
		x = x + b:GetWidth() + 3
		return true
	end
	chip(1, "All", nil)
	for i, sub in ipairs(subs) do
		if not chip(i + 1, sub, sub, self.subCounts[sub]) then break end
	end
end

function UI:UpdateTabs()
	self.tabBags:SetActive(self.view == "bags")
	if self.kind == "bags" then
		self.tabBank:SetActive(R.BankUI.frame and R.BankUI.frame:IsShown() or false)
		self.tabGuildToggle:SetActive(R.GuildUI.frame and R.GuildUI.frame:IsShown() or false)
	else
		self.tabBank:SetActive(self.view == "bank")
	end
	if self.allBtn then self.allBtn:SetActive(R.settings.searchAllChars) end
	local c = self:Char()
	if self.kind == "guild" then
		self.charBtn:SetLabel("|cff40c040" .. (c.name or "?") .. "|r")
		local tab = self:GuildTab()
		local rec = tab and c.containers[API.GUILD_BASE + tab]
		self.tabGuild:SetLabel(tab and (rec and rec.name or ("Tab " .. tab)) or R.L.allTabs)
		return
	end
	self.charBtn:SetLabel(R.ClassColorText(c.class, c.name or "?"))
end

end
