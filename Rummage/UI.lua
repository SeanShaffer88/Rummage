-- Rummage: main window — list/grid views, categories, search, columns, footer actions.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, type, wipe, tostring = pairs, ipairs, type, wipe, tostring
local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local InCombatLockdown = InCombatLockdown

local UI = {}
R.UI = UI

-- Scratch tables reused by every Refresh (wiped, never reallocated).
local scratchSearched, scratchInCat, scratchFinal = {}, {}, {}
local scratchSubs, scratchSubList = {}, {}
local catCounts = {}

local W -- Widgets, set in Create

local HEADER_H = 34
local FOOTER_H = 34
local PAD = 6
local COLHEAD_H = 20
local CHIPS_H = 22
local SIDEBAR_W = 156
local SIDEBAR_COMPACT_W = 34
local SCROLL_W = 10
local FAV_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local UPGRADE_ICON = "Interface\\AddOns\\Pawn\\Textures\\UpgradeArrow"
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

UI.view = "bags"
UI.category = "all"
UI.search = ""
UI.offset = 0
UI.rows = {}
UI.gridRows = {}
UI.holders = {}
UI.display = {}
UI.shownButtons = {}
UI.headerButtons = {}
UI.catButtons = {}
UI.chipButtons = {}
UI.bagButtons = {}

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
function UI:Char()
	local c = self.charKey and R.db.chars[self.charKey]
	if not c then
		self.charKey = nil
		c = R.Data.me
	end
	return c
end

function UI:IsMe() return self:Char() == R.Data.me end

function UI:Interactive()
	return self:IsMe() and (self.view == "bags" or R.Data.atBank)
end

function UI:RowHeight() return R.settings.rowHeight end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function UI:Create()
	W = R.Widgets
	W:UpdateFonts()
	local s = R.settings

	local f = CreateFrame("Frame", "RummageFrame", UIParent, API.Backdrop)
	self.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:EnableMouse(true)
	API.SetResizeBounds(f, 460, 320, 2000, 1600)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not R.settings.locked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); UI:SavePosition() end)
	f:Hide()
	f:SetScript("OnShow", function() UI:OnShow() end)
	f:SetScript("OnHide", function() UI:OnHide() end)
	-- OnSizeChanged fires every frame while dragging the grip: coalesce to one layout per frame.
	f:SetScript("OnSizeChanged", function()
		if f:IsShown() then R:Defer("layout", function() UI:Layout() end) end
	end)
	table.insert(UISpecialFrames, "RummageFrame")

	self.category = (s.rememberCategory and type(s.lastCategory) == "string") and s.lastCategory or "all"
	self:CreateHeader()
	self:CreateSidebar()
	self:CreateContent()
	self:CreateFooter()
	self:ApplyPosition()
	self:ApplySkin()

	R:Listen("DATA_CHANGED", function() R:RequestRefresh() end)
	R:Listen("LOCKS_CHANGED", function() UI:UpdateLive() end)
	R:Listen("COOLDOWNS_CHANGED", function() UI:UpdateLive() end)
	R:Listen("MONEY_CHANGED", function() UI:UpdateFooter() end)
	R:Listen("MERCHANT_CHANGED", function() UI:UpdateFooter() end)
	R:Listen("MOVER_CHANGED", function() UI:UpdateFooter() end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if UI.pendingCombat then
			UI.pendingCombat = false
			R:RequestRefresh()
		end
	end)
end

function UI:CreateHeader()
	local f = self.frame
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", PAD, -PAD)
	header:SetPoint("TOPRIGHT", -PAD, -PAD)
	header:SetHeight(HEADER_H - PAD)
	self.header = header

	-- character selector
	local charBtn = W:Button(header, "", 130, 22, function(btn) UI:ShowCharMenu(btn) end)
	charBtn:SetPoint("LEFT", 0, 0)
	charBtn.text:ClearAllPoints()
	charBtn.text:SetPoint("LEFT", 8, 0)
	charBtn.text:SetPoint("RIGHT", -16, 0)
	charBtn.text:SetJustifyH("LEFT")
	local arrow = charBtn:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -4, 0)
	arrow:SetRotation(-math.pi / 2)
	W:SetTooltip(charBtn, "Character", "View the bags and bank of any of your characters.")
	self.charBtn = charBtn

	-- tabs
	self.tabBags = W:Button(header, R.L.bags, 56, 22, function() UI:SetView("bags") end)
	self.tabBags:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
	self.tabBank = W:Button(header, R.L.bank, 56, 22, function() UI:SetView("bank") end)
	self.tabBank:SetPoint("LEFT", self.tabBags, "RIGHT", 2, 0)

	-- cross-character search toggle (applies while the search box has text)
	local allBtn = W:Button(header, "All", 30, 22, function()
		R.settings.searchAllChars = not R.settings.searchAllChars
		UI:UpdateTabs()
		R:RequestRefresh()
	end)
	allBtn:SetPoint("LEFT", self.tabBank, "RIGHT", 6, 0)
	W:SetTooltip(allBtn, "Search all characters",
		"When on and you type a search, results come from every character's cached bags and bank. Results are view-only (no item actions) in this mode.")
	self.allBtn = allBtn

	-- right-side buttons
	local close = W:Button(header, "X", 22, 22, function() UI:Close() end)
	close:SetPoint("RIGHT", 0, 0)
	W:SetTooltip(close, "Close")
	local gear = W:IconButton(header, "Interface\\Icons\\INV_Misc_Gear_01", 22, function() R.Options:Toggle() end)
	gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
	W:SetTooltip(gear, "Settings")
	local viewBtn = W:Button(header, R.L.toGrid, 44, 22, function()
		R.settings.viewMode = (R.settings.viewMode == "list") and "grid" or "list"
		UI.offset = 0
		UI:Layout()
	end)
	viewBtn:SetPoint("RIGHT", gear, "LEFT", -4, 0)
	W:SetTooltip(viewBtn, "Toggle view", "Switch between the table (list) view and the icon grid view.")
	self.viewBtn = viewBtn

	-- sort presets
	local presetBtn = W:Button(header, R.L.preset, 52, 22, function(btn) UI:ShowPresetMenu(btn) end)
	presetBtn:SetPoint("RIGHT", viewBtn, "LEFT", -4, 0)
	W:SetTooltip(presetBtn, "Sort presets", "Apply or save a named combination of sort, grouping and view settings.")
	self.presetBtn = presetBtn

	-- search
	local search = W:EditBox(header, 160, 22)
	search:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
	search:SetPoint("RIGHT", presetBtn, "LEFT", -8, 0)
	search:SetTextInsets(22, 40, 0, 0)
	local mag = search:CreateTexture(nil, "OVERLAY")
	mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	mag:SetSize(14, 14)
	mag:SetPoint("LEFT", 5, -1)
	mag:SetVertexColor(0.7, 0.7, 0.7)
	local hint = W:Text(search, "small")
	hint:SetPoint("LEFT", 22, 0)
	hint:SetText(R.L.searchHint)
	hint:SetTextColor(0.5, 0.5, 0.5)
	local clear = CreateFrame("Button", nil, search)
	clear:SetSize(16, 16)
	clear:SetPoint("RIGHT", -4, 0)
	clear.tex = clear:CreateTexture(nil, "ARTWORK")
	clear.tex:SetAllPoints()
	clear.tex:SetTexture("Interface\\Buttons\\UI-StopButton")
	clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)
	-- search history dropdown
	local histBtn = CreateFrame("Button", nil, search)
	histBtn:SetSize(14, 14)
	histBtn:SetPoint("RIGHT", -21, 0)
	histBtn.tex = histBtn:CreateTexture(nil, "ARTWORK")
	histBtn.tex:SetAllPoints()
	histBtn.tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	histBtn.tex:SetRotation(-math.pi / 2)
	histBtn:SetScript("OnClick", function() UI:ShowHistoryMenu(histBtn) end)
	W:SetTooltip(histBtn, "Recent searches")
	search:SetScript("OnTextChanged", function(self)
		local t = self:GetText() or ""
		hint:SetShown(t == "" and not self:HasFocus())
		clear:SetShown(t ~= "")
		if t ~= UI.search then
			UI.search = t
			UI.offset = 0
			R:RequestRefresh()
		end
	end)
	search:SetScript("OnEditFocusGained", function() hint:Hide() end)
	search:SetScript("OnEditFocusLost", function(self)
		hint:SetShown((self:GetText() or "") == "")
		UI:RecordSearch(UI.search)
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		UI:RecordSearch(UI.search)
	end)
	clear:Hide()
	W:SetTooltip(search, "Search",
		"Words: name/type.  #fav #new #junk #upgrade #boe #bop #bound #gear #consumable #quest #trade #recipe #key #usable\n" ..
		"Fields: ilvl lvl count bag q type sub slot value ah tsm pawn  with : = > < >= <=  (ilvl:10-20, value>1g)\n" ..
		"\"|\" = OR, \"!\" = NOT")
	self.searchBox = search
