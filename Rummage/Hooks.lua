-- Rummage: replaces Blizzard bag/bank windows, takes over bag keybinds,
-- and warns about other bag addons that would conflict.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local Hooks = {}
R.Hooks = Hooks

local hidden = CreateFrame("Frame")
hidden:Hide()
Hooks.hidden = hidden

---------------------------------------------------------------------------
-- Bag open/close intents (coalesced per frame; an explicit toggle wins)
---------------------------------------------------------------------------
local intent

local function Context()
	if MerchantFrame and MerchantFrame:IsShown() then return "merchant" end
	if MailFrame and MailFrame:IsShown() then return "mail" end
	if (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) then return "auction" end
	if TradeFrame and TradeFrame:IsShown() then return "trade" end
	if R.Data.atBank then return "bank" end
	return "other"
end

local function Resolve()
	local i = intent
	intent = nil
	local UI = R.UI
	if not UI.frame then return end
	if i == "toggle" then
		UI:Toggle("bags")
		UI.autoOpened = false
	elseif i == "open" then
		if not UI.frame:IsShown() and R.settings.autoOpen[Context()] ~= false then
			UI:Open("bags")
			UI.autoOpened = true
		end
	elseif i == "close" then
		if UI.autoOpened and UI.frame:IsShown() and not R.Data.atBank then UI:Close() end
	end
end

local function Queue(kind)
	if intent ~= "toggle" then intent = kind end
	R:Defer("bagintent", Resolve)
end

local function HideBlizzard(frame)
	if frame and not frame.rummageHooked then
		frame.rummageHooked = true
		frame:HookScript("OnShow", function(self)
			if R.settings.replaceBags then self:Hide() end
		end)
	end
end

