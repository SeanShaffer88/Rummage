-- Rummage: controller (gamepad) navigation for the item list (1.14.0).
-- D-pad moves the selection (left/right switch category in the list view, move by one in
-- the grid), shoulders page, A uses the item, X cycles the favorite marker, Y marks or
-- unmarks junk, B clears the selection or closes the window. The selected item's tooltip
-- follows the selection. Active only while the controller is enabled, the window is
-- shown, the search box isn't focused and you're out of combat; other buttons go to the game.
-- Builds on the 1.5.0 keyboard navigation (UI_Input.lua).
-- UNVERIFIED in game: Frame:EnableGamePadButton and C_GamePad.IsEnabled are in the Forever
-- 1.60.1 API documentation; the OnGamePadButtonDown script and button propagation are
-- taken from Blizzard's own UI (Blizzard_Keybindings, FlyoutRadial) and guarded.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
R.UIParts[#R.UIParts + 1] = function(UI)

local InCombatLockdown = InCombatLockdown

-- Controller button -> keyboard-navigation key (handled by UI:HandleNavKey).
local PAD_TO_KEY = {
	PADDUP = "UP", PADDDOWN = "DOWN",
	PADLSHOULDER = "PAGEUP", PADRSHOULDER = "PAGEDOWN",
	PAD1 = "ENTER", PAD3 = "SPACE",
}

local function GamePadOn()
	local G = _G.C_GamePad
	if not (G and G.IsEnabled) then return false end
	local ok, on = pcall(G.IsEnabled)
	return ok and on and true or false
end
UI.GamePadOn = GamePadOn

-- The window controller input goes to: the one shown or clicked most recently.
local function Active()
	local a = R.gamepadUI
	if a and a.frame and a.frame:IsShown() then return a end
	for _, w in ipairs(R.UIList) do
		if w.frame and w.frame:IsShown() then return w end
	end
end

-- Next/previous sidebar category, wrapping at the ends.
function UI:StepCategory(dir)
	local cats = self.catList or R.Categories:List()
	if #cats == 0 then return false end
	local idx = 1
	for i, c in ipairs(cats) do if c.id == self.category then idx = i; break end end
	local n = ((idx - 1 + dir) % #cats) + 1
	self:SetCategory(cats[n].id)
	self.subfilter = nil
	self.offset = 0
	self.selected = nil
	R:RequestRefresh()
	return true
end

-- Tooltip for the selected entry, anchored to the row (or grid cell) showing it.
function UI:ShowSelectionTooltip()
	local e = self.selected
	if not (e and e.link and GameTooltip) then return end
	local owner
	for _, row in ipairs(self.rows or {}) do
		if row:IsShown() and row.entry == e then owner = row; break end
	end
	if not owner then
		for _, row in ipairs(self.gridRows or {}) do
			for _, c in ipairs(row.cells or {}) do
				if c:IsShown() and c.entry == e then owner = c; break end
			end
			if owner then break end
		end
	end
	GameTooltip:SetOwner(owner or self.frame, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(e.link)
	if (e.count or 1) > 1 then GameTooltip:AddLine("Count: " .. e.count, 1, 1, 1) end
	GameTooltip:Show()
end

-- Returns true when the button was consumed.
function UI:HandlePadButton(button)
	local s = R.settings
	if not s.gamepadNav or InCombatLockdown() or not GamePadOn() then return false end
	if not (self.frame and self.frame:IsShown()) or Active() ~= self then return false end
	if self.searchBox and self.searchBox:HasFocus() then return false end
	local handled = false
	if button == "PAD2" then
		if self.selected then
			self.selected = nil
			if GameTooltip then GameTooltip:Hide() end
			self:Render()
		else
			self:Close()
		end
		return true
	elseif button == "PAD4" then
		local e = self.selected
		if e and e.id and not self.searchAllActive then
			R.Junk:Toggle(e)
			R:RequestRefresh()
			handled = true
		end
	elseif button == "PADDLEFT" or button == "PADDRIGHT" then
		local dir = button == "PADDRIGHT" and 1 or -1
		if s.viewMode == "grid" then
			local list = self:NavEntries()
			if #list > 0 then
				local idx
				for i, e in ipairs(list) do if e == self.selected then idx = i; break end end
				idx = math.max(1, math.min(#list, (idx or (dir > 0 and 0 or #list + 1)) + dir))
				self:SelectEntry(list[idx])
				handled = true
			end
		else
			handled = self:StepCategory(dir)
		end
	elseif PAD_TO_KEY[button] then
		-- reuse the keyboard path, but under the controller setting rather than keyboardNav
		local kb = s.keyboardNav
		s.keyboardNav, self.padInput = true, true
		local ok, res = pcall(self.HandleNavKey, self, PAD_TO_KEY[button])
		s.keyboardNav, self.padInput = kb, nil
		handled = ok and res or false
	end
	if handled and self.selected then self:ShowSelectionTooltip() end
	return handled
end

function UI:SetupGamepad()
	local f = self.frame
	if not f or self.gamepadReady then return end
	self.gamepadReady = true
	local function enable(v)
		if InCombatLockdown() or not f.EnableGamePadButton then return end
		pcall(f.EnableGamePadButton, f, v and true or false)
	end
	-- Unhandled buttons must reach the game (jump, abilities). Forever has no separate
	-- controller propagation flag; controller buttons follow SetPropagateKeyboardInput.
	local function propagate(v)
		if InCombatLockdown() or not f.SetPropagateKeyboardInput then return end
		pcall(f.SetPropagateKeyboardInput, f, v)
	end
	local function sync()
		local on = R.settings.gamepadNav and f:IsShown() and GamePadOn()
		enable(on)
		propagate(true)
	end
	f:HookScript("OnShow", function() R.gamepadUI = UI; sync() end)
	f:HookScript("OnHide", function()
		enable(false)
		if R.gamepadUI == UI then R.gamepadUI = nil end
	end)
	f:HookScript("OnMouseDown", function() R.gamepadUI = UI end)
	if f.HasScript and f:HasScript("OnGamePadButtonDown") ~= false then
		pcall(f.SetScript, f, "OnGamePadButtonDown", function(_, button)
			local handled = UI:HandlePadButton(button)
			propagate(not handled)
		end)
	end
	R:RegisterEvent("PLAYER_REGEN_DISABLED", function() pcall(f.EnableGamePadButton or function() end, f, false) end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", sync)
	R:RegisterEvent("GAME_PAD_ACTIVE_CHANGED", sync)
	R:RegisterEvent("GAME_PAD_CONNECTED", sync)
	R:RegisterEvent("GAME_PAD_DISCONNECTED", sync)
	self.SyncGamepad = sync
end
end