end

function UI:CreateSidebar()
	local f = self.frame
	local side = CreateFrame("Frame", nil, f, API.Backdrop)
	side:SetPoint("TOPLEFT", PAD, -HEADER_H)
	side:SetPoint("BOTTOMLEFT", PAD, FOOTER_H)
	side:SetWidth(SIDEBAR_W)
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(_, delta)
		UI.catOffset = math.max(0, (UI.catOffset or 0) - delta)
		UI:UpdateSidebar()
	end)
	self.sidebar = side

	local add = W:Button(side, "+ New category", SIDEBAR_W - 8, 18, function() UI:PromptNewCategory() end)
	add:SetPoint("BOTTOM", 0, 4)
	W:SetTooltip(add, "New category", "Creates a custom category from a search query. The current search text is used as the default.")
	self.addCatBtn = add
end

function UI:CreateContent()
	local f = self.frame
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", PAD, 0)
	content:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H)
	self.content = content

	-- subfilter chips
	local chips = CreateFrame("Frame", nil, content)
	chips:SetPoint("TOPLEFT")
	chips:SetPoint("TOPRIGHT")
	chips:SetHeight(CHIPS_H)
	self.chips = chips

	-- column headers
	local colhead = CreateFrame("Frame", nil, content, API.Backdrop)
	colhead:SetHeight(COLHEAD_H)
	self.colhead = colhead

	-- list area
	local list = CreateFrame("Frame", nil, content)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list:SetClipsChildren(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		UI:Scroll(-delta * (IsShiftKeyDown() and 10 or 3))
	end)
	list:SetScript("OnReceiveDrag", function() UI:DropCursorItem() end)
	list:SetScript("OnMouseUp", function() UI:DropCursorItem() end)
	self.list = list

	local empty = W:Text(list, "normal")
	empty:SetPoint("CENTER")
	empty:SetTextColor(0.6, 0.6, 0.6)
	self.emptyText = empty

	-- scrollbar
	local scroll = CreateFrame("Slider", nil, content, API.Backdrop)
	scroll:SetOrientation("VERTICAL")
	scroll:SetWidth(SCROLL_W)
	scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	W:Backdrop(scroll, "flat", { 0, 0, 0, 0.3 }, { 0, 0, 0, 0 })
	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.5, 0.5, 0.5, 0.6)
	thumb:SetSize(SCROLL_W - 2, 30)
	scroll:SetThumbTexture(thumb)
	scroll:SetMinMaxValues(0, 0)
	scroll:SetValueStep(1)
	if scroll.SetObeyStepOnDrag then scroll:SetObeyStepOnDrag(true) end
	scroll:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v + 0.5)
		if v ~= UI.offset and not UI.settingScroll then
			UI.offset = v
			UI:Render()
		end
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(-delta * 3) end)
	self.scroll = scroll
	self.scrollThumb = thumb
end

function UI:CreateFooter()
	local f = self.frame
	local foot = CreateFrame("Frame", nil, f)
	foot:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
	foot:SetPoint("BOTTOMRIGHT", -PAD - 14, PAD - 2)
	foot:SetHeight(FOOTER_H - PAD)
	self.footer = foot

	local moneyBtn = CreateFrame("Button", nil, foot)
	moneyBtn:SetSize(130, 20)
	moneyBtn:SetPoint("LEFT", 2, 0)
	moneyBtn.text = W:Text(moneyBtn, "normal")
	moneyBtn.text:SetPoint("LEFT")
	moneyBtn:SetScript("OnEnter", function(self) UI:ShowMoneyTooltip(self) end)
	moneyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.moneyBtn = moneyBtn

	local free = W:Text(foot, "small")
	free:SetPoint("LEFT", moneyBtn, "RIGHT", 6, 0)
	self.freeText = free

	local bagBar = CreateFrame("Frame", nil, foot)
	bagBar:SetSize(10, 22)
	bagBar:SetPoint("LEFT", free, "RIGHT", 8, 0)
	self.bagBar = bagBar

	local cached = W:Text(foot, "small")
	cached:SetPoint("LEFT", bagBar, "RIGHT", 8, 0)
	cached:SetTextColor(0.6, 0.6, 0.6)
	self.cachedText = cached

	local total = W:Text(foot, "small")
	total:SetPoint("LEFT", cached, "RIGHT", 10, 0)
	self.totalText = total

	-- action buttons (right to left)
	self.btnTransfer = W:Button(foot, R.L.transfer, 70, 22, function() UI:DoTransfer() end)
	W:SetTooltip(self.btnTransfer, "Transfer", "Moves every item currently listed (after search/category filters) to the other side: bags to bank, or bank to bags.")
	self.btnSort = W:Button(foot, R.L.sort, 46, 22, function()
		if UI.view == "bank" then
			if R.Data.atBank and API.SortBankBags then API.SortBankBags() end
		elseif API.SortBags then API.SortBags() end
	end)
	W:SetTooltip(self.btnSort, "Sort", "Blizzard's physical bag sort. The list view is always sorted regardless.")
	self.btnRestack = W:Button(foot, R.L.restack, 60, 22, function() R.Mover:Restack(UI.view) end)
	W:SetTooltip(self.btnRestack, "Restack", "Combines partial stacks of the same item.")
	self.btnSell = W:Button(foot, R.L.sellJunk, 74, 22, function() R.Junk:SellAll() end)
	W:SetTooltip(self.btnSell, "Sell Junk", function()
		return "Sells all junk to this merchant for " .. (R.FormatMoney(R.Junk:TotalValue()) ~= "" and R.FormatMoney(R.Junk:TotalValue()) or "nothing") .. "."
	end)

	-- resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() if not R.settings.locked then f:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SavePosition(); UI:Layout() end)
end

---------------------------------------------------------------------------
-- Position, skin, layout
---------------------------------------------------------------------------
function UI:ApplyPosition()
	local f, s = self.frame, R.settings
	f:ClearAllPoints()
	f:SetSize(s.width, s.height)
	f:SetScale(s.scale)
	if s.point then
		f:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 0)
	end
end

function UI:SavePosition()
	local f, s = self.frame, R.settings
	local p, _, rp, x, y = f:GetPoint()
	s.point = { p, rp, x, y }
	s.width, s.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
end

