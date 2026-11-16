-- Rummage: built-in and custom categories.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

local Categories = {}
R.Categories = Categories

local I = "Interface\\Icons\\"
local function cls(e) return e.info and e.info.class end

Categories.builtin = {
	{ id = "all", name = "All Items", icon = I .. "INV_Misc_Bag_07", filter = function() return true end },
	{ id = "fav", name = "Favorites", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
		filter = function(e) return e.fav ~= nil end },
	{ id = "new", name = "New", icon = I .. "INV_Misc_Gift_01", filter = function(e) return e.new and true or false end },
	{ id = "equip", name = "Equipment", icon = I .. "INV_Chest_Chain_05",
		filter = function(e) local c = cls(e); return c == 2 or c == 4 end },
	{ id = "consumable", name = "Consumables", icon = I .. "INV_Potion_51", filter = function(e) return cls(e) == 0 end },
	{ id = "trade", name = "Trade Goods", icon = I .. "INV_Fabric_Linen_01",
		filter = function(e) local c = cls(e); return c == 7 or c == 5 or c == 3 or c == 8 end },
	{ id = "recipe", name = "Recipes", icon = I .. "INV_Scroll_03", filter = function(e) return cls(e) == 9 end },
	{ id = "quest", name = "Quest Items", icon = I .. "INV_Misc_Note_02",
		filter = function(e) return cls(e) == 12 or (e.info and e.info.bindType == 4) end },
	{ id = "containers", name = "Bags & Ammo", icon = I .. "INV_Misc_Bag_10",
		filter = function(e) local c = cls(e); return c == 1 or c == 6 or c == 11 end },
	{ id = "keys", name = "Keys", icon = I .. "INV_Misc_Key_03", filter = function(e) return R.Items:IsKey(e) end },
	{ id = "misc", name = "Miscellaneous", icon = I .. "INV_Misc_QuestionMark",
		filter = function(e)
			local c = cls(e)
			return c == nil or c == 15 or c == 10 or c == 14 or c == 16
		end },
	{ id = "junk", name = "Junk", icon = I .. "INV_Misc_Coin_02", filter = function(e) return e.junk end },
}

-- Order used when grouping by category (first match wins; skips all/fav/new).
Categories.groupOrder = { "junk", "quest", "equip", "consumable", "trade", "recipe", "containers", "keys", "misc" }

local byId = {}
for i, c in ipairs(Categories.builtin) do
	c.order = i
	byId[c.id] = c
end

-- Custom category objects are cached per saved definition table (weak keys), and the
-- list array is reused, so building the sidebar list allocates nothing per refresh.
local customObjs = setmetatable({}, { __mode = "k" })
local DEFAULT_CUSTOM_ICON = I .. "INV_Misc_Note_01"
local customIds = {}
local listCache = {}

local function CustomObject(def, i)
	local o = customObjs[def]
	if not o then
		local Search = R.Search
		-- items added by dragging (1.10.0) always belong; a category with only added
		-- items and no filter holds just those (an empty filter otherwise matches all)
		o = { filter = function(e)
			local items = def.items
			if items then
				if e.id and items[e.id] then return true end
				if def.query == "" and next(items) then return false end
			end
			return Search:Matches(def.query, e)
		end }
		customObjs[def] = o
	end
	local id = customIds[i]
	if not id then id = "custom" .. i; customIds[i] = id end
	o.id, o.name, o.custom = id, def.name, i
	o.icon = def.icon or DEFAULT_CUSTOM_ICON
	return o
end

-- Plugin categories (1.9.0): Rummage:RegisterCategory(id, name, icon, filter)
-- adds a sidebar entry after the built-ins. ids are namespaced "plugin:<id>".
local plugins, pluginById = {}, {}
Categories.plugins = plugins

function Categories:RegisterPlugin(id, name, icon, filter)
	if type(id) ~= "string" or id == "" or type(name) ~= "string" or type(filter) ~= "function" then return nil end
	local key = "plugin:" .. id
	local o = pluginById[key]
	if not o then
		o = { id = key, plugin = true }
		pluginById[key] = o
		plugins[#plugins + 1] = o
	end
	o.name, o.icon = name, icon or DEFAULT_CUSTOM_ICON
	o.filter = function(e)
		local ok, res = pcall(filter, e)
		return ok and res and true or false
	end
	R:RequestRefresh()
	return key
end

function Categories:UnregisterPlugin(id)
	local key = "plugin:" .. tostring(id)
	if not pluginById[key] then return end
	pluginById[key] = nil
	for i = #plugins, 1, -1 do if plugins[i].id == key then table.remove(plugins, i) end end
	R:RequestRefresh()
end

function Categories:Get(id)
	if byId[id] then return byId[id] end
	if pluginById[id] then return pluginById[id] end
	local idx = type(id) == "string" and tonumber(id:match("^custom(%d+)$"))
	local def = idx and R.db.categories[idx]
	if def then return CustomObject(def, idx) end
end

-- Full list for the sidebar: built-ins then customs. Valid until the next call.
function Categories:List()
	local list = wipe(listCache)
	local builtin = self.builtin
	for i = 1, #builtin do list[i] = builtin[i] end
	for i = 1, #plugins do list[#list + 1] = plugins[i] end
	local defs = R.db.categories
	for i = 1, #defs do list[#list + 1] = CustomObject(defs[i], i) end
	return list
end

function Categories:GroupOf(e)
	for i, id in ipairs(self.groupOrder) do
		if byId[id].filter(e) then return id, i, byId[id].name end
	end
	return "misc", #self.groupOrder, byId.misc.name
end

function Categories:AddCustom(name, query, icon, itemID)
	table.insert(R.db.categories, { name = name, query = query or "", icon = icon })
	local idx = #R.db.categories
	if itemID then self:AddItem(idx, itemID) end
	return idx
end

-- Items added to a custom category by dragging (1.10.0): def.items = { [itemID] = true }.
Categories.MAX_ITEMS = 500

function Categories:ItemCount(idx)
	local def = R.db.categories[idx]
	local n = 0
	if def and def.items then for _ in pairs(def.items) do n = n + 1 end end
	return n
end

-- Returns "added", "already", "full" or nil (no such category / bad item).
function Categories:AddItem(idx, itemID)
	local def = R.db.categories[idx]
	itemID = tonumber(itemID)
	if not def or not itemID or itemID <= 0 then return nil end
	def.items = def.items or {}
	if def.items[itemID] then return "already" end
	if self:ItemCount(idx) >= self.MAX_ITEMS then return "full" end
	def.items[itemID] = true
	R:RequestRefresh()
	return "added"
end

function Categories:RemoveItem(idx, itemID)
	local def = R.db.categories[idx]
	if not (def and def.items and def.items[itemID]) then return false end
	def.items[itemID] = nil
	if not next(def.items) then def.items = nil end
	R:RequestRefresh()
	return true
end

function Categories:ClearItems(idx)
	local def = R.db.categories[idx]
	if def then def.items = nil; R:RequestRefresh() end
end

function Categories:RemoveCustom(idx)
	table.remove(R.db.categories, idx)
end

function Categories:MoveCustom(idx, delta)
	local list = R.db.categories
	local j = idx + delta
	if j < 1 or j > #list then return end
	list[idx], list[j] = list[j], list[idx]
end
