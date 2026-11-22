-- Rummage: read-only rule overlap, classification and sale-protection explanations.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local R, D = ns.R, {}
R.RuleDiagnostics = D
local function label(e) return e.name or e.link or ("Item " .. tostring(e.id)) end
function D:AnalyzeRules(draft)
 if draft ~= nil and type(draft) ~= "string" then return nil, "Draft Rule Must Be Text" end
 local draftPreview
 if draft and draft:match("%S") then
  local err; draftPreview, err = R.Junk:PreviewRule(draft)
  if not draftPreview then return nil, err end
 end
 local plannedOK, candidates, _, planned = pcall(R.Junk.Plan, R.Junk)
 if not plannedOK or type(planned.entries) ~= "table" then return nil, "Canonical Sale Snapshot Unavailable" end
 local entries = planned.entries
 local saleSlots = {}
 for _, item in ipairs(candidates) do saleSlots[item[1] .. ":" .. item[2]] = item.sellCount end
 local result = { rows = {}, matchedUnits = 0, overlapUnits = 0, sellUnits = planned.sellUnits or 0,
  retainedUnits = planned.retainedUnits or 0, overlapPairs = {}, unknownUnits = 0, draft = draftPreview }
 for i, e in ipairs(entries) do
  local matches, indices, errors = {}, {}, {}
  for index, query in ipairs(R.db.junkRules) do
   local matchedOK, matched = pcall(R.Search.Matches, R.Search, query, e)
   if not matchedOK then errors[#errors + 1] = "Rule " .. index .. " Unavailable"
   elseif matched then matches[#matches + 1] = { index = index, query = query }; indices[#indices + 1] = tostring(index) end
  end
  if #matches > 0 then result.matchedUnits = result.matchedUnits + e.count end
  if #matches > 1 then
   result.overlapUnits = result.overlapUnits + e.count
   for a = 1, #matches - 1 do for b = a + 1, #matches do
    local pair = matches[a].index .. ":" .. matches[b].index
    result.overlapPairs[pair] = (result.overlapPairs[pair] or 0) + e.count
   end end
  end
  local decision, source = e.junk, e.junkSource or "Classification Unknown"
  if e.junkError then errors[#errors + 1] = e.junkError end
  if source == "Manual Override" then source = decision and "Manual Junk" or "Manual Keep" end
  local canonical = planned.rows and planned.rows[i]
  local amount = saleSlots[e.bag .. ":" .. e.slot] or 0
  local effect = canonical and canonical.reason or "Plan Snapshot Changed"
  local protection = effect
  if canonical and (canonical.id ~= e.id or canonical.link ~= e.link or canonical.count ~= e.count) then amount, effect = 0, "Plan Snapshot Changed" end
  if not e.info then errors[#errors + 1] = "Unknown Item Data" end
  if #errors > 0 then result.unknownUnits = result.unknownUnits + e.count end
  local ruleText = #indices > 0 and ("Rules " .. table.concat(indices, ", ")) or "No Matching Enabled Rules"
  if #matches > 1 then ruleText = ruleText .. " — Overlapping Rules (OR; No Priority Winner)" end
  if R.db.favorites[e.id] and #matches > 0 then ruleText = ruleText .. "; Favorite Excluded From Rule Classification" end
  local detail = ruleText .. " | " .. source .. ": " .. (decision and "Junk" or "Not Junk")
   .. " | Sale " .. amount .. "/" .. e.count .. " | " .. (protection or effect or "Eligible")
  if #errors > 0 then detail = detail .. " | " .. table.concat(errors, "; ") end
  if draftPreview and R.db.favorites[e.id] then detail = detail .. " | Draft Preview Excludes Favorites Even With Sale Protection Off" end
  result.rows[#result.rows + 1] = { itemID = e.id, bag = e.bag, slot = e.slot, matches = matches,
   junk = decision, source = source, saleUnits = amount, reason = protection or effect, label = label(e) .. " x" .. e.count, detail = detail }
 end
 result.summary = #entries == 0 and "No Items In Current Bags" or string.format("Matched Units: %d | Overlap Units: %d | Planned Sale: %d | Reserve-Retained Eligible Units: %d", result.matchedUnits, result.overlapUnits, result.sellUnits, result.retainedUnits)
 if #R.db.junkRules == 0 then result.summary = result.summary .. " | No Enabled Rules" end
 if result.overlapUnits == 0 then result.summary = result.summary .. " | No Overlaps" end
 if draftPreview then result.summary = result.summary .. " | Draft Is Read-Only; Not Enabled" end
 return result
end
