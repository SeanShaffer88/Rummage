-- Rummage: window geometry — corner scale grips, edge resizing, per-view layouts,
-- the pending-layout badge. Split out of UI.lua in 1.5.0; shares the UI table via R.UI.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local UI = R.UI

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown

local SNAPS = { 0.75, 1, 1.25, 1.5 }   -- Shift-drag snaps to these scale values
UI.SCALE_SNAPS = SNAPS

-- Pure helpers (also exercised by tests/cases.lua).
function UI.SnapScale(ns_)
	local best, bd = SNAPS[1], abs(ns_ - SNAPS[1])
	for i = 2, #SNAPS do
		local d = abs(ns_ - SNAPS[i])
		if d < bd then best, bd = SNAPS[i], d end
	end
	return best
end

-- Scale for a cursor x (UIParent units) given the fixed corner x and unscaled width.
function UI.ScaleFromCursor(side, cx, fixedX, w)
	if not w or w <= 0 then return nil end
	local v = (side == "RIGHT") and (cx - fixedX) / w or (fixedX - cx) / w
	return max(0.5, min(2, v))
end

---------------------------------------------------------------------------
-- Pending-layout badge: a change that needs out-of-combat time (scale, size,
-- re-anchoring, refresh of protected item buttons) is flagged instead of lost.
---------------------------------------------------------------------------
function UI:SetPending(on)
	on = on and true or false
	self.pendingCombat = on
	local f = self.frame
	if not f then return end
	if on and not self.pendingBadge then
		local b = f:CreateFontString(nil, "OVERLAY")
		local W = R.Widgets
		if W and W.Text then b = W:Text(f, "small") end
		b:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
		b:SetTextColor(1, 0.65, 0.2)
		b:SetText("Layout pending: waiting for combat to end")
		self.pendingBadge = b
	end
	if self.pendingBadge then self.pendingBadge:SetShown(on) end
end

---------------------------------------------------------------------------
-- Scale grips
---------------------------------------------------------------------------
function UI:CreateGrips()
	local f = self.frame
	-- Drag either bottom corner to scale the whole window (frame, rows, icons,
	-- text). The opposite bottom corner and the top edge stay put on screen.
	-- Hold Shift to snap to 75 / 100 / 125 / 150 %. Width/height come from the edges.
	local function MakeGrip(side)
		local g = CreateFrame("Button", nil, f)
		local right = side == "RIGHT"
		g.side = side
		g:SetSize(14, 14)
		g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -3 or 3, 3)
		g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
		if not right then  -- mirror the art for the left corner
			for _, tex in ipairs({ g:GetNormalTexture(), g:GetPushedTexture(), g:GetHighlightTexture() }) do
				if tex and tex.SetTexCoord then tex:SetTexCoord(1, 0, 0, 1) end
			end
		end
		g:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then UI:BeginScale(self) end
		end)
		g:SetScript("OnMouseUp", function(self) UI:EndScale(self) end)
		g:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, right and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
			GameTooltip:AddLine("Drag to scale the window")
			GameTooltip:AddLine("Hold Shift to snap to 75 / 100 / 125 / 150%", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		g:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return g
	end
	self.gripR, self.gripL = MakeGrip("RIGHT"), MakeGrip("LEFT")

	-- Live readout shown only while a grip is held.
	local W = R.Widgets
	local ro = W and W.Text and W:Text(f, "normal") or f:CreateFontString(nil, "OVERLAY")
	ro:SetPoint("BOTTOM", f, "BOTTOM", 0, 22)
	ro:SetTextColor(1, 0.82, 0.2)
	ro:Hide()
	self.scaleReadout = ro

	-- Edge handles: right edge = width, bottom edge = height. Kept clear of the
	-- corners so they never fight the grips.
	local function MakeEdge(dir)
		local e = CreateFrame("Button", nil, f)
		if dir == "RIGHT" then
			e:SetWidth(5)
			e:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -40)
			e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
		else
			e:SetHeight(5)
			e:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 0)
			e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 0)
		end
		e:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" and not R.settings.locked and not InCombatLockdown() then f:StartSizing(dir) end
		end)
		e:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SavePosition(); UI:Layout() end)
		e:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:AddLine(dir == "RIGHT" and "Drag to change the width" or "Drag to change the height")
			GameTooltip:Show()
		end)
		e:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	MakeEdge("RIGHT")
	MakeEdge("BOTTOM")
