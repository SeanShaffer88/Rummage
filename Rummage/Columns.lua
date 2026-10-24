-- Rummage: table columns registry.
-- A column: { key, title, width, align, kind = "text"|"icon"|"fav"|"junk", flex,
--             value(e) -> sortable, text(e, value) -> string, available() -> bool, hidden = default-hidden }
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local Columns = {}
R.Columns = Columns
Columns.list = {}
Columns.byKey = {}

function Columns:Register(def)
	if self.byKey[def.key] then return end
	def.align = def.align or "LEFT"
	def.kind = def.kind or "text"
	self.byKey[def.key] = def
	self.list[#self.list + 1] = def
	local cfg = R.settings.columns
	local found = false
	for _, k in ipairs(cfg.order) do
		if k == def.key then found = true; break end
	end
	if not found then
		table.insert(cfg.order, def.key)
		if def.hidden and cfg.hidden[def.key] == nil then cfg.hidden[def.key] = true end
	end
end

function Columns:ValueOf(key, e)
	local col = self.byKey[key]
	if not col or (col.available and not col.available()) then return nil end
	local vals = e.vals
	if vals then
		local v = vals[key]
		if v ~= nil then return v ~= false and v or nil end
	end
	local v = col.value(e)
	if vals then vals[key] = (v == nil) and false or v end
	return v
end

function Columns:Width(col)
	return R.settings.columns.widths[col.key] or col.width
end

-- Visible columns in configured order.
function Columns:Visible()
	local out = {}
	local cfg = R.settings.columns
	for _, key in ipairs(cfg.order) do
		local col = self.byKey[key]
		if col and not cfg.hidden[key] and (not col.available or col.available()) then
			out[#out + 1] = col
		end
	end
	return out
end

function Columns:Move(key, delta)
	local order = R.settings.columns.order
	for i, k in ipairs(order) do
		if k == key then
			local j = i + delta
			if j >= 1 and j <= #order then
				order[i], order[j] = order[j], order[i]
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Built-in columns
---------------------------------------------------------------------------
local function info(e, k, default)
	local i = e.info
	if i and i[k] ~= nil then return i[k] end
	return default
end

function Columns:RegisterBuiltins()
	self:Register({ key = "fav", title = "", headerIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
		width = 22, kind = "fav", align = "CENTER", label = "Favorite",
		value = function(e) return e.fav and (9 - e.fav) or 0 end })

	self:Register({ key = "icon", title = "", width = 24, kind = "icon", label = "Icon", fixed = true,
		value = function(e) return e.quality end })

	self:Register({ key = "name", title = "Name", width = 200, flex = true, label = "Name",
		value = function(e) return e.lname end,
		text = function(e)
			local _, _, _, hex = R.QualityColor(e.quality)
			local s = hex .. e.name .. "|r"
			if e.new then s = s .. " |cff40ff40new|r" end
			return s
		end })

	self:Register({ key = "count", title = "Qty", width = 40, align = "RIGHT", label = "Quantity",
		value = function(e) return e.count end,
		text = function(e) return e.count > 1 and tostring(e.count) or "" end })

	self:Register({ key = "ilvl", title = "iLvl", width = 38, align = "RIGHT", label = "Item level",
		value = function(e) return info(e, "ilvl", 0) end,
		text = function(e, v)
			if not e.info or not (e.info.equippable or e.info.class == 2 or e.info.class == 4) then return "" end
			return v > 0 and tostring(v) or ""
		end })

	self:Register({ key = "req", title = "Req", width = 34, align = "RIGHT", label = "Required level",
		value = function(e) return info(e, "req", 0) end,
		text = function(e, v)
			if v <= 1 then return "" end
			if v > UnitLevel("player") then return "|cffff5050" .. v .. "|r" end
			return tostring(v)
		end })

	self:Register({ key = "type", title = "Type", width = 90, label = "Type",
		value = function(e) return info(e, "type", "") end })

	self:Register({ key = "sub", title = "Subtype", width = 90, label = "Subtype", hidden = true,
		value = function(e) return info(e, "sub", "") end })

	self:Register({ key = "slot", title = "Slot", width = 80, label = "Equip slot", hidden = true,
		value = function(e) return info(e, "slotName", "") end })

	self:Register({ key = "bind", title = "Bind", width = 46, label = "Binding", hidden = true,
		value = function(e) return e.bound and 5 or info(e, "bindType", 0) end,
		text = function(e) return R.Items:BindText(e) end })

	self:Register({ key = "value", title = "Vendor", width = 86, align = "RIGHT", label = "Vendor value",
		value = function(e)
			local p = info(e, "sell", 0)
			if R.settings.stackValue then p = p * e.count end
			return p
		end,
		text = function(_, v) return R.FormatMoney(v, true) end })

	self:Register({ key = "age", title = "Age", width = 42, align = "RIGHT", label = "Time since acquired",
		value = function(e) return e.acquired or 0 end,
		text = function(e) return R.FormatAge(e.acquired) end })

	self:Register({ key = "location", title = "Bag", width = 40, align = "CENTER", label = "Location", hidden = true,
		value = function(e) return e.bag end,
		text = function(e) return API.BagShort(e.bag) end })

	self:Register({ key = "junk", title = "", headerIcon = "Interface\\Icons\\INV_Misc_Coin_02", width = 22,
		kind = "junk", align = "CENTER", label = "Junk",
		value = function(e) return e.junk and 1 or 0 end })

	self:Register({ key = "owner", title = "Owner", width = 90, label = "Owner (cross-character search)", hidden = true,
		value = function(e) return e.owner or "" end })
end

-- Comparator for the given column key. Memoized on its inputs so a refresh does not
-- allocate a new closure each time.
local cmpKey, cmpAsc, cmpFav, cmpNew, cmpFn
function Columns:Comparator(key, asc)
	local favFirst = R.settings.favoritesFirst
	local newFirst = R.settings.newFirst
	if cmpFn and cmpKey == key and cmpAsc == asc and cmpFav == favFirst and cmpNew == newFirst then
		return cmpFn
	end
	cmpKey, cmpAsc, cmpFav, cmpNew = key, asc, favFirst, newFirst
	cmpFn = function(a, b)
		if favFirst and (a.fav ~= nil) ~= (b.fav ~= nil) then return a.fav ~= nil end
		if newFirst and (a.new and true or false) ~= (b.new and true or false) then return a.new and true or false end
		local va, vb = Columns:ValueOf(key, a), Columns:ValueOf(key, b)
		if va ~= vb then
			if va == nil then return false end
			if vb == nil then return true end
			local ta, tb = type(va), type(vb)
			if ta ~= tb then va, vb = tostring(va), tostring(vb) end
			if asc then return va < vb else return va > vb end
		end
		if a.quality ~= b.quality then return a.quality > b.quality end
		if a.lname ~= b.lname then return a.lname < b.lname end
		if a.count ~= b.count then return a.count > b.count end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end
	return cmpFn
end
