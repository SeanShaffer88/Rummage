-- Rummage: native read-only planning views and explicit restock confirmation.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, P = ns.R, { current = "restock", page = 1, rows = {}, forecastKind = "sale" }
R.Planning = P
local W
local TABS = { { "restock", "Restock" }, { "rules", "Rules" }, { "vendor", "Vendor" }, { "forecast", "Forecast" } }
local MAX_ROWS = 8
local function place(frame, x, y, width, height)
 frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", x, -y); frame:SetSize(width, height)
end
local function text(parent, value, font)
 local t = W:Text(parent, font or "normal"); t:SetText(value or ""); t:SetWordWrap(false); t:SetJustifyH("LEFT")
 return t
end
local function button(parent, value, fn)
 local b = W:Button(parent, value, 100, 24, fn)
 W:SetTooltip(b, function(self) return self.text:GetText() end)
 return b
end
local function edit(parent, label)
 local e = W:EditBox(parent, 100, 24); e.label = text(parent, label)
 W:SetTooltip(e, label, function(self) return self:GetText() end)
 e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
 return e
end
local function setButton(b, x, y, width, height, line)
 place(b, x, y, width, height); b.text:SetSize(math.max(1, width - 12), line); b.text:SetWordWrap(false)
end
local function itemName(id)
 local ok, value = pcall(R.API.GetItemInfo, id)
 return ok and value or ("Item " .. tostring(id))
end
function P:Invalidate(reason)
 self.preview, self.result = nil, nil; self.page = 1
 self.message = reason or "Preview Again Before Executing"
 if self.frame and self.frame:IsShown() and self.current ~= "vendor" then self:Refresh() end
end
function P:SaveTarget(remove)
 self.restockID:ClearFocus(); self.restockCount:ClearFocus()
 local ok, err = R.Restock:SetTarget(tonumber(self.restockID:GetText()), remove and 0 or tonumber(self.restockCount:GetText()))
 self:Invalidate(ok and (remove and "Target Removed" or "Target Saved — Preview Required") or err)
end
function P:Run()
 self.page = 1; self.message = nil
 if self.current == "restock" then
  self.preview, self.message = R.Restock:Preview(); self.result = nil
 elseif self.current == "rules" then
  self.queryBox:ClearFocus(); self.result, self.message = R.RuleDiagnostics:AnalyzeRules(self.queryBox:GetText())
 elseif self.current == "forecast" then
  self.queryBox:ClearFocus(); self.result, self.message = R.InventoryPlan:Forecast(self.forecastKind, self.queryBox:GetText())
 end
 self:Refresh()
end
function P:ConfirmExecute()
 if not self.preview or not self.preview.executable or #self.preview.moves == 0 then return end
 StaticPopup_Show("RUMMAGE_CONFIRM_RESTOCK", nil, nil, self.preview)
end
function P:ChooseForecast(anchor)
 local menu = {}
 for _, def in ipairs({ { "sale", "Sale" }, { "toBank", "To Bank" }, { "fromBank", "From Bank" } }) do
  local key, label = def[1], def[2]
  menu[#menu + 1] = { text = label, checked = P.forecastKind == key, func = function()
   P.forecastKind = key; P:Invalidate("Selection Changed — Forecast Again")
  end }
 end
 W:Menu(anchor, menu)
