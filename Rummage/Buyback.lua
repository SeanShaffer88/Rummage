-- Rummage: serialized buyback requests with independent inventory/money evidence.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, B = ns.R, { session = 0 }
R.Buyback = B
local function integer(n, positive)
 return type(n) == "number" and n == n and n >= (positive and 1 or 0) and n <= 1000000000000 and n == math.floor(n)
end
local function validID(id) return type(id) == "string" and #id <= 64 and id:match("^sale:%d+:%d+$") ~= nil end
function B:NextID(db)
 local used = {}
 for _, e in ipairs(db.junkLog or {}) do if validID(e.id) then used[e.id] = true end end
 for _, e in ipairs(type(db.actionHistory) == "table" and db.actionHistory or {}) do if type(e) == "table" and validID(e.saleLedgerID) then used[e.saleLedgerID] = true end end
 local sequence = integer(db.saleLedgerSequence) and db.saleLedgerSequence < 1000000000 and db.saleLedgerSequence or 0
 local id
 repeat sequence = sequence + 1; id = "sale:" .. math.floor(time()) .. ":" .. sequence until not used[id]
 db.saleLedgerSequence = sequence
 return id
end
function B:SanitizeLedger(db)
 local count, ambiguous = {}, {}
 for _, e in ipairs(db.junkLog) do
  if validID(e.id) then count[e.id] = (count[e.id] or 0) + 1 end
 end
 for id, n in pairs(count) do if n > 1 then ambiguous[id] = true end end
 for _, e in ipairs(type(db.actionHistory) == "table" and db.actionHistory or {}) do
  if type(e) == "table" and e.saleLedgerID ~= nil and (not validID(e.saleLedgerID) or ambiguous[e.saleLedgerID]) then e.saleLedgerID = nil; e.ledgerInvalid = true end
 end
 for _, e in ipairs(db.junkLog) do
  if not validID(e.id) or ambiguous[e.id] then e.id = self:NextID(db) end
 end
end
function B:AddSale(link, count, value)
 local log, id = R.db.junkLog, self:NextID(R.db)
 table.insert(log, 1, { id = id, t = time(), link = link, count = count, value = value })
 while #log > 30 do log[#log] = nil end
 return id
end
local function signature(e) return type(e.link) == "string" and e.link ~= "" and integer(e.count, true) and integer(e.value) end
local function ledger(id)
 local found
 for _, e in ipairs(R.db.junkLog) do if e.id == id then if found then return nil end; found = e end end
 return found
end
local function history(id)
 for _, e in ipairs(R.db.actionHistory) do if e.id == id then return e end end
end
function B:LedgerForHistory(id)
 local record = history(id)
 if not record or record.action ~= "Sale" or record.status ~= "Observed" or not signature(record) or record.ledgerInvalid then return nil, "Sale Record Unavailable" end
 local found
 for _, e in ipairs(R.db.junkLog) do
  if (not record.saleLedgerID or record.saleLedgerID == e.id) and e.link == record.link and e.count == record.count and e.value == record.value then
   if found then return nil, "Ambiguous Sale Records" end; found = e
  end
 end
 if found and not record.saleLedgerID then
  for _, other in ipairs(R.db.actionHistory) do
   if other ~= record and other.action == "Sale" and other.status == "Observed" and not other.ledgerInvalid
    and other.link == record.link and other.count == record.count and other.value == record.value
    and (not other.saleLedgerID or other.saleLedgerID == found.id) then return nil, "Ambiguous Historical Sale Claims" end
  end
 end
 return found, found and nil or "Already Bought Back Or Sale No Longer Logged"
end
local function apiReady()
 return type(GetNumBuybackItems) == "function" and type(GetBuybackItemLink) == "function" and type(GetBuybackItemInfo) == "function"
  and type(BuybackItem) == "function" and type(GetMoney) == "function"
