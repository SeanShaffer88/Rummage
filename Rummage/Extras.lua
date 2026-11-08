-- Rummage: 1.5.0 extras — API self-check, inventory export, context auto-profiles.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local Extras = {}
R.Extras = Extras

---------------------------------------------------------------------------
-- /rum apicheck: which APIs this client actually provides. Required entries must
-- exist for the addon to work; optional ones only enable extra features.
---------------------------------------------------------------------------
local CHECKS = {
	-- { label, required, resolver } ; resolver returns true when present
	{ "C_Container.GetContainerItemInfo", true, function() return C_Container and C_Container.GetContainerItemInfo end },
	{ "C_Container.GetContainerNumSlots", true, function() return C_Container and C_Container.GetContainerNumSlots end },
	{ "C_Container.UseContainerItem", true, function() return API.UseContainerItem end },
	{ "C_Item.GetItemInfo", true, function() return API.GetItemInfo end },
	{ "C_Timer.After / NewTicker", true, function() return C_Timer and C_Timer.After and C_Timer.NewTicker end },
	{ "hooksecurefunc", true, function() return _G.hooksecurefunc end },
	{ "Enum.BagIndex bank tabs", false, function() return API.BankTabs end },
	{ "C_Item.GetItemStats / GetItemStats", false, function() return (C_Item and C_Item.GetItemStats) or _G.GetItemStats end },
	{ "TooltipDataProcessor", false, function() return _G.TooltipDataProcessor end },
	{ "issecretvalue", false, function() return _G.issecretvalue end },
	{ "canaccessvalue", false, function() return _G.canaccessvalue end },
	{ "GetNumBuybackItems / BuybackItem", false, function() return _G.GetNumBuybackItems and _G.BuybackItem end },
	{ "GetSpecialization", false, function() return _G.GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) end },
	{ "C_AddOns.GetAddOnMetadata", false, function() return C_AddOns and C_AddOns.GetAddOnMetadata end },
}

