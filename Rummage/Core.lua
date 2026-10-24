-- Rummage: list-view bag & bank replacement for WoW Forever.
-- Copyright (C) 2026 Malikor. Licensed under the GNU GPL v3 or later (see LICENSE).

local ADDON, ns = ...

-- Upvalue frequently used globals (faster than _G hash lookups in hot paths).
local pairs, ipairs, type, tonumber, tostring, next = pairs, ipairs, type, tonumber, tostring, next
local pcall, select, wipe = pcall, select, wipe
local floor, max, min = math.floor, math.max, math.min
local format, concat = string.format, table.concat
local GetTime = GetTime
local debugprofilestop = debugprofilestop

local R = {}
ns.R = R
_G.Rummage = R

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
R.name = ADDON
R.title = "Rummage"
R.version = (GetMeta and GetMeta(ADDON, "Version")) or "dev"
R.media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- One frame dispatches every event to per-event handler lists. Handler lists are
-- copy-on-write, so (un)registering from inside a handler never corrupts iteration.
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Diagnostics (see Debug.lua). All counters are no-ops unless debug mode is on.
local debugOn = false
R.stats = { events = {}, timings = {}, messages = {} }
local statEvents, statTimings = R.stats.events, R.stats.timings

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventHandlers[event]
	if not list then return end
	if debugOn then statEvents[event] = (statEvents[event] or 0) + 1 end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