end
function B:Candidate(sale, allowMissing)
 if not signature(sale) or not apiReady() then return nil, "Buyback Quantity Or Price API Unavailable" end
 local ok, result, reason = pcall(function()
  local chosen, matches = nil, 0
  local size = GetNumBuybackItems()
  if not integer(size) or size > 100 then return nil, "Buyback List Quantity Unknown" end
  for i = 1, size do
   local link = GetBuybackItemLink(i)
   if link == sale.link then
    local _, _, price, count = GetBuybackItemInfo(i)
    if not integer(price) or not integer(count, true) then return nil, "Buyback Quantity Or Price Unknown" end
    if count == sale.count and price == sale.value then chosen, matches = i, matches + 1 end
   end
  end
  if not chosen and not allowMissing then return nil, "Matching Item No Longer In Buyback" end
  return { index = chosen, matches = matches, link = sale.link, count = sale.count, value = sale.value }
 end)
 if not ok then return nil, "Buyback API Could Not Be Read" end
 return result, reason
end
function B:Owned(link)
 local total = 0
 for _, bag in ipairs(R.API.InvBagList) do
  if bag ~= R.API.KEYRING then
   for slot = 1, R.API.GetNumSlots(bag) or 0 do
    local current, count = R.API.GetSlotInfo(bag, slot)
    if current == link then if not integer(count, true) then return nil end; total = total + count end
   end
  end
 end
 return total
end
local function blocked()
 if not R.Junk.MerchantOpen() then return "Open A Merchant To Buy Back" end
 if InCombatLockdown() then return "Unavailable In Combat" end
 if GetCursorInfo() then return "Put Down The Cursor Item" end
end
function B:Availability(historyID)
 local sale, reason = self:LedgerForHistory(historyID)
 if not sale then return false, reason end
 if self.operation then
  return false, self.operation.current and self.operation.current.id == sale.id and "Pending" or "Another Inventory Operation Is Busy"
 end
 reason = blocked(); if reason then return false, reason end
 if R.Mover:Busy() then return false, "Another Inventory Operation Is Busy" end
 local candidate; candidate, reason = self:Candidate(sale)
 if not candidate then return false, reason end
 local money = GetMoney()
 if not integer(money) or money < candidate.value then return false, "Insufficient Funds" end
 return true, nil
end
local function vendorFact(op, status, sale, reason)
 if R.VendorSession then R.VendorSession:Record("Buyback", status, { session = op.vendorSession,
  operationID = "buyback:" .. op.serial .. ":" .. (sale and sale.id or "stop"), saleLedgerID = sale and sale.id,
  link = sale and sale.link, itemID = sale and R.ItemID(sale.link), count = sale and sale.count, value = sale and sale.value, reason = reason }) end
end
function B:Stop(reason, expected)
 local op = self.operation
 if not op or (expected and expected ~= op) then return end
 self.operation = nil
 if op.ticker then op.ticker:Cancel() end
 if reason then vendorFact(op, "Stopped", op.current, reason); R.ActionHistory:Record("Buyback", "Stopped", { link = op.current and op.current.link, saleLedgerID = op.current and op.current.id, reason = reason }) end
 R:Fire("MOVER_CHANGED", false); R:Fire("BUYBACK_CHANGED")