end
function P:Layout()
 local font = math.max(6, math.min(24, R.settings.fontSize or 12))
 local line, control, gap = math.ceil(font * 1.25) + 2, math.max(24, font + 12), 6
 local width = math.max(420, math.min(math.max(680, font * 34 + 60), UIParent:GetWidth() - 16))
 local titleH, tabY = font + 6, font + 28
 local labelY = tabY + control + 12
 local editY, actionY = labelY + line + 4, labelY + line + 4 + control + gap
 local statusY, statusH = actionY + control + 12, line * 3 + 8
 local rowY, rowH, footerH = statusY + statusH + 12, line * 2 + 8, control + 20
 local height = math.max(rowY + rowH + footerH, math.min(UIParent:GetHeight() - 16, rowY + MAX_ROWS * (rowH + 2) + footerH))
 self.pageSize = math.max(1, math.min(MAX_ROWS, math.floor((height - rowY - footerH) / (rowH + 2))))
 self.layout = { line = line, control = control, rowTop = rowY, rowHeight = rowH, statusTop = statusY, statusHeight = statusH }
 self.frame:SetSize(width, height)
 local stopWidth = math.max(110, font * 7 + 20)
 place(self.title, 14, 12, width - 140 - stopWidth, titleH); setButton(self.close, width - 108, 10, 94, control, line)
 setButton(self.cancelRestock, width - 114 - stopWidth, 10, stopWidth, control, line)
 local tabW = (width - 28 - 3 * gap) / 4
 for i, tab in ipairs(TABS) do setButton(self.tabButtons[tab[1]], 14 + (i - 1) * (tabW + gap), tabY, tabW, control, line) end
 local fieldW = (width - 28 - gap) / 2
 for i, e in ipairs({ self.restockID, self.restockCount }) do
  place(e.label, 14 + (i - 1) * (fieldW + gap), labelY, fieldW, line)
  place(e, 14 + (i - 1) * (fieldW + gap), editY, fieldW, control)
 end
 place(self.queryBox.label, 14, labelY, width - 28, line); place(self.queryBox, 14, editY, width - 28, control)
 for i, b in ipairs({ self.saveTarget, self.removeTarget, self.previewButton, self.executeButton }) do setButton(b, 14 + (i - 1) * (tabW + gap), actionY, tabW, control, line) end
 setButton(self.runButton, 14, actionY, math.max(150, tabW), control, line)
 setButton(self.kindButton, width - 14 - math.max(150, tabW), actionY, math.max(150, tabW), control, line)
 place(self.status, 14, statusY, width - 28, statusH); place(self.statusHit, 14, statusY, width - 28, statusH)
 for i, row in ipairs(self.rows) do
  place(row, 14, rowY + (i - 1) * (rowH + 2), width - 28, rowH)
  place(row.text, 0, 0, width - 38, line); place(row.detail, 0, line + 4, width - 38, line)
 end
 local footerY = height - control - 12
 setButton(self.previous, 14, footerY, 112, control, line); setButton(self.next, width - 126, footerY, 112, control, line)
 place(self.pageLabel, 136, footerY + (control - line) / 2, width - 272, line)
end
function P:ApplyPosition()
 local f = self.frame
 f:SetScale(math.max(0.25, math.min(1, (UIParent:GetWidth() - 12) / f:GetWidth(), (UIParent:GetHeight() - 12) / f:GetHeight())))
 f:ClearAllPoints(); local p = R.settings.planningPoint
 if p and R.ValidPoint(p) then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
 f:SetClampedToScreen(true)