function UI:ResetPosition()
	R.settings.point = nil
	R.settings.width, R.settings.height = R.defaults.width, R.defaults.height
	self:ApplyPosition()
	self:Layout()
end

function UI:ApplySkin()
	W:InvalidateTheme()
	local skin = W:Skin()
	local bg = skin.bg
	W:Backdrop(self.frame, "main", { bg[1], bg[2], bg[3], R.settings.alpha })
	W:Backdrop(self.sidebar, "flat", skin.panel, { 0, 0, 0, 0 })
	W:Backdrop(self.colhead, "flat", skin.panel, { 0, 0, 0, 0 })
	W:RefreshButtons()
	self.frame:SetScale(R.settings.scale)
	W:UpdateFonts()
	if self.frame:IsShown() then self:Layout() end
end

-- Re-anchors the main regions using the active theme's padding.
function UI:Anchor()
	local pad = W:Pad()
	self.header:ClearAllPoints()
	self.header:SetPoint("TOPLEFT", pad, -pad)
	self.header:SetPoint("TOPRIGHT", -pad, -pad)
	self.sidebar:ClearAllPoints()
	self.sidebar:SetPoint("TOPLEFT", pad, -(HEADER_H + pad - 6))
	self.sidebar:SetPoint("BOTTOMLEFT", pad, FOOTER_H + pad - 6)
	self.footer:ClearAllPoints()
	self.footer:SetPoint("BOTTOMLEFT", pad, pad - 2)
	self.footer:SetPoint("BOTTOMRIGHT", -pad - 14, pad - 2)
end

-- Cheap path used by Refresh: re-anchors nothing unless geometry inputs changed,
-- then rebuilds display rows and draws the visible slice.
function UI:LayoutIfChanged()
	local s = R.settings
	local g = self.geom
	if not g then g = {}; self.geom = g end
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if g.w ~= w or g.h ~= h or g.chips ~= self.chips:IsShown() or g.view ~= s.viewMode
		or g.rh ~= s.rowHeight or g.grid ~= s.gridSize or g.side ~= s.showSidebar
		or g.compact ~= s.compactSidebar or g.theme ~= W:Skin() then
		return self:Layout()
	end
	if g.sortKey ~= s.sortKey or g.sortAsc ~= s.sortAsc then
		g.sortKey, g.sortAsc = s.sortKey, s.sortAsc
		self:UpdateHeaders()
	end
	self:BuildDisplay()
	self:Render()
end

-- Full layout: anchors, row geometry, column positions. Called on resize/settings changes.
function UI:Layout()
	if not self.frame then return end
	local s = R.settings
	local pad = W:Pad()
	local g = self.geom or {}
	self.geom = g
	g.w, g.h, g.chips, g.view = self.frame:GetWidth(), self.frame:GetHeight(), self.chips:IsShown(), s.viewMode
	g.rh, g.grid, g.side, g.compact, g.theme = s.rowHeight, s.gridSize, s.showSidebar, s.compactSidebar, W:Skin()
	g.sortKey, g.sortAsc = s.sortKey, s.sortAsc
	self:Anchor()
	local compact = s.compactSidebar
	self.sidebar:SetShown(s.showSidebar)
	self.sidebar:SetWidth(compact and SIDEBAR_COMPACT_W or SIDEBAR_W)
	self.addCatBtn:SetShown(not compact)
	self.content:ClearAllPoints()
	if s.showSidebar then
		self.content:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", PAD, 0)
	else
		self.content:SetPoint("TOPLEFT", pad, -(HEADER_H + pad - 6))
	end
	self.content:SetPoint("BOTTOMRIGHT", -pad, FOOTER_H + pad - 6)
	self.viewBtn:SetLabel(s.viewMode == "list" and R.L.toGrid or R.L.toList)

	local top = 0
	if self.chips:IsShown() then top = CHIPS_H + 2 end
	self.colhead:ClearAllPoints()
	self.list:ClearAllPoints()
	if s.viewMode == "list" then
		self.colhead:Show()
		self.colhead:SetPoint("TOPLEFT", 0, -top)
		self.colhead:SetPoint("TOPRIGHT", 0, -top)
		self.list:SetPoint("TOPLEFT", 0, -(top + COLHEAD_H + 2))
	else
		self.colhead:Hide()
		self.list:SetPoint("TOPLEFT", 0, -top)
	end
	self.list:SetPoint("BOTTOMRIGHT", 0, 0)

	-- row geometry
	local rh = self:RowHeight()
	for i, row in ipairs(self.rows) do
		row:SetHeight(rh)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rh)
		row:SetPoint("RIGHT", self.list, "RIGHT", -SCROLL_W - 2, 0)
	end
	self:ComputeColumns()
	self:BuildDisplay()
	self:Render()
end

function UI:ListWidth()
	return (self.list:GetWidth() or 400) - SCROLL_W - 2
end

function UI:VisibleRows()
	local h = self.list:GetHeight() or 300
	if R.settings.viewMode == "grid" then
		return math.max(1, math.floor(h / (R.settings.gridSize + 2)))
	end
	return math.max(1, math.floor(h / self:RowHeight()))
end

function UI:GridPerRow()
	local size = R.settings.gridSize + 2
	return math.max(1, math.floor(self:ListWidth() / size))
end

---------------------------------------------------------------------------
-- Columns layout & headers
---------------------------------------------------------------------------
function UI:ComputeColumns()
	local cols = R.Columns:Visible()
	local width = self:ListWidth()
	local fixed, flexCol = 0, nil
	for _, col in ipairs(cols) do
		if col.flex then flexCol = col else
			local w = col.kind == "icon" and (self:RowHeight() + 2) or R.Columns:Width(col)
			fixed = fixed + w + 4
		end
	end
	local flexW = math.max(80, width - fixed - 4)
	local layout, x = {}, 2
	for _, col in ipairs(cols) do
		local w
		if col == flexCol then w = flexW
		elseif col.kind == "icon" then w = self:RowHeight() + 2
		else w = R.Columns:Width(col) end
		layout[#layout + 1] = { col = col, x = x, w = w }
		x = x + w + 4
	end
	self.colLayout = layout
	self.colVersion = (self.colVersion or 0) + 1  -- rows re-anchor their cells only when this changes
	self:UpdateHeaders()
end

function UI:UpdateHeaders()
	local s = R.settings
	for _, b in pairs(self.headerButtons) do b:Hide() end
	for _, L in ipairs(self.colLayout or {}) do
		local col = L.col
		local b = self.headerButtons[col.key]
		if not b then
			b = CreateFrame("Button", nil, self.colhead)
			b:SetHeight(COLHEAD_H)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b.text = W:Text(b, "small")
			b.text:SetPoint("LEFT", 2, 0)
			b.text:SetPoint("RIGHT", -10, 0)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetSize(13, 13)
			b.icon:SetPoint("CENTER")
			b.arrow = b:CreateTexture(nil, "OVERLAY")
			b.arrow:SetTexture(SORT_ARROW)
			b.arrow:SetSize(9, 8)
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.06)
			b:SetScript("OnClick", function(self, btn)
				if btn == "RightButton" then return UI:ShowColumnMenu(self) end
				if s.sortKey == self.colKey then s.sortAsc = not s.sortAsc
				else
					s.sortKey = self.colKey
					s.sortAsc = (self.colKey == "name" or self.colKey == "type" or self.colKey == "sub" or self.colKey == "slot" or self.colKey == "location")
				end
				R:RequestRefresh()
			end)
			W:SetTooltip(b, function(self) return self.colLabel end, "Click to sort. Right-click to choose columns. Drag the right edge to resize.")
			-- resize handle
			local h = CreateFrame("Frame", nil, b)
			h:SetWidth(6)
			h:SetPoint("TOPRIGHT", 3, 0)
			h:SetPoint("BOTTOMRIGHT", 3, 0)
			h:EnableMouse(true)
			h.tex = h:CreateTexture(nil, "OVERLAY")
			h.tex:SetColorTexture(1, 1, 1, 0.15)
			h.tex:SetPoint("TOP")
			h.tex:SetPoint("BOTTOM")
			h.tex:SetWidth(1)
			h:SetScript("OnMouseDown", function()
				local x = GetCursorPosition() / b:GetEffectiveScale()
				UI.resizing = { key = b.colKey, startX = x, startW = b:GetWidth(), button = b }
				UI.colhead:SetScript("OnUpdate", function() UI:ResizeColumnUpdate() end)
			end)
			h:SetScript("OnMouseUp", function() UI:EndResize() end)
			b.handle = h
			self.headerButtons[col.key] = b
		end
		b.colKey = col.key
		b.colLabel = col.label or col.title
		b:ClearAllPoints()
		b:SetPoint("LEFT", self.colhead, "LEFT", L.x, 0)
		b:SetWidth(L.w)
		b.text:SetText(col.title or "")
		b.text:SetJustifyH(col.align)
		if col.headerIcon then
			b.icon:SetTexture(col.headerIcon)
			b.icon:Show()
		else
			b.icon:Hide()
		end
		local sorted = s.sortKey == col.key
		b.arrow:SetShown(sorted)
		b.arrow:ClearAllPoints()
		if col.align == "RIGHT" then b.arrow:SetPoint("LEFT", 1, 0) else b.arrow:SetPoint("RIGHT", -2, 0) end
		if s.sortAsc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end
		local skin = W:Skin()
		local tc = sorted and skin.accent or skin.dim
		b.text:SetTextColor(tc[1], tc[2], tc[3])
		b.handle:SetShown(not col.flex and col.kind ~= "icon" and col.kind ~= "fav" and col.kind ~= "junk")
		b:Show()
	end