end
function B:Check(op, fromTicker)
 if self.operation ~= op then return end
 local reason = blocked()
 if reason or self.session ~= op.session then return self:Stop(reason or "Merchant Session Changed", op) end
 if op.pending then
  local p = op.pending
  local fresh, unavailable = self:Candidate(p.sale, true)
  if not fresh then return self:Stop(unavailable or "Buyback API Unavailable", op) end
  local matches = fresh.matches
  local quantity, money = self:Owned(p.sale.link), GetMoney and GetMoney()
  if matches == p.matches - 1 and quantity == p.owned + p.sale.count and money == p.money - p.sale.value then
   local current = ledger(p.sale.id)
   if current ~= p.ledger then return self:Stop("Sale Ledger Changed While Pending", op) end
   for i, e in ipairs(R.db.junkLog) do if e == current then table.remove(R.db.junkLog, i); break end end
   op.pending = nil
   vendorFact(op, "Observed", p.sale, "Exact Buyback Evidence Verified")
   R.ActionHistory:Record("Buyback", "Observed", { link = p.sale.link, count = p.sale.count, value = p.sale.value,
    saleLedgerID = p.sale.id, reason = "Exact Buyback Signature, Inventory Gain And Money Loss Verified" })
   if self.operation ~= op or self.session ~= op.session then return end
   op.pending = nil; R:Fire("BUYBACK_CHANGED")
   if self.operation ~= op or self.session ~= op.session then return end
  else
   if fromTicker then p.waits = p.waits + 1 end
   if p.waits > 24 then return self:Stop("Buyback Remains Unconfirmed", op) end
   return
  end
 end
 while true do
  if self.operation ~= op or self.session ~= op.session then return end
  local interruption = blocked(); if interruption then return self:Stop(interruption, op) end
  op.index = op.index + 1
  local id = op.ids[op.index]
  if not id then return self:Stop(nil, op) end
  local sale = ledger(id)
  local candidate, unavailable
  if sale then candidate, unavailable = self:Candidate(sale) else unavailable = "Sale No Longer Logged" end
  local money = GetMoney and GetMoney()
  if candidate and integer(money) and money >= candidate.value then
   local owned = self:Owned(sale.link)
   if owned == nil then return self:Stop("Inventory Quantity Unavailable", op) end
   local snapshot = { id = sale.id, link = sale.link, count = sale.count, value = sale.value }
   op.current = sale
   op.pending = { sale = snapshot, ledger = sale, matches = candidate.matches, money = money, owned = owned, waits = 0 }
   vendorFact(op, "Requested", sale, "Awaiting Buyback Evidence")
   R.ActionHistory:Record("Buyback", "Requested", { link = sale.link, count = sale.count, value = sale.value, saleLedgerID = sale.id, reason = "Awaiting Buyback, Inventory And Money Changes" })
   if self.operation ~= op or self.session ~= op.session then return end
   local interruption = blocked(); if interruption then return self:Stop(interruption, op) end
   local latest = self:Candidate(snapshot)
   local stillLogged = ledger(snapshot.id)
   if not latest or latest.matches ~= candidate.matches or self:Owned(snapshot.link) ~= owned or GetMoney() ~= money
    or stillLogged ~= sale or sale.link ~= snapshot.link or sale.count ~= snapshot.count or sale.value ~= snapshot.value then
    return self:Stop("Buyback Candidate Changed Before Request", op)
   end
   local issued, errorText = pcall(BuybackItem, latest.index)
   if not issued then return self:Stop("Buyback Request Failed: " .. tostring(errorText), op) end
   R:Fire("BUYBACK_CHANGED")
   return
  end
  R.ActionHistory:Record("Buyback", "Skipped", { link = sale and sale.link, saleLedgerID = id, reason = unavailable or "Insufficient Funds" })
 end
end
function B:Start(ids)
 if self.operation then return false, "A Buyback Is Already Pending" end
 local reason = blocked()
 if reason then return false, reason end
 if R.Mover:Busy() then return false, "Another Inventory Operation Is Busy" end
 self.serial = (self.serial or 0) + 1
 local op = { ids = ids, index = 0, session = self.session, serial = self.serial, vendorSession = R.VendorSession and R.VendorSession:Token() }
 self.operation = op
 op.ticker = C_Timer.NewTicker(0.15, function() B:Check(op, true) end)
 R:Fire("MOVER_CHANGED", true)
 self:Check(op)
 return true
end
function B:FromHistory(id)
 local allowed, reason = self:Availability(id)
 if not allowed then return false, reason end
 local sale, unavailable = self:LedgerForHistory(id)
 if not sale then return false, unavailable end
 return self:Start({ sale.id })
end
function B:Command(n)
 if not apiReady() then R:Print("Buyback API not available on this client."); return end
 self:SanitizeLedger(R.db)
 local ids = {}
 if type(n) == "string" and n:lower() == "all" then
  for _, e in ipairs(R.db.junkLog) do ids[#ids + 1] = e.id end
 else
  local index = tonumber(n) or 1
  if index ~= math.floor(index) or index < 1 or not R.db.junkLog[index] then R:Print("No such sale in the log (/rum junklog)."); return end
  ids[1] = R.db.junkLog[index].id
 end
 local ok, reason = self:Start(ids)
 if not ok then R:Print(reason) end
end
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
 R:RegisterEvent(event, function() B.session = B.session + 1; B:Stop("Merchant Session Changed") end)
end
for _, event in ipairs({ "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
 R:RegisterEvent(event, function() local op = B.operation; if op then B:Check(op) end; R:Fire("BUYBACK_CHANGED") end)
end
R:RegisterEvent("PLAYER_REGEN_DISABLED", function() B:Stop("Entered Combat") end)
