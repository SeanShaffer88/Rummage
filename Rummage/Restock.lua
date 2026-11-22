-- Rummage: account-wide targets, private bank consent and canonical move orchestration.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, Restock = ns.R, {}
R.Restock = Restock
local tokens = setmetatable({}, { __mode = "k" })
local function equal(a, b)
 if type(a) ~= type(b) then return false end
 if type(a) ~= "table" then return a == b end
 for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
 for k in pairs(b) do if a[k] == nil then return false end end
 return true
end
local function integer(v, low, high) return type(v) == "number" and v == v and v >= low and v <= high and v == math.floor(v) end
function Restock:SetTarget(id, quantity)
 id, quantity = tonumber(id), tonumber(quantity)
 if not integer(id, 1, 2147483647) or not integer(quantity, 0, 1000000) then return false, "Use A Positive Item ID And Whole Target (0 To Remove)" end
 local count = 0; for _ in pairs(R.db.restockTargets) do count = count + 1 end
 if quantity > 0 and not R.db.restockTargets[id] and count >= 500 then return false, "Target List Is Full" end
 R.db.restockTargets[id] = quantity > 0 and quantity or nil
 self.latest = nil; R:Fire("RESTOCK_CHANGED"); R:Fire("PLANNING_CHANGED")
 return true