end

-- Cursor-driven; the OnUpdate exists only while a grip is held.
-- ns = horizontal cursor distance from the fixed bottom corner / unscaled width.
-- The window is re-anchored TOPLEFT so the fixed corner and top edge hold still.
function UI:BeginScale(g)
	local f, s = self.frame, R.settings
	if s.locked then return end
	if InCombatLockdown() then
		R:Print("Scaling is blocked in combat.")
		return
	end
	local sc = f:GetScale() or 1
	local l, r, t = f:GetLeft(), f:GetRight(), f:GetTop()
	if not (l and r and t) then return end
	g.baseW = f:GetWidth()
	g.fixedX = (g.side == "RIGHT") and l * sc or r * sc
	g.fixedY = t * sc
	g.sizing = true
	if self.scaleReadout then self.scaleReadout:Show() end
	g:SetScript("OnUpdate", function(self)
		if InCombatLockdown() then return UI:EndScale(self) end
		UI:ScaleStep(self)
	end)
end

function UI:ScaleStep(g)
	local f = self.frame
	local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
	local w = g.baseW
	local ns_ = UI.ScaleFromCursor(g.side, cx, g.fixedX, w)
	if not ns_ then return end
	if IsShiftKeyDown and IsShiftKeyDown() then ns_ = UI.SnapScale(ns_) end
	local left = (g.side == "RIGHT") and g.fixedX or (g.fixedX - w * ns_)
	R.settings.scale = ns_
	f:SetScale(ns_)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ns_, g.fixedY / ns_)
	if self.scaleReadout then self.scaleReadout:SetText(floor(ns_ * 100 + 0.5) .. "%") end
end

function UI:EndScale(g)
	if not g or not g.sizing then return end
	g.sizing = false
	g:SetScript("OnUpdate", nil)
	if self.scaleReadout then self.scaleReadout:Hide() end
	local s = R.settings
	s.scale = floor((s.scale or 1) * 100 + 0.5) / 100
	if not InCombatLockdown() then
		self.frame:SetScale(s.scale)
		self:SavePosition()
	else
		self:SetPending(true)
	end
	if R.Options and R.Options.Rebuild then R.Options:Rebuild() end
end

---------------------------------------------------------------------------
-- Position, size and per-view layouts
---------------------------------------------------------------------------
-- Window "view key": Bags and Bank have their own, any other character's cache
-- (and cross-character search) shares "all".
function UI:ViewKey()
	if self.charKey or self.searchAllActive then return "all" end
	return self.view == "bank" and "bank" or "bags"
end

function UI:SaveViewLayout(key)
	local s = R.settings
	if not s.perViewSize or not key then return end
	s.viewSizes[key] = { w = s.width, h = s.height, scale = s.scale }
end

-- Loads the stored layout for `key` (or keeps the current one when none is stored).
function UI:ApplyViewLayout(key)
	local s = R.settings
	if not s.perViewSize or not self.frame then return end
	local v = s.viewSizes[key]
	if not v then
		s.viewSizes[key] = { w = s.width, h = s.height, scale = s.scale }
		return
	end
	if InCombatLockdown() then self:SetPending(true); return end
	s.width, s.height, s.scale = v.w, v.h, v.scale
	local f = self.frame
	f:SetSize(v.w, v.h)
	f:SetScale(v.scale)
	self:Layout()
end

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
	s.width, s.height = floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5)
	self:SaveViewLayout(self:ViewKey())
end

function UI:ResetPosition()
	R.settings.point = nil
	R.settings.width, R.settings.height = R.defaults.width, R.defaults.height
	R.settings.viewSizes = {}
	self:ApplyPosition()
	self:Layout()
end
