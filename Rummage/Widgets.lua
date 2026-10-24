-- Rummage: skins and small UI widgets (template-light so they work on any client).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local W = {}
R.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8x8"

---------------------------------------------------------------------------
-- Themes
--   style "nineslice": uses the client's own modern Blizzard frame art (matches WoW Forever)
--   style "flat":      1px pixel borders (ElvUI/Tukui/NDui family)
--   style "tooltip":   classic tooltip border
-- A theme may define live(t) to pull colors/fonts from its suite when that suite is loaded.
---------------------------------------------------------------------------
local function arr(c) return { c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a or 1 } end

W.themes = {
	Forever = {
		label = "Forever (Blizzard)", style = "nineslice", pad = 8,
		nineSlice = { "SimplePanelTemplate", "ButtonFrameTemplateNoPortrait", "PortraitFrameTemplate" },
		bgTile = "Interface\\FrameGeneral\\UI-Background-Rock",
		bg = { 0.55, 0.55, 0.6, 1 }, border = { 0.6, 0.55, 0.45, 1 },
		panel = { 0, 0, 0, 0.35 }, rowAlt = { 1, 1, 1, 0.035 }, hover = { 1, 0.82, 0, 0.09 },
		accent = { 1, 0.82, 0 }, button = { 0.09, 0.08, 0.07, 0.95 }, buttonHover = { 0.2, 0.16, 0.08, 1 },
		buttonBorder = { 0.48, 0.4, 0.26, 1 }, text = { 1, 1, 1 }, dim = { 0.74, 0.72, 0.68 },
	},
	ElvUI = {
		label = "ElvUI", style = "flat", pad = 6, suite = "ElvUI",
		bg = { 0.1, 0.1, 0.1, 1 }, border = { 0, 0, 0, 1 },
		panel = { 0.06, 0.06, 0.06, 0.8 }, rowAlt = { 1, 1, 1, 0.025 }, hover = { 1, 1, 1, 0.07 },
		accent = { 0.09, 0.52, 0.82 }, button = { 0.1, 0.1, 0.1, 1 }, buttonHover = { 0.16, 0.16, 0.16, 1 },
		buttonBorder = { 0, 0, 0, 1 }, text = { 1, 1, 1 }, dim = { 0.62, 0.62, 0.62 },
		live = function(t)
			local ok, E = pcall(function() return _G.ElvUI and unpack(_G.ElvUI) end)
			local m = ok and E and E.media
			if not m then return end
			if type(m.backdropcolor) == "table" then t.bg = arr(m.backdropcolor); t.button = arr(m.backdropcolor) end
			if type(m.bordercolor) == "table" then t.border = arr(m.bordercolor); t.buttonBorder = arr(m.bordercolor) end
			if type(m.backdropfadecolor) == "table" then t.panel = arr(m.backdropfadecolor) end
			if type(m.rgbvaluecolor) == "table" then t.accent = arr(m.rgbvaluecolor) end
			if type(m.normFont) == "string" then t.font = m.normFont end
		end,
	},
	EllesmereUI = {
		label = "EllesmereUI", style = "flat", pad = 6, suite = "EllesmereUI",
		bg = { 0.055, 0.06, 0.075, 0.9 }, border = { 1, 1, 1, 0.08 },
		panel = { 1, 1, 1, 0.025 }, rowAlt = { 1, 1, 1, 0.02 }, hover = { 0.5, 0.75, 1, 0.08 },
		accent = { 0.55, 0.8, 1 }, button = { 1, 1, 1, 0.04 }, buttonHover = { 1, 1, 1, 0.09 },
		buttonBorder = { 1, 1, 1, 0.1 }, text = { 0.95, 0.96, 0.98 }, dim = { 0.6, 0.63, 0.68 },
	},
	["GW2 UI"] = {
		label = "GW2 UI", style = "flat", pad = 6, suite = "GW2_UI",
		bg = { 0.07, 0.06, 0.05, 0.95 }, border = { 0.33, 0.27, 0.19, 1 },
		panel = { 0.2, 0.16, 0.1, 0.25 }, rowAlt = { 1, 0.9, 0.7, 0.03 }, hover = { 1, 0.76, 0.33, 0.1 },
		accent = { 1, 0.76, 0.33 }, button = { 0.13, 0.11, 0.09, 1 }, buttonHover = { 0.22, 0.18, 0.12, 1 },
		buttonBorder = { 0.38, 0.31, 0.2, 1 }, text = { 0.97, 0.94, 0.88 }, dim = { 0.7, 0.65, 0.55 },
	},
	Tukui = {
		label = "Tukui", style = "flat", pad = 6, suite = "Tukui", classAccent = true,
		bg = { 0.11, 0.11, 0.11, 1 }, border = { 0.27, 0.27, 0.27, 1 },
		panel = { 0, 0, 0, 0.3 }, rowAlt = { 1, 1, 1, 0.025 }, hover = { 1, 1, 1, 0.07 },
		accent = { 0.99, 0.48, 0.17 }, button = { 0.11, 0.11, 0.11, 1 }, buttonHover = { 0.18, 0.18, 0.18, 1 },
		buttonBorder = { 0.27, 0.27, 0.27, 1 }, text = { 1, 1, 1 }, dim = { 0.62, 0.62, 0.62 },
	},
	NDui = {
		label = "NDui", style = "flat", pad = 6, suite = "NDui", classAccent = true,
		bg = { 0, 0, 0, 0.55 }, border = { 0, 0, 0, 1 },
		panel = { 0, 0, 0, 0.3 }, rowAlt = { 1, 1, 1, 0.025 }, hover = { 1, 1, 1, 0.08 },
		accent = { 0.4, 0.75, 1 }, button = { 0, 0, 0, 0.5 }, buttonHover = { 1, 1, 1, 0.1 },
		buttonBorder = { 0, 0, 0, 1 }, text = { 1, 1, 1 }, dim = { 0.65, 0.65, 0.65 },
	},
	Dark = {
		label = "Minimal Dark", style = "flat", pad = 6,
		bg = { 0.05, 0.05, 0.06, 1 }, border = { 0.22, 0.22, 0.25, 1 },
		panel = { 1, 1, 1, 0.03 }, rowAlt = { 1, 1, 1, 0.025 }, hover = { 1, 1, 1, 0.08 },
		accent = { 0.85, 0.64, 0.25 }, button = { 0.12, 0.12, 0.14, 1 }, buttonHover = { 0.19, 0.19, 0.22, 1 },
		buttonBorder = { 0.25, 0.25, 0.28, 1 }, text = { 0.92, 0.92, 0.92 }, dim = { 0.6, 0.6, 0.63 },
	},
	Parchment = {
		label = "Parchment", style = "flat", pad = 6,
		bg = { 0.15, 0.11, 0.07, 1 }, border = { 0.5, 0.38, 0.2, 1 },
		panel = { 1, 0.85, 0.6, 0.05 }, rowAlt = { 1, 0.9, 0.7, 0.04 }, hover = { 1, 0.85, 0.5, 0.1 },
		accent = { 1, 0.82, 0.4 }, button = { 0.24, 0.17, 0.1, 1 }, buttonHover = { 0.33, 0.24, 0.13, 1 },
		buttonBorder = { 0.5, 0.38, 0.2, 1 }, text = { 0.96, 0.9, 0.78 }, dim = { 0.72, 0.64, 0.5 },
	},
	Classic = {
		label = "Classic Tooltip", style = "tooltip", pad = 7,
		bg = { 0.04, 0.04, 0.05, 0.95 }, border = { 0.75, 0.75, 0.78, 1 },
		panel = { 1, 1, 1, 0.03 }, rowAlt = { 1, 1, 1, 0.03 }, hover = { 0.3, 0.5, 1, 0.15 },
		accent = { 1, 0.82, 0 }, button = { 0.1, 0.1, 0.12, 1 }, buttonHover = { 0.16, 0.18, 0.24, 1 },
		buttonBorder = { 0.4, 0.4, 0.45, 1 }, text = { 1, 1, 1 }, dim = { 0.65, 0.65, 0.68 },
	},
}
W.themeOrder = { "Auto", "Forever", "ElvUI", "EllesmereUI", "GW2 UI", "Tukui", "NDui", "Dark", "Parchment", "Classic" }

