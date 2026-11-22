-- Rummage: in-memory merchant facts, independent of history rendering and eviction.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, V = ns.R, {}
R.VendorSession = V
local current, previous, generation = nil, nil, 0
local function number(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge end
local function integer(v) return number(v) and v == math.floor(v) end
local function money(v) return v == 0 and "0c" or (v < 0 and "-" .. R.FormatMoney(-v) or R.FormatMoney(v)) end
local function identity(fact)
 if type(fact.operationID) == "string" and #fact.operationID > 0 and #fact.operationID <= 128 then return fact.operationID end
 if integer(fact.operationID) then return tostring(fact.operationID) end
 if type(fact.saleLedgerID) == "string" and #fact.saleLedgerID > 0 and #fact.saleLedgerID <= 64 then return fact.saleLedgerID end
end
local function retained(session)
 if not R.InventoryPlan then return nil end
 local ok, snapshot = pcall(R.InventoryPlan.Capture, R.InventoryPlan, R.API.InvBagList, false)
 if not ok or not snapshot.known then return nil end
 local totals = R.InventoryPlan:Totals(snapshot)
 local sum = 0
 for id in pairs(session.candidates) do
  local count, keep = totals[id] or 0, R.db.keepQuantities[id] or 0
  if not number(count) or not number(keep) then return nil end
  sum = sum + math.min(count, keep)
 end
 return sum
end
local function freeSlots()
 if not R.API.GetNumFreeSlots then return nil end
 local total = 0
 for _, bag in ipairs(R.API.InvBagList) do
  if bag ~= R.API.KEYRING then
   local ok, count = pcall(R.API.GetNumFreeSlots, bag)
   if not ok or not number(count) then return nil end
   total = total + count
  end
 end
 return total
end
function V:Token() return current and current.id end
function V:Begin()
 if current then self:End() end
 generation = generation + 1
 local ok, money = pcall(GetMoney)
 current = { id = generation, opened = time(), candidates = {}, sales = {}, buybacks = {}, seen = {}, requests = {}, staging = {},
  stacks = 0, units = 0, gross = 0, buybackUnits = 0, buybackCost = 0, slotsFreed = 0, stopped = 0, skipped = 0,
  walletBaseline = ok and number(money) and money or nil, freeBaseline = freeSlots() }
 R:Fire("VENDOR_SUMMARY_CHANGED")
 return current.id
end
function V:End()
 if not current then return end
 current.retainedAtClose, current.closed = retained(current), time()
 previous, current = current, nil
 R:Fire("VENDOR_SUMMARY_CHANGED")
end
function V:Record(action, status, fact)
 if type(fact) ~= "table" or not current or fact.session ~= current.id then return false end
 if action ~= "Sale" and action ~= "Buyback" and action ~= "Split" then return false end
 local id = fact.itemID or (type(fact.id) == "number" and fact.id) or (type(fact.link) == "string" and R.ItemID(fact.link))
 if integer(id) and id > 0 and id <= 2147483647 then current.candidates[id] = true end
 if status == "Candidate" then return true end
 local op = identity(fact)
 if not op then return false end
 local key = action .. ":" .. op
 local event = key .. ":" .. status
 if current.seen[event] then return false end
 if status == "Observed" and (action == "Sale" or action == "Buyback") then
  if type(fact.saleLedgerID) ~= "string" or #fact.saleLedgerID == 0 or #fact.saleLedgerID > 64 or not integer(fact.count) or fact.count <= 0 or not integer(fact.value) then return false end
  local seen = action == "Sale" and current.sales or current.buybacks
  if seen[fact.saleLedgerID] then return false end
  seen[fact.saleLedgerID] = true
  if action == "Sale" then
   current.stacks, current.units, current.gross = current.stacks + 1, current.units + fact.count, current.gross + fact.value
   if fact.slotsFreed == 0 or fact.slotsFreed == 1 then current.slotsFreed = current.slotsFreed + fact.slotsFreed else current.slotsUnknown = true end
   current.staging[op] = nil
  else current.buybackUnits, current.buybackCost = current.buybackUnits + fact.count, current.buybackCost + fact.value end
  current.requests[key] = nil
 elseif status == "Requested" then current.requests[key] = true
 elseif status == "Stopped" then current.stopped = current.stopped + 1
 elseif status == "Skipped" then current.skipped = current.skipped + 1
 elseif status == "Observed" and action == "Split" then
  current.requests[key] = nil
  if fact.slotsConsumed == 1 then current.staging[op] = 1 else current.stagingUnknown = true end
 else return false end
 current.seen[event] = true
 R:Fire("VENDOR_SUMMARY_CHANGED")
 return true
end
function V:Summary()
 local session = current or previous
 if not session then return { rows = {}, summary = "No Merchant Visit Recorded", active = false } end
 local held = current and retained(session) or session.retainedAtClose
 local unconfirmed, staging = 0, 0
 for _ in pairs(session.requests) do unconfirmed = unconfirmed + 1 end
 for _, slots in pairs(session.staging) do staging = staging + slots end
 local rows = {
  { label = "Observed Sales", detail = session.stacks .. " Stacks / " .. session.units .. " Units" },
  { label = "Gross Observed Sale Proceeds", detail = money(session.gross) },
  { label = "Observed Buyback Cost", detail = money(session.buybackCost) .. " / " .. session.buybackUnits .. " Units" },
  { label = "Net Observed Sale Proceeds", detail = money(session.gross - session.buybackCost) },
  { label = "Currently Retained By Keep Quantities", detail = held == nil and "Unknown" or tostring(held) },
  { label = "Slots Freed By Sales", detail = session.slotsUnknown and "Unknown" or tostring(session.slotsFreed) },
  { label = "Unresolved Confirmed Split Staging Effects", detail = session.stagingUnknown and "Unknown" or (staging .. " Slot(s) Added; Current Occupancy May Differ") },
  { label = "Unconfirmed / Stopped / Skipped", detail = unconfirmed .. " / " .. session.stopped .. " / " .. session.skipped },
 }
 local summary = (current and "Current Merchant Visit" or "Last Merchant Visit — Ended") .. " | " .. (session.stacks == 0 and "No Observed Sales This Visit" or (session.stacks .. " Observed Sale Stacks"))
 return { rows = rows, summary = summary, active = current ~= nil, session = session.id, observedStacks = session.stacks,
  observedUnits = session.units, gross = session.gross, buybackCost = session.buybackCost, net = session.gross - session.buybackCost,
  retained = held, slotsFreed = not session.slotsUnknown and session.slotsFreed or nil, stagingSlots = not session.stagingUnknown and staging or nil,
  unconfirmed = unconfirmed, stopped = session.stopped, skipped = session.skipped }
end
R:RegisterEvent("MERCHANT_SHOW", function() V:Begin() end)
R:RegisterEvent("MERCHANT_CLOSED", function() V:End() end)
