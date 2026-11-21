-- Rummage: search query parser.
-- Syntax:  words AND together, "|" separates OR groups, "!" negates a term or a group,
--   ( ) group terms, "quoted text" keeps spaces (name:"linen cloth", "of the bear").
--   plain text        name / type / subtype / slot contains text
--   #keyword          #fav #new #junk #upgrade #bound #boe #bop #gear #consumable
--                     #quest #trade #recipe #key #usable #set, plus plugin keywords
--   field op value    ilvl>20  lvl<=30  count>5  q:rare  q>=uncommon  type:armor
--                     sub:cloth  slot:head  bag:2  value>1g  ah>50s  tsm>2g  ilvl:10-20
--                     set:tank  name:linen
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

-- Text getters return lower-case strings (values are lower-cased at compile time).
local TEXT_FIELDS = {
	type = function(e) return infoField(e, "ltype") end,
	sub = function(e) return infoField(e, "lsub") end,
	subtype = function(e) return infoField(e, "lsub") end,
	slot = function(e) return infoField(e, "lslot") end,
	name = function(e) return e.lname end,
	set = function(e) return R.Items:SetNames(e) end,
}

local KEYWORDS = {
	fav = function(e) return e.fav ~= nil end,
	favorite = function(e) return e.fav ~= nil end,
	new = function(e) return e.new and true or false end,
	junk = function(e) return e.junk end,
	trash = function(e) return e.junk end,
	upgrade = function(e) return R.Upgrade and R.Upgrade:EntryIsUpgrade(e) or false end,
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
	usable = function(e) return R.Items:Usable(e) end,
	set = function(e) return R.Items:InSet(e) end,
	equipset = function(e) return R.Items:InSet(e) end,
}

-- Plugin keywords (1.9.0): other addons add #name terms with
-- Rummage:RegisterSearchKeyword(name, function(entry) return bool end).
-- Built-in keywords cannot be replaced.
local BUILTIN_KEYWORDS = {}
for k in pairs(KEYWORDS) do BUILTIN_KEYWORDS[k] = true end

function Search:RegisterKeyword(name, fn)
	if type(name) ~= "string" or type(fn) ~= "function" then return false end
	name = name:lower():gsub("^#", "")
	if name == "" or name:find("[%s|&!]") or BUILTIN_KEYWORDS[name] then return false end
	KEYWORDS[name] = function(e)
		local ok, res = pcall(fn, e)
		return ok and res and true or false
	end
	self:ClearCache()
	return true
end

