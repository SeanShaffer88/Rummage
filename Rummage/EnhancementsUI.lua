-- Rummage: focused rule preview, reserves, action history and context profile editors.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local Tools = { current = "preview", page = 1, filter = "All", pages = {}, rows = {} }
R.Tools = Tools
local W
local WIDTH, HEIGHT, MAX_ROWS = 660, 590, 8
local TABS = { { "preview", "Preview" }, { "keep", "Keep" }, { "history", "History" }, { "profiles", "Profiles" } }

local function Text(parent, label, x, y, width, font)
	local t = W:Text(parent, font or "normal")
	t:SetPoint("TOPLEFT", x, y); t:SetWidth(width or WIDTH - 28); t:SetJustifyH("LEFT")
	t:SetText(label or "")
	t.fontKind = font or "normal"
	t:SetHeight(math.max(12, (R.settings.fontSize or 12) + 6))
	return t
end
local function Button(parent, label, x, y, width, fn)
	local b = W:Button(parent, label, width or 112, 22, fn)
	b:SetPoint("TOPLEFT", x, y)
	if b.text then b.text:SetWidth(math.max(10, (width or 112) - 10)); b.text:SetHeight(math.max(12, (R.settings.fontSize or 12) + 6)); b.text:SetWordWrap(false) end
	W:SetTooltip(b, function(self) return self.text and self.text:GetText() end)
	return b
end
local function Edit(parent, label, x, y, width)
	local title = Text(parent, label, x, y, width)
	local e = W:EditBox(parent, width, 22)
	e:SetPoint("TOPLEFT", x, y - 20)
	e.label = title
	W:SetTooltip(e, label, function(self) return self:GetText() end)
	return e
end
local function ItemText(id, link)
	if link and link ~= "" then return link end
	if not id then return "Operation" end
	local ok, name = pcall(R.API.GetItemInfo, id)
	return (ok and name) or ("Item " .. tostring(id))
end
local function TimeText(timestamp)
	if date then local ok, text = pcall(date, "%H:%M:%S", timestamp); if ok then return text end end
	return tostring(timestamp)
end
local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end

function Tools:SetStatus(message)
	self.status:SetText(message or "")
end

local function Place(frame, x, y, width, height)
	frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", x, -y)
	if width then frame:SetWidth(width) end
	if height then frame:SetHeight(height) end
end
local function SizeButton(button, x, y, width, height, line)
	Place(button, x, y, width, height)
	if button.text then button.text:SetWidth(math.max(10, width - 10)); button.text:SetHeight(line); button.text:SetWordWrap(false) end
end