end
function Restock:Preview()
 local carried = R.InventoryPlan:Capture(R.API.InvBagList, false)
 local bank = R.InventoryPlan:Capture(R.API.BankBagList, true)
 local totals, bankTotals = R.InventoryPlan:Totals(carried), R.InventoryPlan:Totals(bank)
 local wanted, ids = {}, {}
 for id, target in pairs(R.db.restockTargets) do wanted[id] = math.max(0, target - (totals[id] or 0)); ids[#ids + 1] = id end
 table.sort(ids)
 local allocation = R.InventoryPlan:Allocate(bank, carried, wanted)
 local preview = { session = R.Mover.bankSession, targetsSnapshot = R.DeepCopy(R.db.restockTargets), rows = {}, moves = allocation.moves,
  forecast = allocation, reasons = allocation.unknownReasons, executable = R.Data.atBank and carried.known and #allocation.moves > 0, initial = {} }
 for _, id in ipairs(ids) do
  local deficit, remaining = wanted[id], allocation.remaining[id]
  preview.rows[#preview.rows + 1] = { itemID = id, target = R.db.restockTargets[id], carried = totals[id] or 0, carriedKnown = carried.known, deficit = deficit, deficitKnown = carried.known,
   availableBank = R.Data.atBank and (bankTotals[id] or 0) or nil, bankKnown = bank.known, availableBankLowerBound = not bank.known, plannedWithdraw = deficit - remaining, remainingDeficit = remaining,
   reason = not carried.known and "Current Carried Quantity Unknown; Restock Unavailable" or deficit == 0 and "Target Already Met" or (not R.Data.atBank and "Bank Quantity Unknown / Visit A Banker" or (remaining > 0 and "Partial Plan: Locked, Unknown Or Insufficient Compatible Capacity" or "Exact Known Moves Planned")) }
 end
 for _, move in ipairs(preview.moves) do
  for _, pair in ipairs({ move.from, move.to }) do
   local key = pair[1] .. ":" .. pair[2]
   if not preview.initial[key] then
    local original = carried.byKey[key] or bank.byKey[key]
    preview.initial[key] = { bag = pair[1], slot = pair[2], link = original and original.link, count = original and original.count or 0, locked = original and original.locked or false, family = original and original.family, familyKnown = original and original.familyKnown,
     stack = original and original.meta and original.meta.stack, stackKnown = original and original.meta and original.meta.stackKnown, itemFamily = original and original.meta and original.meta.family }
   end
  end
 end
 preview.reason = preview.executable and "Confirm This Exact Preview To Withdraw" or (R.Data.atBank and "No Executable Restock Moves" or "Visit A Banker")
 self.latest = preview; tokens[preview] = R.DeepCopy(preview)
 return preview
end
local function matches(s)
 local size = R.API.GetNumSlots(s.bag)
 if type(size) ~= "number" or size < s.slot then return false end
 if s.familyKnown then
  local ok, _, family = pcall(R.API.GetNumFreeSlots, s.bag)
  if not ok or family ~= s.family then return false end
 end
 if s.stackKnown then
  local meta = R.InventoryPlan:Metadata(s.link, R.ItemID(s.link))
  if not meta.stackKnown or not meta.familyKnown or meta.stack ~= s.stack or meta.family ~= s.itemFamily then return false end
 end
 local link, count, _, _, locked = R.API.GetSlotInfo(s.bag, s.slot)
 return link == s.link and (count or 0) == s.count and (locked and true or false) == s.locked
end
function Restock:Execute(preview)
 local plan = tokens[preview]
 if preview ~= self.latest or not plan or not equal(preview, plan) then return false, "Preview Changed; Preview Again" end
 if not R.Data.atBank or plan.session ~= R.Mover.bankSession or not equal(plan.targetsSnapshot, R.db.restockTargets) then return false, "Bank Session Or Targets Changed; Preview Again" end
 if not plan.executable or InCombatLockdown() or GetCursorInfo() or R.Mover:Busy() then return false, "Restock Unavailable: Bank, Combat, Cursor Or Another Operation" end
 for _, slot in pairs(plan.initial) do if not matches(slot) then return false, "Source Or Destination Changed; Preview Again" end end
 self.latest, tokens[preview] = nil, nil
 local op = { observed = 0, index = 0, session = plan.session }
 self.operation = op
 local function context()
  return Restock.operation == op and R.Data.atBank and R.Mover.bankSession == op.session and equal(plan.targetsSnapshot, R.db.restockTargets)
 end
 local function planner()
  if not context() then return nil, "Restock Session Or Targets Changed" end
  while true do
   op.index = op.index + 1
   local original = plan.moves[op.index]; if not original then return nil end
   local snapshot = R.InventoryPlan:Capture(R.API.InvBagList, false)
   if not snapshot.known then return nil, "Current Carried Quantity Unknown" end
   local totals = R.InventoryPlan:Totals(snapshot)
   local deficit = math.max(0, (R.db.restockTargets[original.itemID] or 0) - (totals[original.itemID] or 0))
   if deficit > 0 then
    local amount = math.min(original.count, deficit)
    local from = { bag = original.from[1], slot = original.from[2], link = original.link, count = original.sourceCount, locked = false }
    local to = { bag = original.to[1], slot = original.to[2], link = original.destLink, count = original.destCount, locked = false }
    if not matches(from) or not matches(to) then return nil, "Restock Source Or Destination Changed; Preview Again" end
    local move = { from = original.from, to = original.to, amount = amount < original.sourceCount and amount or nil, reason = "Restock", count = amount }
    move.validate = function()
     if not context() then return false end
     local size = R.API.GetNumSlots(original.to[1])
     local ok, _, family = pcall(R.API.GetNumFreeSlots, original.to[1])
     local meta = R.InventoryPlan:Metadata(original.link, original.itemID)
     if type(size) ~= "number" or size < original.to[2] or not ok or family ~= original.destFamily
      or not meta.stackKnown or not meta.familyKnown or meta.stack ~= original.sourceStack or meta.family ~= original.sourceFamily then return false end
     local snapshot = R.InventoryPlan:Capture(R.API.InvBagList, false)
     if not snapshot.known then return false end
     local live = R.InventoryPlan:Totals(snapshot)
     return (R.db.restockTargets[original.itemID] or 0) - (live[original.itemID] or 0) >= amount
    end
    move.onObserved = function() op.observed = op.observed + amount; R:Fire("PLANNING_CHANGED") end
    return move
   end
  end
 end
 local started = R.Mover:Start(planner, "restock", nil, context, function(reason, completed)
  if Restock.operation ~= op then return end
  Restock.operation = nil
  R:Print("Restock Observed " .. op.observed .. " Unit(s)" .. (completed and "; Check Current Target Counts." or "; Stopped: " .. (reason or "Interrupted")))
  R:Fire("PLANNING_CHANGED")
 end)
 if not started then self.operation = nil; return false, "Restock Could Not Start" end
 return true
end
function Restock:Cancel() if self.operation then R.Mover:Stop("Restock Cancelled") end end
