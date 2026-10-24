-- Rummage: optional integrations — Auctionator, TradeSkillMaster, Pawn (arrow + upgrade %),
-- Can I Mog It?, Scrap (see Junk.lua), Syndicator (see Tooltip.lua).
-- Every integration activates only when that addon is loaded.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local I = {}
R.Integrations = I
I.active = {}

local function stackMul(e, p)
	if p and R.settings.stackValue then return p * e.count end
	return p
end

local function money(_, v) return v and v > 0 and R.FormatMoney(v, true) or "" end

---------------------------------------------------------------------------
-- Auctionator
---------------------------------------------------------------------------
local function AuctionatorAPI()
	local A = _G.Auctionator
	return A and A.API and A.API.v1
end

function I:InitAuctionator()
	local api = AuctionatorAPI()
	if not api or not api.GetAuctionPriceByItemLink then return end
	I.active.Auctionator = true
	R.Columns:Register({ key = "ah", title = "Auction", width = 86, align = "RIGHT", label = "Auctionator: auction price",
		available = function() return AuctionatorAPI() ~= nil end,
		value = function(e)
			if e.bound then return nil end
			local ok, p = pcall(api.GetAuctionPriceByItemLink, "Rummage", e.link)
			return stackMul(e, ok and p or nil)
		end,
		text = money })
	if api.GetDisenchantPriceByItemLink then
		R.Columns:Register({ key = "ahde", title = "Disench.", width = 80, align = "RIGHT", hidden = true,
			label = "Auctionator: disenchant value",
			value = function(e)
				local ok, p = pcall(api.GetDisenchantPriceByItemLink, "Rummage", e.link)
				return ok and p or nil
			end,
			text = money })
	end
end

---------------------------------------------------------------------------
-- TradeSkillMaster
---------------------------------------------------------------------------
function I:InitTSM()
	local T = _G.TSM_API
	if not (T and T.GetCustomPriceValue and T.ToItemString) then return end
	I.active.TradeSkillMaster = true
	local col = { key = "tsm", width = 86, align = "RIGHT", label = "TSM: custom price source",
		value = function(e)
			local okS, itemString = pcall(T.ToItemString, e.link)
			if not okS or not itemString then return nil end
			local ok, p = pcall(T.GetCustomPriceValue, R.settings.tsmSource, itemString)
			return stackMul(e, ok and p or nil)
		end,
		text = money }
	col.title = "TSM"
	R.Columns:Register(col)
end

---------------------------------------------------------------------------
-- Pawn (upgrade arrow + upgrade percentage, Sorted-Pawn and Sorted-Pawn-Reloaded)
---------------------------------------------------------------------------
local pawnCache = {}
local PAWN_ARROW = "|TInterface\\AddOns\\Pawn\\Textures\\UpgradeArrow:0|t"

function I:PawnAvailable()
	return type(_G.PawnGetItemData) == "function" and type(_G.PawnIsItemAnUpgrade) == "function"
end

-- Returns nil if not an upgrade, else the best upgrade fraction (0 when Pawn gives no %).
function I:PawnUpgrade(e)
	if not self:PawnAvailable() then return nil end
	if not (e.info and e.info.equippable) then return nil end
	local cached = pawnCache[e.link]
	if cached ~= nil then return cached or nil end
	local ok, item = pcall(_G.PawnGetItemData, e.link)
	if not ok or not item then return nil end -- not cached by Pawn yet; try again later
	local result = false
	local ok2, upgrades = pcall(_G.PawnIsItemAnUpgrade, item)
	if ok2 and type(upgrades) == "table" then
		local best
		for _, u in pairs(upgrades) do
			if type(u) == "table" then
				local p = tonumber(u.PercentUpgrade) or 0
				if p > 1000 then p = 0 end -- empty slot: Pawn reports a huge value
				if not best or p > best then best = p end
			end
		end
		if best then result = best end
	elseif type(_G.PawnShouldItemLinkHaveUpgradeArrow) == "function" then
		local ok3, arrow = pcall(_G.PawnShouldItemLinkHaveUpgradeArrow, e.link)
		if ok3 and arrow then result = 0 end
	end
	pawnCache[e.link] = result
	return result or nil
end

function I:ResetPawn() wipe(pawnCache) end

function I:InitPawn()
	if not self:PawnAvailable() then return end
	I.active.Pawn = true
	R.Columns:Register({ key = "pawn", title = "Pawn", width = 58, align = "RIGHT", label = "Pawn: upgrade %",
		available = function() return I:PawnAvailable() end,
		value = function(e) return I:PawnUpgrade(e) or -1 end,
		text = function(_, v)
			if not v or v < 0 then return "" end
			if v > 0 then return format("%s|cff40ff40+%.0f%%|r", PAWN_ARROW, v * 100) end
			return PAWN_ARROW
		end })
	R:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() I:ResetPawn() end)
	R:RegisterEvent("PLAYER_LEVEL_UP", function() I:ResetPawn() end)
end

---------------------------------------------------------------------------
-- Can I Mog It?
---------------------------------------------------------------------------
function I:InitCanIMogIt()
	local C = _G.CanIMogIt
	if type(C) ~= "table" or type(C.GetTooltipText) ~= "function" then return end
	I.active.CanIMogIt = true
	R.Columns:Register({ key = "cimi", title = "Mog", width = 120, label = "Can I Mog It?",
		value = function(e)
			if not (e.info and e.info.equippable) then return "" end
			local ok, text = pcall(C.GetTooltipText, C, e.link, e.bag, e.slot)
			return ok and type(text) == "string" and text or ""
		end,
		text = function(_, v) return v or "" end })
end

---------------------------------------------------------------------------
-- Badges drawn on icons (grid view and list icon)
---------------------------------------------------------------------------
function I:UpgradeBadge(e)
	return self:PawnUpgrade(e) ~= nil
end

function I:Init()
	self:InitAuctionator()
	self:InitTSM()
	self:InitPawn()
	self:InitCanIMogIt()
	if R.Junk.ScrapAvailable() then I.active.Scrap = true end
	if _G.Syndicator then I.active.Syndicator = true end
end

function I:Summary()
	local t = {}
	for k in pairs(self.active) do t[#t + 1] = k end
	table.sort(t)
	return #t > 0 and table.concat(t, ", ") or "none"
end