function Search:Keywords()
	local t = {}
	for k in pairs(KEYWORDS) do t[#t + 1] = k end
	table.sort(t)
	return t
end

local function textTerm(word)
	return function(e)
		if e.lname:find(word, 1, true) then return true end
		local inf = e.info
		if inf then
			if inf.ltype:find(word, 1, true) then return true end
			if inf.lsub:find(word, 1, true) then return true end
			if inf.lslot ~= "" and inf.lslot:find(word, 1, true) then return true end
		end
		return false
	end
end

local function compileTerm(term, literal)
	local neg = false
	if term:sub(1, 1) == "!" then
		neg = true
		term = term:sub(2)
	end
	if term == "" then return nil end
	local fn

	if literal then
		fn = textTerm(term)  -- a quoted phrase is plain text, never a field or keyword
	elseif term:sub(1, 1) == "#" then
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
					return v ~= nil and v:find(value, 1, true) ~= nil
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

-- Tokens: "(" ")" "|" "!" and terms. A term may contain "quoted text" (spaces kept);
-- a term that starts with a quote (after "!") is literal text. "&" is the same as a space.
local function tokenize(query)
	local toks, i, n = {}, 1, #query
	while i <= n do
		local c = query:sub(i, i)
		if c:find("%s") or c == "&" then
			i = i + 1
		elseif c == "(" or c == ")" or c == "|" then
			toks[#toks + 1] = { op = c }
			i = i + 1
		elseif c == "!" and (query:sub(i + 1, i + 1) == "(" or query:sub(i + 1, i + 1) == "!") then
			toks[#toks + 1] = { op = "!" }
			i = i + 1
		else
			local buf, literal = {}, false
			if c == "!" then buf[1] = "!"; i = i + 1 end
			if query:sub(i, i) == '"' then literal = true end
			while i <= n do
				c = query:sub(i, i)
				if c == '"' then
					local close = query:find('"', i + 1, true) or (n + 1)
					buf[#buf + 1] = query:sub(i + 1, close - 1)
					i = close + 1
				elseif c:find("%s") or c == "&" or c == "(" or c == ")" or c == "|" then
					break
				else
					buf[#buf + 1] = c
					i = i + 1
				end
			end
			local term = table.concat(buf)
			if term ~= "" and term ~= "!" then toks[#toks + 1] = { term = term, literal = literal } end
		end
	end
	return toks
end

-- Strict shape validation for destructive-rule drafts; normal search remains forgiving.
function Search:ValidateQuery(query)
 local tokens, pos = tokenize(query), 1
 local expression
 local function unary()
  local token = tokens[pos]
  if not token then return false end
  if token.op == "!" then pos = pos + 1; return unary() end
  if token.op == "(" then
   pos = pos + 1
   if not expression() or not tokens[pos] or tokens[pos].op ~= ")" then return false end
   pos = pos + 1; return true
  end
  if token.term and token.term:find("[%w\128-\255]") then pos = pos + 1; return true end
  return false
 end
 function expression()
  if not unary() then return false end
  while tokens[pos] and tokens[pos].op ~= ")" do
   if tokens[pos].op == "|" then pos = pos + 1 end
   if not unary() then return false end
  end
  return true
 end
 return expression() and tokens[pos] == nil
end

local function always() return true end

-- Recursive descent:  or := and ("|" and)* ; and := unary unary* ;
-- unary := "!" unary | "(" or ")" | term.  Missing ")" closes at the end; stray ")" is ignored.
local function parse(toks)
	local pos = 1
	local parseOr
	local function parseUnary()
		local t = toks[pos]
		if not t then return nil end
		if t.op == "!" then
			pos = pos + 1
			local inner = parseUnary()
			if not inner then return nil end
			return function(e) return not inner(e) end
		elseif t.op == "(" then
			pos = pos + 1
			local inner = parseOr()
			if toks[pos] and toks[pos].op == ")" then pos = pos + 1 end
			return inner or always
		elseif t.term then
			pos = pos + 1
			return compileTerm(t.term, t.literal) or always
		end
		return nil
	end
	local function parseAnd()
		local terms = {}
		while toks[pos] and toks[pos].op ~= "|" and toks[pos].op ~= ")" do
			local f = parseUnary()
			if f then terms[#terms + 1] = f elseif toks[pos] then pos = pos + 1 end
		end
		if #terms == 0 then return nil end
		if #terms == 1 then return terms[1] end
		return function(e)
			for i = 1, #terms do if not terms[i](e) then return false end end
			return true
		end
	end
	function parseOr()
		local groups = {}
		while toks[pos] and toks[pos].op ~= ")" do
			if toks[pos].op == "|" then pos = pos + 1
			else
				local g = parseAnd()
				if g then groups[#groups + 1] = g end
			end
		end
		if #groups == 0 then return nil end
		if #groups == 1 then return groups[1] end
		return function(e)
			for i = 1, #groups do if groups[i](e) then return true end end
			return false
		end
	end
	local pred
	repeat
		local p = parseOr()
		if p then pred = pred and (function(a, b) return function(e) return a(e) and b(e) end end)(pred, p) or p end
		if toks[pos] and toks[pos].op == ")" then pos = pos + 1 end  -- stray ")"
	until not toks[pos]
	return pred
end

function Search:CompileUncached(query)
	query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if query == "" then return nil end
	if cache[query] then return cache[query] end
	local pred = parse(tokenize(query))
	if not pred then return nil end
	cache[query] = pred
	return pred
end

function Search:ClearCache()
	wipe(rawCache); wipe(cache); rawCount = 0
end

function Search:Matches(query, e)
	local p = self:Compile(query)
	return not p or p(e)
end