function Hooks:InitBags()
	if not R.settings.replaceBags then return end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do HideBlizzard(_G["ContainerFrame" .. i]) end
	HideBlizzard(ContainerFrameCombinedBags)

	local function toggle() Queue("toggle") end
	local function open() Queue("open") end
	local function close() Queue("close") end
	for _, fn in ipairs({ "ToggleBackpack", "ToggleBag", "ToggleAllBags" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, toggle) end
	end
	for _, fn in ipairs({ "OpenAllBags", "OpenBackpack" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, open) end
	end
	for _, fn in ipairs({ "CloseAllBags", "CloseBackpack" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, close) end
	end
end

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------
function Hooks:InitBank()
	if R.settings.replaceBank and BankFrame then
		pcall(BankFrame.UnregisterEvent, BankFrame, "BANKFRAME_OPENED")
		pcall(BankFrame.UnregisterEvent, BankFrame, "BANKFRAME_CLOSED")
		BankFrame:SetParent(hidden)
	end
	R:RegisterEvent("BANKFRAME_OPENED", function()
		R.Data.atBank = true
		R.Data:ScanBank()
		if R.settings.replaceBank then
			local UI = R.UI
			UI.openedByBank = not UI.frame:IsShown()
			if R.settings.autoOpen.bank ~= false or UI.frame:IsShown() then
				UI:Open("bank")
			end
		end
		R:Fire("DATA_CHANGED")
	end)
	R:RegisterEvent("BANKFRAME_CLOSED", function()
		if not R.Data.atBank then return end
		R.Data.atBank = false
		local UI = R.UI
		if UI.openedByBank and UI.frame:IsShown() then
			UI:Close()
		elseif UI.view == "bank" then
			R:RequestRefresh()
		end
		UI.openedByBank = false
		R:Fire("DATA_CHANGED")
	end)
end

---------------------------------------------------------------------------
-- Keybinds: route "Open All Bags" (and optionally the per-bag keys) to Rummage.
-- Uses override bindings, so the player's saved keybinds are never modified.
---------------------------------------------------------------------------
local bindOwner = CreateFrame("Frame", "RummageBindingOwner")
local lastSignature

local BAG_ACTIONS = { "TOGGLEBACKPACK", "TOGGLEBAG1", "TOGGLEBAG2", "TOGGLEBAG3", "TOGGLEBAG4", "TOGGLEBAG5",
	"TOGGLEREAGENTBAG", "TOGGLEKEYRING" }

function Hooks:ApplyBindings(force)
	if InCombatLockdown() then
		self.bindPending = true
		return
	end
	self.bindPending = false
	local keys = {}
	if R.settings.takeoverKeybinds then
		local actions = { "OPENALLBAGS" }
		if R.settings.takeoverBagKeys then
			for _, a in ipairs(BAG_ACTIONS) do actions[#actions + 1] = a end
		end
		for _, action in ipairs(actions) do
			local k1, k2 = GetBindingKey(action)
			if k1 then keys[#keys + 1] = k1 end
			if k2 then keys[#keys + 1] = k2 end
		end
	end
	table.sort(keys)
	local sig = table.concat(keys, ",")
	if sig == lastSignature and not force then return end
	lastSignature = sig
	ClearOverrideBindings(bindOwner)
	for _, key in ipairs(keys) do
		SetOverrideBinding(bindOwner, true, key, "RUMMAGE_TOGGLE")
	end
end

function Hooks:InitBindings()
	R:RegisterEvent("UPDATE_BINDINGS", function() Hooks:ApplyBindings() end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if Hooks.bindPending then Hooks:ApplyBindings() end
	end)
	self:ApplyBindings(true)
end

function Hooks:BoundKeys()
	return lastSignature ~= "" and lastSignature or nil
end

---------------------------------------------------------------------------
-- Conflicting bag addons
---------------------------------------------------------------------------
local EXACT = {
	Baganator = true, Bagnon = true, ArkInventory = true, AdiBags = true, BetterBags = true, Combuctor = true,
	OneBag3 = true, OneBank3 = true, Inventorian = true, Sorted = true, LiteBag = true, BagMom = true,
	Bagforge = true, OneWoW_Bags = true, ["OneWoW-Bags"] = true, cargBags_Nivaya = true, Bagnonium = true,
	ClassicUI_Bags = true, BaudBag = true, AdiBags_Config = false,
}
local PATTERNS = { "^cargBags", "^Bagnon_", "[Ee]llesmere.*[Bb]ag" }

local function GetNumAddOns_() return (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)() end
local function GetAddOnName(i)
	local info = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
	if type(info) == "table" then return info.name end
	return info
end

function Hooks:FindConflicts()
	local addons, modules = {}, {}
	for i = 1, GetNumAddOns_() do
		local name = GetAddOnName(i)
		if name and name ~= R.name and API.IsAddOnLoaded(name) then
			local hit = EXACT[name]
			if hit == nil then
				for _, p in ipairs(PATTERNS) do
					if name:find(p) then hit = true; break end
				end
			end
			if hit then addons[#addons + 1] = name end
		end
	end
	-- UI suites with built-in bag modules
	local ok, E = pcall(function() return _G.ElvUI and unpack(_G.ElvUI) end)
	if ok and E and E.private and E.private.bags and E.private.bags.enable then
		modules[#modules + 1] = "ElvUI (Bags module)"
	end
	local nd = _G.NDuiDB
	if type(nd) == "table" and type(nd.Bags) == "table" and nd.Bags.Enable then
		modules[#modules + 1] = "NDui (Bags module)"
	end
	table.sort(addons)
	return addons, modules
end

function Hooks:CheckConflicts(manual)
	local addons, modules = self:FindConflicts()
	if #addons == 0 and #modules == 0 then
		if manual then R:Print("No conflicting bag addons found.") end
		return
	end
	local all = {}
	for _, a in ipairs(addons) do all[#all + 1] = a end
	for _, m in ipairs(modules) do all[#all + 1] = m end
	local sig = table.concat(all, ",")
	R:Print("|cffff6060Warning:|r other bag addons are active and may cause missing items, double windows or errors: "
		.. table.concat(all, ", ") .. ". Type /rum conflicts to resolve.")
	if not R.settings.warnConflicts and not manual then return end
	if R.settings.ignoredConflicts == sig and not manual then return end
	self.pendingDisable = addons
	self.pendingSig = sig
	local lines = {}
	for _, a in ipairs(addons) do lines[#lines + 1] = "|cffffd100" .. a .. "|r" end
	for _, m in ipairs(modules) do lines[#lines + 1] = "|cffffd100" .. m .. "|r  (turn the module off in its settings)" end
	StaticPopup_Show(#addons > 0 and "RUMMAGE_CONFLICTS" or "RUMMAGE_CONFLICTS_MODULES", table.concat(lines, "\n"))
end

function Hooks:RegisterPopups()
	StaticPopupDialogs["RUMMAGE_CONFLICTS"] = {
		text = "|cffd9a441Rummage|r found other bag addons that will fight over your bags during gameplay:\n\n%s\n\nDisable the addons above and reload the UI?",
		button1 = "Disable & Reload",
		button2 = "Not now",
		button3 = "Don't warn again",
		OnAccept = function()
			local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
			for _, name in ipairs(Hooks.pendingDisable or {}) do pcall(disable, name) end
			ReloadUI()
		end,
		OnAlt = function()
			R.settings.ignoredConflicts = Hooks.pendingSig or ""
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
	}
	StaticPopupDialogs["RUMMAGE_CONFLICTS_MODULES"] = {
		text = "|cffd9a441Rummage|r: another addon's bag module is active and will fight over your bags:\n\n%s",
		button1 = OKAY or "OK",
		button3 = "Don't warn again",
		OnAlt = function()
			R.settings.ignoredConflicts = Hooks.pendingSig or ""
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
	}
end

---------------------------------------------------------------------------
function Hooks:Init()
	self:RegisterPopups()
	self:InitBags()
	self:InitBank()
	self:InitBindings()
end
