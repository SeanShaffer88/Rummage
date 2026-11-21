-- Rummage: bounded local action evidence, never a source of inventory commands.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R = ns.R
local H = {}
R.ActionHistory = H
local actions = { Sale = true, Buyback = true, Transfer = true, Mail = true, Trade = true, Split = true }
local statuses = { Requested = true, Observed = true, Skipped = true, Stopped = true }
local function number(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge end
local function text(v, limit) return type(v) == "string" and v:sub(1, limit) or nil end
local function clean(e)
 if type(e) ~= "table" or not actions[e.action] or not statuses[e.status] or not number(e.t) then return end
 local c = { t = e.t, action = e.action, status = e.status }
 for _, key in ipairs({ "itemID", "count", "value" }) do
  if number(e[key]) then c[key] = math.min(1000000000000, math.floor(e[key])) end
 end
 for _, key in ipairs({ "link", "from", "to", "reason" }) do c[key] = text(e[key], key == "link" and 512 or 180) end
 return c
end
function H:Sanitize(db)
 local out, high = {}, 0
 for _, e in ipairs(type(db.actionHistory) == "table" and db.actionHistory or {}) do
  local c = clean(e)
  if c and #out < 100 then
   local id = number(e.id) and e.id < 9007199254740000 and math.floor(e.id) or 0
   if id > high then high = id end
   c.id = id; out[#out + 1] = c
  end
 end
 -- Reassign on load so malformed/duplicate persisted IDs cannot alias selected rows.
 high = 0 -- IDs are session-local; never trust a persisted counter near numeric precision limits.
 for i = #out, 1, -1 do high = high + 1; out[i].id = high end
 db.actionHistory, db.actionHistoryNextID = out, high
end
function H:Record(action, status, details)
 if not R.db then return end
 local e = {}; for k, v in pairs(details or {}) do e[k] = v end
 e.action, e.status, e.t = action, status, time()
 e = clean(e); if not e then return end
 R.db.actionHistoryNextID = (R.db.actionHistoryNextID or 0) + 1
 e.id = R.db.actionHistoryNextID
 local history = R.db.actionHistory
 table.insert(history, 1, e)
 while #history > 100 do history[#history] = nil end
 R:Fire("ACTION_HISTORY_CHANGED")
 return e
end
function H:Page(filter, page, size)
 size = math.max(1, math.min(10, tonumber(size) or 8))
 local matches = {}
 for _, e in ipairs(R.db.actionHistory) do
  if not filter or filter == "All" or (filter == "Sales" and e.action == "Sale")
   or (filter == "Buyback" and e.action == "Buyback")
   or (filter == "Transfers" and (e.action == "Transfer" or e.action == "Mail" or e.action == "Trade"))
   or (filter == "Skipped" and (e.status == "Skipped" or e.status == "Stopped")) then matches[#matches + 1] = e end
 end
 local pages = math.max(1, math.ceil(#matches / size))
 page = math.max(1, math.min(pages, tonumber(page) or 1))
 local out = {}; for i = (page - 1) * size + 1, math.min(#matches, page * size) do out[#out + 1] = matches[i] end
 return out, #matches, pages
end
function H:Clear() R.db.actionHistory = {}; R:Fire("ACTION_HISTORY_CHANGED") end