-- Registers fn for event. Unknown events (not present in this client) are ignored.
function R:RegisterEvent(event, fn)
	local list = eventHandlers[event]
	local new = {}
	if list then
		for i = 1, #list do new[i] = list[i] end
	else
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then return false end
	end
	new[#new + 1] = fn
	eventHandlers[event] = new
	return true
end

-- Removes fn from event; unregisters the event from the client when no handlers remain.
function R:UnregisterEvent(event, fn)
	local list = eventHandlers[event]
	if not list then return end
	local new = {}
	for i = 1, #list do
		if list[i] ~= fn then new[#new + 1] = list[i] end
	end
	if #new == 0 then
		eventHandlers[event] = nil
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	else
		eventHandlers[event] = new
	end
end

-- Registers a handler that runs once and then unregisters itself (startup events).
function R:RegisterEventOnce(event, fn)
	local wrapper
	wrapper = function(...)
		R:UnregisterEvent(event, wrapper)
		fn(...)
	end
	return R:RegisterEvent(event, wrapper)
end

function R:IsDebug() return debugOn end
function R:SetDebug(on)
	debugOn = on and true or false
	if debugOn then
		wipe(statEvents); wipe(statTimings); wipe(R.stats.messages)
	end
end

-- Profiling: t0 = R:ProfileStart() ... R:ProfileEnd("name", t0). Free when debug is off.
function R:ProfileStart()
	if debugOn and debugprofilestop then return debugprofilestop() end
end
function R:ProfileEnd(name, t0)
	if not t0 then return end
	local ms = debugprofilestop() - t0
	local t = statTimings[name]
	if not t then t = { n = 0, total = 0, max = 0 }; statTimings[name] = t end
	t.n = t.n + 1
	t.total = t.total + ms
	if ms > t.max then t.max = ms end
end

---------------------------------------------------------------------------
-- Internal messages
---------------------------------------------------------------------------
local listeners = {}

function R:Listen(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end

function R:Fire(msg, ...)
	local list = listeners[msg]
	if not list then return end
	if debugOn then local m = R.stats.messages; m[msg] = (m[msg] or 0) + 1 end
	for i = 1, #list do
		list[i](msg, ...)
	end
end

---------------------------------------------------------------------------
-- Next-frame job scheduler (coalesces repeated requests by key)
---------------------------------------------------------------------------
local pending = {}
local scheduler = CreateFrame("Frame")
scheduler:Hide()
scheduler:SetScript("OnUpdate", function(self)
	self:Hide()
	local jobs = pending
	pending = {}
	for _, fn in pairs(jobs) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end)

function R:Defer(key, fn)
	pending[key] = fn
	scheduler:Show()
end

-- Coalesced, rate-limited window refresh (max ~12/s even during loot/bag-update storms).
local lastRefresh, refreshQueued = 0, false
local function DoRefresh()
	refreshQueued = false
	lastRefresh = GetTime()
	if R.UI and R.UI.Refresh then
		local t0 = R:ProfileStart()
		R.UI:Refresh()
		R:ProfileEnd("UI:Refresh", t0)
	end
end
function R:RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	local wait = 0.08 - (GetTime() - lastRefresh)
	if wait > 0 and C_Timer then
		C_Timer.After(wait, function() R:Defer("refresh", DoRefresh) end)
	else
		R:Defer("refresh", DoRefresh)
	end
end

BINDING_HEADER_RUMMAGE = "Rummage"
BINDING_NAME_RUMMAGE_TOGGLE = "Toggle bags"
BINDING_NAME_RUMMAGE_TOGGLE_BANK = "Toggle bank (cached or live)"
BINDING_NAME_RUMMAGE_SEARCH = "Open bags and focus search"

---------------------------------------------------------------------------
-- Localization scaffolding: enUS strings live here; a translation file can set
-- RummageLocales["deDE"] = { key = "...", ... } before this file loads. Chrome
-- strings (tabs, buttons, footer, minimap, options tabs) route through R.L;
-- longer option labels migrate incrementally.
---------------------------------------------------------------------------
R.L = {
	bags = "Bags", bank = "Bank", toGrid = "Grid", toList = "List",
	transfer = "Transfer", toBags = "To Bags", toBank = "To Bank",
	sort = "Sort", restack = "Restack", sellJunk = "Sell Junk",
	freeFmt = "%d/%d free", cachedBank = "Cached bank",
	viewTotal = "View", junkTotal = "junk",
	searchHint = "Search  (e.g. ilvl>20 #boe | q:epic)",
	emptyBank = "No bank data yet. Visit a banker on this character.",
	nothingMatches = "Nothing matches.", empty = "Empty.",
	mmFree = "%d / %d bag slots free",
	mmBags = "Left-click: bags", mmBank = "Shift/middle-click: bank", mmSettings = "Right-click: settings",
	tabGeneral = "General", tabAppearance = "Appearance", tabItems = "Items & Junk",
	tabColumns = "Columns", tabCategories = "Categories", tabAbout = "About",
	preset = "Preset",
	slashUsage = "/rum [bank | search <text> | config | restack | sell | conflicts | keys | reset | upgrade (preview popup) | export | import <string> | debug [report|reset]]",
}
do
	local loc = (GetLocale and GetLocale()) or "enUS"
	local pack = _G.RummageLocales and _G.RummageLocales[loc]
	if type(pack) == "table" then
		for k, v in pairs(pack) do if type(v) == "string" then R.L[k] = v end end
	end
end

local function DeepCopy(src)
	if type(src) ~= "table" then return src end
	local t = {}
	for k, v in pairs(src) do t[k] = DeepCopy(v) end
	return t
end
R.DeepCopy = DeepCopy

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function R:Print(...)
	local msg = string.join(" ", tostringall(...))
	DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441Rummage|r: " .. msg)
end

function R.ItemID(link)
	if type(link) == "number" then return link end
	return link and tonumber(link:match("item:(%-?%d+)"))
end

local GOLD, SILVER, COPPER = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"

-- Formats copper as "12g 34s 5c". short=true drops copper once gold is present.
-- Allocation-light: builds the string directly instead of via a temporary table;
-- results for the (very common) short form are memoized.
local moneyCache, moneyCacheSize = {}, 0
function R.FormatMoney(copper, short)
	copper = floor(tonumber(copper) or 0)
	if copper <= 0 then return "" end
	if short then
		local hit = moneyCache[copper]
		if hit then return hit end
	end
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	local out = ""
	if g > 0 then out = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. GOLD end
	if s > 0 and not (short and g >= 1000) then out = (out ~= "" and (out .. " ") or out) .. s .. SILVER end
	if c > 0 and not (short and g > 0) then out = (out ~= "" and (out .. " ") or out) .. c .. COPPER end
	if short then
		if moneyCacheSize > 2000 then wipe(moneyCache); moneyCacheSize = 0 end
		moneyCache[copper] = out
		moneyCacheSize = moneyCacheSize + 1
	end
	return out
end

-- Parses "1g20s5c", "50s", "3" (plain number = gold) into copper.
function R.ParseMoney(str)
	if not str or str == "" then return nil end
	str = str:lower():gsub("%s", "")
	local plain = tonumber(str)
	if plain then return plain * 10000 end
	local total, found = 0, false
	for num, unit in str:gmatch("([%d%.]+)([gsc])") do
		num = tonumber(num)
		if num then
			found = true
			if unit == "g" then total = total + num * 10000
			elseif unit == "s" then total = total + num * 100
			else total = total + num end
		end
	end
	return found and floor(total) or nil
end

-- "3m", "5h", "2d" style age.
function R.FormatAge(ts)
	if not ts or ts <= 0 then return "" end
	local d = time() - ts
	if d < 60 then return "now" end
	if d < 3600 then return floor(d / 60) .. "m" end
	if d < 86400 then return floor(d / 3600) .. "h" end
	if d < 86400 * 60 then return floor(d / 86400) .. "d" end
	return floor(d / (86400 * 30)) .. "mo"
end

function R.ClassColor(class)
	local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
	if c then return c.r, c.g, c.b end
	return 0.9, 0.9, 0.9
end

function R.ClassColorText(class, text)
	local r, g, b = R.ClassColor(class)
	return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function R.QualityColor(q)
	q = q or 1
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b, c.hex or "|cffffffff" end
	return 1, 1, 1, "|cffffffff"
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
R.defaults = {
	scale = 1,
	alpha = 0.97,
	fontSize = 12,
	font = "",              -- "" = theme font; otherwise a LibSharedMedia/built-in font name
	rowHeight = 22,
	skin = "Auto",          -- Auto picks the theme of a detected UI suite, else Forever
	classAccent = false,
	locked = false,
	takeoverKeybinds = true,
	takeoverBagKeys = true,
	warnConflicts = true,
	ignoredConflicts = "",
	autoOpen = { merchant = true, mail = true, auction = true, trade = true, bank = true, other = true },
	rememberCategory = true, -- restore the last selected category (also across sessions)
	lastCategory = "all",
	searchAllChars = false,  -- while searching, look through every character's cached bags
	profilePerChar = false,  -- re-apply each character's own profile at login
	upgradePopup = true,
	upgradeDuration = 20,   -- seconds; 0 = stay until dismissed
	upgradeSound = true,
	upgradeIlvlFallback = true, -- without Pawn, judge upgrades by item level
	resetSearchOnOpen = true,
	lowSpaceWarn = 3,
	tintUnusable = true,
	gridItemLevel = true,
	questBadges = true,
	hideEmptyCategories = false,
	protectFavorites = true,
	buybackSafe = false,
	autoRepair = false,
	autoRepairGuild = true,
	minimap = { show = true, angle = 200 },
	width = 680,
	height = 520,
	point = nil,
	viewMode = "list",      -- list | grid
	gridSize = 38,
	combineStacks = true,
	groupBy = "none",       -- none | category | type | quality | bag
	sortKey = "quality",
	sortAsc = false,
	favoritesFirst = true,
	newFirst = false,
	showSidebar = true,
	compactSidebar = false,
	replaceBags = true,
	replaceBank = true,
	tooltipCounts = true,
	tooltipWithSyndicator = false,
	tooltipRealmOnly = false,
	clearNewOnClose = true,
	autoSellJunk = false,
	useScrap = true,
	stackValue = true,
	tsmSource = "DBMarket",
	columns = { order = {}, hidden = {}, widths = {} },
	collapsed = {},
}

---------------------------------------------------------------------------
-- SavedVariables sanitizing. The WTF file is user-editable and may come from an
-- older or corrupted version, so every value is type-checked, clamped or dropped.
---------------------------------------------------------------------------
local DB_VERSION = 3

-- Fills missing keys and replaces values whose type differs from the default.
local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		local cur = dst[k]
		if type(v) == "table" then
			if type(cur) ~= "table" then cur = {}; dst[k] = cur end
			CopyDefaults(v, cur)
		elseif cur == nil or type(cur) ~= type(v) then
			dst[k] = v
		end
	end
end

local CLAMP = {
	scale = { 0.5, 2 }, alpha = { 0.1, 1 }, fontSize = { 6, 24 }, rowHeight = { 14, 40 },
	gridSize = { 20, 64 }, width = { 400, 3000 }, height = { 300, 2000 }, lowSpaceWarn = { 0, 40 },
	upgradeDuration = { 0, 120 },
}
local ENUMS = {
	viewMode = { list = true, grid = true },
	groupBy = { none = true, category = true, type = true, quality = true, bag = true },
}

local function ValidPoint(p)
	return type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
		and type(p[3]) == "number" and type(p[4]) == "number"
end

local function SanitizeSettings(st)
	-- migration (1.1 -> 1.2): "reset category on open" became "remember category"
	if st.resetCategoryOnOpen ~= nil then
		if st.rememberCategory == nil then st.rememberCategory = not st.resetCategoryOnOpen end
		st.resetCategoryOnOpen = nil
	end
	CopyDefaults(R.defaults, st)
	if st.upgradePoint ~= nil and not ValidPoint(st.upgradePoint) then st.upgradePoint = nil end
	for k, r in pairs(CLAMP) do st[k] = min(r[2], max(r[1], st[k])) end
	for k, set in pairs(ENUMS) do
		if not set[st[k]] then st[k] = R.defaults[k] end
	end
	local p = st.point
	if p ~= nil and not (type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
		and type(p[3]) == "number" and type(p[4]) == "number") then
		st.point = nil
	end
	local cols = st.columns
	local seen, order = {}, {}
	for _, key in ipairs(cols.order) do
		if type(key) == "string" and not seen[key] then seen[key] = true; order[#order + 1] = key end
	end
	cols.order = order
	for k, v in pairs(cols.hidden) do if type(k) ~= "string" or v ~= true then cols.hidden[k] = nil end end
	for k, v in pairs(cols.widths) do
		if type(k) ~= "string" or type(v) ~= "number" then cols.widths[k] = nil
		else cols.widths[k] = min(600, max(16, v)) end
	end
	for k, v in pairs(st.collapsed) do if v ~= true then st.collapsed[k] = nil end end
end

local function ValidSlot(s)
	return type(s) == "table" and type(s.l) == "string" and type(s.c) == "number"
end

local function SanitizeChar(c)
	if type(c) ~= "table" then return false end
	if type(c.containers) ~= "table" then c.containers = {} end
	for bag, rec in pairs(c.containers) do
		if type(bag) ~= "number" or type(rec) ~= "table" or type(rec.slots) ~= "table" then
			c.containers[bag] = nil
		else
			rec.size = type(rec.size) == "number" and rec.size or 0
			for slot, sl in pairs(rec.slots) do
				if type(slot) ~= "number" or not ValidSlot(sl) then rec.slots[slot] = nil
				elseif type(sl.i) ~= "number" then sl.i = R.ItemID(sl.l) end
			end
		end
	end
	if type(c.equipped) ~= "table" then c.equipped = {} end
	for k, sl in pairs(c.equipped) do if not ValidSlot(sl) then c.equipped[k] = nil end end
	if type(c.mail) ~= "table" then c.mail = {} end
	local mail = {}
	for _, sl in ipairs(c.mail) do if ValidSlot(sl) then mail[#mail + 1] = sl end end
	c.mail = mail
	if type(c.acquired) ~= "table" then c.acquired = {} end
	if type(c.money) ~= "number" then c.money = 0 end
	return true
end

function R:InitDB()
	if type(RummageDB) ~= "table" then RummageDB = {} end
	local db = RummageDB
	if type(db.settings) ~= "table" then db.settings = {} end
	SanitizeSettings(db.settings)
	if type(db.chars) ~= "table" then db.chars = {} end
	for key, c in pairs(db.chars) do
		if type(key) ~= "string" or not SanitizeChar(c) then db.chars[key] = nil end
	end
	if type(db.favorites) ~= "table" then db.favorites = {} end   -- [itemID] = marker 1-8
	for id, v in pairs(db.favorites) do
		if type(id) ~= "number" or type(v) ~= "number" or v < 1 or v > 8 then db.favorites[id] = nil
		else db.favorites[id] = floor(v) end
	end
	if type(db.upgradeIgnore) ~= "table" then db.upgradeIgnore = {} end -- [itemID] = true
	for id, v in pairs(db.upgradeIgnore) do
		if type(id) ~= "number" or v ~= true then db.upgradeIgnore[id] = nil end
	end
	if type(db.junk) ~= "table" then db.junk = {} end             -- [itemID] = true/false override
	for id, v in pairs(db.junk) do
		if type(id) ~= "number" or type(v) ~= "boolean" then db.junk[id] = nil end
	end
	if type(db.categories) ~= "table" then db.categories = {} end -- { name=, query=, icon= }
	local cats = {}
	for _, c in ipairs(db.categories) do
		if type(c) == "table" and type(c.name) == "string" then
			if type(c.query) ~= "string" then c.query = "" end
			if c.icon ~= nil and type(c.icon) ~= "string" and type(c.icon) ~= "number" then c.icon = nil end
			cats[#cats + 1] = c
		end
	end
	db.categories = cats
	-- 1.3.0 additions: profiles, per-character profiles, search history,
	-- auto-junk rules (search queries) and sort presets.
	if type(db.profiles) ~= "table" then db.profiles = {} end
	for k, v in pairs(db.profiles) do
		if type(k) ~= "string" or type(v) ~= "table" then db.profiles[k] = nil end
	end
	if type(db.charProfiles) ~= "table" then db.charProfiles = {} end
	for k, v in pairs(db.charProfiles) do
		if type(k) ~= "string" or type(v) ~= "string" then db.charProfiles[k] = nil end
	end
	if type(db.profileName) ~= "string" then db.profileName = nil end
	if type(db.searchHistory) ~= "table" then db.searchHistory = {} end
	local hist = {}
	for _, q in ipairs(db.searchHistory) do
		if type(q) == "string" and q ~= "" and #hist < 10 then hist[#hist + 1] = q end
	end
	db.searchHistory = hist
	if type(db.junkRules) ~= "table" then db.junkRules = {} end
	local rules = {}
	for _, q in ipairs(db.junkRules) do
		if type(q) == "string" and q ~= "" and #rules < 8 then rules[#rules + 1] = q end
	end
	db.junkRules = rules
	if type(db.sortPresets) ~= "table" then db.sortPresets = {} end
	local presets = {}
	for _, pr in ipairs(db.sortPresets) do
		if type(pr) == "table" and type(pr.name) == "string" and type(pr.sortKey) == "string" then
			pr.sortAsc = pr.sortAsc and true or false
			if pr.groupBy ~= "category" and pr.groupBy ~= "type" and pr.groupBy ~= "quality" and pr.groupBy ~= "bag" then pr.groupBy = "none" end
			if pr.viewMode ~= "grid" then pr.viewMode = "list" end
			pr.favoritesFirst = pr.favoritesFirst and true or false
			pr.newFirst = pr.newFirst and true or false
			presets[#presets + 1] = pr
		end
	end
	db.sortPresets = presets
	db.version = DB_VERSION
	R.db = db
	R.settings = db.settings
	R.charKey = UnitName("player") .. "-" .. GetRealmName()
	-- Per-character profile: re-apply this character's profile (silent; the UI
	-- doesn't exist yet at ADDON_LOADED time, so ApplyProfile just sets state).
	if db.settings.profilePerChar then
		local pn = db.charProfiles[R.charKey]
		if pn and db.profiles[pn] and pn ~= db.profileName then
			R:ApplyProfile(pn, true)
		end
	end
end

function R:ResetSettings()
	wipe(R.db.settings)
	SanitizeSettings(R.db.settings)
end

---------------------------------------------------------------------------
-- Profiles: named snapshots of the whole settings table.
---------------------------------------------------------------------------
function R:SaveProfile(name)
	if type(name) ~= "string" or name == "" then return false end
	R.db.profiles[name] = DeepCopy(R.settings)
	R.db.profileName = name
	return true
end

function R:DeleteProfile(name)
	if not R.db.profiles[name] then return end
	R.db.profiles[name] = nil
	for k, v in pairs(R.db.charProfiles) do
		if v == name then R.db.charProfiles[k] = nil end
	end
	if R.db.profileName == name then R.db.profileName = nil end
end

function R:ApplyProfile(name, silent)
	local snap = R.db.profiles[name]
	if not snap then return false end
	local copy = DeepCopy(snap)
	wipe(R.settings)
	for k, v in pairs(copy) do R.settings[k] = v end
	SanitizeSettings(R.settings)
	R.db.profileName = name
	if R.settings.profilePerChar and R.charKey then
		R.db.charProfiles[R.charKey] = name
	end
	if not silent then R:Print("Profile '" .. name .. "' applied.") end
	-- Refresh any surfaces that already exist (none do at ADDON_LOADED time).
	if R.Minimap and R.Minimap.Update then pcall(R.Minimap.Update, R.Minimap) end
	if R.Options and R.Options.Rebuild then pcall(R.Options.Rebuild, R.Options) end
	if R.UI and R.UI.frame then R.UI:ApplyPosition(); R.UI:ApplySkin() end
	R:RequestRefresh()
	return true
end

---------------------------------------------------------------------------
-- Settings export / import: flat "RUM1;path=value;..." text, no code.
-- Covers settings (incl. column order/widths/hidden), custom categories and
-- auto-junk rules. Favorites, junk marks and character caches stay local.
---------------------------------------------------------------------------
local function Esc(s)
	return (tostring(s):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D")
		:gsub("\n", "%%0A"):gsub("\r", "%%0D"))
end
local function Unesc(s)
	return (s:gsub("%%3B", ";"):gsub("%%3D", "="):gsub("%%0A", "\n")
		:gsub("%%0D", "\r"):gsub("%%25", "%%"))
end

local function FlattenInto(out, prefix, defaultsNode, settingsNode)
	for k, dv in pairs(defaultsNode) do
		if not (prefix == "" and k == "lastCategory") then
			local sv = settingsNode and settingsNode[k]
			local path = prefix == "" and k or (prefix .. "." .. k)
			if type(dv) == "table" then
				-- columns.order/hidden/widths and other open maps are emitted by the caller
				if prefix ~= "columns" then FlattenInto(out, path, dv, sv) end
			elseif sv ~= nil and type(sv) == type(dv) then
				if type(dv) == "boolean" then out[#out + 1] = path .. "=" .. (sv and "1" or "0")
				elseif type(dv) == "number" then out[#out + 1] = path .. "=" .. tostring(sv)
				elseif type(dv) == "string" then out[#out + 1] = path .. "=" .. Esc(sv) end
			end
		end
	end
end

function R:ExportSettings()
	local out = { "RUM1" }
	FlattenInto(out, "", R.defaults, R.settings)
	local cols = R.settings.columns
	if cols then
		out[#out + 1] = "columns.order=" .. concat(cols.order or {}, ",")
		for k, v in pairs(cols.hidden or {}) do
			if v then out[#out + 1] = "columns.hidden." .. k .. "=1" end
		end
		for k, v in pairs(cols.widths or {}) do
			out[#out + 1] = "columns.widths." .. k .. "=" .. tostring(v)
		end
	end
	for i, def in ipairs(R.db.categories) do
		out[#out + 1] = "cat" .. i .. ".name=" .. Esc(def.name or "")
		out[#out + 1] = "cat" .. i .. ".query=" .. Esc(def.query or "")
		if def.icon ~= nil then out[#out + 1] = "cat" .. i .. ".icon=" .. Esc(def.icon) end
	end
	for i, q in ipairs(R.db.junkRules) do
		out[#out + 1] = "rule" .. i .. "=" .. Esc(q)
	end
	return concat(out, ";")
end

-- Resolves a dotted path against the defaults shape; returns the leaf's
-- default value (whose type drives coercion) or nil for unknown paths.
local function DefaultsLeaf(path)
	local node = R.defaults
	for seg in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil end
		node = node[seg]
		if node == nil then return nil end
	end
	return node
end

local function SetPath(tbl, path, value)
	local parts = {}
	for seg in path:gmatch("[^%.]+") do parts[#parts + 1] = seg end
	local node = tbl
	for i = 1, #parts - 1 do
		if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
		node = node[parts[i]]
	end
	node[parts[#parts]] = value
end

function R:ImportSettings(str)
	if type(str) ~= "string" then return false, "not text" end
	str = str:match("^%s*(.-)%s*$")
	if str:sub(1, 5) ~= "RUM1;" then return false, "not a Rummage settings string" end
	local vals = {}
	for pair in str:gmatch("[^;]+") do
		local k, v = pair:match("^([^=]+)=(.*)$")
		if k then vals[k] = v end
	end

	local newSettings = DeepCopy(R.settings)
	local catFields, ruleVals = {}, {}
	for path, raw in pairs(vals) do
		local catIdx, catKey = path:match("^cat(%d+)%.(%a+)$")
		local ruleIdx = path:match("^rule(%d+)$")
		if catIdx then
			catIdx = tonumber(catIdx)
			if catKey == "name" or catKey == "query" or catKey == "icon" then
				catFields[catIdx] = catFields[catIdx] or {}
				catFields[catIdx][catKey] = Unesc(raw)
			end
		elseif ruleIdx then
			ruleVals[tonumber(ruleIdx)] = Unesc(raw)
		elseif path == "columns.order" then
			local order = {}
			for key in raw:gmatch("[^,]+") do order[#order + 1] = key end
			SetPath(newSettings, path, order)
		elseif path:match("^columns%.hidden%.") then
			SetPath(newSettings, path, raw == "1")
		elseif path:match("^columns%.widths%.") then
			local n = tonumber(raw)
			if n then SetPath(newSettings, path, n) end
		else
			local leaf = DefaultsLeaf(path)
			if type(leaf) == "boolean" then
				if raw ~= "0" and raw ~= "1" then return false, "bad value for " .. path end
				SetPath(newSettings, path, raw == "1")
			elseif type(leaf) == "number" then
				local n = tonumber(raw)
				if not n then return false, "bad value for " .. path end
				SetPath(newSettings, path, n)
			elseif type(leaf) == "string" then
				SetPath(newSettings, path, Unesc(raw))
			end
			-- unknown paths are ignored (forward compatibility)
		end
	end
	SanitizeSettings(newSettings)

	local newCats = {}
	for i = 1, 50 do
		local f = catFields[i]
		if not f then break end
		if f.name and f.name ~= "" then
			local icon = f.icon
			if icon and tonumber(icon) then icon = tonumber(icon) end
			newCats[#newCats + 1] = { name = f.name, query = f.query or "", icon = icon }
		end
	end
	local hasCats = false
	for _ in pairs(catFields) do hasCats = true; break end
	local newRules = {}
	for i = 1, 8 do
		if ruleVals[i] and ruleVals[i] ~= "" then newRules[#newRules + 1] = ruleVals[i] end
	end

	wipe(R.settings)
	for k, v in pairs(newSettings) do R.settings[k] = v end
	if hasCats then R.db.categories = newCats end
	if next(ruleVals) then R.db.junkRules = newRules end
	R.db.profileName = nil
	if R.Minimap and R.Minimap.Update then pcall(R.Minimap.Update, R.Minimap) end
	if R.Options and R.Options.Rebuild then pcall(R.Options.Rebuild, R.Options) end
	if R.UI and R.UI.frame then R.UI:ApplyPosition(); R.UI:ApplySkin() end
	R:RequestRefresh()
	return true
end
