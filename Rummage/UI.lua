-- Rummage: main window — list/grid views, categories, search, columns, footer actions.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, type, wipe, tostring = pairs, ipairs, type, wipe, tostring
local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local InCombatLockdown = InCombatLockdown

-- 1.8.0: the window is a factory run once per window (Bags, Bank), so each gets its own
-- state, frames and closures. UI_Boot.lua builds the instances; UI.kind is "bags", "bank"
-- or "guild" (1.9.0: guild bank, whose items use plain rows instead of secure buttons).
R.UIParts = R.UIParts or {}

-- Layout constants shared by every UI part (UI_Rows, UI_Sidebar, UI_Footer read these).
R.UIK = {
	HEADER_H = 34, FOOTER_H = 34, PAD = 6, COLHEAD_H = 20, CHIPS_H = 22,
	SIDEBAR_W = 156,
	SIDEBAR_COMPACT_W = 44,   -- 1.9.1: icon rail (icons only, counts as badges)
	SCROLL_W = 10,
	FAV_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_",
	COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_02",
	UPGRADE_ICON = "Interface\\AddOns\\Pawn\\Textures\\UpgradeArrow",
	SORT_ARROW = "Interface\\Buttons\\UI-SortArrow",
}

R.UIParts[#R.UIParts + 1] = function(UI)

-- Scratch tables reused by every Refresh (wiped, never reallocated).
local scratchSearched, scratchInCat, scratchFinal = {}, {}, {}
local scratchSubs, scratchSubList = {}, {}
local catCounts = {}

local W -- Widgets, set in Create

local K = R.UIK
local HEADER_H, FOOTER_H, PAD, COLHEAD_H, CHIPS_H, SIDEBAR_W, SIDEBAR_COMPACT_W, SCROLL_W, FAV_ICON, COIN_ICON, UPGRADE_ICON, SORT_ARROW =
	K.HEADER_H, K.FOOTER_H, K.PAD, K.COLHEAD_H, K.CHIPS_H, K.SIDEBAR_W, K.SIDEBAR_COMPACT_W, K.SCROLL_W, K.FAV_ICON, K.COIN_ICON, K.UPGRADE_ICON, K.SORT_ARROW

UI.view = UI.kind
UI.suffix = (UI.kind == "bank" and "Bank") or (UI.kind == "guild" and "Guild") or ""
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
local NO_GUILD = { containers = {}, money = 0, numTabs = 0 }
UI.NO_GUILD = NO_GUILD  -- UI_Footer.lua reads it

function UI:Char()
	if self.kind == "guild" then
		-- in a guild whose bank isn't cached yet: show the guild's name, not "No guild"
		local _, gname = R.GuildBank:Key()
		NO_GUILD.name = gname or R.L.noGuild
		local key = self.guildKey
		local alt = not key and not R.GuildBank.atBank and R.UI.charKey and R.db.chars[R.UI.charKey]
		if alt then
			-- browsing an alt in Bags: show that alt's guild
			return (alt.guildKey and R.GuildBank:Record(alt.guildKey)) or NO_GUILD
		end
		local g = R.GuildBank:Record(key)
		if not g and key then self.guildKey = nil; g = R.GuildBank:Record() end
		return g or NO_GUILD
	end
	local c = self.charKey and R.db.chars[self.charKey]
	if not c then
		self.charKey = nil
		c = R.Data.me
	end
	return c
end

function UI:IsMe() return self:Char() == R.Data.me end

function UI:Interactive()
	if self.kind == "guild" then return false end  -- guild rows act through GuildLive instead
	return self:IsMe() and (self.view == "bags" or R.Data.atBank)
end

-- Guild Bank window showing the vault that is open right now (items can be moved).
function UI:GuildLive()
	return self.kind == "guild" and R.GuildBank:IsLive(self:Char()) and not self.searchAllActive
end

-- Selected guild tab (number) or nil for all tabs.
function UI:GuildTab()
	return self.kind == "guild" and API.GuildTabOf(self.bagFilter) or nil
end

function UI:SetGuildTab(tab)
	self.bagFilter = tab and (API.GUILD_BASE + tab) or nil
	self.offset = 0
	if tab and self:GuildLive() then R.GuildBank:SelectTab(tab) end
	R:RequestRefresh()
end

-- Container list for this window's view.
function UI:BagList()
	if self.view == "guild" then return API.GuildBagList end
	return self.view == "bank" and API.BankBagList or API.InvBagList
end

-- Guild rows: click picks up (or drops the cursor item into the tab), right-click
-- withdraws per the guildRightClick setting, drag picks up. Cached views only link.
function UI:GuildClick(e, button)
	if not e then return end
	if IsModifiedClick and HandleModifiedItemClick and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
	if not self:GuildLive() then return end
	if CursorHasItem and CursorHasItem() then return self:DropCursorItem() end
	local tab, slot = API.GuildTabOf(e.bag), e.slot
	if not tab then return end
	if button == "RightButton" then
		local mode = R.settings.guildRightClick
		if mode ~= "none" then R.GuildBank:Withdraw(tab, slot, mode == "cursor" and "cursor" or "bags") end
	else
		R.GuildBank:Withdraw(tab, slot, "cursor")
	end
end

function UI:GuildDrag(e)
	if not e or not self:GuildLive() then return end
	local tab = API.GuildTabOf(e.bag)
	if tab then R.GuildBank:Withdraw(tab, e.slot, "cursor") end
end

function UI:RowHeight() return R.settings.rowHeight end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function UI:Create()
	W = R.Widgets
	W:UpdateFonts()
	local s = R.settings

	local suffix = self.suffix
	local f = CreateFrame("Frame", "RummageFrame" .. suffix, UIParent, API.Backdrop)
	self.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:EnableMouse(true)
	API.SetResizeBounds(f, 460, 320, 4000, 2400)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not R.settings.locked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); UI:SavePosition() end)
	f:Hide()
	f:SetScript("OnShow", function() UI:OnShow() end)
	f:SetScript("OnHide", function() UI:OnHide() end)
	-- OnSizeChanged fires every frame while dragging the grip: coalesce to one layout per frame.
	f:SetScript("OnSizeChanged", function()
		if f:IsShown() then R:Defer("layout" .. UI.suffix, function() UI:Layout() end) end
	end)
	table.insert(UISpecialFrames, "RummageFrame" .. suffix)

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
	if self.kind == "bags" then
		-- the Bank / Guild header buttons light up while those windows are open
		local function sync() if UI.frame:IsShown() then UI:UpdateTabs() end end
		R:Listen("FRAME_SHOWN", sync)
		R:Listen("FRAME_HIDDEN", sync)
	end
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if UI.pendingCombat then
			UI:SetPending(false)
			UI:ApplyViewLayout(UI:ViewKey())
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
	if self.kind == "guild" then
		W:SetTooltip(charBtn, "Guild", "View the cached guild bank of any guild your characters visited.")
	else
		W:SetTooltip(charBtn, "Character", "View the bags and bank of any of your characters.")
	end
	self.charBtn = charBtn

	-- tabs
	self.tabBags = W:Button(header, R.L.bags, 56, 22, function() UI:SetView("bags") end)
	self.tabBags:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
	self.tabBank = W:Button(header, R.L.bank, 56, 22, function()
		if UI.kind == "bags" then R.BankUI:Toggle() else UI:SetView("bank") end
	end)
	self.tabBank:SetPoint("LEFT", self.tabBags, "RIGHT", 2, 0)
	-- One tab per window: Bags shows only "Bags", the Bank window only "Bank".
	if self.kind == "bank" then
		self.tabBags:Hide()
		self.tabBank:ClearAllPoints()
		self.tabBank:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
	elseif self.kind == "guild" then
		self.tabBags:Hide()
		self.tabBank:Hide()
		-- guild tab selector (the footer's tab icons do the same)
		local tabSel = W:Button(header, R.L.allTabs, 110, 22, function(btn) UI:ShowGuildTabMenu(btn) end)
		tabSel:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
		W:SetTooltip(tabSel, "Guild bank tab", "Choose which tab to list, or all tabs. Items dropped on this window go into the selected tab (or the vault's current tab when showing all).")
		self.tabGuild = tabSel
	else
		-- Bags: Bank and Guild open those windows beside Bags; anywhere, with the cache when away.
		W:SetTooltip(self.tabBank, "Bank window", "Opens the Bank window beside Bags. Away from a banker it shows your cached bank (view-only).")
		local guildBtn = W:Button(header, R.L.guildShort, 50, 22, function() R.GuildUI:Toggle() end)
		guildBtn:SetPoint("LEFT", self.tabBank, "RIGHT", 2, 0)
		W:SetTooltip(guildBtn, "Guild Bank window", "Opens the Guild Bank window beside Bags. Away from the guild vault it shows the cached guild bank (view-only).")
		self.tabGuildToggle = guildBtn
	end

	-- cross-character search toggle (applies while the search box has text)
	local allBtn = W:Button(header, "All", 30, 22, function()
		R.settings.searchAllChars = not R.settings.searchAllChars
		UI:UpdateTabs()
		R:RequestRefresh()
	end)
	allBtn:SetPoint("LEFT", self.tabGuild or self.tabGuildToggle or self.tabBank, "RIGHT", 6, 0)
	W:SetTooltip(allBtn, "Search all characters",
		"When on and you type a search, results come from every character's cached bags and bank. Results are view-only (no item actions) in this mode.")
	self.allBtn = allBtn
	if self.kind == "guild" then allBtn:Hide(); allBtn:SetWidth(1) end

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
	-- clipped to the box (it used to run over the Preset button when the header is crowded)
	hint:SetPoint("RIGHT", search, "RIGHT", -40, 0)
	hint:SetJustifyH("LEFT")
	if hint.SetWordWrap then hint:SetWordWrap(false) end
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
		"\"|\" = OR, \"!\" = NOT, ( ) groups, \"quoted text\" keeps spaces  (!(#junk | q:poor), name:\"linen cloth\")")
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

	local add = W:Button(side, "+ New category", SIDEBAR_W - 8, 18, function()
		if CursorHasItem and CursorHasItem() then return UI:DropOnNewCategory() end
		UI:PromptNewCategory()
	end)
	add:SetScript("OnReceiveDrag", function() UI:DropOnNewCategory() end)
	add:SetPoint("BOTTOM", 0, 4)
	W:SetTooltip(add, "New category", "Creates a custom category from a search query. The current search text is used as the default.\nDrop an item here to start a category holding that item.")
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
	colhead:SetClipsChildren(true)  -- header labels never spill past the list
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
	-- Layout() measures the list right after re-anchoring it, before the new anchors
	-- resolve, so the width it sees can be stale (or 0 on first show). Recompute the
	-- columns once the list's real width is known, or Name stays at its minimum.
	list:SetScript("OnSizeChanged", function(_, w)
		if not (w and w > 0) or w == UI.colListW then return end
		R:Defer("columns" .. UI.suffix, function()
			if not UI.frame or not UI.frame:IsShown() then return end
			UI:ComputeColumns()
			UI:Render()
		end)
	end)
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
	foot:SetPoint("BOTTOMLEFT", PAD + 14, PAD - 2)
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

	local currency = W:Text(foot, "small")
	currency:SetPoint("LEFT", total, "RIGHT", 10, 0)
	self.currencyText = currency

	-- action buttons (right to left)
	self.btnTransfer = W:Button(foot, R.L.transfer, 70, 22, function() UI:DoTransfer() end)
	W:SetTooltip(self.btnTransfer, "Transfer", "Moves every item currently listed (after search/category filters) to the other side: bags to bank, or bank to bags. With the Send Mail tab or a trade open, adds the listed items to it instead (bound items skipped).")
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

	self:CreateGrips()