-- Name of the theme "Auto" resolves to.
function W:AutoTheme()
	for _, name in ipairs({ "ElvUI", "EllesmereUI", "GW2 UI", "Tukui", "NDui" }) do
		local t = self.themes[name]
		if t.suite and API.IsAddOnLoaded and API.IsAddOnLoaded(t.suite) then return name end
	end
	return "Forever"
end

function W:ThemeName()
	local n = R.settings.skin
	if n == "Auto" or not self.themes[n] then return self:AutoTheme() end
	return n
end

-- Resolved theme (copy with live suite colors + class accent applied). Cached until InvalidateTheme().
function W:Skin()
	if self.resolved then return self.resolved end
	local base = self.themes[self:ThemeName()]
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	if base.live then pcall(base.live, t) end
	if R.settings.classAccent or base.classAccent then
		local r, g, b = R.ClassColor(select(2, UnitClass("player")))
		t.accent = { r, g, b }
	end
	self.resolved = t
	return t
end

function W:InvalidateTheme() self.resolved = nil end

local function ApplyNineSlice(frame, t)
	if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then return false end
	local ns = frame.rumNineSlice
	if not ns then
		local ok, f = pcall(CreateFrame, "Frame", nil, frame, "NineSlicePanelTemplate")
		if not ok or not f then return false end
		ns = f
		ns:SetAllPoints()
		frame.rumNineSlice = ns
	end
	for _, layout in ipairs(t.nineSlice) do
		if pcall(NineSliceUtil.ApplyLayoutByName, ns, layout) then
			ns:Show()
			return true
		end
	end
	ns:Hide()
	return false
