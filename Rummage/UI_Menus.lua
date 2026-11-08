-- Rummage: window menus and popups (search history, presets, character menu, dialogs).
-- Split out of UI.lua in 1.5.0; shares the UI table through R.UI.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API
local UI = R.UI
local W = R.Widgets

local pairs, ipairs, type, wipe, tostring = pairs, ipairs, type, wipe, tostring
local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local InCombatLockdown = InCombatLockdown

---------------------------------------------------------------------------
-- Menus & popups
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Search history, sort presets, cross-character search
---------------------------------------------------------------------------
function UI:RecordSearch(text)
	text = text and text:match("^%s*(.-)%s*$")
	if not text or text == "" then return end
	local h = R.db.searchHistory
	if not h then return end
	for i = #h, 1, -1 do
		if h[i] == text then table.remove(h, i) end
	end
	table.insert(h, 1, text)
	while #h > 10 do table.remove(h) end
end

function UI:ShowHistoryMenu(anchor)
	local items = { { text = "Recent searches", isTitle = true } }
	local h = R.db.searchHistory or {}
	if #h == 0 then
		items[#items + 1] = { text = "(none yet)", disabled = true }
	end
	for _, q in ipairs(h) do
		items[#items + 1] = { text = q, func = function() UI.searchBox:SetText(q) end }
	end
	items[#items + 1] = { text = "Save current search", func = function() UI:SaveCurrentSearch() end }
	if #h > 0 then
		items[#items + 1] = { text = "Clear history", func = function() wipe(R.db.searchHistory) end }
	end
	W:Menu(anchor, items)
end

function UI:ShowPresetMenu(anchor)
	local s = R.settings
	local items = { { text = "Sort presets", isTitle = true } }
	local presets = R.db.sortPresets or {}
	if #presets == 0 then
		items[#items + 1] = { text = "(none saved)", disabled = true }
	end
	for i, pr in ipairs(presets) do
		items[#items + 1] = {
			text = pr.name,
			checked = s.sortKey == pr.sortKey and s.sortAsc == pr.sortAsc
				and s.groupBy == pr.groupBy and s.viewMode == pr.viewMode,
			func = function()
				s.sortKey, s.sortAsc = pr.sortKey, pr.sortAsc
				s.groupBy, s.viewMode = pr.groupBy, pr.viewMode
				s.favoritesFirst, s.newFirst = pr.favoritesFirst, pr.newFirst
				UI.offset = 0
				UI:Layout()
			end,
			onDelete = function()
				table.remove(R.db.sortPresets, i)
				R:Print("Preset '" .. pr.name .. "' deleted.")
			end,
		}
	end
	items[#items + 1] = { text = "Save current as preset...", func = function()
		StaticPopup_Show("RUMMAGE_NEW_PRESET")
	end }
	W:Menu(anchor, items)
end

-- Snapshot entries for every character (cross-character search). Items:Build
-- recycles its pooled entries on the next call, so matching data is copied
-- into plain tables here; the copies are only ever displayed, never acted on
-- (Render forces interactive=false while this mode is active).
function UI:BuildAllChars(view)
	local out = {}
	local Items = R.Items
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		local built = Items:Build(c, view)
		for i = 1, #built do
			local e = built[i]
			Items:Prepare(e, c, c == R.Data.me, false)
			local slotsCopy = {}
			for j = 1, #e.slots do slotsCopy[j] = { e.slots[j][1], e.slots[j][2] } end
			out[#out + 1] = {
				link = e.link, id = e.id, count = e.count, bag = e.bag, slot = e.slot,
				slots = slotsCopy, icon = e.icon, q = e.q, bound = e.bound,
				info = e.info, name = e.name, lname = e.lname, quality = e.quality,
				fav = e.fav, new = e.new, acquired = e.acquired, junk = e.junk,
				owner = c.name, foreign = c ~= R.Data.me, vals = {},
			}
		end
	end
	return out
end

function UI:ShowCharMenu(anchor)
	local items = { { text = "Characters", isTitle = true } }
	local current = self:Char()
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		local label = R.ClassColorText(c.class, c.name or entry.key)
		if c.realm ~= GetRealmName() then label = label .. " |cff888888- " .. (c.realm or "?") .. "|r" end
		if c.level then label = label .. " |cff888888(" .. c.level .. ")|r" end
		if entry.key ~= R.charKey and c.lastSeen then
			local age = R.FormatAge(c.lastSeen)
			if age ~= "" then label = label .. " |cff" .. (R.IsStale(c) and "c06060" or "777777") .. age .. " ago|r" end
		end
		local item = {
			text = label, checked = c == current,
			func = function()
				UI:SaveViewLayout(UI:ViewKey())
				UI.charKey = (entry.key ~= R.charKey) and entry.key or nil
				UI:ApplyViewLayout(UI:ViewKey())
				UI.offset = 0
				UI.bagFilter = nil
				R:RequestRefresh()
			end,
		}
		if entry.key ~= R.charKey then
			item.onDelete = function()
				StaticPopup_Show("RUMMAGE_DELETE_CHAR", entry.key, nil, entry.key)
			end
		end
		items[#items + 1] = item
	end
	W:Menu(anchor, items)
end

function UI:ShowCategoryMenu(anchor, cat)
	local idx = cat.custom
	W:Menu(anchor, {
		{ text = cat.name, isTitle = true },
		{ text = "Edit filter...", func = function() StaticPopup_Show("RUMMAGE_EDIT_CATEGORY", cat.name, nil, idx) end },
		{ text = "Rename...", func = function() StaticPopup_Show("RUMMAGE_RENAME_CATEGORY", cat.name, nil, idx) end },
		{ text = "Use current search as filter", func = function()
			R.db.categories[idx].query = UI.search
			R:RequestRefresh()
		end },
		{ text = "Move up", func = function() R.Categories:MoveCustom(idx, -1); R:RequestRefresh() end },
		{ text = "Move down", func = function() R.Categories:MoveCustom(idx, 1); R:RequestRefresh() end },
		{ text = "|cffff6060Delete|r", func = function()
			R.Categories:RemoveCustom(idx)
			if UI.category == cat.id then UI:SetCategory("all") end
			R:RequestRefresh()
		end },
	}, "TOPLEFT", "TOPRIGHT", 2, 0)
end

function UI:PromptNewCategory()
	StaticPopup_Show("RUMMAGE_NEW_CATEGORY")
end

local function EditBoxOf(dialog)
	return dialog.editBox or dialog.EditBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
end

function UI:RegisterPopups()
	StaticPopupDialogs["RUMMAGE_NEW_CATEGORY"] = {
		text = "Name for the new category?\n(Its filter will be the current search: \"%s\")",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name ~= "" then
				local idx = R.Categories:AddCustom(name, UI.search)
				UI:SetCategory("custom" .. idx)
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_NEW_CATEGORY"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_EDIT_CATEGORY"] = {
		text = "Filter for %s:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 200,
		OnShow = function(self, idx)
			local eb = EditBoxOf(self)
			local def = R.db.categories[idx]
			if eb and def then eb:SetText(def.query or ""); eb:SetFocus(); eb:HighlightText() end
		end,
		OnAccept = function(self, idx)
			local eb = EditBoxOf(self)
			if eb and R.db.categories[idx] then
				R.db.categories[idx].query = eb:GetText() or ""
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_EDIT_CATEGORY"].OnAccept(p, p.data)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_RENAME_CATEGORY"] = {
		text = "Rename %s:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self, idx)
			local eb = EditBoxOf(self)
			local def = R.db.categories[idx]
			if eb and def then eb:SetText(def.name or ""); eb:SetFocus(); eb:HighlightText() end
		end,
		OnAccept = function(self, idx)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name ~= "" and R.db.categories[idx] then
				R.db.categories[idx].name = name
				R:RequestRefresh()
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_RENAME_CATEGORY"].OnAccept(p, p.data)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_SELL_CONFIRM"] = {
		text = "Sell %s junk item(s) for %s?\nThis sale includes Uncommon or better items, or is worth more than your safeguard value.",
		button1 = YES, button2 = NO,
		OnAccept = function() R.Junk:SellAll(true) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_DELETE_CHAR"] = {
		text = "Forget all cached data for %s?",
		button1 = YES, button2 = NO,
		OnAccept = function(_, key)
			R.db.chars[key] = nil
			if UI.charKey == key then UI.charKey = nil end
			R:Fire("DATA_CHANGED")
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_CONFIRM_TRANSFER"] = {
		text = "Move EVERY listed item to your %s?",
		button1 = YES, button2 = NO,
		OnAccept = function()
			UI.transferConfirmed = true
			UI:DoTransfer()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_BUY_BANK_SLOT"] = {
		text = "Purchase the next bank bag slot?",
		button1 = YES, button2 = NO,
		OnShow = function(self)
			local cost = GetBankSlotCost and GetBankSlotCost((GetNumBankSlots and GetNumBankSlots()) or 0)
			local t = self.text or self.Text
			if t and cost then
				t:SetText("Purchase the next bank bag slot for " .. R.FormatMoney(cost) .. "?")
			end
		end,
		OnAccept = function()
			if PurchaseSlot then PurchaseSlot() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_NEW_PRESET"] = {
		text = "Name for this sort preset?\n(It saves the current sort, grouping and view settings.)",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 40,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local name = eb and eb:GetText() or ""
			if name == "" then return end
			local s = R.settings
			for i, pr in ipairs(R.db.sortPresets) do
				if pr.name == name then table.remove(R.db.sortPresets, i); break end
			end
			R.db.sortPresets[#R.db.sortPresets + 1] = {
				name = name, sortKey = s.sortKey, sortAsc = s.sortAsc,
				groupBy = s.groupBy, viewMode = s.viewMode,
				favoritesFirst = s.favoritesFirst, newFirst = s.newFirst,
			}
			R:Print("Preset '" .. name .. "' saved.")
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_NEW_PRESET"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_EXPORT_SETTINGS"] = {
		text = "Your Rummage settings string (settings, columns, custom categories, auto-junk rules). Copy it somewhere safe:",
		button1 = CLOSE, hasEditBox = true, maxLetters = 0,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(R:ExportSettings()); eb:SetFocus(); eb:HighlightText() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs["RUMMAGE_IMPORT_SETTINGS"] = {
		text = "Paste a Rummage settings string (RUM1;...). It replaces your settings, custom categories and auto-junk rules:",
		button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 0,
		OnShow = function(self)
			local eb = EditBoxOf(self)
			if eb then eb:SetText(""); eb:SetFocus() end
		end,
		OnAccept = function(self)
			local eb = EditBoxOf(self)
			local ok, err = R:ImportSettings(eb and eb:GetText() or "")
			if ok then R:Print("Settings imported.")
			else R:Print("Import failed: " .. tostring(err)) end
		end,
		EditBoxOnEnterPressed = function(self)
			local p = self:GetParent()
			StaticPopupDialogs["RUMMAGE_IMPORT_SETTINGS"].OnAccept(p)
			p:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

---------------------------------------------------------------------------
-- Copy window (inventory export, 1.5.0): a read-only multi-line box to Ctrl+C from.
---------------------------------------------------------------------------
function UI:ShowTextWindow(title, text)
	local f = self.textWindow
	if not f then
		f = CreateFrame("Frame", "RummageTextWindow", UIParent, API.Backdrop)
		f:SetSize(520, 360)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		f.title = W:Text(f, "normal")
		f.title:SetPoint("TOPLEFT", 12, -10)
		local scroll = CreateFrame("ScrollFrame", "RummageTextWindowScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -34)
		scroll:SetPoint("BOTTOMRIGHT", -30, 40)
		local eb = CreateFrame("EditBox", nil, scroll)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetWidth(470)
		eb:SetFontObject(ChatFontNormal or GameFontHighlight)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(eb)
		f.edit = eb
		local close = W:Button(f, CLOSE, 80, 22, function() f:Hide() end)
		close:SetPoint("BOTTOMRIGHT", -12, 10)
		tinsert(UISpecialFrames, "RummageTextWindow")
		self.textWindow = f
	end
	f.title:SetText(title or "")
	f.edit:SetText(text or "")
	f.edit:HighlightText()
	f:Show()
	f.edit:SetFocus()
end
