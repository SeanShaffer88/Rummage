-- Rummage: settings window (tabs: General, Appearance, Items, Columns, Categories, About).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local O = {}
R.Options = O

local W
local WIDTH, HEIGHT = 560, 600
local COL2 = 280

local function S() return R.settings end
-- Sliders fire OnValueChanged continuously while dragged; re-skinning the main window on
-- every tick was the most expensive thing the options panel did. Coalesce to once per frame.
local function DoRelayout() R.UI:ApplySkin(); R:RequestRefresh() end
local function Relayout() R:Defer("optionsRelayout", DoRelayout) end

local function Cycle(list, current, dir)
	local idx = 1
	for i, v in ipairs(list) do if v == current then idx = i; break end end
	idx = ((idx - 1 + (dir or 1)) % #list) + 1
	return list[idx]
end

---------------------------------------------------------------------------
-- Layout helper: places widgets top-down in two columns
---------------------------------------------------------------------------
local function Stacker(parent)
	local st = { y = { [0] = -8, [1] = -8 }, col = 0, widgets = {}, headers = {} }
	function st:Col(c) self.col = c end
	function st:Place(w, h, gap)
		w:SetPoint("TOPLEFT", parent, "TOPLEFT", 12 + self.col * COL2, self.y[self.col])
		self.y[self.col] = self.y[self.col] - (h or 22) - (gap or 4)
		self.widgets[#self.widgets + 1] = w
		return w
	end
	function st:Header(text)
		local fs = W:Text(parent, "title")
		fs:SetText(text)
		local skin = W:Skin()
		fs:SetTextColor(skin.accent[1], skin.accent[2], skin.accent[3])
		self.headers[#self.headers + 1] = fs
		self.y[self.col] = self.y[self.col] - 4
		fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12 + self.col * COL2, self.y[self.col])
		self.y[self.col] = self.y[self.col] - 20
		return fs
	end
	function st:Check(label, key, tip, onChange, tbl)
		local t = tbl or S()
		local c = W:Check(parent, label, function() return t[key] end, function(v)
			t[key] = v
			if onChange then onChange(v) else R:RequestRefresh() end
		end, tip)
		c:SetWidth(COL2 - 16)
		return self:Place(c, 20, 2)
	end
	function st:Slider(label, key, a, b, step, fmt, onChange)
		local s = W:Slider(parent, label, a, b, step, function() return S()[key] end, function(v)
			S()[key] = v
			if onChange then onChange(v) end
		end, fmt)
		return self:Place(s, 34, 6)
	end
	function st:CycleButton(labelFn, onClick, tip)
		local b = W:Button(parent, "", COL2 - 30, 20, function(btn, mouse)
			onClick(mouse == "RightButton" and -1 or 1)
			btn:SetLabel(labelFn())
		end)
		b:SetLabel(labelFn())
		b.Update = function(self) self:SetLabel(labelFn()) end
		if tip then W:SetTooltip(b, tip, "Click: next  ·  Right-click: previous") end
		return self:Place(b, 20, 6)
	end
	function st:Note(text)
		local fs = W:Text(parent, "small")
		fs:SetWidth(COL2 - 24)
		fs:SetWordWrap(true)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		fs:SetTextColor(0.65, 0.65, 0.65)
		return self:Place(fs, fs:GetStringHeight() + 2, 6)
	end
	return st
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local builders = {}

builders.general = function(p)
	local st = Stacker(p)
	st:Header("Window")
	st:Check("Replace Blizzard bags", "replaceBags", "Requires /reload to take full effect.", function() O:NeedReload() end)
	st:Check("Replace Blizzard bank", "replaceBank", "Requires /reload to take full effect.", function() O:NeedReload() end)
	st:Check("Lock window position", "locked", "Prevents moving and resizing.")
	st:Check("Clear search when opened", "resetSearchOnOpen")
	st:Check("Remember last selected category", "rememberCategory",
		"On: the bag reopens on the category you used last, even after logging out. Off: it always opens on All Items.",
		function(v) if v then S().lastCategory = R.UI.category or "all" end end)
	st:Check("Clear \"new\" marks when closed", "clearNewOnClose")
	st:Check("Minimap button", "show", nil, function() R.Minimap:Update() end, S().minimap)
	local reset = W:Button(p, "Reset window position", COL2 - 30, 20, function() R.UI:ResetPosition() end)
	st:Place(reset, 20, 8)

	st:Header("Keybinds")
	st:Check("Open All Bags key opens Rummage", "takeoverKeybinds",
		"Your \"Open All Bags\" keybind opens this window instead. Uses override bindings: your saved keybinds are untouched.",
		function() R.Hooks:ApplyBindings(true) end)
	st:Check("Also backpack / single-bag keys", "takeoverBagKeys",
		"Routes Toggle Backpack and Toggle Bag 1-5 keys (e.g. B, F8-F12) here too.",
		function() R.Hooks:ApplyBindings(true) end)
	st:Note("Dedicated bindings: Esc > Options > Keybindings > AddOns > Rummage.")

	st:Col(1)
	st:Header("Open automatically at")
	local ao = S().autoOpen
	st:Check("Merchant", "merchant", nil, nil, ao)
	st:Check("Mailbox", "mail", nil, nil, ao)
	st:Check("Auction House", "auction", nil, nil, ao)
	st:Check("Trade window", "trade", nil, nil, ao)
	st:Check("Banker (opens Bank tab)", "bank", nil, nil, ao)
	st:Check("Other Blizzard \"open bags\" calls", "other", nil, nil, ao)

	st:Header("Safety")
	st:Check("Warn about conflicting bag addons", "warnConflicts")
	local chk = W:Button(p, "Check for conflicts now", COL2 - 30, 20, function() R.Hooks:CheckConflicts(true) end)
	st:Place(chk, 20, 6)
	st:Slider("Low bag space warning at", "lowSpaceWarn", 0, 20, 1, function(v) return v == 0 and "off" or (v .. " free") end)
	st:Check("Search all characters while searching", "searchAllChars",
		"While the search box has text, results come from every character's cached bags (the 'All' button in the window header does the same). Results are view-only in this mode.")

	st:Header("Profiles")
	local profName = W:EditBox(p, COL2 - 30, 20)
	profName:SetText(R.db.profileName or "")
	st:Place(profName, 20, 4)
	local profSave = W:Button(p, "Save current settings as profile", COL2 - 30, 20, function()
		local n = profName:GetText() or ""
		if n ~= "" and R:SaveProfile(n) then R:Print("Profile '" .. n .. "' saved.") end
	end)
	st:Place(profSave, 20, 4)
	local profPick = W:Button(p, "Apply / delete profile...", COL2 - 30, 20, function(btn)
		local items = { { text = "Profiles", isTitle = true } }
		local names = {}
		for n in pairs(R.db.profiles) do names[#names + 1] = n end
		table.sort(names)
		if #names == 0 then items[#items + 1] = { text = "(none saved)", disabled = true } end
		for _, n in ipairs(names) do
			items[#items + 1] = {
				text = n, checked = R.db.profileName == n,
				func = function() R:ApplyProfile(n); profName:SetText(n) end,
				onDelete = function() R:DeleteProfile(n) end,
			}
		end
		R.Widgets:Menu(btn, items)
	end)
	st:Place(profPick, 20, 4)
	st:Check("Per-character profiles", "profilePerChar",
		"On: each character automatically re-applies the profile last used on it at login.")
	return st
end

builders.appearance = function(p)
	local st = Stacker(p)
	st:Header("Theme")
	st:CycleButton(function()
		local n = S().skin
		local t = W.themes[n]
		if n == "Auto" then return "Theme: Auto (" .. W:AutoTheme() .. ")" end
		return "Theme: " .. (t and t.label or n)
	end, function(dir)
		S().skin = Cycle(W.themeOrder, S().skin, dir)
		O:Rebuild()
		Relayout()
	end, "Theme")
	st:Check("Class-colored accent", "classAccent", nil, function() O:Rebuild(); Relayout() end)
	st:CycleButton(function()
		local f = S().font
		return "Font: " .. ((f == nil or f == "") and "Theme default" or f)
	end, function(dir)
		S().font = Cycle(W:FontList(), S().font or "", dir)
		Relayout()
	end, "Font (includes LibSharedMedia fonts)")
	st:Slider("Font size", "fontSize", 8, 18, 1, nil, Relayout)
	st:Slider("Scale", "scale", 0.6, 1.6, 0.05, function(v) return format("%.2f", v) end, Relayout)
	st:Slider("Background opacity", "alpha", 0.2, 1, 0.05, function(v) return format("%d%%", v * 100) end, Relayout)

	st:Header("Layout")
	st:Check("Show category sidebar", "showSidebar", nil, Relayout)
	st:Check("Compact sidebar (icons only)", "compactSidebar", nil, Relayout)
	st:Check("Hide empty categories", "hideEmptyCategories")

	st:Col(1)
	st:Header("Items")
	st:CycleButton(function() return "View: " .. (S().viewMode == "grid" and "Grid" or "List") end,
		function() S().viewMode = S().viewMode == "grid" and "list" or "grid"; Relayout() end, "View mode")
	local groups = { "none", "category", "type", "quality", "bag" }
	st:CycleButton(function() return "Group by: " .. S().groupBy end,
		function(dir) S().groupBy = Cycle(groups, S().groupBy, dir); R:RequestRefresh() end, "Grouping")
	st:Slider("Row height (list)", "rowHeight", 16, 34, 1, nil, Relayout)
	st:Slider("Icon size (grid)", "gridSize", 26, 56, 2, nil, Relayout)
	st:Check("Combine identical stacks", "combineStacks")
	st:Check("Favorites always on top", "favoritesFirst")
	st:Check("New items on top", "newFirst")
	st:Check("Tint items you can't use yet", "tintUnusable")
	st:Check("Quest-starter badges", "questBadges")
	st:Check("Item level on grid icons", "gridItemLevel")
	return st
end

builders.items = function(p)
	local st = Stacker(p)
	st:Header("Junk & merchants")
	st:Check("Sell junk automatically at merchants", "autoSellJunk")
	st:Check("Use Scrap's junk list (if installed)", "useScrap")
	st:Check("Never sell favorites", "protectFavorites")
	st:Check("Buyback-safe (sell max 12 per visit)", "buybackSafe", "Sells only the 12 most valuable junk items so every sale can still be bought back.")
	st:Check("Auto-repair at merchants", "autoRepair")
	st:Check("Prefer guild funds for repairs", "autoRepairGuild")
	st:Note("Mark junk: click the coin column, or Alt+right-click an item. Grey items are junk by default.")
	local rulesBtn = W:Button(p, "Auto-junk rules...", COL2 - 30, 20, function(btn)
		local items = { { text = "Auto-junk rules (search syntax)", isTitle = true } }
		local rules = R.db.junkRules
		if #rules == 0 then items[#items + 1] = { text = "(none)", disabled = true } end
		for i, q in ipairs(rules) do
			items[#items + 1] = {
				text = q,
				onDelete = function()
					table.remove(R.db.junkRules, i)
					R:RequestRefresh()
				end,
			}
		end
		if #rules < 8 then
			items[#items + 1] = { text = "Add rule...", func = function() StaticPopup_Show("RUMMAGE_ADD_JUNK_RULE") end }
		end
		R.Widgets:Menu(btn, items)
	end)
	st:Place(rulesBtn, 20, 6)
	st:Note("Items matching a rule count as junk. Favorites are never junk by rule; manual marks win. Example: q:poor ilvl<5")

	st:Header("Values")
	st:Check("Price columns show whole stack", "stackValue")
	local lbl = W:Text(p, "normal")
	lbl:SetText("TSM price source:")
	st:Place(lbl, 16, 2)
	local eb = W:EditBox(p, COL2 - 30, 20)
	eb:SetText(S().tsmSource or "DBMarket")
	eb:SetScript("OnEnterPressed", function(self)
		local v = self:GetText()
		if v and v ~= "" then S().tsmSource = v end
		self:ClearFocus()
		R:RequestRefresh()
	end)
	st:Place(eb, 20, 6)

	st:Col(1)
	st:Header("Tooltips")
	local function tipChanged() R:Fire("DATA_CHANGED") end
	st:Check("Item counts from all characters", "tooltipCounts", nil, tipChanged)
	st:Check("...even when Syndicator is installed", "tooltipWithSyndicator", nil, tipChanged)
	st:Check("Only characters on this realm", "tooltipRealmOnly", nil, tipChanged)

	st:Header("Upgrade popup")
	st:Check("Show when I loot an upgrade", "upgradePopup",
		"A small popup appears when new gear is better than what you're wearing, with a one-click Equip button.")
	st:Check("Judge by item level without Pawn", "upgradeIlvlFallback",
		"With Pawn installed, Pawn decides. Without it, higher item level for your armor type counts as an upgrade.")
	st:Check("Play a sound", "upgradeSound")
	st:Slider("Hide after", "upgradeDuration", 0, 60, 5, function(v) return v == 0 and "never" or (v .. "s") end)
	local prev = W:Button(p, "Preview / move popup", COL2 - 30, 20, function() R.Upgrade:Test() end)
	st:Place(prev, 20, 4)
	local rpos = W:Button(p, "Reset popup position", COL2 - 30, 20, function() R.Upgrade:ResetPosition() end)
	st:Place(rpos, 20, 4)
	local unign = W:Button(p, "Clear ignored upgrades", COL2 - 30, 20, function()
		wipe(R.db.upgradeIgnore); R:Print("Ignored upgrades cleared.")
	end)
	st:Place(unign, 20, 8)

	st:Header("Data")
	local forget = W:Button(p, "Forget a character...", COL2 - 30, 20, function(btn) R.UI:ShowCharMenu(btn) end)
	st:Place(forget, 20, 6)
	local unfav = W:Button(p, "Clear all favorites", COL2 - 30, 20, function()
		wipe(R.db.favorites); R:RequestRefresh(); R:Print("Favorites cleared.")
	end)
	st:Place(unfav, 20, 6)
	local unjunk = W:Button(p, "Clear junk overrides", COL2 - 30, 20, function()
		wipe(R.db.junk); R:RequestRefresh(); R:Print("Junk overrides cleared.")
	end)
	st:Place(unjunk, 20, 6)
	local resetAll = W:Button(p, "|cffff6060Reset all settings|r", COL2 - 30, 20, function()
		R:ResetSettings(); R.UI:ApplyPosition(); O:Rebuild(); Relayout()
	end)
	st:Place(resetAll, 20, 6)
	return st
end

builders.columns = function(p)
	local st = Stacker(p)
	st:Header("Columns (order top to bottom = left to right)")
	local cfg = S().columns
	local rows = {}
	local function build()
		for _, r in ipairs(rows) do r:Hide() end
		local i = 0
		for _, key in ipairs(cfg.order) do
			local col = R.Columns.byKey[key]
			if col and (not col.available or col.available()) then
				i = i + 1
				local r = rows[i]
				if not r then
					r = CreateFrame("Frame", nil, p)
					r:SetSize(WIDTH - 40, 22)
					r:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 24)
					r.check = W:Check(r, "", function() return not cfg.hidden[r.key] end, function(v)
						cfg.hidden[r.key] = (not v) or nil
						R.UI:Layout()
					end)
					r.check:SetPoint("LEFT")
					r.up = W:Button(r, "Up", 36, 18, function() R.Columns:Move(r.key, -1); build(); R.UI:Layout() end)
					r.up:SetPoint("LEFT", 300, 0)
					r.down = W:Button(r, "Down", 44, 18, function() R.Columns:Move(r.key, 1); build(); R.UI:Layout() end)
					r.down:SetPoint("LEFT", r.up, "RIGHT", 4, 0)
					r.width = W:Text(r, "small")
					r.width:SetPoint("LEFT", r.down, "RIGHT", 10, 0)
					rows[i] = r
				end
				r.key = key
				local label = col.label or col.title or key
				r.label = r.label or W:Text(r, "normal")
				r.label:SetPoint("LEFT", 26, 0)
				r.label:SetText(label)
				r.check:Update()
				r.check:SetEnabled(not col.fixed)
				r.width:SetText(col.flex and "fills" or (R.Columns:Width(col) .. "px"))
				r:Show()
			end
		end
	end
	build()
	local reset = W:Button(p, "Reset widths", 100, 20, function() wipe(cfg.widths); build(); R.UI:Layout() end)
	reset:SetPoint("BOTTOMLEFT", 12, 12)
	local note = W:Text(p, "small")
	note:SetPoint("LEFT", reset, "RIGHT", 10, 0)
	note:SetText("Tip: right-click a column header to toggle, drag its edge to resize.")
	note:SetTextColor(0.65, 0.65, 0.65)
	return st
end

builders.categories = function(p)
	local st = Stacker(p)
	st:Header("Custom categories")
	local rows = {}
	local add
	local function build()
		for _, r in ipairs(rows) do r:Hide() end
		for i, def in ipairs(R.db.categories) do
			local r = rows[i]
			if not r then
				r = CreateFrame("Frame", nil, p)
				r:SetSize(WIDTH - 30, 24)
				r:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 26)
				r.name = W:EditBox(r, 130, 20)
				r.name:SetPoint("LEFT")
				r.query = W:EditBox(r, 230, 20)
				r.query:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
				local function save()
					local d = R.db.categories[r.idx]
					if d then
						d.name = r.name:GetText() ~= "" and r.name:GetText() or d.name
						d.query = r.query:GetText() or ""
						R:RequestRefresh()
					end
				end
				r.name:SetScript("OnEnterPressed", function(self) save(); self:ClearFocus() end)
				r.query:SetScript("OnEnterPressed", function(self) save(); self:ClearFocus() end)
				r.name:SetScript("OnEditFocusLost", save)
				r.query:SetScript("OnEditFocusLost", save)
				r.up = W:Button(r, "Up", 30, 20, function() R.Categories:MoveCustom(r.idx, -1); build(); R:RequestRefresh() end)
				r.up:SetPoint("LEFT", r.query, "RIGHT", 4, 0)
				r.down = W:Button(r, "Dn", 30, 20, function() R.Categories:MoveCustom(r.idx, 1); build(); R:RequestRefresh() end)
				r.down:SetPoint("LEFT", r.up, "RIGHT", 2, 0)
				r.del = W:Button(r, "|cffff6060X|r", 22, 20, function()
					R.Categories:RemoveCustom(r.idx); build(); R:RequestRefresh()
				end)
				r.del:SetPoint("LEFT", r.down, "RIGHT", 2, 0)
				rows[i] = r
			end
			r.idx = i
			r.name:SetText(def.name or "")
			r.query:SetText(def.query or "")
			r:Show()
		end
		add:ClearAllPoints()
		add:SetPoint("TOPLEFT", 12, -38 - #R.db.categories * 26)
	end
	add = W:Button(p, "+ Add category", 120, 20, function()
		R.Categories:AddCustom("New category", "")
		build()
		R:RequestRefresh()
	end)
	local help = W:Text(p, "small")
	help:SetPoint("BOTTOMLEFT", 12, 12)
	help:SetWidth(WIDTH - 40)
	help:SetWordWrap(true)
	help:SetJustifyH("LEFT")
	help:SetTextColor(0.65, 0.65, 0.65)
	help:SetText("Filters use search syntax. Examples:\n" ..
		"  #boe q>=uncommon      bind-on-equip greens and better\n" ..
		"  type:consumable | #quest     consumables or quest items\n" ..
		"  ilvl>=40 !#bound      unbound gear, item level 40+\n" ..
		"  value>5g              anything worth over 5 gold at a vendor")
	build()
	return st
end

builders.about = function(p)
	local st = Stacker(p)
	st:Header("Rummage " .. R.version)
	st:Note("A list-view bag and bank replacement for WoW Forever by Malikor. Licensed GPLv3.")
	st:Header("Integrations detected")
	st:Note(R.Integrations:Summary())
	st:Note("Supported: Auctionator, TradeSkillMaster, Pawn, Can I Mog It?, Scrap, Syndicator, LibSharedMedia, LibDataBroker/LibDBIcon. Themes adapt to ElvUI, EllesmereUI, GW2 UI, Tukui and NDui.")
	st:Header("Keybinds")
	st:Note("Routed to Rummage: " .. (R.Hooks:BoundKeys() or "none"))
	st:Header("Slash commands")
	st:Note("/rum  toggle bags\n/rum bank  toggle bank\n/rum search <text>\n/rum config\n/rum restack\n/rum sell\n/rum conflicts\n/rum reset  (window position)\n/rum export · /rum import <string>")
	st:Header("Settings sharing")
	local expB = W:Button(p, "Export settings...", COL2 - 30, 20, function() StaticPopup_Show("RUMMAGE_EXPORT_SETTINGS") end)
	st:Place(expB, 20, 4)
	local impB = W:Button(p, "Import settings...", COL2 - 30, 20, function() StaticPopup_Show("RUMMAGE_IMPORT_SETTINGS") end)
	st:Place(impB, 20, 4)
	st:Note("The string covers settings, columns, custom categories and auto-junk rules. Favorites, junk marks and character caches are not included.")
	st:Header("Mouse")
	st:Note("Alt+click item: cycle favorite marker\nAlt+right-click item: toggle junk\nClick a bag icon: show only that bag  ·  right-click: empty it\nDrag items onto empty list space to drop them in a free slot")
	return st
end

local TABS = {
	{ "general", R.L.tabGeneral }, { "appearance", R.L.tabAppearance }, { "items", R.L.tabItems },
	{ "columns", R.L.tabColumns }, { "categories", R.L.tabCategories }, { "about", R.L.tabAbout },
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function O:Create()
	W = R.Widgets
	local f = CreateFrame("Frame", "RummageOptions", UIParent, API.Backdrop)
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "RummageOptions")
	self.frame = f

	f.title = W:Text(f, "title")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetText("|cffd9a441Rummage|r Settings")
	local close = W:Button(f, "X", 22, 22, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -8)

	self.tabButtons = {}
	local prev
	for _, t in ipairs(TABS) do
		local b = W:Button(f, t[2], 80, 22, function() O:Show(t[1]) end)
		b:FitText(18)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 10, -38) end
		prev = b
		self.tabButtons[t[1]] = b
	end
	self.reloadNote = W:Text(f, "small")
	self.reloadNote:SetPoint("BOTTOMRIGHT", -14, 10)
	self.reloadNote:SetTextColor(1, 0.4, 0.4)
	self.pages = {}
end

function O:NeedReload()
	if self.reloadNote then self.reloadNote:SetText("Some changes need /reload") end
end

-- Refreshes every built page in place (theme colors, labels, values). Pages are never
-- rebuilt: WoW frames can't be destroyed, so rebuilding leaked every widget each time.
function O:Rebuild()
	if not self.frame then return end
	W:InvalidateTheme()
	W:Backdrop(self.frame, "main")
	W:RefreshButtons()
	local skin = W:Skin()
	for _, page in pairs(self.pages) do
		local st = page.stacker
		if st then
			for _, fs in ipairs(st.headers) do fs:SetTextColor(skin.accent[1], skin.accent[2], skin.accent[3]) end
			for _, w in ipairs(st.widgets) do
				if w.Update then w:Update() end
			end
		end
	end
end

function O:Show(tab)
	if not self.frame then self:Create() end
	W:Backdrop(self.frame, "main")
	tab = tab or self.current or "general"
	for key, page in pairs(self.pages) do page:SetShown(key == tab) end
	if not self.pages[tab] then
		local page = CreateFrame("Frame", nil, self.frame)
		page:SetPoint("TOPLEFT", 4, -66)
		page:SetPoint("BOTTOMRIGHT", -4, 28)
		page.stacker = builders[tab](page)
		self.pages[tab] = page
	end
	for key, b in pairs(self.tabButtons) do b:SetActive(key == tab) end
	self.current = tab
	self.frame:Show()
end

function O:Toggle()
	if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

-- Entry in Blizzard's AddOns settings list
function O:Init()
	StaticPopupDialogs["RUMMAGE_ADD_JUNK_RULE"] = {
		text = "Auto-junk rule (search syntax). Matching items count as junk:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 120,
		OnShow = function(self)
			local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
			local q = eb and (eb:GetText() or ""):match("^%s*(.-)%s*$") or ""
			if q ~= "" and #R.db.junkRules < 8 then
				R.db.junkRules[#R.db.junkRules + 1] = q
				R:RequestRefresh()
				R:Print("Auto-junk rule added: " .. q)
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_ADD_JUNK_RULE"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}

	local panel = CreateFrame("Frame")
	panel.name = "Rummage"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Rummage")
	local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btn:SetSize(200, 26)
	btn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	btn:SetText("Open Rummage settings")
	btn:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
		O:Show()
	end)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local cat = Settings.RegisterCanvasLayoutCategory(panel, "Rummage")
		Settings.RegisterAddOnCategory(cat)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end