-- Typography drives geometry. Short displays use fewer rows per page, never overlapping text.
function Tools:Layout()
	local font = math.max(6, math.min(24, R.settings.fontSize or 12))
	local line, control, gap = math.ceil(font * 1.25) + 2, math.max(22, font + 12), 6
	local availableW, availableH = math.max(320, UIParent:GetWidth() - 16), math.max(400, UIParent:GetHeight() - 16)
	local width = math.max(420, math.min(math.max(WIDTH, font * 34 + 60), availableW))
	local titleH = font + 6
	local tabY = 12 + titleH + 10
	local labelY = tabY + control + 12
	local editY = labelY + line + 4
	local buttonY = editY + control + gap
	local statusY, statusH = buttonY + control + 12, line * (self.current == "profiles" and 4 or 3) + 8
	local rowY, rowH, footerH = statusY + statusH + 12, line * 2 + 8, control + 20
	local minimumH = rowY + rowH + 2 + footerH
	local height = math.max(minimumH, math.min(availableH, math.max(HEIGHT, rowY + MAX_ROWS * (rowH + 2) + footerH)))
	local count = math.max(1, math.min(MAX_ROWS, math.floor((height - rowY - footerH) / (rowH + 2))))
	self.pageSize = count
	self.layout = { line = line, control = control, rowHeight = rowH, rowTop = rowY, statusTop = statusY, statusHeight = statusH, width = width, height = height }
	self.frame:SetSize(width, height)
	Place(self.title, 14, 12, width - 140, titleH)
	SizeButton(self.close, width - 108, 10, 94, control, line)
	local tabW = (width - 28 - 3 * gap) / 4
	for i, tab in ipairs(TABS) do SizeButton(self.tabButtons[tab[1]], 14 + (i - 1) * (tabW + gap), tabY, tabW, control, line) end
	Place(self.status, 14, statusY, width - 28, statusH)
	Place(self.statusHit, 14, statusY, width - 28, statusH)
	local footerY = height - control - 12
	SizeButton(self.previous, 14, footerY, 112, control, line)
	SizeButton(self.next, width - 126, footerY, 112, control, line)
	Place(self.pageLabel, 136, footerY + (control - line) / 2, width - 272, line)
	Place(self.queryBox.label, 14, labelY, width - 28, line)
	Place(self.queryBox, 14, editY, width - 28, control)
	for i, button in ipairs({ self.previewButton, self.enableButton, self.enabledRules, self.cancel }) do
		SizeButton(button, 14 + (i - 1) * (tabW + gap), buttonY, tabW, control, line)
	end
	local fieldW = (width - 28 - gap) / 2
	for i, edit in ipairs({ self.keepID, self.keepCount }) do
		Place(edit.label, 14 + (i - 1) * (fieldW + gap), labelY, fieldW, line)
		Place(edit, 14 + (i - 1) * (fieldW + gap), editY, fieldW, control)
	end
	SizeButton(self.keepSave, 14, buttonY, 112, control, line)
	SizeButton(self.keepRemove, 132, buttonY, 112, control, line)
	SizeButton(self.filterButton, 14, editY, math.min(240, width / 2), control, line)
	SizeButton(self.clearHistory, width - 214, editY, 200, control, line)
	Place(self.autoProfile, 14, labelY, width - 28, control)
	for _, page in pairs(self.pages) do
		for i, row in ipairs(page.rows or {}) do
			Place(row, 14, rowY + (i - 1) * (rowH + 2), width - 28, rowH)
			Place(row.text, 0, 0, width - 38, line)
			Place(row.detail, 0, line + 4, width - 38, line)
		end
	end
	local profileH = control + gap
	self.profilePageSize = math.max(1, math.min(9, math.floor((height - rowY - footerH) / profileH)))
	for i, row in ipairs(self.profileRows) do
		local visible = math.floor((i - 1) / self.profilePageSize) + 1 == self.page
		row.label:SetShown(visible); row.button:SetShown(visible); row.clear:SetShown(visible)
		local y = rowY + ((i - 1) % self.profilePageSize) * profileH
		local labelW, clearW = math.max(104, font * 7.5), math.max(74, font * 3 + 20)
		Place(row.label, 14, y + (control - line) / 2, labelW, line)
		SizeButton(row.button, 14 + labelW + gap, y, width - 28 - labelW - clearW - 2 * gap, control, line)
		SizeButton(row.clear, width - 14 - clearW, y, clearW, control, line)
	end
end

function Tools:ApplyPosition()
	local f = self.frame
	local scale = math.min(1, (UIParent:GetWidth() - 12) / f:GetWidth(), (UIParent:GetHeight() - 12) / f:GetHeight())
	f:SetScale(math.max(0.25, scale)); f:ClearAllPoints()
	local p = R.settings.toolsPoint
	if p and R.ValidPoint(p) then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else f:SetPoint("CENTER") end
	f:SetClampedToScreen(true)
end

function Tools:InvalidatePreview()
	self.preview, self.previewText = nil, nil
	self.enableButton:SetDisabledLook(true)
	self.page = 1
	if self.current == "preview" then self:Refresh() end
end

function Tools:RunPreview()
	self.queryBox:ClearFocus()
	local result, err = R.Junk:PreviewRule(self.queryBox:GetText())
	self.preview = result
	self.previewText = result and self.queryBox:GetText() or nil
	self.page = 1
	self.previewError = err
	self:Refresh()
