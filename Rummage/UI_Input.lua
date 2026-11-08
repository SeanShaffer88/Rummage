-- Rummage: keyboard navigation for the item list (1.5.0).
-- Up/Down/PageUp/PageDown/Home/End move a selection, Enter uses the selected item,
-- Space cycles its favorite marker. Active only while the window is shown, out of combat, and the
-- search box is not focused; every other key is passed through to the game.
-- UNVERIFIED on Forever 1.60.1: relies on EnableKeyboard + SetPropagateKeyboardInput.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API
local UI = R.UI

local InCombatLockdown = InCombatLockdown

local NAV_KEYS = { UP = true, DOWN = true, PAGEUP = true, PAGEDOWN = true, HOME = true, END = true }

-- Flat, ordered array of the item entries currently shown (headers skipped; grid
-- rows contribute their cells in order).
function UI:NavEntries()
	local list = {}
	for _, d in ipairs(self.display) do
		if d.header then
			-- skip
		elseif d.items then
			for _, e in ipairs(d.items) do list[#list + 1] = e end
		else
			list[#list + 1] = d
		end
	end
	return list
end

-- Display-row index containing entry `e` (for scrolling it into view).
function UI:RowOf(e)
	for i, d in ipairs(self.display) do
		if d == e then return i end
		if d.items then
			for _, x in ipairs(d.items) do if x == e then return i end end
		end
	end
end

function UI:SelectEntry(e)
	self.selected = e
	if e then
		local row = self:RowOf(e)
		local vis = self:VisibleRows()
		if row then
			if row <= self.offset then self:Scroll(row - 1 - self.offset)
			elseif row > self.offset + vis then self:Scroll(row - vis - self.offset) end
		end
	end
	self:Render()
end

-- Returns true when the key was consumed.
function UI:HandleNavKey(key)
	local s = R.settings
	if not s.keyboardNav or InCombatLockdown() then return false end
	if self.searchBox and self.searchBox:HasFocus() then return false end
	local list = self:NavEntries()
	if key == "ESCAPE" then self.selected = nil; return false end
	if #list == 0 then return false end
	local idx
	for i, e in ipairs(list) do if e == self.selected then idx = i; break end end
	if NAV_KEYS[key] then
		local step = (self.view and s.viewMode == "grid") and math.max(1, self:GridPerRow()) or 1
		local page = math.max(1, self:VisibleRows() - 1)
		local ni
		if not idx then ni = (key == "END" or key == "UP" or key == "PAGEUP") and #list or 1
		elseif key == "DOWN" then ni = idx + 1
		elseif key == "UP" then ni = idx - 1
		elseif key == "PAGEDOWN" then ni = idx + page
		elseif key == "PAGEUP" then ni = idx - page
		elseif key == "HOME" then ni = 1
		else ni = #list end
		if s.viewMode == "grid" and (key == "UP" or key == "DOWN") then
			ni = idx and (idx + (key == "DOWN" and step or -step)) or ni
		end
		ni = math.max(1, math.min(#list, ni))
		self:SelectEntry(list[ni])
		return true
	end
	local e = self.selected
	if not e or not idx then return false end
	if key == "ENTER" and self:Interactive() and not self.searchAllActive and e.bag and e.slot then
		API.UseContainerItem(e.bag, e.slot)
		return true
	elseif key == "SPACE" and not self.searchAllActive and e.id then
		self:CycleFavorite(e)   -- same marker cycle as the favorite column
		return true
	end
	return false
end

function UI:SetupKeyboard()
	local f = self.frame
	if not f or self.keyboardReady then return end
	self.keyboardReady = true
	local function sync()
		local on = R.settings.keyboardNav and f:IsShown() and not InCombatLockdown()
		f:EnableKeyboard(on and true or false)
		if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
	end
	f:HookScript("OnShow", sync)
	f:HookScript("OnHide", function() f:EnableKeyboard(false); UI.selected = nil end)
	f:SetScript("OnKeyDown", function(self, key)
		local handled = UI:HandleNavKey(key)
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not handled) end
	end)
	R:RegisterEvent("PLAYER_REGEN_DISABLED", function() f:EnableKeyboard(false) end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", sync)
	self.SyncKeyboard = sync
end