end

-- Applies a backdrop. kind = "main" (theme frame style) or "flat" (thin 1px style)
function W:Backdrop(frame, kind, bg, border)
	if not frame.SetBackdrop then
		if BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) else return end
	end
	local t = self:Skin()
	local b = bg or t.bg
	local e = border or t.border
	if kind == "main" then
		if frame.rumNineSlice then frame.rumNineSlice:Hide() end
		if frame.rumBG then frame.rumBG:Hide() end
		if t.style == "nineslice" and ApplyNineSlice(frame, t) then
			frame:SetBackdrop(nil)
			if not frame.rumBG then
				frame.rumBG = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
				frame.rumBG:SetPoint("TOPLEFT", 3, -3)
				frame.rumBG:SetPoint("BOTTOMRIGHT", -3, 3)
			end
			if frame.rumBG:SetTexture(t.bgTile, "REPEAT", "REPEAT") == false then
				frame.rumBG:SetColorTexture(0.08, 0.08, 0.09, 1)
			end
			if frame.rumBG.SetHorizTile then frame.rumBG:SetHorizTile(true); frame.rumBG:SetVertTile(true) end
			frame.rumBG:SetVertexColor(b[1], b[2], b[3])
			frame.rumBG:SetAlpha(b[4] or 1)
			frame.rumBG:Show()
			return
		end
		if t.style == "flat" then
			frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		else
			frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, tile = true, tileSize = 16,
				insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		end
	else
		frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	end
	frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
	frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
end

function W:Pad() return self:Skin().pad or 6 end

