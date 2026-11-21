-- Rummage: window footer: money, free slots, bag bar, guild tab status and actions.
-- Split out of UI.lua in 1.10.0; shares the UI table through R.UIParts.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API
R.UIParts[#R.UIParts + 1] = function(UI)
local W = R.Widgets

local pairs, ipairs, type, wipe, tostring = pairs, ipairs, type, wipe, tostring
local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local InCombatLockdown = InCombatLockdown
local NO_GUILD = UI.NO_GUILD

-- Footer status for the Guild Bank window: live limits, or the cache's age.
function UI:GuildFooterText(c)
	if self:GuildLive() then
		if not R.settings.guildFooterLimits then return "" end
		local tab = self:GuildTab() or tonumber(R.GuildBank.Call("GetCurrentGuildBankTab"))
		local lim = tab and R.GuildBank:Limits(tab)
		if not lim then return "" end
		local rec = c.containers[API.GUILD_BASE + tab]
		local left = lim.remaining
		return ((rec and rec.name) or ("Tab " .. tab)) .. ": "
			.. ((left == nil or left < 0) and "unlimited withdrawals" or (left .. " withdrawal" .. (left == 1 and "" or "s") .. " left"))
			.. (lim.deposit and "" or ", no deposits")
	end
	if c == NO_GUILD then return "" end
	local age = c.lastSeen and R.FormatAge(c.lastSeen) or ""
	return R.L.cachedGuild .. (age ~= "" and (" · seen " .. age .. " ago") or "")
end

-- Withdrawal / deposit permissions for a live guild tab.
function UI:AddGuildLimits(tt, tab)
	if not (tab and self:GuildLive()) then return end
	local lim = R.GuildBank:Limits(tab)
	if not lim then return end
	local left = lim.remaining
	tt:AddLine((left == nil or left < 0) and "Withdrawals: unlimited" or ("Withdrawals left today: " .. left), 1, 1, 1)
	if not lim.deposit then tt:AddLine("You can't deposit in this tab", 1, 0.4, 0.4) end
end

function UI:AddGuildHint(tt, e)
	if self.kind ~= "guild" or not e then return end
	local tab = API.GuildTabOf(e.bag)
	local rec = tab and self:Char().containers[e.bag]
	if rec then tt:AddLine("Guild bank: " .. (rec.name or ("Tab " .. tab)), 0.25, 0.75, 0.25) end
	if self:GuildLive() then
		self:AddGuildLimits(tt, tab)
		local rc = R.settings.guildRightClick
		tt:AddLine("Click or drag: pick up" .. (rc == "bags" and "   Right-click: to bags" or (rc == "cursor" and "   Right-click: pick up" or "")), 0.6, 0.6, 0.6)
	else
		tt:AddLine("Cached view: open the guild vault to move items", 0.6, 0.6, 0.6)
	end
end

function UI:SetView(view)
	if self.view == view or view ~= self.kind then return end
	self:SaveViewLayout(self:ViewKey())
	self.view = view
	self:ApplyViewLayout(self:ViewKey())
	self.bagFilter = nil
	self.offset = 0
	R:RequestRefresh()
end

---------------------------------------------------------------------------
-- Footer
---------------------------------------------------------------------------
local function BagButtonOnEnter(self)
	local bag = self.bag
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local c = UI:Char()
	local rec = c.containers[bag]
	if API.IsGuildBag(bag) then
		GameTooltip:SetText(rec and rec.name or API.BagLabel(bag))
		if rec then
			local used = 0
			for _ in pairs(rec.slots) do used = used + 1 end
			GameTooltip:AddLine(format("%d / %d slots used", used, rec.size or 0), 0.8, 0.8, 0.8)
		end
		UI:AddGuildLimits(GameTooltip, API.GuildTabOf(bag))
		GameTooltip:AddLine("Click: show only this tab (click again for all tabs)", 0.6, 0.6, 0.6)
		if UI:GuildLive() then GameTooltip:AddLine("Drop an item here: deposit it in this tab", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
		return
	end
	if self.locked then
		GameTooltip:SetText("Bank bag slot (locked)")
		if R.Data.atBank and UI:IsMe() and GetBankSlotCost then
			GameTooltip:AddLine("Click to purchase: " .. R.FormatMoney(GetBankSlotCost(c.bankBags or 0)), 1, 1, 1)
		end
	elseif self.link and UI:Interactive() and API.BagInvID(bag) then
		GameTooltip:SetInventoryItem("player", API.BagInvID(bag))
	elseif self.link then
		GameTooltip:SetHyperlink(self.link)
	else
		GameTooltip:SetText(API.BagLabel(bag))
	end
	if rec then
		local used = 0
		for _ in pairs(rec.slots) do used = used + 1 end
		GameTooltip:AddLine(format("%d / %d slots used", used, rec.size or 0), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Click: show only this bag", 0.6, 0.6, 0.6)
	if UI:Interactive() then GameTooltip:AddLine("Right-click: empty this bag", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function BagButtonOnClick(self, button)
	if API.IsGuildBag(self.bag) then
		local tab = API.GuildTabOf(self.bag)
		if UI:GuildLive() and CursorHasItem and CursorHasItem() then
			R.GuildBank:Deposit(tab)
			return
		end
		UI:SetGuildTab(UI.bagFilter ~= self.bag and tab or nil)
		return
	end
	if self.locked then
		if R.Data.atBank and UI:IsMe() then R.popupUI = UI; StaticPopup_Show("RUMMAGE_BUY_BANK_SLOT") end
		return
	end
	if UI:Interactive() and (CursorHasItem and CursorHasItem()) then
		local inv = API.BagInvID(self.bag)
		if self.bag == API.BACKPACK and API.PutItemInBackpack then API.PutItemInBackpack()
		elseif inv and API.PutItemInBag then API.PutItemInBag(inv) end
		return
	end
	if button == "RightButton" then
		if UI:Interactive() then R.Mover:EmptyBag(self.bag) end
		return
	end
	UI.bagFilter = (UI.bagFilter ~= self.bag) and self.bag or nil
	UI.offset = 0
	R:RequestRefresh()
end

function UI:UpdateBagBar()
	for _, b in ipairs(self.bagButtons) do b:Hide() end
	local c = self:Char()
	local list = self:BagList()
	local x, n = 0, 0
	local interactive = self:Interactive()
	for _, bag in ipairs(list) do
		local rec = c.containers[bag]
		local isKey = API.KEYRING and bag == API.KEYRING
		local purchasedLimit = API.IsLegacyBankBag(bag) and c.bankBags
		local locked = purchasedLimit and (bag - API.NUM_BAGS) > purchasedLimit
		if (rec and (rec.size or 0) > 0) or (not isKey and API.IsEquippedBag(bag)) or (bag == API.BANK and not API.BankTabs) or locked then
			if not (isKey and not rec) then
				n = n + 1
				local b = self.bagButtons[n]
				if not b then
					b = W:IconButton(self.bagBar, nil, 22, BagButtonOnClick)
					b:SetScript("OnEnter", BagButtonOnEnter)
					b:SetScript("OnLeave", function() GameTooltip:Hide() end)
					b:RegisterForDrag("LeftButton")
					b:SetScript("OnDragStart", function(self)
						local inv = API.BagInvID(self.bag)
						if inv and UI:Interactive() and API.PickupBagFromSlot and self.bag ~= API.BACKPACK then API.PickupBagFromSlot(inv) end
					end)
					b:SetScript("OnReceiveDrag", function(self) BagButtonOnClick(self, "LeftButton") end)
					b.free = W:Text(b, "tiny")
					b.free:SetPoint("BOTTOMRIGHT", -1, 1)
					self.bagButtons[n] = b
				end
				b.bag = bag
				b.locked = locked
				b.link = rec and rec.link
				local tex
				if bag == API.BACKPACK then tex = "Interface\\Buttons\\Button-Backpack-Up"
				elseif bag == API.BANK then tex = "Interface\\Icons\\INV_Misc_Bag_08"
				elseif isKey then tex = "Interface\\Icons\\INV_Misc_Key_03"
				elseif API.BankTabs and API.IsBankBag(bag) then tex = "Interface\\Icons\\INV_Misc_Bag_08"
				else tex = rec and rec.icon or (rec and rec.link and select(10, API.GetItemInfo(rec.link))) end
				if not tex then tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" end
				b.icon:SetTexture(tex)
				b.icon:SetVertexColor(locked and 1 or 1, locked and 0.3 or 1, locked and 0.3 or 1)
				local free
				if rec then
					local used = 0
					for _ in pairs(rec.slots) do used = used + 1 end
					free = (rec.size or 0) - used
				end
				b.free:SetText((free and rec.size and rec.size > 0 and not isKey) and free or "")
				b:SetActive(self.bagFilter == bag)
				b:ClearAllPoints()
				b:SetPoint("LEFT", self.bagBar, "LEFT", x, 0)
				b:Show()
				x = x + 24
			end
		end
	end
	self.bagBar:SetWidth(math.max(1, x))
	local _ = interactive
end

-- Separate action and metadata lanes only when the compact chrome is crowded.
function UI:LayoutFooter(buttons, busy)
 local responsive = self:ResponsiveChrome()
 local control = responsive and math.max(22, R.settings.fontSize + 8) or 22
 local available = math.max(1, self.frame:GetWidth() - W:Pad() * 2 - 28)
 local defaults = { [self.btnSell] = 74, [self.btnRestack] = 60, [self.btnSort] = 46, [self.btnTransfer] = 70 }
 local right, row, prev = available, 0, nil
 local bounds = {}
 for i = #buttons, 1, -1 do
  local b = buttons[i]
  local width = responsive and math.min(available, math.max(defaults[b], W:MeasureText(b.text) + 16)) or defaults[b]
  self:FitChromeButton(b, width, control); b:ClearAllPoints()
  if responsive then
   if right - width < 0 then row = row + 1; right = available end
   right = right - width
   b:SetPoint("BOTTOMLEFT", self.footer, "BOTTOMLEFT", right, row * (control + 4))
   bounds[#bounds + 1] = { left = right, right = right + width, row = row }
   right = right - 4
  else
   if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", self.footer, "RIGHT", 0, 0) end
   right = right - width - 4
  end
  b:SetDisabledLook(busy); prev = b
 end
 local actionHeight = #buttons > 0 and ((row + 1) * control + row * 4) or 0
 local line = math.max(22, R.settings.fontSize + 4)
 local newHeight = responsive and actionHeight + line + 4 + W:Pad() * 2 or R.UIK.FOOTER_H
 local changed = (self.chromeFooterHeight or R.UIK.FOOTER_H) ~= newHeight
 self.chromeFooterHeight = newHeight; self.footer:SetHeight(newHeight - W:Pad())
 if not responsive then
  self.moneyBtn:ClearAllPoints(); self.moneyBtn:SetPoint("LEFT", 2, 0); self.moneyBtn:SetHeight(20)
  self.moneyBtn.text:SetSize(math.max(1, self.moneyBtn:GetWidth() - 4), 20)
  self.freeText:ClearAllPoints(); self.freeText:SetPoint("LEFT", self.moneyBtn, "RIGHT", 6, 0)
  self.freeText:SetSize(W:MeasureText(self.freeText), line)
  self.bagBar:ClearAllPoints(); self.bagBar:SetPoint("LEFT", self.freeText, "RIGHT", 8, 0)
  local previous = self.bagBar
  for _, field in ipairs({ self.cachedText, self.totalText, self.currencyText }) do
   field:ClearAllPoints(); field:SetPoint("LEFT", previous, "RIGHT", previous == self.bagBar and 8 or 10, 0)
   field:SetSize(W:MeasureText(field), line); field:SetWordWrap(false); previous = field
  end
  self.chromeFooterGeometry = { available = available, rows = 1, actionsHeight = control, metadataY = 0, buttons = {} }
  if changed then R:Defer("chromeFooter" .. self.suffix, function() if UI.frame:IsShown() then UI:LayoutIfChanged() end end) end
  return
 end
 local metadataWidth = responsive and available or math.max(1, right - 4)
 local y = responsive and actionHeight + 6 or 3
 local x = 2
 local moneyWidth = math.min(math.max(60, W:MeasureText(self.moneyBtn.text) + 4), math.max(60, metadataWidth * 0.24))
 self.moneyBtn:ClearAllPoints(); self.moneyBtn:SetPoint("BOTTOMLEFT", self.footer, "BOTTOMLEFT", x, y)
 self.moneyBtn:SetSize(moneyWidth, line)
 self.moneyBtn.text:SetWordWrap(false); self.moneyBtn.text:SetSize(math.max(1, moneyWidth - 4), line)
 x = x + moneyWidth + 6
 local freeWidth = math.min(W:MeasureText(self.freeText), math.max(50, metadataWidth * 0.22))
 self.freeText:ClearAllPoints(); self.freeText:SetPoint("BOTTOMLEFT", self.footer, "BOTTOMLEFT", x, y)
 self.freeText:SetSize(freeWidth, line); self.freeText:SetWordWrap(false); x = x + freeWidth + 8
 self.bagBar:ClearAllPoints(); self.bagBar:SetPoint("BOTTOMLEFT", self.footer, "BOTTOMLEFT", x, y)
 x = x + self.bagBar:GetWidth() + 8
 local active = 0
 local fields = { self.cachedText, self.totalText, self.currencyText }
 for _, field in ipairs(fields) do if field:GetText() ~= "" then active = active + 1 end end
 local remaining = math.max(0, metadataWidth - x)
 for _, field in ipairs(fields) do
  local width = field:GetText() ~= "" and math.max(1, math.floor(remaining / math.max(1, active))) or 1
  field:ClearAllPoints(); field:SetPoint("BOTTOMLEFT", self.footer, "BOTTOMLEFT", math.min(x, metadataWidth - 1), y)
  field:SetSize(width, line); field:SetWordWrap(false)
  if field:GetText() ~= "" then x = x + width end
 end
 self.chromeFooterGeometry = { available = available, rows = row + 1, actionsHeight = actionHeight,
  metadataY = y, metadataWidth = metadataWidth, buttons = bounds }
 if changed then R:Defer("chromeFooter" .. self.suffix, function() if UI.frame:IsShown() then UI:LayoutIfChanged() end end) end
end

function UI:UpdateFooter()
	if not self.frame or not self.frame:IsShown() then return end
	local c = self:Char()
	self.moneyBtn.text:SetText(R.FormatMoney(c.money or 0) ~= "" and R.FormatMoney(c.money or 0) or "0")
	self.moneyBtn:SetWidth(math.max(60, W:MeasureText(self.moneyBtn.text) + 4))
	local list = self:BagList()
	local free, total = R.Data:FreeSlots(c, list)
	self.freeText:SetText(format(R.L.freeFmt, free, total))
	if free <= (R.settings.lowSpaceWarn or 0) and total > 0 then self.freeText:SetTextColor(1, 0.3, 0.3)
	else local d = W:Skin().dim; self.freeText:SetTextColor(d[1], d[2], d[3]) end
	self:UpdateBagBar()

	local cachedMsg = ""
	if self.kind == "guild" then
		cachedMsg = self:GuildFooterText(c)
	elseif not self:IsMe() then
		cachedMsg = "Cached · seen " .. (R.FormatAge(c.lastSeen) ~= "" and R.FormatAge(c.lastSeen) or "?") .. " ago"
	elseif self.view == "bank" and not R.Data.atBank then
		cachedMsg = R.L.cachedBank
	end
	local stale = not self:IsMe() and not self:GuildLive() and R.IsStale(c)
	if stale then
		cachedMsg = cachedMsg .. " (stale)"
		self.cachedText:SetTextColor(0.85, 0.4, 0.4)
	else
		self.cachedText:SetTextColor(0.6, 0.6, 0.6)
	end
	if self.list then self.list:SetAlpha(stale and 0.6 or 1) end
	self.cachedText:SetText(cachedMsg)

	-- Vendor value of everything currently listed (after filters), with the
	-- junk portion broken out. Uses the filtered entry list from Refresh.
	local totText = ""
	if self.entries and #self.entries > 0 then
		local sum, junkSum = 0, 0
		for i = 1, #self.entries do
			local e = self.entries[i]
			local v = (e.info and e.info.sell or 0) * (e.count or 1)
			sum = sum + v
			if e.junk then junkSum = junkSum + v end
		end
		if sum > 0 then
			totText = R.L.viewTotal .. ": " .. R.FormatMoney(sum, true)
			if junkSum > 0 then totText = totText .. " · " .. R.L.junkTotal .. " " .. R.FormatMoney(junkSum, true) end
		end
	end
	self.totalText:SetText(totText)
	self.currencyText:SetText((R.settings.showCurrencies and self.kind == "bags") and R.Data:CurrencyText(c) or "")

	local interactive = self:Interactive() and not self.searchAllActive
	local merchant = R.Junk.MerchantOpen()
	local buttons = wipe(self.footerButtons or {})
	self.footerButtons = buttons
	self.btnSell:SetShown(interactive and self.view == "bags" and merchant)
	if self.btnSell:IsShown() then buttons[#buttons + 1] = self.btnSell end
	self.btnRestack:SetShown(interactive)
	if interactive then buttons[#buttons + 1] = self.btnRestack end
	local canSort = interactive and ((self.view == "bags" and API.SortBags) or (self.view == "bank" and API.SortBankBags))
	self.btnSort:SetShown(canSort and true or false)
	if canSort then buttons[#buttons + 1] = self.btnSort end
	-- mail / trade target (bags only, live): wins over the bank so "To Mail" works at a mailbox
	local target = interactive and self.view == "bags" and R.Mover:OpenTarget()
	self.transferTarget = target or nil
	local canTransfer = target or (self:IsMe() and R.Data.atBank)
	self.btnTransfer:SetShown(canTransfer and true or false)
	if canTransfer then
		if target then self.btnTransfer:SetLabel(R.Mover.targets[target].label)
		else self.btnTransfer:SetLabel(self.view == "bank" and R.L.toBags or R.L.toBank) end
		buttons[#buttons + 1] = self.btnTransfer
	end
	self:LayoutFooter(buttons, R.Mover:Busy())
end

function UI:ShowMoneyTooltip(anchor)
	GameTooltip:SetOwner(anchor, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Gold")
	local total = 0
	for _, entry in ipairs(R.Data:SortedChars()) do
		local c = entry.c
		total = total + (c.money or 0)
		local name = c.name or entry.key
		if c.realm ~= GetRealmName() then name = name .. "-" .. (c.realm or "?") end
		GameTooltip:AddDoubleLine(R.ClassColorText(c.class, name), R.FormatMoney(c.money or 0) ~= "" and R.FormatMoney(c.money or 0) or "0", 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("|cffd9a441Total|r", R.FormatMoney(total), 1, 1, 1, 1, 1, 1)
	GameTooltip:Show()
end

function UI:DoTransfer()
	if self.searchAllActive then return end
	local target = self.view == "bags" and self:Interactive() and R.Mover:OpenTarget()
	if target then
		-- mail and trade hold only a few items, so no "move everything?" prompt
		local entries = {}
		for _, e in ipairs(self.entries or {}) do
			if not (API.KEYRING and e.bag == API.KEYRING) then entries[#entries + 1] = e end
		end
		return R.Mover:SendTo(target, entries)
	end
	if not R.Data.atBank then return end
	local entries = {}
	for _, e in ipairs(self.entries or {}) do
		if not (API.KEYRING and e.bag == API.KEYRING) then entries[#entries + 1] = e end
	end
	local toBank = self.view == "bags"
	if self.bagFilter == nil and self.search == "" and self.category == "all" then
		local transfer = { window = self, entries = R.Mover:SnapshotEntries(entries), toBank = toBank, session = R.Mover.bankSession }
		StaticPopup_Show("RUMMAGE_CONFIRM_TRANSFER", toBank and "bank" or "bags", nil, transfer)
		return
	end
	R.Mover:TransferEntries(entries, toBank)
end

end
