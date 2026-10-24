-- Rummage: minimap button (LibDBIcon if available, otherwise a lightweight built-in button)
-- and a LibDataBroker launcher for Titan Panel / ElvUI datatexts / Bazooka etc.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

local MM = {}
R.Minimap = MM

local ICON = R.media .. "Icon"

local function OnClick(button)
	if button == "RightButton" then
		R.Options:Toggle()
	elseif button == "MiddleButton" or IsShiftKeyDown() then
		R.UI:Toggle("bank")
	else
		R.UI:Toggle("bags")
	end
end

local function Tooltip(tt)
	tt:AddLine("|cffd9a441Rummage|r")
	local free, total = R.Data:FreeSlots(R.Data.me, R.API.InvBagList)
	tt:AddLine(format(R.L.mmFree, free, total), 1, 1, 1)
	tt:AddLine(" ")
	tt:AddLine(R.L.mmBags, 0.8, 0.8, 0.8)
	tt:AddLine(R.L.mmBank, 0.8, 0.8, 0.8)
	tt:AddLine(R.L.mmSettings, 0.8, 0.8, 0.8)
end

function MM:Init()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if LDB then
		self.ldb = LDB:NewDataObject("Rummage", {
			type = "launcher", icon = ICON, label = "Rummage",
			OnClick = function(_, button) OnClick(button) end,
			OnTooltipShow = Tooltip,
		})
		local DBIcon = LibStub("LibDBIcon-1.0", true)
		if DBIcon and self.ldb then
			R.settings.minimap.hide = not R.settings.minimap.show
			DBIcon:Register("Rummage", self.ldb, R.settings.minimap)
			self.dbicon = DBIcon
			return
		end
	end
	self:CreateButton()
end

function MM:CreateButton()
	local b = CreateFrame("Button", "RummageMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)
	b:SetScript("OnClick", function(_, button) OnClick(button) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		Tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			R.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			MM:Position()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	self.button = b
	self:Position()
	self:Update()
end

function MM:Position()
	local b = self.button
	if not b then return end
	local a = math.rad(R.settings.minimap.angle or 200)
	local r = (Minimap:GetWidth() / 2) + 5
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function MM:Update()
	if self.dbicon then
		if R.settings.minimap.show then self.dbicon:Show("Rummage") else self.dbicon:Hide("Rummage") end
	elseif self.button then
		self.button:SetShown(R.settings.minimap.show)
	end
end