end
function P:Create()
 if self.frame then return end
 W = R.Widgets
 local f = CreateFrame("Frame", "RummagePlanningFrame", UIParent, R.API.Backdrop)
 f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
 f:SetScript("OnDragStart", f.StartMoving)
 f:SetScript("OnDragStop", function(frame)
  frame:StopMovingOrSizing(); local a, _, b, x, y = frame:GetPoint(); local p = { a, b, x, y }
  if R.ValidPoint(p) then R.settings.planningPoint = p end
 end)
 f:SetScript("OnHide", function() for _, e in ipairs({ P.restockID, P.restockCount, P.queryBox }) do e:ClearFocus() end end)
 f:Hide(); self.frame = f; table.insert(UISpecialFrames, "RummagePlanningFrame")
 self.title = text(f, "Rummage Planning", "title")
 self.close = button(f, "Close", function() f:Hide() end)
 self.cancelRestock = button(f, "Stop Restock", function() R.Restock:Cancel(); P.message = "Restock Stop Requested"; P:Refresh() end)
 self.tabButtons = {}
 for _, tab in ipairs(TABS) do local key = tab[1]; self.tabButtons[key] = button(f, tab[2], function() P:Show(key) end) end
 self.restockID, self.restockCount = edit(f, "Item ID"), edit(f, "Target Quantity")
 self.queryBox = edit(f, "Optional Draft Rule")
 self.restockID:SetScript("OnEnterPressed", function() P:SaveTarget(false) end)
 self.restockCount:SetScript("OnEnterPressed", function() P:SaveTarget(false) end)
 for _, e in ipairs({ self.restockID, self.restockCount }) do e:SetScript("OnTextChanged", function() if P.preview then P:Invalidate("Target Draft Changed — Save And Preview Again") end end) end
 self.queryBox:SetMaxLetters(512)
 self.queryBox:SetScript("OnTextChanged", function() P.result = nil; P.message = "Query Changed — Analyze Again"; P.page = 1; if P.frame:IsShown() then P:Refresh() end end)
 self.queryBox:SetScript("OnEnterPressed", function() P:Run() end)
 self.saveTarget = button(f, "Save Target", function() P:SaveTarget(false) end)
 self.removeTarget = button(f, "Remove", function() P:SaveTarget(true) end)
 self.previewButton = button(f, "Preview", function() P:Run() end)
 self.executeButton = button(f, "Execute", function() P:ConfirmExecute() end)
 self.runButton = button(f, "Analyze", function() P:Run() end)
 self.kindButton = button(f, "Sale", function(b) P:ChooseForecast(b) end)
 self.status = text(f, "", "small"); self.status:SetWordWrap(true)
 self.statusHit = CreateFrame("Frame", nil, f); self.statusHit:EnableMouse(true)
 W:SetTooltip(self.statusHit, "Planning Details", function() return P.status:GetText() end)
 for i = 1, MAX_ROWS do
  local row = CreateFrame("Button", nil, f); row.text = text(row, "", "small"); row.detail = text(row, "", "small")
  W:SetTooltip(row, function(self) return self.text:GetText() end, function(self) return self.detail:GetText() end)
  row:SetScript("OnClick", function(self)
   if P.current == "restock" and self.record and self.record.itemID then P.restockID:SetText(tostring(self.record.itemID)); P.restockCount:SetText(tostring(self.record.target or 0)) end
  end)
  self.rows[i] = row
 end
 self.previous = button(f, "Previous", function() P.page = math.max(1, P.page - 1); P:Refresh() end)
 self.next = button(f, "Next", function() P.page = P.page + 1; P:Refresh() end)
 self.pageLabel = text(f, "", "small")
 StaticPopupDialogs.RUMMAGE_CONFIRM_RESTOCK = { text = "Execute This Exact Restock Preview? Changed Items, Targets Or Bank Sessions Require A Fresh Preview.", button1 = ACCEPT, button2 = CANCEL,
  OnAccept = function(_, preview)
   local ok, reason = R.Restock:Execute(preview); P:Invalidate(ok and "Restock Started — Completion Requires Observed Inventory Changes" or reason)
  end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
 local function changed(reason) if P.frame:IsShown() then P:Invalidate(reason) else P.preview, P.result = nil, nil end end
 for _, message in ipairs({ "DATA_CHANGED", "RESTOCK_CHANGED", "PLANNING_INVALIDATED" }) do R:Listen(message, function() changed("Inventory Or Targets Changed — Preview Again") end) end
 R:Listen("PLANNING_CHANGED", function(reason) if P.frame:IsShown() then if type(reason) == "string" then P.message = reason end; P:Refresh() end end)
 R:Listen("VENDOR_SUMMARY_CHANGED", function() if P.frame:IsShown() and P.current == "vendor" then P:Refresh() end end)
 for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do R:RegisterEvent(event, function() changed("Bank Session Changed — Preview Again") end) end
 R:RegisterEvent("DISPLAY_SIZE_CHANGED", function() if P.frame:IsShown() then P:Refresh(); P:ApplyPosition() end end)
end
function P:Refresh()
 if not self.frame then return end
 self:Layout(); W:Backdrop(self.frame, "main")
 local restock = self.current == "restock"
 self.cancelRestock:SetShown(restock)
 for _, e in ipairs({ self.restockID, self.restockCount }) do e:SetShown(restock); e.label:SetShown(restock) end
 for _, b in ipairs({ self.saveTarget, self.removeTarget, self.previewButton, self.executeButton }) do b:SetShown(restock) end
 local query = self.current == "rules" or self.current == "forecast"
 self.queryBox:SetShown(query); self.queryBox.label:SetShown(query); self.runButton:SetShown(query); self.kindButton:SetShown(self.current == "forecast")
 self.queryBox.label:SetText(self.current == "rules" and "Optional Draft Rule" or "Inventory Query (Empty Means All)")
 self.runButton:SetLabel(self.current == "rules" and "Analyze" or "Forecast")
 self.kindButton:SetLabel(({ sale = "Sale", toBank = "To Bank", fromBank = "From Bank" })[self.forecastKind])
 for key, b in pairs(self.tabButtons) do b:SetActive(key == self.current) end
 local records, summary = {}, self.message
 if restock then
  if self.preview then
   for _, row in ipairs(self.preview.rows or {}) do
    local carried = row.carriedKnown == false and "Unknown" or (row.carried == nil and "Unknown" or tostring(row.carried))
    local deficit = row.deficitKnown == false and "Unknown" or (row.remainingDeficit == nil and "Unknown" or tostring(row.remainingDeficit))
    local bank = row.availableBank == nil and "Unknown" or tostring(row.availableBank)
    if row.bankKnown == false and type(row.availableBank) == "number" then bank = "At Least " .. row.availableBank .. " (Unknown Total)" end
    records[#records + 1] = { itemID = row.itemID, target = row.target,
     label = itemName(row.itemID) .. " | Target " .. row.target .. " / Carried " .. carried,
     detail = "Withdraw " .. row.plannedWithdraw .. " | Bank " .. bank .. " | Remaining Deficit " .. deficit .. " | " .. (row.reason or "Ready") }
   end
   local forecast = self.preview.forecast or {}
   summary = summary or ((self.preview.executable and "Preview Ready — Execute Requires Confirmation" or self.preview.reason or "Visit A Banker") .. " | If This Preview Completes: " .. (forecast.known and tostring(forecast.netCarriedSlots) .. " Net Free Slots" or "Forecast Unknown"))
  else
   for id, target in pairs(R.db.restockTargets or {}) do records[#records + 1] = { itemID = id, target = target, label = itemName(id) .. " | Target " .. target, detail = "Preview Current Carried And Live Bank Quantities" } end
   table.sort(records, function(a, b) return a.itemID < b.itemID end)
   summary = summary or "Account-Wide Targets; Preview This Character's Live Bank Deficit. No Automatic Withdrawals."
  end
  self.executeButton:SetDisabledLook(not self.preview or not self.preview.executable or #(self.preview.moves or {}) == 0)
 elseif self.current == "vendor" then local result = R.VendorSession:Summary(); records, summary = result.rows, result.summary
 elseif self.result then records, summary = self.result.rows or {}, self.result.summary or summary end
 self.status:SetText(summary or (self.current == "rules" and "Analyze Current Rules; Overlaps Use OR With No Priority Winner" or "Forecast Unknown Until You Preview; This View Never Moves Items"))
 local pages = math.max(1, math.ceil(#records / self.pageSize)); self.page = math.max(1, math.min(pages, self.page))
 for i, row in ipairs(self.rows) do
  local record = i <= self.pageSize and records[(self.page - 1) * self.pageSize + i] or nil
  row.record = record; row:SetShown(record ~= nil)
  row.text:SetText(record and record.label or ""); row.detail:SetText(record and record.detail or "")
 end
 self.previous:SetDisabledLook(self.page <= 1); self.next:SetDisabledLook(self.page >= pages)
 self.pageLabel:SetText(#records == 0 and "No Results" or ("Page " .. self.page .. " / " .. pages .. " (" .. #records .. ")"))
end
function P:Show(tab)
 self:Create(); local nextTab = tab or self.current
 if not self.tabButtons[nextTab] then nextTab = "restock" end
 if self.current ~= nextTab then self.page = 1; self.message = nil end
 self.current = nextTab; self.frame:Show(); self:Refresh(); self:ApplyPosition()
end