end

function UI:EndResize()
	self.resizing = nil
	self.colhead:SetScript("OnUpdate", nil)
	self:Layout()
end

function UI:ResizeColumnUpdate()
	local r = self.resizing
	if not r then return end
	if not IsMouseButtonDown("LeftButton") then return self:EndResize() end
	local x = GetCursorPosition() / r.button:GetEffectiveScale()
	local w = math.max(20, math.floor(r.startW + (x - r.startX)))
	if w ~= R.settings.columns.widths[r.key] then
		R.settings.columns.widths[r.key] = w
		self:ComputeColumns()
		self:Render()
	end
end

function UI:ShowColumnMenu(anchor)
	local items = { { text = "Columns", isTitle = true } }
	local cfg = R.settings.columns
	for _, key in ipairs(cfg.order) do
		local col = R.Columns.byKey[key]
		if col and not col.fixed and (not col.available or col.available()) then
			items[#items + 1] = {
				text = col.label or col.title, checked = not cfg.hidden[key], keepOpen = false,
				func = function()
					cfg.hidden[key] = not cfg.hidden[key] or nil
					UI:Layout()
				end,
			}
		end
	end
	items[#items + 1] = { text = "Reset column widths", func = function() wipe(cfg.widths); UI:Layout() end }
	items[#items + 1] = { text = "More in settings...", func = function() R.Options:Show("columns") end }
	W:Menu(anchor, items)
end

---------------------------------------------------------------------------
-- Data -> display rows
---------------------------------------------------------------------------
local QUALITY_LABEL = function(q)
	local _, _, _, hex = R.QualityColor(q)
	return hex .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q)) .. "|r"
end

local function bagOrder(bag)
	for i, b in ipairs(API.InvBagList) do if b == bag then return i end end
	for i, b in ipairs(API.BankBagList) do if b == bag then return 100 + i end end
	return 999