end

---------------------------------------------------------------------------
-- Position, skin, layout
---------------------------------------------------------------------------
function UI:ApplySkin()
	W:InvalidateTheme()
	local skin = W:Skin()
	local bg = skin.bg
	W:Backdrop(self.frame, "main", { bg[1], bg[2], bg[3], R.settings.alpha })
	W:Backdrop(self.sidebar, "flat", skin.panel, { 0, 0, 0, 0 })
	W:Backdrop(self.colhead, "flat", skin.panel, { 0, 0, 0, 0 })
	W:RefreshButtons()
	self.frame:SetScale(self:Geo().scale)
	W:UpdateFonts()
	if self.frame:IsShown() then self:Layout() end
end

-- Re-anchors the main regions using the active theme's padding.
function UI:RailSide()
	local side = R.settings and R.settings.sidebarSide
	if side == "left" then return "LEFT" end
	if side == "right" then return "RIGHT" end
	if self.kind == "bags" then return "LEFT" end
	return self.railSide or "LEFT"
end

function UI:Anchor()
	local pad = W:Pad()
	self.header:ClearAllPoints()
	self.header:SetPoint("TOPLEFT", pad, -pad)
	self.header:SetPoint("TOPRIGHT", -pad, -pad)
	self.sidebar:ClearAllPoints()
	-- Bank / Guild Bank docked beside Bags keep their rail on the outer edge (railSide).
	if self:RailSide() == "RIGHT" then
		self.sidebar:SetPoint("TOPRIGHT", -pad, -(HEADER_H + pad - 6))
		self.sidebar:SetPoint("BOTTOMRIGHT", -pad, FOOTER_H + pad - 6)
	else
		self.sidebar:SetPoint("TOPLEFT", pad, -(HEADER_H + pad - 6))
		self.sidebar:SetPoint("BOTTOMLEFT", pad, FOOTER_H + pad - 6)
	end
	self.footer:ClearAllPoints()
	self.footer:SetPoint("BOTTOMLEFT", pad + 14, pad - 2)
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
		or g.rh ~= s.rowHeight or g.grid ~= R:GridCellSize() or g.side ~= s.showSidebar
		or g.compact ~= s.compactSidebar or g.cols ~= s.categoryColumns or g.sidePos ~= s.sidebarSide
		or g.theme ~= W:Skin() or g.rail ~= self:RailSide() then
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
	g.rh, g.grid, g.side, g.compact, g.theme = s.rowHeight, R:GridCellSize(), s.showSidebar, s.compactSidebar, W:Skin()
	g.cols, g.sidePos = s.categoryColumns, s.sidebarSide
	g.rail = self:RailSide()
	g.sortKey, g.sortAsc = s.sortKey, s.sortAsc
	self:Anchor()
	local compact = s.compactSidebar
	local columns = max(1, min(3, floor(tonumber(s.categoryColumns) or 1)))
	local columnWidth = compact and SIDEBAR_COMPACT_W or SIDEBAR_W
	local sidebarWidth = columnWidth * columns
	self.sidebar:SetShown(s.showSidebar)
	self.sidebar:SetWidth(sidebarWidth)
	self.addCatBtn:SetWidth(sidebarWidth - 8)
	self.addCatBtn:SetLabel(compact and "+" or "+ New category")
	self.content:ClearAllPoints()
	if s.showSidebar and self:RailSide() == "RIGHT" then
		self.content:SetPoint("TOPLEFT", pad, -(HEADER_H + pad - 6))
		self.content:SetPoint("BOTTOMRIGHT", self.sidebar, "BOTTOMLEFT", -PAD, 0)
	else
		if s.showSidebar then
			self.content:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", PAD, 0)
		else
			self.content:SetPoint("TOPLEFT", pad, -(HEADER_H + pad - 6))
		end
		self.content:SetPoint("BOTTOMRIGHT", -pad, FOOTER_H + pad - 6)
	end
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
	local w = self.list:GetWidth()
	if not w or w <= 0 then w = 400 end  -- not laid out yet; OnSizeChanged recomputes
	return w - SCROLL_W - 2
