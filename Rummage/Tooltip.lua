-- Rummage: item counts on other characters in item tooltips (Syndicator-style).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

local Tooltip = {}
R.Tooltip = Tooltip

local function Enabled()
	if not R.settings or not R.settings.tooltipCounts then return false end
	if _G.Syndicator and not R.settings.tooltipWithSyndicator then return false end
	return true
end

local function detail(bags, bank, eq, mail)
	local parts = {}
	if bags > 0 then parts[#parts + 1] = "Bags " .. bags end
	if bank > 0 then parts[#parts + 1] = "Bank " .. bank end
	if eq > 0 then parts[#parts + 1] = "Equipped " .. eq end
	if mail > 0 then parts[#parts + 1] = "Mail " .. mail end
	return table.concat(parts, ", ")
end

-- Computed lines are cached per itemID until inventory data changes. Bag tooltips are
-- re-set several times per second while hovered, so this keeps hovering allocation-free.
local lineCache = {}
local NONE = {}
R:Listen("DATA_CHANGED", function() wipe(lineCache) end)

local function BuildLines(id)
	local myRealm = GetRealmName()
	local total, shown = 0, 0
	local lines = {}
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		if not R.settings.tooltipRealmOnly or c.realm == myRealm then
			local bags, bank, eq, mail = R.Data:CountFor(c, id)
			local sum = bags + bank + eq + mail
			if sum > 0 then
				total = total + sum
				shown = shown + 1
				local name = c.name or entry.key
				if c.realm ~= myRealm then name = name .. "-" .. (c.realm or "?") end
				lines[#lines + 1] = { R.ClassColorText(c.class, name) .. ": |cffffffff" .. sum .. "|r", detail(bags, bank, eq, mail) }
			end
		end
	end
	if shown == 0 then return NONE end
	if shown > 1 then lines[#lines + 1] = { "|cffd9a441Total|r", "|cffffffff" .. total .. "|r" } end
	return lines
end

function Tooltip:Add(tt, link)
	if not Enabled() or not link then return end
	local id = R.ItemID(link)
	if not id then return end
	if tt.rummageID == id then return end
	tt.rummageID = id
	local lines = lineCache[id]
	if not lines then
		lines = BuildLines(id)
		lineCache[id] = lines
	end
	if lines == NONE then return end
	tt:AddLine(" ")
	for i = 1, #lines do
		local l = lines[i]
		tt:AddDoubleLine(l[1], l[2], 1, 1, 1, 0.65, 0.65, 0.65)
	end
	tt:Show()
end

local function OnCleared(tt) tt.rummageID = nil end

function Tooltip:Init()
	local tips = { GameTooltip, ItemRefTooltip }
	for _, tt in ipairs(tips) do
		if tt and tt.HasScript and tt:HasScript("OnTooltipCleared") then
			tt:HookScript("OnTooltipCleared", OnCleared)
		end
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
			if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
			local link
			if TooltipUtil and TooltipUtil.GetDisplayedItem then
				local _, l = TooltipUtil.GetDisplayedItem(tt)
				link = l
			elseif tt.GetItem then
				local _, l = tt:GetItem()
				link = l
			end
			if link then Tooltip:Add(tt, link) end
		end)
	else
		for _, tt in ipairs(tips) do
			if tt and tt.HasScript and tt:HasScript("OnTooltipSetItem") then
				tt:HookScript("OnTooltipSetItem", function(self)
					local _, link = self:GetItem()
					if link then Tooltip:Add(self, link) end
				end)
			end
		end
	end
end
