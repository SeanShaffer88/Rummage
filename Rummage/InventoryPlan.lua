-- Rummage: read-only full-link slot capacity simulation.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, P = ns.R, {}
R.InventoryPlan = P
local function integer(n, min, max) return type(n) == "number" and n == n and n >= min and n <= max and n == math.floor(n) end
local function unknown(result, reason)
 result.known = false
 for _, old in ipairs(result.unknownReasons) do if old == reason then return end end
 result.unknownReasons[#result.unknownReasons + 1] = reason
end
function P:Metadata(link, id)
 local read, info = pcall(R.Items.Info, R.Items, link)
 if not read then info = nil end
 local ok, family = false, nil
 if R.API.GetItemFamily then ok, family = pcall(R.API.GetItemFamily, id or link) end
 return { stack = info and info.stack, stackKnown = info and info.stackKnown == true,
  family = family, familyKnown = ok and integer(family, 0, 2147483647), info = info }
end
function P:Capture(bags, bank)
 local result = { known = true, unknownReasons = {}, slots = {}, byKey = {} }
 if bank and not R.Data.atBank then unknown(result, "Bank Quantity Unknown / Visit A Banker"); return result end
 for _, bag in ipairs(bags) do
  if bag ~= R.API.KEYRING then
   local ok, size = pcall(R.API.GetNumSlots, bag)
   if not ok or not integer(size, 0, 1000) or ((bank or bag == R.API.BACKPACK) and size == 0) then unknown(result, "Bank Or Bag Container Unavailable")
   elseif size > 0 then
    local familyOK, _, family = false, nil, nil
    if R.API.GetNumFreeSlots then familyOK, _, family = pcall(R.API.GetNumFreeSlots, bag) end
    local familyKnown = familyOK and integer(family, 0, 2147483647)
    if not familyKnown then unknown(result, "Bag Family Unknown") end
    for slot = 1, size do
     local read, link, count, _, _, locked, id = pcall(R.API.GetSlotInfo, bag, slot)
     if not read or (link and (type(link) ~= "string" or R.IsSecret(link) or not integer(count, 1, 1000000))) then unknown(result, "Slot Identity Or Quantity Unknown")
     else
      local entry = { bag = bag, slot = slot, link = link, count = link and count or 0, id = id or (link and R.ItemID(link)), locked = locked and true or false,
       carried = not bank, family = family, familyKnown = familyKnown }
      if link then entry.meta = self:Metadata(link, entry.id) end
      result.slots[#result.slots + 1] = entry; result.byKey[bag .. ":" .. slot] = entry
     end
    end
   end
  end
 end
 return result
end
function P:Totals(snapshot)
 local totals = {}
 for _, e in ipairs(snapshot.slots) do if e.id then totals[e.id] = (totals[e.id] or 0) + e.count end end
 return totals
end
local function fits(source, dest)
 if not dest.familyKnown or not source.meta or not source.meta.familyKnown then return false end
 return dest.family == 0 or (source.meta.family ~= 0 and bit.band(source.meta.family, dest.family) ~= 0)
end
function P:Destination(source, destinations, onlyEmpty)
 local meta = source.meta
 if not meta or not meta.stackKnown or not meta.familyKnown then return nil, "Item Stack Or Family Unknown" end
 if not onlyEmpty then
  for _, d in ipairs(destinations) do
   if (d.bag ~= source.bag or d.slot ~= source.slot) and not d.locked and d.link == source.link and d.count < meta.stack then return d, meta.stack - d.count end
  end
 end
 for _, special in ipairs({ true, false }) do
  for _, d in ipairs(destinations) do
   if (d.bag ~= source.bag or d.slot ~= source.slot) and not d.link and not d.locked and d.familyKnown and (d.family ~= 0) == special and fits(source, d) then return d, meta.stack end
  end
 end
 return nil, "No Compatible Unlocked Slot Capacity"
end
function P:Allocate(sourceSnapshot, destinationSnapshot, wanted)
 local result = { known = sourceSnapshot.known and destinationSnapshot.known, unknownReasons = {}, moves = {}, rows = {},
  netCarriedSlots = 0, temporarySlotsNeeded = 0, blockedMoves = 0, remaining = R.DeepCopy(wanted) }
 for _, snapshot in ipairs({ sourceSnapshot, destinationSnapshot }) do for _, reason in ipairs(snapshot.unknownReasons) do unknown(result, reason) end end
 local sources, destinations = R.DeepCopy(sourceSnapshot.slots), R.DeepCopy(destinationSnapshot.slots)
 local keys = {}; for _, source in ipairs(sources) do keys[source.bag .. ":" .. source.slot] = true end
 for _, dest in ipairs(destinations) do
  if keys[dest.bag .. ":" .. dest.slot] then
   unknown(result, "Overlapping Source And Destination Regions Unsupported")
   result.blockedMoves, result.summary = #sources, "Forecast Unknown: Overlapping Slot Regions"
   return result
  end
 end
 for _, s in ipairs(sources) do
  while s.link and s.count > 0 and (result.remaining[s.id] or 0) > 0 do
   if s.locked then result.blockedMoves = result.blockedMoves + 1; break end
   local dest, capacity = self:Destination(s, destinations)
   if not dest then
    result.blockedMoves = result.blockedMoves + 1
    if capacity:find("Unknown", 1, true) then unknown(result, capacity) end
    break
   end
   local amount = math.min(s.count, capacity, result.remaining[s.id])
   if amount < s.count and not R.API.SplitContainerItem then result.blockedMoves = result.blockedMoves + 1; unknown(result, "Exact Split Unsupported"); break end
   if #result.moves >= 400 then result.blockedMoves = result.blockedMoves + 1; unknown(result, "Plan Step Limit"); break end
   local move = { from = { s.bag, s.slot }, to = { dest.bag, dest.slot }, count = amount, link = s.link, itemID = s.id,
    sourceCount = s.count, sourceStack = s.meta.stack, sourceFamily = s.meta.family, destFamily = dest.family, destLink = dest.link, destCount = dest.count, sourceCarried = s.carried, destinationCarried = dest.carried }
   result.moves[#result.moves + 1] = move
   if s.carried and amount == s.count then result.netCarriedSlots = result.netCarriedSlots + 1 end
   if dest.carried and not dest.link then result.netCarriedSlots = result.netCarriedSlots - 1 end
   dest.link, dest.id, dest.count, dest.meta = s.link, s.id, dest.count + amount, s.meta
   s.count = s.count - amount; if s.count == 0 then s.link = nil end
   result.remaining[move.itemID] = result.remaining[move.itemID] - amount
  end
 end
 for _, move in ipairs(result.moves) do result.rows[#result.rows + 1] = { label = move.link .. " x" .. move.count, detail = move.from[1] .. ":" .. move.from[2] .. " -> " .. move.to[1] .. ":" .. move.to[2] } end
 result.summary = result.known and ("If This Preview Completes: " .. (result.netCarriedSlots >= 0 and "+" or "") .. result.netCarriedSlots .. " Free Carried Slots") or "Forecast Unknown; Known Moves Are Listed Separately"
 return result
end
function P:Forecast(kind, query)
 query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
 if query ~= "" then local valid, errorText = R.Junk:PreviewRule(query); if not valid then return nil, errorText end end
 local carried = self:Capture(R.API.InvBagList, false)
 if kind == "sale" then
  if not carried.known then return { known = false, netCarriedSlots = 0, temporarySlotsNeeded = 0, blockedMoves = 0,
   unknownReasons = R.DeepCopy(carried.unknownReasons), rows = {}, summary = "Forecast Unknown: Carried Inventory Unavailable" } end
  local read, list = pcall(R.Junk.Collect, R.Junk)
  if not read then return { known = false, netCarriedSlots = 0, temporarySlotsNeeded = 0, blockedMoves = 0,
   unknownReasons = { "Canonical Sale Snapshot Unavailable" }, rows = {}, summary = "Forecast Unknown" } end
  -- -- canonical enabled rules, protections, reserves and final cap first
  local result = { known = carried.known, netCarriedSlots = 0, temporarySlotsNeeded = 0, blockedMoves = 0, unknownReasons = {}, rows = {} }
  for _, reason in ipairs(carried.unknownReasons) do unknown(result, reason) end
  local slots = R.DeepCopy(carried.slots)
  for _, it in ipairs(list) do
   local e = { id = it.id, link = it[5], count = it[6], bag = it[1], slot = it[2], q = it[4], slots = { { it[1], it[2] } } }
   R.Items:Prepare(e, R.Data.me, true, true)
   if query == "" or R.Search:Matches(query, e) then
    local source
    for _, slot in ipairs(slots) do if slot.bag == it[1] and slot.slot == it[2] then source = slot; break end end
    local reason
    if not source then reason = "Source Unknown"; unknown(result, reason)
    elseif it.sellCount == it[6] then result.netCarriedSlots = result.netCarriedSlots + 1; source.link, source.count = nil, 0
    else
     result.temporarySlotsNeeded = math.max(result.temporarySlotsNeeded, 1)
     local dest, why = self:Destination(source, slots, true)
     if not R.API.SplitContainerItem then reason = "Exact Split Unsupported"
     elseif not dest then reason = why end
     if reason then result.blockedMoves = result.blockedMoves + 1; if reason:find("Unknown", 1, true) then unknown(result, reason) end end
    end
    result.rows[#result.rows + 1] = { label = it[5] .. " x" .. it.sellCount, detail = reason or (it.sellCount == it[6] and "Full Sale Frees 1 Slot" or "Partial Sale: Net 0 Slots; Needs 1 Temporary Slot") }
   end
  end
  result.summary = result.known and ("If This Preview Completes: +" .. result.netCarriedSlots .. " Free Carried Slots") or "Forecast Unknown"
  return result
 end
 if kind ~= "toBank" and kind ~= "fromBank" then return nil, "Choose Sale, To Bank Or From Bank" end
 local bank = self:Capture(R.API.BankBagList, true)
 local sources, destinations = kind == "toBank" and carried or bank, kind == "toBank" and bank or carried
 local selected, wanted = { known = sources.known, unknownReasons = sources.unknownReasons, slots = {} }, {}
 for _, source in ipairs(sources.slots) do if source.link then
  local e = { id = source.id, link = source.link, count = source.count, bag = source.bag, slot = source.slot, slots = { { source.bag, source.slot } } }
  R.Items:Prepare(e, R.Data.me, true, true)
  if query == "" or R.Search:Matches(query, e) then selected.slots[#selected.slots + 1] = source; wanted[source.id] = (wanted[source.id] or 0) + source.count end
 end end
 return self:Allocate(selected, destinations, wanted)
end