end

function UI:VisibleRows()
	local h = self.list:GetHeight() or 300
	if R.settings.viewMode == "grid" then
		return math.max(1, math.floor(h / (R:GridCellSize() + 2)))
	end
	return math.max(1, math.floor(h / self:RowHeight()))
end

function UI:GridPerRow()
	local size = R:GridCellSize() + 2
	return math.max(1, math.floor(self:ListWidth() / size))
end

---------------------------------------------------------------------------
-- Columns layout & headers
---------------------------------------------------------------------------
function UI:ComputeColumns()
	local cols = R.Columns:Visible()
	local width = self:ListWidth()
	self.colListW = self.list:GetWidth()
	local fixed, flexCol = 0, nil
	for _, col in ipairs(cols) do
		-- A flex column fills the leftover space until the user drags it to a width.
		if col.flex and not R.settings.columns.widths[col.key] then flexCol = col else
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
	-- Columns that don't fit the window are left out instead of being drawn half over the
	-- scrollbar and the window edge (the name column always stays).
	local fitted = {}
	for _, L in ipairs(layout) do
		if L.x + L.w <= width + 2 or L.col == flexCol or L.col.key == "name" then fitted[#fitted + 1] = L end
	end
	self.colLayout = fitted
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
			h:SetWidth(10)
			h:SetPoint("TOPRIGHT", 5, 0)
			h:SetPoint("BOTTOMRIGHT", 5, 0)
			h:SetFrameLevel(b:GetFrameLevel() + 5)
			h:EnableMouse(true)
			h.tex = h:CreateTexture(nil, "OVERLAY")
			h.tex:SetColorTexture(1, 1, 1, 0.15)
			h.tex:SetPoint("TOP")
			h.tex:SetPoint("BOTTOM")
			h.tex:SetWidth(1)
			h:SetScript("OnEnter", function(self)
				self.tex:SetColorTexture(1, 0.82, 0.2, 0.9)
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
				GameTooltip:AddLine("Drag to resize the column")
				GameTooltip:AddLine("Double-click to reset it", 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end)
			h:SetScript("OnLeave", function(self)
				if not UI.resizing then self.tex:SetColorTexture(1, 1, 1, 0.15) end
				GameTooltip:Hide()
			end)
			h:SetScript("OnMouseDown", function()
				local now = GetTime and GetTime() or 0
				if h.lastDown and now - h.lastDown < 0.4 then
					h.lastDown = nil
					R.settings.columns.widths[b.colKey] = nil
					UI:Layout()
					return
				end
				h.lastDown = now
				local x = GetCursorPosition() / b:GetEffectiveScale()
				UI.resizing = { key = b.colKey, startX = x, startW = b:GetWidth(), button = b }
				UI.colhead:SetScript("OnUpdate", function() UI:ResizeColumnUpdate() end)
			end)
			h:SetScript("OnMouseUp", function(self)
				self.tex:SetColorTexture(1, 1, 1, 0.15)
				UI:EndResize()
			end)
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
b.handle:SetShown(col.kind ~= "icon" and col.kind ~= "fav" and col.kind ~= "junk")
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
	local w = math.min(1200, math.max(r.key == "name" and 60 or 20, math.floor(r.startW + (x - r.startX))))
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
	if API.IsGuildBag(bag) then return 200 + API.GuildTabOf(bag) end
	return 999
end

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then
		self.dirty = true
		return
	end
	if InCombatLockdown() and self.protectedButtons then
		self:SetPending(true)
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
	self.searchAllActive = R.settings.searchAllChars and self.search ~= "" and self.kind ~= "guild" or false
	local entries
	if self.searchAllActive then
		entries = self:BuildAllChars(self.view)
	else
		entries = Items:Build(char, self.view, self)
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
		if API.IsGuildBag(b) then
			local rec = self:Char().containers[b]
			if not bagKey[b] then bagKey[b] = "b" .. b end
			return bagKey[b], bagOrder(b), (rec and rec.name) or API.BagLabel(b)
		end
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
-- Render visible slice
---------------------------------------------------------------------------
function UI:Render()
	if not self.frame or not self.frame:IsShown() then return end
	if InCombatLockdown() and self.protectedButtons then
		self:SetPending(true)
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

	local rh = grid and (R:GridCellSize() + 2) or self:RowHeight()
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
			row:SetHeight(d and d.header and 20 or R:GridCellSize())
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
				if d == self.selected then self:Highlight(row, true) end
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
		for _, bag in ipairs(self:BagList()) do
			if char.containers[bag] then cached = true; break end
		end
		if self.view == "guild" and not cached then
			text = (char == NO_GUILD and NO_GUILD.name == R.L.noGuild) and R.L.notInGuild or R.L.emptyGuild
		elseif self.view == "bank" and not cached then
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

-- Drop the item on the cursor into the first free slot of the current view.
function UI:DropCursorItem()
	if not (CursorHasItem and CursorHasItem()) then return end
	if self.kind == "guild" then
		if self:GuildLive() then return R.GuildBank:Deposit(self:GuildTab()) end
		R:Print(R.L.cachedDropGuild)
		return
	end
	if self.kind == "bank" and not self:Interactive() then
		R:Print(R.L.cachedDropBank)
		return
	end
	if not self:Interactive() or self.searchAllActive then return end
	local list = self:BagList()
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
-- Small helpers
---------------------------------------------------------------------------
function UI:TintUnusable(tex, e)
	if R.settings.tintUnusable and e.info and not R.Items:Usable(e) then
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
function UI:Open()
	if not self.frame:IsShown() then
		self.frame:Show()
	else
		R:RequestRefresh()
	end
end

function UI:Close()
	self.frame:Hide()
end

function UI:Toggle()
	if self.frame:IsShown() then
		self:Close()
	else
		self:Open(view)
	end
end

function UI:OnShow()
	R.Integrations:ResetPawn()
	if R.settings.resetSearchOnOpen and self.search ~= "" then self.searchBox:SetText("") end
	if not R.settings.rememberCategory then
		self:SetCategory("all"); self.subfilter = nil
		-- the Guild Bank's tab choice is set by the vault (guildDefaultTab), not a bag filter to forget
		if self.kind ~= "guild" then self.bagFilter = nil end
	end
	if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
	self:ApplySkin()
	-- Bank / Guild Bank open beside Bags; Bags opening pulls already-open ones beside it.
	if self.kind == "bags" then self:DockAll() else self:DockBesideBags() end
	self:Refresh()
	R:Fire("FRAME_SHOWN")
end

function UI:OnHide()
	W.HideMenu()
	self.autoOpened = false
	if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
	if R.settings.clearNewOnClose then R.Data:ClearNew() end
	self.searchBox:ClearFocus()
	-- Only the Bank window closes the banker; hiding Bags leaves the bank open.
	if self.kind == "bank" and R.Data.atBank and R.settings.replaceBank and CloseBankFrame then
		CloseBankFrame()
	end
	-- Likewise only the Guild Bank window closes the guild vault.
	if self.kind == "guild" and R.GuildBank.atBank and R.settings.replaceGuildBank then
		R.GuildBank.Call("CloseGuildBankFrame")
	end
	R:Fire("FRAME_HIDDEN")
end
end
