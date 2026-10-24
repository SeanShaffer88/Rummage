-- Rummage: search query parser.
-- Syntax:  words AND together, "|" separates OR groups, "!" negates a term.
--   plain text        name / type / subtype / slot contains text
--   #keyword          #fav #new #junk #upgrade #bound #boe #bop #gear #consumable
--                     #quest #trade #recipe #key #usable
--   field op value    ilvl>20  lvl<=30  count>5  q:rare  q>=uncommon  type:armor
--                     sub:cloth  slot:head  bag:2  value>1g  ah>50s  tsm>2g  ilvl:10-20
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

local Search = {}
R.Search = Search

local QUALITY = {
	poor = 0, grey = 0, gray = 0, junk = 0,
	common = 1, white = 1,
	uncommon = 2, green = 2,
	rare = 3, blue = 3,
	epic = 4, purple = 4,
	legendary = 5, orange = 5,
	artifact = 6, heirloom = 7,
}

local function num(v) return tonumber(v) end

local function compare(a, op, b)
	if a == nil or b == nil then return false end
	if op == ">" then return a > b
	elseif op == "<" then return a < b
	elseif op == ">=" then return a >= b
	elseif op == "<=" then return a <= b
	else return a == b end
end

local function infoField(e, k) return e.info and e.info[k] end

-- numeric fields: getter(e), value parser
local NUMERIC = {
	ilvl = function(e) return infoField(e, "ilvl") end,
	lvl = function(e) return infoField(e, "req") end,
	req = function(e) return infoField(e, "req") end,
	count = function(e) return e.count end,
	bag = function(e) return e.bag end,
	value = function(e) return (infoField(e, "sell") or 0) * e.count end,
	vendor = function(e) return (infoField(e, "sell") or 0) * e.count end,
	ah = function(e) return R.Columns:ValueOf("ah", e) end,
	tsm = function(e) return R.Columns:ValueOf("tsm", e) end,
	pawn = function(e)
		local v = R.Integrations.PawnUpgrade and R.Integrations:PawnUpgrade(e)
		return v and v * 100 or nil
	end,
}
local MONEY_FIELDS = { value = true, vendor = true, ah = true, tsm = true }

local TEXT_FIELDS = {
	type = function(e) return infoField(e, "type") end,
	sub = function(e) return infoField(e, "sub") end,
	subtype = function(e) return infoField(e, "sub") end,
	slot = function(e) return infoField(e, "slotName") end,
	name = function(e) return e.name end,
}

local KEYWORDS = {
	fav = function(e) return e.fav ~= nil end,
	favorite = function(e) return e.fav ~= nil end,
	new = function(e) return e.new and true or false end,
	junk = function(e) return e.junk end,
	trash = function(e) return e.junk end,
	upgrade = function(e)
		return R.Integrations.PawnUpgrade and R.Integrations:PawnUpgrade(e) ~= nil or false
	end,
	bound = function(e) return e.bound and true or false end,
	soulbound = function(e) return e.bound and true or false end,
	unbound = function(e) return not e.bound end,
	boe = function(e) return not e.bound and infoField(e, "bindType") == 2 end,
	bop = function(e) return infoField(e, "bindType") == 1 end,
	gear = function(e) return infoField(e, "equippable") or false end,
	equipment = function(e) return infoField(e, "equippable") or false end,
	consumable = function(e) return infoField(e, "class") == 0 end,
	quest = function(e) return infoField(e, "class") == 12 or infoField(e, "bindType") == 4 end,
	trade = function(e) local c = infoField(e, "class"); return c == 7 or c == 5 end,
	reagent = function(e) local c = infoField(e, "class"); return c == 7 or c == 5 end,
	recipe = function(e) return infoField(e, "class") == 9 end,
	key = function(e) return R.Items:IsKey(e) end,
	usable = function(e) return (infoField(e, "req") or 0) <= UnitLevel("player") end,
}

local function textTerm(word)
	return function(e)
		if e.lname:find(word, 1, true) then return true end
		local inf = e.info
		if inf then
			if inf.type:lower():find(word, 1, true) then return true end
			if inf.sub:lower():find(word, 1, true) then return true end
			if inf.slotName ~= "" and inf.slotName:lower():find(word, 1, true) then return true end
		end
		return false
	end
end

local function compileTerm(term)
	local neg = false
	if term:sub(1, 1) == "!" then
		neg = true
		term = term:sub(2)
	end
	if term == "" then return nil end
	local fn

	if term:sub(1, 1) == "#" then
		local k = KEYWORDS[term:sub(2)]
		fn = k or function() return false end
	else
		local field, op, value = term:match("^(%a+)([:=<>]=?)(.+)$")
		if field and (NUMERIC[field] or TEXT_FIELDS[field] or field == "q" or field == "quality") then
			if field == "q" or field == "quality" then
				local q = QUALITY[value] or num(value)
				local o = (op == ":" ) and "=" or op
				fn = function(e) return compare(e.quality, o, q) end
			elseif NUMERIC[field] then
				local getter = NUMERIC[field]
				local lo, hi = value:match("^([%w%.]+)%-([%w%.]+)$")
				local parse = MONEY_FIELDS[field] and R.ParseMoney or num
				if op == ":" and lo then
					lo, hi = parse(lo), parse(hi)
					fn = function(e) local v = getter(e); return v ~= nil and lo ~= nil and hi ~= nil and v >= lo and v <= hi end
				else
					local target = parse(value)
					local o = (op == ":") and "=" or op
					fn = function(e) return compare(getter(e), o, target) end
				end
			else
				local getter = TEXT_FIELDS[field]
				fn = function(e)
					local v = getter(e)
					return v ~= nil and v:lower():find(value, 1, true) ~= nil
				end
			end
		else
			fn = textTerm(term)
		end
	end

	if neg then
		local inner = fn
		fn = function(e) return not inner(e) end
	end
	return fn
end

-- Two-level cache: rawCache is keyed by the exact query string so the hot path
-- (custom-category filters run once per item per refresh) does no string work at all.
local cache, rawCache, rawCount = {}, {}, 0
local EMPTY = {}

-- Returns a predicate for the query, or nil when the query is empty.
function Search:Compile(query)
	if not query then return nil end
	local hit = rawCache[query]
	if hit ~= nil then
		if hit == EMPTY then return nil end
		return hit
	end
	local pred = self:CompileUncached(query)
	if rawCount > 300 then wipe(rawCache); wipe(cache); rawCount = 0 end
	rawCache[query] = pred or EMPTY
	rawCount = rawCount + 1
	return pred
end

function Search:CompileUncached(query)
	query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if query == "" then return nil end
	if cache[query] then return cache[query] end

	local groups = {}
	for group in (query .. "|"):gmatch("(.-)|") do
		local terms = {}
		for term in group:gsub("&", " "):gmatch("%S+") do
			local t = compileTerm(term)
			if t then terms[#terms + 1] = t end
		end
		if #terms > 0 then groups[#groups + 1] = terms end
	end
	if #groups == 0 then return nil end

	local pred = function(e)
		for gi = 1, #groups do
			local terms = groups[gi]
			local ok = true
			for ti = 1, #terms do
				if not terms[ti](e) then ok = false; break end
			end
			if ok then return true end
		end
		return false
	end
	cache[query] = pred
	return pred
end

function Search:Matches(query, e)
	local p = self:Compile(query)
	return not p or p(e)
end