end

function Tools:EnablePreview()
	if not self.preview or self.previewText ~= self.queryBox:GetText() then return end
	local ok, err = R.Junk:EnableRule(self.preview)
	if ok then
		self.preview, self.previewText = nil, nil
		self.previewError = "Rule Enabled. Remove It From Enabled Rules To Disable It."
	else self.previewError = err or "Rule Could Not Be Enabled" end
	self:Refresh()
end

function Tools:ShowEnabledRules(anchor)
	local menu = { { text = "Enabled Rules — Select To Remove", isTitle = true } }
	for i, query in ipairs(R.db.junkRules) do
		local index, expected = i, query
		menu[#menu + 1] = { text = query, func = function()
			if R.db.junkRules[index] == expected then table.remove(R.db.junkRules, index) end
			R:RequestRefresh(); Tools:Refresh()
		end }
	end
	if #R.db.junkRules == 0 then menu[#menu + 1] = { text = "No Enabled Rules", disabled = true } end
	W:Menu(anchor, menu)
end

function Tools:SaveKeep(remove)
	self.keepID:ClearFocus(); self.keepCount:ClearFocus()
	local id = tonumber(Trim(self.keepID:GetText()))
	local count = remove and 0 or tonumber(Trim(self.keepCount:GetText()))
	local ok, err = R.Junk:SetKeep(id, count)
	self.keepMessage = ok and (remove and "Reserve Removed" or "Reserve Saved") or (err or "Enter A Valid Item ID And Whole Quantity")
	if ok then
		self.previewError = "Keep Quantities Changed. Preview This Query Again Before Enabling It."
		self:InvalidatePreview()
	end
	self:Refresh()
end

function Tools:MapProfile(key, name)
	local ok, err = R.Extras:SetContextMapping(key, name)
	if ok and R.settings.autoProfile then R.Extras:ApplyContext() end
	self.profileMessage = err
	self:Refresh()
end

function Tools:ChooseProfile(key, anchor)
	local menu = { { text = "Profile For " .. key, isTitle = true } }
	local context = key
	menu[#menu + 1] = { text = "None", checked = not R.db.contextProfiles[context], func = function()
		Tools:MapProfile(context, nil)
	end }
	local names = {}
	for name in pairs(R.db.profiles) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local selectedName = name
		menu[#menu + 1] = { text = selectedName, checked = R.db.contextProfiles[context] == selectedName, func = function()
			Tools:MapProfile(context, selectedName)
		end }
	end
	if #names == 0 then menu[#menu + 1] = { text = "No Profiles — Save One In General Settings", disabled = true } end
	W:Menu(anchor, menu)
end

local function Rows(parent, startY)
	local rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, parent)
		row:SetSize(WIDTH - 28, 40); row:SetPoint("TOPLEFT", 14, startY - (i - 1) * 42)
		row.text = Text(row, "", 0, 0, WIDTH - 38, "small")
		row.detail = Text(row, "", 0, -18, WIDTH - 38, "small")
		W:SetTooltip(row, function(self) return self.text:GetText() end, function(self) return self.detail:GetText() end)
		row:SetScript("OnClick", function(self)
			if Tools.current == "keep" and self.record then
				Tools.keepID:SetText(tostring(self.record.id)); Tools.keepCount:SetText(tostring(self.record.count))
			elseif Tools.current == "history" and self.record then
				Tools.selectedID = self.record.id
				Tools:SetStatus((self.record.reason or "") .. (self.record.from and ("  From: " .. self.record.from) or "") .. (self.record.to and ("  To: " .. self.record.to) or ""))
			end
		end)
		rows[i] = row
	end
	return rows
end