---------------------------------------------------------------------------
-- Fonts (theme font, built-ins, or any LibSharedMedia font)
---------------------------------------------------------------------------
W.builtinFonts = {
	["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
	["Arial Narrow"] = "Fonts\\ARIALN.TTF",
	["Skurri"] = "Fonts\\skurri.ttf",
	["Morpheus"] = "Fonts\\MORPHEUS.ttf",
}

local function LSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function W:FontList()
	local list = { "" }
	local seen = {}
	for name in pairs(self.builtinFonts) do list[#list + 1] = name; seen[name] = true end
	local lsm = LSM()
	if lsm then
		for _, name in ipairs(lsm:List("font")) do
			if not seen[name] then list[#list + 1] = name end
		end
	end
	table.sort(list)
	return list
end

function W:FontPath()
	local name = R.settings.font
	if name and name ~= "" then
		if self.builtinFonts[name] then return self.builtinFonts[name] end
		local lsm = LSM()
		local p = lsm and lsm:Fetch("font", name, true)
		if p then return p end
	end
	return self:Skin().font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

W.fonts = {}
function W:UpdateFonts()
	local size = R.settings.fontSize or 12
	local face = self:FontPath()
	local flat = self:Skin().style == "flat"
	local defs = { normal = size, small = size - 1, title = size + 2, tiny = math.max(size - 2, 8) }
	for key, sz in pairs(defs) do
		local f = self.fonts[key]
		if not f then
			f = CreateFont("RummageFont_" .. key)
			self.fonts[key] = f
		end
		local res = f:SetFont(face, sz, key == "tiny" and "OUTLINE" or "")
		if res == false or not f:GetFont() then
			f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", sz, key == "tiny" and "OUTLINE" or "")
		end
		if key ~= "tiny" then
			f:SetShadowColor(0, 0, 0, flat and 0.9 or 1)
			f:SetShadowOffset(1, -1)
		end
	end
end

function W:Text(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(self.fonts[font or "normal"])
	fs:SetWordWrap(false)
	return fs
end

---------------------------------------------------------------------------
-- Tooltip helper
---------------------------------------------------------------------------
function W:SetTooltip(frame, title, body)
	frame.tipTitle, frame.tipBody = title, body
	if frame.tipHooked then return end
	frame.tipHooked = true
	frame:HookScript("OnEnter", function(self)
		local t = type(self.tipTitle) == "function" and self.tipTitle(self) or self.tipTitle
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(t, 1, 0.82, 0)
		local b = type(self.tipBody) == "function" and self.tipBody(self) or self.tipBody
		if b then GameTooltip:AddLine(b, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Flat button
---------------------------------------------------------------------------
local buttons = {}

local function ButtonColors(b)
	local s = W:Skin()
	local c = (b.active and s.buttonHover) or (b.hover and s.buttonHover) or s.button
	b:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
	local e = b.active and { s.accent[1], s.accent[2], s.accent[3], 1 } or s.buttonBorder
	b:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
	if b.text then
		local t = b.active and s.accent or s.text
		if b.disabled then t = s.dim end
		b.text:SetTextColor(t[1], t[2], t[3])
	end
	if b.icon then b.icon:SetDesaturated(b.disabled and true or false) end
end

function W:Button(parent, label, width, height, onClick)
	local b = CreateFrame("Button", nil, parent, API.Backdrop)
	b:SetSize(width or 80, height or 20)
	W:Backdrop(b, "flat")
	if label then
		b.text = W:Text(b, "small")
		b.text:SetPoint("CENTER")
		b.text:SetText(label)
	end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self) self.hover = true; ButtonColors(self) end)
	b:SetScript("OnLeave", function(self) self.hover = false; ButtonColors(self) end)
	if onClick then b:SetScript("OnClick", function(self, btn) if not self.disabled then onClick(self, btn) end end) end
	function b:SetActive(v) self.active = v; ButtonColors(self) end
	function b:SetDisabledLook(v) self.disabled = v; ButtonColors(self) end
	function b:SetLabel(t) if self.text then self.text:SetText(t) end end
	function b:FitText(pad) if self.text then self:SetWidth(self.text:GetStringWidth() + (pad or 16)) end end
	ButtonColors(b)
	buttons[#buttons + 1] = b
	return b
end

function W:IconButton(parent, texture, size, onClick, coords)
	local b = W:Button(parent, nil, size, size, onClick)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	b.icon:SetTexture(texture)
	if coords then b.icon:SetTexCoord(unpack(coords)) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	return b
end

function W:RefreshButtons()
	for _, b in ipairs(buttons) do
		W:Backdrop(b, "flat")
		ButtonColors(b)
	end
end

---------------------------------------------------------------------------
-- Check box (plain)
---------------------------------------------------------------------------
function W:Check(parent, label, get, set, tip)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(220, 20)
	local box = CreateFrame("Frame", nil, f, API.Backdrop)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 2, 0)
	W:Backdrop(box, "flat", { 0, 0, 0, 0.6 })
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	mark:SetPoint("CENTER")
	mark:SetSize(18, 18)
	local text = W:Text(f, "normal")
	text:SetPoint("LEFT", box, "RIGHT", 6, 0)
	text:SetText(label)
	function f:Update() mark:SetShown(get() and true or false) end
	f:SetScript("OnClick", function(self) set(not get()); self:Update() end)
	if tip then W:SetTooltip(f, label, tip) end
	f:Update()
	return f
end

---------------------------------------------------------------------------
-- Slider (plain)
---------------------------------------------------------------------------
function W:Slider(parent, label, minV, maxV, step, get, set, fmt)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(220, 34)
	local text = W:Text(f, "normal")
	text:SetPoint("TOPLEFT", 2, 0)
	local s = CreateFrame("Slider", nil, f, API.Backdrop)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(200, 10)
	s:SetPoint("TOPLEFT", 2, -18)
	W:Backdrop(s, "flat", { 0, 0, 0, 0.6 })
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local thumb = s:GetThumbTexture()
	if thumb then thumb:SetSize(24, 24) end
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local function label_(v)
		text:SetText(label .. ": |cffffffff" .. (fmt and fmt(v) or tostring(v)) .. "|r")
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		if f.updating then return end
		label_(v)
		set(v)
	end)
	function f:Update()
		self.updating = true
		local v = get()
		s:SetValue(v)
		label_(v)
		self.updating = false
	end
	f:Update()
	return f
end

---------------------------------------------------------------------------
-- Edit box (plain)
---------------------------------------------------------------------------
function W:EditBox(parent, width, height)
	local e = CreateFrame("EditBox", nil, parent, API.Backdrop)
	e:SetSize(width or 160, height or 20)
	W:Backdrop(e, "flat", { 0, 0, 0, 0.5 })
	e:SetFontObject(W.fonts.normal)
	e:SetTextInsets(6, 6, 0, 0)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end

---------------------------------------------------------------------------
-- Popup menu
---------------------------------------------------------------------------
local menu, catcher
local menuButtons = {}

local function HideMenu()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end
W.HideMenu = HideMenu

-- items: { text=, checked=bool, func=fn, isTitle=bool, disabled=bool, onDelete=fn, keepOpen=bool }
function W:Menu(anchor, items, point, relPoint, x, y)
	if not menu then
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:SetScript("OnClick", HideMenu)
		catcher:Hide()
		menu = CreateFrame("Frame", "RummageMenu", UIParent, API.Backdrop)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		table.insert(UISpecialFrames, "RummageMenu")
	end
	W:Backdrop(menu, "main")
	for _, b in ipairs(menuButtons) do b:Hide() end
	local width, y0 = 120, -6
	for i, it in ipairs(items) do
		local b = menuButtons[i]
		if not b then
			b = CreateFrame("Button", nil, menu)
			b:SetHeight(18)
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.1)
			b.check = b:CreateTexture(nil, "ARTWORK")
			b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			b.check:SetSize(16, 16)
			b.check:SetPoint("LEFT", 2, 0)
			b.text = W:Text(b, "normal")
			b.text:SetPoint("LEFT", 20, 0)
			b.text:SetJustifyH("LEFT")
			b.del = CreateFrame("Button", nil, b)
			b.del:SetSize(14, 14)
			b.del:SetPoint("RIGHT", -2, 0)
			b.del.tex = b.del:CreateTexture(nil, "ARTWORK")
			b.del.tex:SetAllPoints()
			b.del.tex:SetTexture("Interface\\Buttons\\UI-StopButton")
			W:SetTooltip(b.del, "Delete")
			menuButtons[i] = b
		end
		b:SetFrameLevel(menu:GetFrameLevel() + 2)
		b.text:SetText(it.text or "")
		b.check:SetShown(it.checked and true or false)
		if it.isTitle then
			b.text:SetTextColor(1, 0.82, 0)
			b:EnableMouse(false)
		elseif it.disabled then
			b.text:SetTextColor(0.5, 0.5, 0.5)
			b:EnableMouse(false)
		else
			b.text:SetTextColor(1, 1, 1)
			b:EnableMouse(true)
		end
		b:SetScript("OnClick", function()
			if not it.keepOpen then HideMenu() end
			if it.func then it.func() end
		end)
		if it.onDelete then
			b.del:Show()
			b.del:SetScript("OnClick", function() HideMenu(); it.onDelete() end)
		else
			b.del:Hide()
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, y0)
		b:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
		b:Show()
		width = math.max(width, b.text:GetStringWidth() + 48)
		y0 = y0 - 18
	end
	menu:SetSize(width, -y0 + 6)
	menu:ClearAllPoints()
	menu:SetPoint(point or "TOPLEFT", anchor, relPoint or "BOTTOMLEFT", x or 0, y or -2)
	catcher:Show()
	menu:Show()
end