-- Returns the result list and the count of missing REQUIRED entries.
function Extras:ApiCheck()
	local out, missing = {}, 0
	for _, c in ipairs(CHECKS) do
		local ok, res = pcall(c[3])
		local present = ok and res and true or false
		if c[2] and not present then missing = missing + 1 end
		out[#out + 1] = { name = c[1], required = c[2], present = present }
	end
	return out, missing
end

function Extras:PrintApiCheck()
	local res, missing = self:ApiCheck()
	local version, build = "?", "?"
	if GetBuildInfo then version, build = GetBuildInfo() end
	R:Print(format("API check on client %s (build %s):", tostring(version), tostring(build)))
	for _, r in ipairs(res) do
		local tag = r.present and "|cff40ff40ok|r" or (r.required and "|cffff4040MISSING|r" or "|cffffa040absent|r")
		R:Print(format("  %s  %s%s", tag, r.name, r.required and "" or " (optional)"))
	end
	R:Print(missing == 0 and "All required APIs present." or (missing .. " required API(s) missing — please report this output."))
	return missing
end

---------------------------------------------------------------------------
-- Inventory export: every cached character, bags + bank + equipped + mail.
---------------------------------------------------------------------------
local function ItemName(link)
	return (link and link:match("%[(.-)%]")) or "?"
end

local function CsvField(v)
	v = tostring(v)
	if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
	return v
end

-- Lines of { char, realm, where, bag, slot, name, count, id }, stable order.
function Extras:InventoryRows()
	local rows = {}
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		local name, realm = c.name or entry.key, c.realm or ""
		local bags = {}
		for bag in pairs(c.containers) do bags[#bags + 1] = bag end
		table.sort(bags)
		for _, bag in ipairs(bags) do
			local rec = c.containers[bag]
			local slots = {}
			for slot in pairs(rec.slots) do slots[#slots + 1] = slot end
			table.sort(slots)
			for _, slot in ipairs(slots) do
				local sl = rec.slots[slot]
				rows[#rows + 1] = { name, realm, API.IsBankBag(bag) and "bank" or "bags", bag, slot, ItemName(sl.l), sl.c or 1, sl.i or R.ItemID(sl.l) or 0 }
			end
		end
		local eq = {}
		for k in pairs(c.equipped) do eq[#eq + 1] = k end
		table.sort(eq, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(eq) do
			local sl = c.equipped[k]
			rows[#rows + 1] = { name, realm, "equipped", 0, k, ItemName(sl.l), sl.c or 1, sl.i or R.ItemID(sl.l) or 0 }
		end
		for i, sl in ipairs(c.mail) do
			rows[#rows + 1] = { name, realm, "mail", 0, i, ItemName(sl.l), sl.c or 1, sl.i or R.ItemID(sl.l) or 0 }
		end
	end
	return rows
end

function Extras:InventoryCSV()
	local out = { "character,realm,location,bag,slot,item,count,itemID" }
	for _, r in ipairs(self:InventoryRows()) do
		local f = {}
		for i = 1, 8 do f[i] = CsvField(r[i]) end
		out[#out + 1] = table.concat(f, ",")
	end
	return table.concat(out, "\n")
end

function Extras:InventoryText()
	local totals, order = {}, {}
	for _, r in ipairs(self:InventoryRows()) do
		local key = r[6]
		if not totals[key] then totals[key] = 0; order[#order + 1] = key end
		totals[key] = totals[key] + r[7]
	end
	table.sort(order)
	local out = {}
	for _, key in ipairs(order) do out[#out + 1] = format("%dx %s", totals[key], key) end
	return table.concat(out, "\n")
end

function Extras:ShowInventory(kind)
	if kind == "text" then
		R.UI:ShowTextWindow("Inventory totals (all characters)", self:InventoryText())
	else
		R.UI:ShowTextWindow("Inventory CSV (all characters) — Ctrl+C to copy", self:InventoryCSV())
	end
end

---------------------------------------------------------------------------
-- Context auto-profiles: switch to a saved profile by spec or zone type.
-- Keys: spec1..spec4, dungeon, raid, battleground, arena, world.
-- Zone-type keys win over spec keys. Only acts out of combat.
---------------------------------------------------------------------------
Extras.CONTEXT_KEYS = { "spec1", "spec2", "spec3", "spec4", "dungeon", "raid", "battleground", "arena", "world" }

local function SpecIndex()
	local f = _G.GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
	if not f then return nil end
	local ok, idx = pcall(f)
	if ok and type(idx) == "number" and idx > 0 then return idx end
end

local ZONE_KEY = { party = "dungeon", raid = "raid", pvp = "battleground", arena = "arena" }

-- Returns the candidate context keys, most specific first.
function Extras:ContextKeys()
	local keys = {}
	local inInstance, kind = false, "none"
	if IsInInstance then inInstance, kind = IsInInstance() end
	if inInstance and ZONE_KEY[kind] then keys[#keys + 1] = ZONE_KEY[kind] end
	local spec = SpecIndex()
	if spec then keys[#keys + 1] = "spec" .. spec end
	if not inInstance then keys[#keys + 1] = "world" end
	return keys
end

function Extras:ApplyContext()
	if not R.db or not R.settings.autoProfile then return false end
	if InCombatLockdown() then self.waiting = true; return false end
	for _, key in ipairs(self:ContextKeys()) do
		local name = R.db.contextProfiles[key]
		if name and R.db.profiles[name] then
			if R.db.profileName ~= name then
				local keep = R.settings.autoProfile
				R:ApplyProfile(name, true)
				R.settings.autoProfile = keep   -- a profile never switches auto-profiles off
				R:Print("Auto-profile: " .. key .. " -> '" .. name .. "'.")
				if R.UI and R.UI.frame then
					R.UI:ApplyPosition(); R.UI:ApplySkin(); R.UI:Layout(); R:RequestRefresh()
				end
			end
			return true
		end
	end
	return false
end

function Extras:Init()
	local function trigger() R:Defer("autoprofile", function() Extras:ApplyContext() end) end
	R:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", trigger)
	R:RegisterEvent("PLAYER_ENTERING_WORLD", trigger)
	R:RegisterEvent("ZONE_CHANGED_NEW_AREA", trigger)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if Extras.waiting then Extras.waiting = false; trigger() end
	end)
end

function Extras:Command(rest)
	local sub, a, b = (rest or ""):match("^(%S*)%s*(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "on" or sub == "off" then
		R.settings.autoProfile = sub == "on"
		R:Print("Auto-profile " .. sub .. ".")
		if sub == "on" then self:ApplyContext() end
	elseif sub == "set" and a ~= "" and b ~= "" then
		local valid = false
		for _, k in ipairs(self.CONTEXT_KEYS) do if k == a then valid = true end end
		if not valid then R:Print("Unknown context. Use: " .. table.concat(self.CONTEXT_KEYS, ", ")); return end
		if not R.db.profiles[b] then R:Print("No profile named '" .. b .. "' (save one in settings first)."); return end
		R.db.contextProfiles[a] = b
		R:Print(a .. " -> '" .. b .. "'.")
	elseif sub == "clear" and a ~= "" then
		R.db.contextProfiles[a] = nil
		R:Print(a .. " cleared.")
	else
		R:Print("Auto-profile is " .. (R.settings.autoProfile and "on" or "off") .. ". Contexts: " .. table.concat(self.CONTEXT_KEYS, ", "))
		for k, v in pairs(R.db.contextProfiles) do R:Print("  " .. k .. " -> " .. v) end
		R:Print("/rum autoprofile on|off  ·  set <context> <profile>  ·  clear <context>")
	end
end