function Tools:Create()
	if self.frame then return end
	W = R.Widgets
	local f = CreateFrame("Frame", "RummageToolsFrame", UIParent, R.API.Backdrop)
	f:SetSize(WIDTH, HEIGHT); f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local p, _, rp, x, y = frame:GetPoint()
		local saved = { p, rp, x, y }
		if R.ValidPoint(saved) then R.settings.toolsPoint = saved end
	end)
	f:SetScript("OnHide", function()
		for _, e in ipairs({ Tools.queryBox, Tools.keepID, Tools.keepCount }) do if e then e:ClearFocus() end end
	end)
	f:Hide(); self.frame = f
	table.insert(UISpecialFrames, "RummageToolsFrame")
	self.title = Text(f, "Rummage Tools", 14, -12, 300, "title")
	self.close = Button(f, "Close", WIDTH - 82, -10, 68, function() f:Hide() end)
	self.tabButtons = {}
	for i, tab in ipairs(TABS) do
		local key = tab[1]
		self.tabButtons[key] = Button(f, tab[2], 14 + (i - 1) * 112, -42, 108, function() Tools:Show(key) end)
	end
	self.status = Text(f, "", 14, -126, WIDTH - 28, "small")
	self.status:SetHeight(64); self.status:SetWordWrap(true)
	self.statusHit = CreateFrame("Frame", nil, f)
	self.statusHit:EnableMouse(true)
	W:SetTooltip(self.statusHit, "Details", function() return Tools.status:GetText() end)
	self.pageLabel = Text(f, "", 224, -559, 210, "small")
	self.previous = Button(f, "Previous", 14, -552, 100, function() Tools.page = math.max(1, Tools.page - 1); Tools:Refresh() end)
	self.next = Button(f, "Next", WIDTH - 114, -552, 100, function() Tools.page = Tools.page + 1; Tools:Refresh() end)

	local preview = CreateFrame("Frame", nil, f); preview:SetAllPoints(); self.pages.preview = preview
	self.queryBox = Edit(preview, "Rule Query", 14, -76, 310); self.queryBox:SetMaxLetters(512)
	self.queryBox:SetScript("OnTextChanged", function() Tools.previewError = nil; Tools:InvalidatePreview() end)
	self.queryBox:SetScript("OnEnterPressed", function() Tools:RunPreview() end)
	self.previewButton = Button(preview, "Preview", 332, -96, 86, function() Tools:RunPreview() end)
	self.enableButton = Button(preview, "Enable Rule", 424, -96, 104, function() Tools:EnablePreview() end)
	self.enabledRules = Button(preview, "Enabled Rules", 534, -96, 112, function(b) Tools:ShowEnabledRules(b) end)
	self.cancel = Button(preview, "Cancel Draft", 534, -72, 112, function()
		Tools.queryBox:SetText(""); Tools.previewError = nil; Tools:InvalidatePreview(); f:Hide()
	end)
	preview.rows = Rows(preview, -202)

	local keep = CreateFrame("Frame", nil, f); keep:SetAllPoints(); self.pages.keep = keep
	self.keepID = Edit(keep, "Item ID", 14, -76, 140)
	self.keepCount = Edit(keep, "Keep Quantity", 166, -76, 140)
	self.keepSave = Button(keep, "Save", 318, -96, 86, function() Tools:SaveKeep(false) end)
	self.keepRemove = Button(keep, "Remove", 410, -96, 90, function() Tools:SaveKeep(true) end)
	self.keepID:SetScript("OnEnterPressed", function() Tools.keepCount:SetFocus() end)
	self.keepCount:SetScript("OnEnterPressed", function() Tools:SaveKeep(false) end)
	keep.rows = Rows(keep, -202)

	local history = CreateFrame("Frame", nil, f); history:SetAllPoints(); self.pages.history = history
	self.filterButton = Button(history, "Filter: All", 14, -86, 160, function(b)
		local menu = {}
		for _, value in ipairs({ "All", "Sales", "Buyback", "Transfers", "Skipped" }) do
			local filter = value
			menu[#menu + 1] = { text = filter, checked = Tools.filter == filter, func = function() Tools.filter = filter; Tools.page = 1; Tools.selectedID = nil; Tools:Refresh() end }
		end
		W:Menu(b, menu)
	end)
	self.clearHistory = Button(history, "Clear History", WIDTH - 132, -86, 118, function() StaticPopup_Show("RUMMAGE_CLEAR_HISTORY") end)
	history.rows = Rows(history, -202)
	StaticPopupDialogs.RUMMAGE_CLEAR_HISTORY = {
		text = "Clear Rummage Action History? This Cannot Be Undone.", button1 = YES, button2 = CANCEL,
		OnAccept = function() R.ActionHistory:Clear(); Tools.selectedID = nil; Tools:Refresh() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}

	local profiles = CreateFrame("Frame", nil, f); profiles:SetAllPoints(); self.pages.profiles = profiles
	self.autoProfile = W:Check(profiles, "Automatically Switch Profiles", function() return R.settings.autoProfile end, function(v)
		R.settings.autoProfile = v
		if v then R.Extras:ApplyContext() end
		Tools:Refresh()
	end)
	self.autoProfile:SetPoint("TOPLEFT", 14, -84); self.autoProfile:SetWidth(300)
	self.profileRows = {}
	for i, key in ipairs(R.Extras.CONTEXT_KEYS) do
		local context = key
		local row = { key = context }
		row.label = Text(profiles, context:sub(1, 1):upper() .. context:sub(2), 14, -202 - (i - 1) * 32, 130)
		row.button = Button(profiles, "None", 150, -196 - (i - 1) * 32, 410, function(b) Tools:ChooseProfile(context, b) end)
		row.clear = Button(profiles, "Clear", 570, -196 - (i - 1) * 32, 76, function()
			Tools:MapProfile(context, nil)
		end)
		self.profileRows[i] = row
	end
	R:Listen("ACTION_HISTORY_CHANGED", function() if Tools.frame:IsShown() and Tools.current == "history" then Tools:Refresh() end end)
	R:RegisterEvent("DISPLAY_SIZE_CHANGED", function() if Tools.frame:IsShown() then Tools:Refresh(); Tools:ApplyPosition() end end)
	R:RegisterEvent("PLAYER_REGEN_ENABLED", function() if Tools.frame:IsShown() and Tools.current == "profiles" then Tools:Refresh() end end)
end

function Tools:Refresh()
	if not self.frame then return end
	self:Layout()
	W:Backdrop(self.frame, "main")
	for key, page in pairs(self.pages) do page:SetShown(key == self.current); self.tabButtons[key]:SetActive(key == self.current) end
	local records, pages, total = {}, 1, 0
	if self.current == "preview" then
		local p = self.preview
		self.enableButton:SetDisabledLook(not p or self.previewText ~= self.queryBox:GetText() or #R.db.junkRules >= 8)
		if p then
			records = p.rows or {}; total = #records
			self:SetStatus(string.format("Matched: %d Stacks / %d Units  |  Planned Sale: %d Units / %s\nRetained: %d Units  |  Excluded: %d Units. Preview Does Not Sell Or Enable A Rule.", p.matchedStacks or 0, p.matchedUnits or 0, p.sellUnits or 0, R.FormatMoney(p.value or 0), p.retainedUnits or 0, p.excludedUnits or 0))
		else self:SetStatus(self.previewError or "Enter A Rule And Preview Your Current Bags Before Enabling It.\nFavorites, Equipment Sets, Unpriced And Locked Items Stay Protected.") end
	elseif self.current == "keep" then
		for id, count in pairs(R.db.keepQuantities) do records[#records + 1] = { id = id, count = count } end
		table.sort(records, function(a, b) return a.id < b.id end); total = #records
		self:SetStatus((self.keepMessage and (self.keepMessage .. "\n") or "") .. "Across Your Current Bags; Bank And Alts Excluded.\nSelect A Reserve To Edit It. Zero Or Remove Clears A Reserve.")
	elseif self.current == "history" then
		records, total, pages = R.ActionHistory:Page(self.filter, self.page, self.pageSize)
		self.filterButton:SetLabel("Filter: " .. self.filter)
		local selected
		for _, record in ipairs(R.db.actionHistory) do if record.id == self.selectedID then selected = record; break end end
		self:SetStatus(selected and ((selected.reason or "") .. (selected.from and ("  From: " .. selected.from) or "") .. (selected.to and ("  To: " .. selected.to) or "")) or "Observed Means The Inventory Change Was Seen; Requested Is Unconfirmed.\nMail/Trade Placement Does Not Mean Sent Or Accepted. Select A Row For Details.")
	elseif self.current == "profiles" then
		self.autoProfile:Update()
		local resolved = "None"
		for _, key in ipairs(R.Extras:ContextKeys()) do
			local name = R.db.contextProfiles[key]
			if name and R.db.profiles[name] then resolved = key .. " -> " .. name; break end
		end
		local any = next(R.db.profiles) ~= nil
		self:SetStatus((self.profileMessage and (self.profileMessage .. "\n") or "") .. (not any and "No Profiles: Save A Profile In General Settings First.\n" or "") .. "Instance Type Wins, Then Spec, Then World Outside Instances.\nCurrent: " .. resolved .. (InCombatLockdown() and " — Switching Waits For Combat To End." or ""))
		for _, row in ipairs(self.profileRows) do
			local name = R.db.contextProfiles[row.key]
			row.button:SetLabel(not name and "None" or (R.db.profiles[name] and name or ("Unavailable: " .. name)))
		end
	end
	local page = self.pages[self.current]
	self.rows = page.rows or {}
	if self.current == "profiles" then total = #self.profileRows; pages = math.max(1, math.ceil(total / self.profilePageSize))
	elseif self.current ~= "history" then pages = math.max(1, math.ceil(total / self.pageSize)) end
	self.page = math.max(1, math.min(self.page, pages))
	if self.current == "profiles" then
		for i, row in ipairs(self.profileRows) do
			local visible = math.floor((i - 1) / self.profilePageSize) + 1 == self.page
			row.label:SetShown(visible); row.button:SetShown(visible); row.clear:SetShown(visible)
		end
	end
	for i, row in ipairs(self.rows) do
		local record = i <= self.pageSize and records[self.current == "history" and i or ((self.page - 1) * self.pageSize + i)] or nil
		row.record = record
		row:SetShown(record ~= nil)
		if record then
			if self.current == "preview" then
				row.text:SetText(ItemText(record.id, record.link) .. "  ×" .. tostring(record.count or 0))
				row.detail:SetText("Planned Sale: " .. tostring(record.sellCount or 0) .. "  |  " .. (record.reason or "Eligible") .. "  |  " .. (record.value == nil and "Value Unknown" or R.FormatMoney(record.value)))
			elseif self.current == "keep" then
				row.text:SetText(ItemText(record.id) .. "  (" .. record.id .. ")")
				row.detail:SetText("Keep " .. record.count .. " Across Current Bags")
			else
				row.text:SetText(TimeText(record.t) .. "  " .. record.action .. "  " .. ItemText(record.itemID, record.link) .. "  ×" .. tostring(record.count or 0))
				row.detail:SetText(record.status .. "  |  " .. (record.reason or ""))
			end
		else row.text:SetText(""); row.detail:SetText("") end
	end
	local paged = self.current ~= "profiles" or pages > 1
	self.previous:SetShown(paged); self.next:SetShown(paged); self.pageLabel:SetShown(paged)
	self.previous:SetDisabledLook(self.page <= 1); self.next:SetDisabledLook(self.page >= pages)
	self.pageLabel:SetText(total == 0 and (self.current == "history" and "No Actions Recorded" or (self.current == "keep" and "No Reserves Saved" or "No Matches")) or ("Page " .. self.page .. " / " .. pages .. "  (" .. total .. ")"))
end

function Tools:Show(tab)
	self:Create()
	local wanted = tab or self.current
	if not self.pages[wanted] then wanted = "preview" end
	if wanted ~= self.current then self.page = 1 end
	self.current = wanted
	self:Refresh(); self:ApplyPosition(); self.frame:Show()
end
