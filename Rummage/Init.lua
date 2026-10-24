-- Rummage: startup and slash commands.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

-- ADDON_LOADED fires for every addon; unregister as soon as ours has been handled.
local function OnAddonLoaded(event, name)
	if name ~= R.name then return end
	R:UnregisterEvent(event, OnAddonLoaded)
	R:InitDB()
end
R:RegisterEvent("ADDON_LOADED", OnAddonLoaded)

local lastFree
local function CheckSpace()
	local threshold = R.settings.lowSpaceWarn or 0
	if threshold <= 0 then return end
	local free = R.Data:FreeSlots(R.Data.me, API.InvBagList)
	if free <= threshold and (lastFree == nil or lastFree > threshold) then
		R:Print(format("|cffff6060Bags almost full:|r %d free slot%s left.", free, free == 1 and "" or "s"))
	end
	lastFree = free
end

-- One-shot startup events unregister themselves after running.
R:RegisterEventOnce("PLAYER_LOGIN", function()
	if not R.db then R:InitDB() end
	R.Data:Init()
	R.Columns:RegisterBuiltins()
	R.Integrations:Init()
	R.Tooltip:Init()
	R.Upgrade:Init()
	R.UI:RegisterPopups()
	R.UI:Create()
	R.Hooks:Init()
	R.Options:Init()
	R.Minimap:Init()
	R:Listen("DATA_CHANGED", function() R:Defer("spacecheck", CheckSpace) end)
end)

R:RegisterEventOnce("PLAYER_ENTERING_WORLD", function()
	R.Data:ScanEquipped()
	R.Data:ScanInventory()
	if C_Timer then
		C_Timer.After(4, function() R.Hooks:CheckConflicts() end)
	else
		R.Hooks:CheckConflicts()
	end
end)

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
-- Addon compartment entry (named in the TOC).
function Rummage_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		R.Options:Toggle()
	else
		R.UI:Toggle("bags")
	end
end

SLASH_RUMMAGE1 = "/rummage"
SLASH_RUMMAGE2 = "/rum"
SlashCmdList.RUMMAGE = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		R.UI:Toggle("bags")
	elseif cmd == "bank" then
		R.UI:Toggle("bank")
	elseif cmd == "config" or cmd == "options" or cmd == "settings" then
		R.Options:Toggle()
	elseif cmd == "search" then
		R.UI:Open("bags")
		R.UI.searchBox:SetText(rest or "")
	elseif cmd == "restack" then
		R.Mover:Restack(R.UI.view)
	elseif cmd == "sell" then
		R.Junk:SellAll()
	elseif cmd == "conflicts" then
		R.Hooks:CheckConflicts(true)
	elseif cmd == "reset" then
		R.UI:ResetPosition()
		R:Print("Window position reset.")
	elseif cmd == "upgrade" then
		R.Upgrade:Test()
	elseif cmd == "debug" then
		R.Debug:Command(rest)
	elseif cmd == "keys" then
		R.Hooks:ApplyBindings(true)
		R:Print("Keys routed to Rummage: " .. (R.Hooks:BoundKeys() or "none"))
	elseif cmd == "export" then
		R:Print("settings string (also on the About tab in settings):")
		print(R:ExportSettings())
	elseif cmd == "import" then
		local ok, err = R:ImportSettings(rest)
		if ok then R:Print("Settings imported.")
		else R:Print("Import failed: " .. tostring(err)) end
	else
		R:Print(R.L.slashUsage)
	end
end