end

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then
		self.dirty = true
		return
	end
	if InCombatLockdown() and self.protectedButtons then
		self.pendingCombat = true
		self:UpdateLive()
		return
	end
	self.dirty = false
	local s = R.settings
	local char = self:Char()
	local isMe = char == R.Data.me
	local isLive = self:Interactive()
	local Items = R.Items

	-- Pipeline: build (pooled entries) -> prepare -> search -> category -> chips -> sort.
	-- All intermediate arrays are module-level scratch tables; nothing is allocated per item.
	-- Cross-character search swaps the pooled build for snapshot copies and forces
	-- the window non-interactive for as long as it's active.
	self.searchAllActive = R.settings.searchAllChars and self.search ~= "" or false
	local entries
	if self.searchAllActive then
		entries = self:BuildAllChars(self.view)
	else
		entries = Items:Build(char, self.view)
		for i = 1, #entries do Items:Prepare(entries[i], char, isMe, isLive) end
	end
	self.allEntries = entries

	local pred = R.Search:Compile(self.search)
	local searched = wipe(scratchSearched)
	for i = 1, #entries do
		local e = entries[i]
		if not pred or pred(e) then searched[#searched + 1] = e end
	end

	local cats = R.Categories:List()
	self.catList = cats
	wipe(catCounts)
	self.catCounts = catCounts
	local cat
	for ci = 1, #cats do
		local c = cats[ci]
		local filter, n = c.filter, 0
		for i = 1, #searched do if filter(searched[i]) then n = n + 1 end end
		catCounts[c.id] = n
		if c.id == self.category then cat = c end
	end
	if not cat then
		self:SetCategory("all")
		cat = cats[1]
	end
	local inCat = wipe(scratchInCat)
	local filter = cat.filter
	for i = 1, #searched do
		local e = searched[i]
		if filter(e) then inCat[#inCat + 1] = e end
	end

	local subs, subList = wipe(scratchSubs), wipe(scratchSubList)
	if self.category ~= "all" then
		for i = 1, #inCat do
			local inf = inCat[i].info
			local sub = inf and inf.sub or ""
			if sub ~= "" then
				local n = subs[sub]
				if not n then subList[#subList + 1] = sub; n = 0 end
				subs[sub] = n + 1
			end
		end
		if #subList > 1 then tsort(subList) end
	end
	if #subList < 2 then wipe(subList) end
	if self.subfilter and not subs[self.subfilter] then self.subfilter = nil end
	self.subList, self.subCounts = subList, subs

	local final = wipe(scratchFinal)
	local subfilter, bagFilter = self.subfilter, self.bagFilter
	for i = 1, #inCat do
		local e = inCat[i]
		local ok = not subfilter or (e.info ~= nil and e.info.sub == subfilter)
		if ok and bagFilter then
			ok = false
			local sl = e.slots
			for j = 1, #sl do if sl[j][1] == bagFilter then ok = true; break end end
		end
		if ok then final[#final + 1] = e end
	end

	tsort(final, R.Columns:Comparator(s.sortKey, s.sortAsc))
	self.entries = final

	self:UpdateChips()
	self:UpdateSidebar()
	self:UpdateTabs()
	self:UpdateFooter()
	self:LayoutIfChanged()
end

-- Group keys/labels are cached per quality/bag so grouping allocates no strings.
local qualityKey, qualityLabel, bagKey, bagLabel = {}, {}, {}, {}
function UI:GroupInfo(e)
	local g = R.settings.groupBy
	if g == "category" then
		return R.Categories:GroupOf(e)
	elseif g == "type" then
		local t = e.info and e.info.type ~= "" and e.info.type or "Other"
		return t, 0, t
	elseif g == "quality" then
		local q = e.quality
		if not qualityKey[q] then qualityKey[q] = "q" .. q; qualityLabel[q] = QUALITY_LABEL(q) end
		return qualityKey[q], -q, qualityLabel[q]
	elseif g == "bag" then
		local b = e.bag
		if not bagKey[b] then bagKey[b] = "b" .. b; bagLabel[b] = API.BagLabel(b) end
		return bagKey[b], bagOrder(b), bagLabel[b]
	end
end

-- Display rows are built from pooled objects: group headers, groups and grid rows
-- are recycled across refreshes (wiped, not reallocated).
local display = {}
local headerPool, headerUsed = {}, 0
local gridRowPool, gridRowUsed = {}, 0
local groupPool, groupUsed = {}, 0
local groupsByKey, groupList = {}, {}

local function NewHeader()
	headerUsed = headerUsed + 1
	local h = headerPool[headerUsed]
	if not h then h = { header = true }; headerPool[headerUsed] = h end
	return h
end
local function NewGridRow()
	gridRowUsed = gridRowUsed + 1
	local r = gridRowPool[gridRowUsed]
	if not r then r = { items = {} }; gridRowPool[gridRowUsed] = r else wipe(r.items) end
	return r
end
local function NewGroup()
	groupUsed = groupUsed + 1
	local g = groupPool[groupUsed]
	if not g then g = { items = {} }; groupPool[groupUsed] = g else wipe(g.items) end
	return g
end
local function GroupSort(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.label < b.label
end

local function AddItems(items, grid, perRow)
	if grid then
		local row
		for i = 1, #items do
			if (i - 1) % perRow == 0 then
				row = NewGridRow()
				display[#display + 1] = row
			end
			row.items[#row.items + 1] = items[i]
		end
	else
		for i = 1, #items do display[#display + 1] = items[i] end
	end
end

function UI:BuildDisplay()
	local s = R.settings
	wipe(display)
	headerUsed, gridRowUsed, groupUsed = 0, 0, 0
	local entries = self.entries or display
	local grid = s.viewMode == "grid"
	local perRow = grid and self:GridPerRow() or 1

	if s.groupBy == "none" then
		AddItems(entries, grid, perRow)
	else
		wipe(groupsByKey); wipe(groupList)
		for i = 1, #entries do
			local e = entries[i]
			local key, order, label = self:GroupInfo(e)
			local g = groupsByKey[key]
			if not g then
				g = NewGroup()
				g.key, g.order, g.label = key, order, label
				groupsByKey[key] = g
				groupList[#groupList + 1] = g
			end
			g.items[#g.items + 1] = e
		end
		tsort(groupList, GroupSort)
		for gi = 1, #groupList do
			local g = groupList[gi]
			local collapsed = s.collapsed[g.key]
			local h = NewHeader()
			h.key, h.label, h.count, h.collapsed = g.key, g.label, #g.items, collapsed
			display[#display + 1] = h
			if not collapsed then AddItems(g.items, grid, perRow) end
		end
	end
	self.display = display

	local visible = self:VisibleRows()
	local maxOff = max(0, #display - visible)
	if self.offset > maxOff then self.offset = maxOff end
	if self.offset < 0 then self.offset = 0 end
	self.settingScroll = true
	self.scroll:SetMinMaxValues(0, maxOff)
	self.scroll:SetValue(self.offset)
	self.settingScroll = false
	local total = max(#display, 1)
	local trackH = self.scroll:GetHeight() or 100
	self.scrollThumb:SetHeight(max(20, trackH * min(1, visible / total)))
	self.scroll:SetShown(maxOff > 0)
end

function UI:Scroll(delta)
	local maxOff = math.max(0, #self.display - self:VisibleRows())
	local new = math.min(maxOff, math.max(0, self.offset + delta))
	if new ~= self.offset then
		self.offset = new
		self.settingScroll = true
		self.scroll:SetValue(new)
		self.settingScroll = false
		self:Render()
	end
end

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
	btn:SetScript("OnDragStart", function(self) API.PickupContainerItem(bs(self)) end)
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
			GameTooltip:Show()
		end
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

---------------------------------------------------------------------------
-- Render visible slice
---------------------------------------------------------------------------
function UI:Render()
	if not self.frame or not self.frame:IsShown() then return end
	if InCombatLockdown() and self.protectedButtons then
		self.pendingCombat = true
		return
	end
	local s = R.settings
	local grid = s.viewMode == "grid"
	local display = self.display
	local visible = self:VisibleRows()
	local interactive = self:Interactive() and not self.searchAllActive
	local t0 = R:ProfileStart()
	self:BeginButtons()

	local pool, other = grid and self.gridRows or self.rows, grid and self.rows or self.gridRows
	for _, r in ipairs(other) do r:Hide() end

	local rh = grid and (s.gridSize + 2) or self:RowHeight()
	for i = 1, visible do
		local d = display[self.offset + i]
		local row = grid and self:GetGridRow(i) or self:GetListRow(i)
		if grid then
			if row.anchorRH ~= rh then
				row.anchorRH = rh
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rh)
				row:SetPoint("RIGHT", self.list, "RIGHT", -SCROLL_W - 2, 0)
			end
			row:SetHeight(d and d.header and 20 or s.gridSize)
		end
		if not d then
			row:Hide()
		else
			row:Show()
			if grid then
				self:SetupGridRow(row, d, interactive)
				if interactive and not d.header then
					for ci, e in ipairs(d.items) do
						local cell = row.cells[ci]
						self:AttachButton(cell, e, cell:GetFrameLevel() + 2)
					end
				end
			elseif d.header then
				self:SetupHeaderRow(row, d)
			else
				self:SetupItemRow(row, d, self.offset + i, interactive)
				if interactive then self:AttachButton(row, d, row:GetFrameLevel() + 3) end
			end
		end
	end
	for i = visible + 1, #pool do pool[i]:Hide() end
	self:EndButtons()
	R:ProfileEnd("UI:Render", t0)

	-- empty state
	local text = ""
	if #display == 0 then
		local char = self:Char()
		local cached = false
		for _, bag in ipairs(self.view == "bank" and API.BankBagList or API.InvBagList) do
			if char.containers[bag] then cached = true; break end
		end
		if self.view == "bank" and not cached then
			text = R.L.emptyBank
		elseif self.search ~= "" or self.category ~= "all" or self.bagFilter then
			text = R.L.nothingMatches
		else
			text = R.L.empty
		end
	end
	self.emptyText:SetText(text)
	self.emptyText:SetShown(text ~= "")
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

---------------------------------------------------------------------------
-- Sidebar & chips
---------------------------------------------------------------------------
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
	for _, b in ipairs(self.catButtons) do b:Hide() end
	local width = compact and SIDEBAR_COMPACT_W or SIDEBAR_W
	local bh = 22
	local avail = (self.sidebar:GetHeight() or 300) - (compact and 6 or 30)
	local maxVisible = math.max(1, math.floor(avail / bh))
	local maxOff = math.max(0, #cats - maxVisible)
	self.catOffset = math.min(self.catOffset or 0, maxOff)
	local skin = W:Skin()
	for i = 1, math.min(maxVisible, #cats) do
		local c = cats[i + self.catOffset]
		if not c then break end
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
				if self.cat.custom then
					local def = R.db.categories[self.cat.custom]
					GameTooltip:AddLine("Filter: " .. (def and def.query or ""), 1, 1, 1, true)
					GameTooltip:AddLine("Right-click to edit, move or delete.", 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			self.catButtons[i] = b
		end
		b.cat = c
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 2, -3 - (i - 1) * bh)
		b:SetWidth(width - 4)
		b.icon:SetTexture(c.icon)
		if c.id ~= "fav" then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
		b.text:SetText(c.name)
		b.text:SetShown(not compact)
		local n = self.catCounts and self.catCounts[c.id] or 0
		b.count:SetText(n > 0 and n or "")
		b.count:SetShown(not compact)
		local active = self.category == c.id
		b.bar:SetColorTexture(skin.accent[1], skin.accent[2], skin.accent[3], 1)
		b.bar:SetShown(active)
		b.bg:SetColorTexture(1, 1, 1, active and 0.08 or 0)
		local tc = active and skin.accent or (n > 0 and skin.text or skin.dim)
		b.text:SetTextColor(tc[1], tc[2], tc[3])
		b.count:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])
		b.icon:SetDesaturated(n == 0 and not active)
		b:Show()
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
	self.tabBank:SetActive(self.view == "bank")
	if self.allBtn then self.allBtn:SetActive(R.settings.searchAllChars) end
	local c = self:Char()
	self.charBtn:SetLabel(R.ClassColorText(c.class, c.name or "?"))
end

function UI:SetView(view)
	if self.view == view then return end
	self.view = view
	self.bagFilter = nil
	self.offset = 0
	R:RequestRefresh()
end

---------------------------------------------------------------------------
-- Footer
---------------------------------------------------------------------------
local function BagButtonOnEnter(self)
	local bag = self.bag
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local c = UI:Char()
	local rec = c.containers[bag]
	if self.locked then
		GameTooltip:SetText("Bank bag slot (locked)")
		if R.Data.atBank and UI:IsMe() and GetBankSlotCost then
			GameTooltip:AddLine("Click to purchase: " .. R.FormatMoney(GetBankSlotCost(c.bankBags or 0)), 1, 1, 1)
		end
	elseif self.link and UI:Interactive() and API.BagInvID(bag) then
		GameTooltip:SetInventoryItem("player", API.BagInvID(bag))
	elseif self.link then
		GameTooltip:SetHyperlink(self.link)
	else
		GameTooltip:SetText(API.BagLabel(bag))
	end
	if rec then
		local used = 0
		for _ in pairs(rec.slots) do used = used + 1 end
		GameTooltip:AddLine(format("%d / %d slots used", used, rec.size or 0), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Click: show only this bag", 0.6, 0.6, 0.6)
	if UI:Interactive() then GameTooltip:AddLine("Right-click: empty this bag", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function BagButtonOnClick(self, button)
	if self.locked then
		if R.Data.atBank and UI:IsMe() then StaticPopup_Show("RUMMAGE_BUY_BANK_SLOT") end
		return
	end
	if UI:Interactive() and (CursorHasItem and CursorHasItem()) then
		local inv = API.BagInvID(self.bag)
		if self.bag == API.BACKPACK and API.PutItemInBackpack then API.PutItemInBackpack()
		elseif inv and API.PutItemInBag then API.PutItemInBag(inv) end
		return
	end
	if button == "RightButton" then
		if UI:Interactive() then R.Mover:EmptyBag(self.bag) end
		return
	end
	UI.bagFilter = (UI.bagFilter ~= self.bag) and self.bag or nil
	UI.offset = 0
	R:RequestRefresh()
end

function UI:UpdateBagBar()
	for _, b in ipairs(self.bagButtons) do b:Hide() end
	local c = self:Char()
	local list = self.view == "bank" and API.BankBagList or API.InvBagList
	local x, n = 0, 0
	local interactive = self:Interactive()
	for _, bag in ipairs(list) do
		local rec = c.containers[bag]
		local isKey = API.KEYRING and bag == API.KEYRING
		local purchasedLimit = API.IsLegacyBankBag(bag) and c.bankBags
		local locked = purchasedLimit and (bag - API.NUM_BAGS) > purchasedLimit
		if (rec and (rec.size or 0) > 0) or (not isKey and API.IsEquippedBag(bag)) or (bag == API.BANK and not API.BankTabs) or locked then
			if not (isKey and not rec) then
				n = n + 1
				local b = self.bagButtons[n]
				if not b then
					b = W:IconButton(self.bagBar, nil, 22, BagButtonOnClick)
					b:SetScript("OnEnter", BagButtonOnEnter)
					b:SetScript("OnLeave", function() GameTooltip:Hide() end)
					b:RegisterForDrag("LeftButton")
					b:SetScript("OnDragStart", function(self)
						local inv = API.BagInvID(self.bag)
						if inv and UI:Interactive() and API.PickupBagFromSlot and self.bag ~= API.BACKPACK then API.PickupBagFromSlot(inv) end
					end)
					b:SetScript("OnReceiveDrag", function(self) BagButtonOnClick(self, "LeftButton") end)
					b.free = W:Text(b, "tiny")
					b.free:SetPoint("BOTTOMRIGHT", -1, 1)
					self.bagButtons[n] = b
				end
				b.bag = bag
				b.locked = locked
				b.link = rec and rec.link
				local tex
				if bag == API.BACKPACK then tex = "Interface\\Buttons\\Button-Backpack-Up"
				elseif bag == API.BANK then tex = "Interface\\Icons\\INV_Misc_Bag_08"
				elseif isKey then tex = "Interface\\Icons\\INV_Misc_Key_03"
				elseif API.BankTabs and API.IsBankBag(bag) then tex = "Interface\\Icons\\INV_Misc_Bag_08"
				else tex = rec and rec.icon or (rec and rec.link and select(10, API.GetItemInfo(rec.link))) end
				if not tex then tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" end
				b.icon:SetTexture(tex)
				b.icon:SetVertexColor(locked and 1 or 1, locked and 0.3 or 1, locked and 0.3 or 1)
				local free
				if rec then
					local used = 0
					for _ in pairs(rec.slots) do used = used + 1 end
					free = (rec.size or 0) - used
				end
				b.free:SetText((free and rec.size and rec.size > 0 and not isKey) and free or "")
				b:SetActive(self.bagFilter == bag)
				b:ClearAllPoints()
				b:SetPoint("LEFT", self.bagBar, "LEFT", x, 0)
				b:Show()
				x = x + 24
			end
		end
	end
	self.bagBar:SetWidth(math.max(1, x))
	local _ = interactive
end

function UI:UpdateFooter()
	if not self.frame or not self.frame:IsShown() then return end
	local c = self:Char()
	self.moneyBtn.text:SetText(R.FormatMoney(c.money or 0) ~= "" and R.FormatMoney(c.money or 0) or "0")
	self.moneyBtn:SetWidth(math.max(60, self.moneyBtn.text:GetStringWidth() + 4))
	local list = self.view == "bank" and API.BankBagList or API.InvBagList
	local free, total = R.Data:FreeSlots(c, list)
	self.freeText:SetText(format(R.L.freeFmt, free, total))
	if free <= (R.settings.lowSpaceWarn or 0) and total > 0 then self.freeText:SetTextColor(1, 0.3, 0.3)
	else local d = W:Skin().dim; self.freeText:SetTextColor(d[1], d[2], d[3]) end
	self:UpdateBagBar()

	local cachedMsg = ""
	if not self:IsMe() then
		cachedMsg = "Cached · seen " .. (R.FormatAge(c.lastSeen) ~= "" and R.FormatAge(c.lastSeen) or "?") .. " ago"
	elseif self.view == "bank" and not R.Data.atBank then
		cachedMsg = R.L.cachedBank
	end
	self.cachedText:SetText(cachedMsg)

	-- Vendor value of everything currently listed (after filters), with the
	-- junk portion broken out. Uses the filtered entry list from Refresh.
	local totText = ""
	if self.entries and #self.entries > 0 then
		local sum, junkSum = 0, 0
		for i = 1, #self.entries do
			local e = self.entries[i]
			local v = (e.info and e.info.sell or 0) * (e.count or 1)
			sum = sum + v
			if e.junk then junkSum = junkSum + v end
		end
		if sum > 0 then
			totText = R.L.viewTotal .. ": " .. R.FormatMoney(sum, true)
			if junkSum > 0 then totText = totText .. " · " .. R.L.junkTotal .. " " .. R.FormatMoney(junkSum, true) end
		end
	end
	self.totalText:SetText(totText)

	local interactive = self:Interactive() and not self.searchAllActive
	local merchant = R.Junk.MerchantOpen()
	local buttons = wipe(self.footerButtons or {})
	self.footerButtons = buttons
	self.btnSell:SetShown(interactive and self.view == "bags" and merchant)
	if self.btnSell:IsShown() then buttons[#buttons + 1] = self.btnSell end
	self.btnRestack:SetShown(interactive)
	if interactive then buttons[#buttons + 1] = self.btnRestack end
	local canSort = interactive and ((self.view == "bags" and API.SortBags) or (self.view == "bank" and API.SortBankBags))
	self.btnSort:SetShown(canSort and true or false)
	if canSort then buttons[#buttons + 1] = self.btnSort end
	local canTransfer = self:IsMe() and R.Data.atBank
	self.btnTransfer:SetShown(canTransfer and true or false)
	if canTransfer then
		self.btnTransfer:SetLabel(self.view == "bank" and R.L.toBags or R.L.toBank)
		buttons[#buttons + 1] = self.btnTransfer
	end
	local busy = R.Mover:Busy()
	local prev
	for i = #buttons, 1, -1 do
		local b = buttons[i]
		b:ClearAllPoints()
		if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", self.footer, "RIGHT", 0, 0) end
		b:SetDisabledLook(busy)
		prev = b
	end
end

function UI:ShowMoneyTooltip(anchor)
	GameTooltip:SetOwner(anchor, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Gold")
	local total = 0
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		total = total + (c.money or 0)
		local name = c.name or entry.key
		if c.realm ~= GetRealmName() then name = name .. "-" .. (c.realm or "?") end
		GameTooltip:AddDoubleLine(R.ClassColorText(c.class, name), R.FormatMoney(c.money or 0) ~= "" and R.FormatMoney(c.money or 0) or "0", 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("|cffd9a441Total|r", R.FormatMoney(total), 1, 1, 1, 1, 1, 1)
	GameTooltip:Show()
end

function UI:DoTransfer()
	if not R.Data.atBank or self.searchAllActive then return end
	if self.bagFilter == nil and self.search == "" and self.category == "all" and not self.transferConfirmed then
		StaticPopup_Show("RUMMAGE_CONFIRM_TRANSFER", self.view == "bank" and "bags" or "bank")
		return
	end
	self.transferConfirmed = nil
	local entries = {}
	for _, e in ipairs(self.entries or {}) do
		if not (API.KEYRING and e.bag == API.KEYRING) then entries[#entries + 1] = e end
	end
	R.Mover:TransferEntries(entries, self.view == "bags")
end

-- Drop the item on the cursor into the first free slot of the current view.
function UI:DropCursorItem()
	if not (CursorHasItem and CursorHasItem()) or not self:Interactive() or self.searchAllActive then return end
	local list = self.view == "bank" and API.BankBagList or API.InvBagList
	local _, itemID = GetCursorInfo()
	for _, bag in ipairs(list) do
		if not (API.KEYRING and bag == API.KEYRING) then
			local family = 0
			if bag ~= API.BACKPACK and bag ~= API.BANK and API.GetNumFreeSlots then
				local _, f = API.GetNumFreeSlots(bag)
				family = f or 0
			end
			if family == 0 or (itemID and API.FitsBag(itemID, family)) then
				for slot = 1, API.GetNumSlots(bag) or 0 do
					if not API.GetSlotInfo(bag, slot) then
						API.PickupContainerItem(bag, slot)
						return
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Menus & popups
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Search history, sort presets, cross-character search
---------------------------------------------------------------------------
function UI:RecordSearch(text)
	text = text and text:match("^%s*(.-)%s*$")
	if not text or text == "" then return end
	local h = R.db.searchHistory
	if not h then return end
	for i = #h, 1, -1 do
		if h[i] == text then table.remove(h, i) end
	end
	table.insert(h, 1, text)
	while #h > 10 do table.remove(h) end
end

function UI:ShowHistoryMenu(anchor)
	local items = { { text = "Recent searches", isTitle = true } }
	local h = R.db.searchHistory or {}
	if #h == 0 then
		items[#items + 1] = { text = "(none yet)", disabled = true }
	end
	for _, q in ipairs(h) do
		items[#items + 1] = { text = q, func = function() UI.searchBox:SetText(q) end }
	end
	if #h > 0 then
		items[#items + 1] = { text = "Clear history", func = function() wipe(R.db.searchHistory) end }
	end
	W:Menu(anchor, items)
end

function UI:ShowPresetMenu(anchor)
	local s = R.settings
	local items = { { text = "Sort presets", isTitle = true } }
	local presets = R.db.sortPresets or {}
	if #presets == 0 then
		items[#items + 1] = { text = "(none saved)", disabled = true }
	end
	for i, pr in ipairs(presets) do
		items[#items + 1] = {
			text = pr.name,
			checked = s.sortKey == pr.sortKey and s.sortAsc == pr.sortAsc
				and s.groupBy == pr.groupBy and s.viewMode == pr.viewMode,
			func = function()
				s.sortKey, s.sortAsc = pr.sortKey, pr.sortAsc
				s.groupBy, s.viewMode = pr.groupBy, pr.viewMode
				s.favoritesFirst, s.newFirst = pr.favoritesFirst, pr.newFirst
				UI.offset = 0
				UI:Layout()
			end,
			onDelete = function()
				table.remove(R.db.sortPresets, i)
				R:Print("Preset '" .. pr.name .. "' deleted.")
			end,
		}
	end
	items[#items + 1] = { text = "Save current as preset...", func = function()
		StaticPopup_Show("RUMMAGE_NEW_PRESET")
	end }
	W:Menu(anchor, items)
end

-- Snapshot entries for every character (cross-character search). Items:Build
-- recycles its pooled entries on the next call, so matching data is copied
-- into plain tables here; the copies are only ever displayed, never acted on
-- (Render forces interactive=false while this mode is active).
function UI:BuildAllChars(view)
	local out = {}
	local Items = R.Items
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		local built = Items:Build(c, view)
		for i = 1, #built do
			local e = built[i]
			Items:Prepare(e, c, c == R.Data.me, false)
			local slotsCopy = {}
			for j = 1, #e.slots do slotsCopy[j] = { e.slots[j][1], e.slots[j][2] } end
			out[#out + 1] = {
				link = e.link, id = e.id, count = e.count, bag = e.bag, slot = e.slot,
				slots = slotsCopy, icon = e.icon, q = e.q, bound = e.bound,
				info = e.info, name = e.name, lname = e.lname, quality = e.quality,
				fav = e.fav, new = e.new, acquired = e.acquired, junk = e.junk,
				owner = c.name, foreign = c ~= R.Data.me, vals = {},
			}
		end
	end
	return out
end

function UI:ShowCharMenu(anchor)
	local items = { { text = "Characters", isTitle = true } }
	local current = self:Char()
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		local label = R.ClassColorText(c.class, c.name or entry.key)
		if c.realm ~= GetRealmName() then label = label .. " |cff888888- " .. (c.realm or "?") .. "|r" end
		if c.level then label = label .. " |cff888888(" .. c.level .. ")|r" end
		local item = {
			text = label, checked = c == current,
			func = function()
				UI.charKey = (entry.key ~= R.charKey) and entry.key or nil
				UI.offset = 0
				UI.bagFilter = nil
				R:RequestRefresh()
			end,
		}
		if entry.key ~= R.charKey then
			item.onDelete = function()
				StaticPopup_Show("RUMMAGE_DELETE_CHAR", entry.key, nil, entry.key)
			end
		end
		items[#items + 1] = item
	end
	W:Menu(anchor, items)
end

function UI:ShowCategoryMenu(anchor, cat)
	local idx = cat.custom
	W:Menu(anchor, {
		{ text = cat.name, isTitle = true },
		{ text = "Edit filter...", func = function() StaticPopup_Show("RUMMAGE_EDIT_CATEGORY", cat.name, nil, idx) end },
		{ text = "Rename...", func = function() StaticPopup_Show("RUMMAGE_RENAME_CATEGORY", cat.name, nil, idx) end },
		{ text = "Use current search as filter", func = function()
			R.db.categories[idx].query = UI.search
			R:RequestRefresh()
		end },
		{ text = "Move up", func = function() R.Categories:MoveCustom(idx, -1); R:RequestRefresh() end },
		{ text = "Move down", func = function() R.Categories:MoveCustom(idx, 1); R:RequestRefresh() end },
		{ text = "|cffff6060Delete|r", func = function()
			R.Categories:RemoveCustom(idx)
			if UI.category == cat.id then UI:SetCategory("all") end
			R:RequestRefresh()
		end },
	}, "TOPLEFT", "TOPRIGHT", 2, 0)
end

function UI:PromptNewCategory()
	StaticPopup_Show("RUMMAGE_NEW_CATEGORY")
end

local function EditBoxOf(dialog)
	return dialog.editBox or dialog.EditBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
end

function UI:RegisterPopups()
	StaticPopupDialogs["RUMMAGE_NEW_CATEGORY"] = {
		text = "Name for the new category?\n(Its filter will be the current search: \"%s\")",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name ~= "" then
				local idx = R.Categories:AddCustom(name, UI.search)
				UI:SetCategory("custom" .. idx)
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_NEW_CATEGORY"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_EDIT_CATEGORY"] = {
		text = "Filter for %s:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 200,
		OnShow = function(self, idx)
			local eb = EditBoxOf(self)
			local def = R.db.categories[idx]
			if eb and def then eb:SetText(def.query or ""); eb:SetFocus(); eb:HighlightText() end
		end,
		OnAccept = function(self, idx)
			local eb = EditBoxOf(self)
			if eb and R.db.categories[idx] then
				R.db.categories[idx].query = eb:GetText() or ""
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_EDIT_CATEGORY"].OnAccept(p, p.data)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_RENAME_CATEGORY"] = {
		text = "Rename %s:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self, idx)
			local eb = EditBoxOf(self)
			local def = R.db.categories[idx]
			if eb and def then eb:SetText(def.name or ""); eb:SetFocus(); eb:HighlightText() end
		end,
		OnAccept = function(self, idx)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name ~= "" and R.db.categories[idx] then
				R.db.categories[idx].name = name
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_RENAME_CATEGORY"].OnAccept(p, p.data)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_DELETE_CHAR"] = {
		text = "Forget all cached data for %s?",
		button1 = YES, button2 = NO,
		OnAccept = function(_, key)
			R.db.chars[key] = nil
			if UI.charKey == key then UI.charKey = nil end
			R:Fire("DATA_CHANGED")
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_CONFIRM_TRANSFER"] = {
		text = "Move EVERY listed item to your %s?",
		button1 = YES, button2 = NO,
		OnAccept = function()
			UI.transferConfirmed = true
			UI:DoTransfer()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_BUY_BANK_SLOT"] = {
		text = "Purchase the next bank bag slot?",
		button1 = YES, button2 = NO,
		OnShow = function(self)
			local cost = GetBankSlotCost and GetBankSlotCost((GetNumBankSlots and GetNumBankSlots()) or 0)
			local t = self.text or self.Text
			if t and cost then
				t:SetText("Purchase the next bank bag slot for " .. R.FormatMoney(cost) .. "?")
			end
		end,
		OnAccept = function()
			if PurchaseSlot then PurchaseSlot() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_NEW_PRESET"] = {
		text = "Name for this sort preset?\n(It saves the current sort, grouping and view settings.)",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name == "" then return end
			local s = R.settings
			for i, pr in ipairs(R.db.sortPresets) do
				if pr.name == name then table.remove(R.db.sortPresets, i); break end
			end
			R.db.sortPresets[#R.db.sortPresets + 1] = {
				name = name, sortKey = s.sortKey, sortAsc = s.sortAsc,
				groupBy = s.groupBy, viewMode = s.viewMode,
				favoritesFirst = s.favoritesFirst, newFirst = s.newFirst,
			}
			R:Print("Preset '" .. name .. "' saved.")
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_NEW_PRESET"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_EXPORT_SETTINGS"] = {
		text = "Your Rummage settings string (settings, columns, custom categories, auto-junk rules). Copy it somewhere safe:",
		button1 = CLOSE, hasEditBox = true, maxLetters = 0,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(R:ExportSettings()); eb:SetFocus(); eb:HighlightText() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_IMPORT_SETTINGS"] = {
		text = "Paste a Rummage settings string (RUM1;...). It replaces your settings, custom categories and auto-junk rules:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 0,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local ok, err = R:ImportSettings(eb and eb:GetText() or "")
			if ok then R:Print("Settings imported.")
			else R:Print("Import failed: " .. tostring(err)) end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_IMPORT_SETTINGS"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function UI:TintUnusable(tex, e)
	if R.settings.tintUnusable and e.info and (e.info.req or 0) > UnitLevel("player") then
		tex:SetVertexColor(1, 0.35, 0.35)
	else
		tex:SetVertexColor(1, 1, 1)
	end
end

local GetQuestInfo = API.GetContainerItemQuestInfo
function UI:QuestStarter(e, interactive)
	if not (R.settings.questBadges and interactive and GetQuestInfo) then return false end
	local a, b, c = GetQuestInfo(e.bag, e.slot)
	if type(a) == "table" then return a.questID ~= nil and not a.isActive end
	return b ~= nil and not c
end

-- Single place that changes the category, so "remember last category" can persist it.
function UI:SetCategory(id)
	self.category = id or "all"
	if R.settings.rememberCategory then R.settings.lastCategory = self.category end
end

function UI:FocusSearch()
	self:Open("bags")
	self.searchBox:SetFocus()
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
function UI:Open(view)
	if view then
		if view ~= self.view then self.bagFilter = nil; self.offset = 0 end
		self.view = view
	end
	if not self.frame:IsShown() then
		self.frame:Show()
	else
		R:RequestRefresh()
	end
end

function UI:Close()
	self.frame:Hide()
end

function UI:Toggle(view)
	if self.frame:IsShown() and (not view or view == self.view) then
		self:Close()
	else
		self:Open(view)
	end
end

function UI:OnShow()
	R.Integrations:ResetPawn()
	if R.settings.resetSearchOnOpen and self.search ~= "" then self.searchBox:SetText("") end
	if not R.settings.rememberCategory then self:SetCategory("all"); self.subfilter = nil; self.bagFilter = nil end
	if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
	self:ApplySkin()
	self:Refresh()
	R:Fire("FRAME_SHOWN")
end

function UI:OnHide()
	W.HideMenu()
	self.autoOpened = false
	if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
	if R.settings.clearNewOnClose then R.Data:ClearNew() end
	self.searchBox:ClearFocus()
	if R.Data.atBank and R.settings.replaceBank and CloseBankFrame then
		CloseBankFrame()
	end
	R:Fire("FRAME_HIDDEN")
end
