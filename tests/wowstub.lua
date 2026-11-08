-- Rummage test stub: a minimal fake WoW client for running the addon under Lua 5.1.
-- Not a game emulator. It provides just enough API for every Rummage file to load,
-- build its windows and answer slash commands, with a controllable combat flag,
-- clock, cursor, timers, bags and merchant. Copyright (C) 2026 Malikor. GPLv3 or later.
--
-- Usage: local env = WOWSTUB(opts) ; loadstring chunks with setfenv(chunk, env).

function WOWSTUB(opts)
  opts = opts or {}
  local env = { __frames = {}, __chat = {}, __timers = {}, __combat = false, __now = 1000, __cursor = 0 }
  local noop = function() end
  local UIW, UIH = 1920, 1080

  ---------------------------------------------------------------------------
  -- Generic frame / region object
  ---------------------------------------------------------------------------
  local function newObject(kind, name, parent)
    local o = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, __text = "",
      points = {}, width = 0, height = 0, scaleV = 1, events = {}, children = {}, attrs = {} }
    local m = {}
    local sized
    function m.SetScript(self, ev, fn) self.scripts[ev] = fn end
    function m.GetScript(self, ev) return self.scripts[ev] end
    function m.HasScript() return true end
    function m.HookScript(self, ev, fn)
      local old = self.scripts[ev]
      self.scripts[ev] = old and function(...) old(...); fn(...) end or fn
    end
    function m.Show(self) local was = self.shown; self.shown = true
      if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function m.Hide(self) local was = self.shown; self.shown = false
      if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function m.SetShown(self, v) if v then self:Show() else self:Hide() end end
    function m.IsShown(self) return self.shown end
    function m.IsVisible(self) return self.shown end
    function m.SetText(self, t) self.__text = t end
    function m.GetText(self) return self.__text end
    function m.SetAlpha(self, a) self.__alpha = a end
    function m.GetAlpha(self) return self.__alpha or 1 end
    function m.GetStringWidth(self) return #tostring(self.__text or "") * 6 end
    function m.GetStringHeight() return 12 end
    function m.NumLines() return 0 end
    function m.SetID(self, id) self.__id = id end
    function m.GetFrameLevel(self) return self.__level or 1 end
    function m.SetFrameLevel(self, v) self.__level = v end
    function m.GetID(self) return self.__id or 0 end
    function m.GetName(self) return self.name end
    function m.GetParent(self) return self.parent end
    function m.GetChildren(self) return unpack(self.children) end
    function m.GetRegions() return end
    function m.SetScale(self, v) self.scaleV = v end
    function m.GetScale(self) return self.scaleV end
    function m.GetEffectiveScale(self)
      local p = self.parent
      return self.scaleV * (p and p ~= self and p.GetEffectiveScale and p:GetEffectiveScale() or 1)
    end
    function m.SetSize(self, w, h) self.width, self.height = w, h; sized(self) end
    function m.SetWidth(self, w) self.width = w; sized(self) end
    function m.SetHeight(self, h) self.height = h; sized(self) end
    function m.GetWidth(self) return self.width end
    function m.GetHeight(self) return self.height end
    sized = function(self)
      local f = self.scripts.OnSizeChanged
      if f and (self.width ~= self.__lw or self.height ~= self.__lh) then
        self.__lw, self.__lh = self.width, self.height
        f(self, self.width, self.height)
      end
    end
    function m.SetPoint(self, point, rel, relPoint, x, y)
      if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, point end
      if type(rel) == "string" then rel, relPoint, x, y = nil, rel, relPoint, x end
      self.points[#self.points + 1] = { point, rel or self.parent or env.UIParent, relPoint or point, x or 0, y or 0 }
    end
    function m.ClearAllPoints(self) self.points = {} end
    function m.GetPoint(self, i)
      local p = self.points[i or 1]
      if p then return p[1], p[2], p[3], p[4], p[5] end
    end
    function m.GetNumPoints(self) return #self.points end
    -- Screen geometry (only exact for frames anchored to UIParent by one point).
    local function anchorXY(f, p)
      local w, h = f.width, f.height
      local ax, ay = 0, 0
      local pt = p[1]
      local rp = p[3]
      local rel = p[2]
      local relW, relH = (rel and rel.width) or UIW, (rel and rel.height) or UIH
      if rel == env.UIParent or rel == nil then relW, relH = UIW, UIH end
      local rx = (rp:find("RIGHT") and relW) or (rp:find("LEFT") and 0) or relW / 2
      local ry = (rp:find("TOP") and relH) or (rp:find("BOTTOM") and 0) or relH / 2
      local s = f.scaleV
      local x, y = rx / s + p[4], ry / s + p[5]
      -- convert to the frame's own scale units: x,y are offsets already in frame units
      local left = x - ((pt:find("RIGHT") and w) or (pt:find("LEFT") and 0) or w / 2)
      local top = y + ((pt:find("TOP") and 0) or (pt:find("BOTTOM") and h) or h / 2)
      return left, top
    end
    function m.GetLeft(self) local p = self.points[1]; if not p then return nil end
      local l = anchorXY(self, p); return l end
    function m.GetTop(self) local p = self.points[1]; if not p then return nil end
      local _, t = anchorXY(self, p); return t end
    function m.GetRight(self) local l = self:GetLeft(); return l and l + self.width end
    function m.GetBottom(self) local t = self:GetTop(); return t and t - self.height end
    function m.GetCenter(self) local l, t = self:GetLeft(), self:GetTop()
      if not l then return nil end return l + self.width / 2, t - self.height / 2 end
    function m.StartSizing(self, how) self.sizing = how end
    function m.StartMoving(self) self.moving = true end
    function m.StopMovingOrSizing(self) self.sizing, self.moving = nil, nil end
    function m.IsMouseOver(self) return env.__mouseOver == self end
    function m.IsProtected() return false end
    function m.RegisterEvent(self, ev) self.events[ev] = true end
    function m.UnregisterEvent(self, ev) self.events[ev] = nil end
    function m.CreateTexture(self) return newObject("Texture", nil, self) end
    function m.CreateFontString(self) local fs = newObject("FontString", nil, self); return fs end
    function m.SetChecked(self, v) self.__checked = v end
    function m.GetChecked(self) return self.__checked or false end
    function m.SetValue(self, v) self.__value = v
      if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    function m.GetValue(self) return self.__value or 0 end
    function m.HasFocus(self) return self.__focus or false end
    function m.SetFocus(self) self.__focus = true end
    function m.ClearFocus(self) self.__focus = false end
    function m.EnableKeyboard(self, v) self.keyboard = v and true or false end
    function m.SetPropagateKeyboardInput(self, v) self.propagate = v end
    function m.SetBackdrop(self, b) self.backdrop = b end
    function m.GetNormalTexture(self) self.__nt = self.__nt or newObject("Texture", nil, self); return self.__nt end
    function m.GetPushedTexture(self) self.__pt = self.__pt or newObject("Texture", nil, self); return self.__pt end
    function m.GetHighlightTexture(self) self.__ht = self.__ht or newObject("Texture", nil, self); return self.__ht end
    function m.SetTexCoord(self, ...) self.texcoord = { ... } end
    function m.SetFontObject() end
    function m.GetTextColor() return 1, 1, 1 end
    function m.IsEnabled(self) return not self.__disabled end
    function m.Disable(self) self.__disabled = true end
    function m.Enable(self) self.__disabled = false end
    function m.Click(self, btn) if self.scripts.OnClick then self.scripts.OnClick(self, btn or "LeftButton") end end
    function m.GetNumLines() return 0 end
    function m.SetOwner(self, owner) self.__owner = owner end
    function m.AddLine(self, t) self.__lines = self.__lines or {}; self.__lines[#self.__lines + 1] = t end
    function m.AddDoubleLine(self, a, b) self.__lines = self.__lines or {}; self.__lines[#self.__lines + 1] = tostring(a) .. "|" .. tostring(b) end
    function m.ClearLines(self) self.__lines = nil end
    function m.SetBagItem() end
    function m.SetHyperlink() end
    function m.SetInventoryItem() end
    function m.GetItem() return nil end
    return setmetatable(o, { __index = function(_, k)
      if type(k) == "string" and k:match("^%u") then return m[k] or noop end
      return nil
    end })
  end
  env.__newObject = newObject

  function env.CreateFrame(kind, name, parent, template)
    local f = newObject(kind, name, parent)
    f.template = template
    if name then env[name] = f end
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    env.__frames[#env.__frames + 1] = f
    return f
  end
  env.CreateFont = function(name) local f = newObject("Font", name); if name then env[name] = f end; return f end
  env.UIParent = newObject("Frame", "UIParent")
  env.UIParent.width, env.UIParent.height = UIW, UIH
  env.WorldFrame = newObject("Frame", "WorldFrame")
  env.Minimap = newObject("Frame", "Minimap")
  env.GameTooltip = newObject("GameTooltip", "GameTooltip")
  env.ItemRefTooltip = newObject("GameTooltip", "ItemRefTooltip")
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) env.__chat[#env.__chat + 1] = msg end }
  env.UISpecialFrames = {}
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function(which, ...) env.__popup = { which = which, args = { ... } } end
  env.SlashCmdList = {}
  env.BackdropTemplateMixin = {}
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  env.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function(_, q) return { r = 0.1 * (q or 0), g = 0.5, b = 0.5, hex = "|cff00ff00" } end })
  env.ACCEPT, env.CANCEL, env.YES, env.NO, env.CLOSE = "Accept", "Cancel", "Yes", "No", "Close"

  ---------------------------------------------------------------------------
  -- Lua-side WoW helpers
  ---------------------------------------------------------------------------
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.tinsert, env.tremove = table.insert, table.remove
  env.format, env.strjoin = string.format, function(sep, ...) return table.concat({ ... }, sep) end
  env.string = setmetatable({ join = function(sep, ...) return table.concat({ ... }, sep) end }, { __index = string })
  env.tostringall = function(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    return unpack(t, 1, select("#", ...))
  end
  env.geterrorhandler = function() return function(e) env.__errors = env.__errors or {}; env.__errors[#env.__errors + 1] = tostring(e) end end
  env.bit = { band = function(a, b)
    local r, bitv = 0, 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
      a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
    end
    return r end }
  env.strsplit = function(sep, s) local out = {}; for p in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = p end return unpack(out) end
  env.time = function() return env.__now end
  env.date = os.date
  env.GetTime = function() return env.__now end
  env.debugprofilestop = function() return os.clock() * 1000 end
  env.collectgarbage = collectgarbage
  env.print = function(...) env.__chat[#env.__chat + 1] = table.concat({ tostringall and select(1, env.tostringall(...)) or "" }, " ") end

  ---------------------------------------------------------------------------
  -- Timers
  ---------------------------------------------------------------------------
  env.C_Timer = {
    After = function(_, f) env.__timers[#env.__timers + 1] = f end,
    NewTicker = function(_, f)
      local t = { fn = f, cancelled = false }
      function t:Cancel() self.cancelled = true end
      env.__tickers = env.__tickers or {}
      env.__tickers[#env.__tickers + 1] = t
      return t
    end,
  }
  function env.__runTimers()
    local list = env.__timers
    env.__timers = {}
    for _, f in ipairs(list) do f() end
  end
  function env.__tick(n)
    for _ = 1, n or 1 do
      for _, t in ipairs(env.__tickers or {}) do if not t.cancelled then t.fn() end end
    end
  end
  -- run scheduler OnUpdate frames (frames with OnUpdate that are shown)
  function env.__update(elapsed)
    for _, f in ipairs(env.__frames) do
      if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, elapsed or 0.016) end
    end
  end
  function env.__settle(n)  -- run deferred work: scheduler, timers
    for _ = 1, n or 4 do env.__update(0.1); env.__runTimers() end
  end

  ---------------------------------------------------------------------------
  -- Game state
  ---------------------------------------------------------------------------
  env.InCombatLockdown = function() return env.__combat end
  env.GetLocale = function() return "enUS" end
  env.GetRealmName = function() return "TestRealm" end
  env.GetBuildInfo = function() return "1.60.1", "70862", "Nov 2026", 16001 end
  env.UnitName = function() return "Tester" end
  env.UnitClass = function() return "Priest", "PRIEST" end
  env.UnitFactionGroup = function() return "Alliance" end
  env.UnitLevel = function() return 60 end
  env.UnitIsDeadOrGhost = function() return false end
  env.GetMoney = function() return env.__money or 123456 end
  env.IsInInstance = function() return env.__inInstance or false, env.__instanceType or "none" end
  env.IsShiftKeyDown = function() return env.__shift or false end
  env.IsAltKeyDown = function() return false end
  env.IsControlKeyDown = function() return false end
  env.GetCursorPosition = function() return env.__cursor, 0 end
  env.GetCursorInfo = function() return nil end
  env.ClearCursor = noop
  env.CursorHasItem = function() return false end
  env.PlaySound = noop
  env.SOUNDKIT = {}
  env.GetFramerate = function() return 60 end
  env.GetCVar = function() return "0" end
  env.hooksecurefunc = noop
  env.GetNumBankSlots = function() return 2 end
  env.BreakUpLargeNumbers = function(n) return tostring(n) end
  env.GetNumAddOns = function() return 0 end
  env.GetBindingKey = function() return nil end
  env.GetSpecialization = function() return env.__spec end
  env.CanMerchantRepair = function() return false end
  env.MerchantFrame = newObject("Frame", "MerchantFrame")
  env.MerchantFrame.shown = false
  env.UnitGUID = function() return "Player-1-0001" end
  env.GetInventoryItemLink = function(_, slot) return env.__equipped and env.__equipped[slot] end

  ---------------------------------------------------------------------------
  -- Containers and items: env.__bags[bag] = { size = n, [slot] = {link=, count=, quality=, id=} }
  ---------------------------------------------------------------------------
  env.__bags = { [0] = { size = 8 } }
  env.__items = {}   -- [id] = { name=, quality=, ilvl=, req=, type=, sub=, stack=, equip=, sell=, class=, subclass= }
  function env.__addItem(bag, slot, id, count, def)
    env.__bags[bag] = env.__bags[bag] or { size = 8 }
    def = def or {}
    local it = env.__items[id] or {}
    for k, v in pairs(def) do it[k] = v end
    it.name = it.name or ("Item" .. id)
    it.quality = it.quality or 1
    env.__items[id] = it
    local link = "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. it.name .. "]|h|r"
    env.__bags[bag][slot] = { link = link, count = count or 1, id = id, quality = it.quality }
    return link
  end
  env.C_Container = {
    GetContainerNumSlots = function(bag) local b = env.__bags[bag]; return b and b.size or 0 end,
    GetContainerNumFreeSlots = function(bag)
      local b = env.__bags[bag]; if not b then return 0, 0 end
      local used = 0; for s = 1, b.size do if b[s] then used = used + 1 end end
      return b.size - used, 0
    end,
    GetContainerItemInfo = function(bag, slot)
      local b = env.__bags[bag]; local s = b and b[slot]
      if not s then return nil end
      return { hyperlink = s.link, stackCount = s.count, iconFileID = 134400, quality = s.quality,
        isLocked = false, itemID = s.id, isBound = false, hasNoValue = false }
    end,
    PickupContainerItem = function(bag, slot) env.__picked = { bag, slot } end,
    SplitContainerItem = function(bag, slot, n) env.__split = { bag, slot, n } end,
    UseContainerItem = function(bag, slot)
      env.__used = env.__used or {}
      env.__used[#env.__used + 1] = { bag, slot }
      local b = env.__bags[bag]
      if env.MerchantFrame.shown and b then b[slot] = nil end  -- sold
    end,
    GetContainerItemCooldown = function() return 0, 0, 0 end,
    ContainerIDToInventoryID = function(bag) return 19 + bag end,
    GetContainerItemQuestInfo = function() return {} end,
    SortBags = noop, SortBankBags = noop, PickupBagFromSlot = noop, PutItemInBag = noop, PutItemInBackpack = noop,
  }
  env.Enum = { BagIndex = {} }
  env.BACKPACK_CONTAINER, env.BANK_CONTAINER = 0, -1
  env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
  env.NUM_BANKBAGSLOTS = 6
  local function itemById(link)
    local id = tonumber(tostring(link):match("item:(%-?%d+)")) or tonumber(link)
    return id, env.__items[id]
  end
  env.C_Item = {
    GetItemInfo = function(link)
      local id, it = itemById(link)
      if not it then return nil end
      return it.name, link, it.quality, it.ilvl or 1, it.req or 0, it.type or "Miscellaneous", it.sub or "Junk",
        it.stack or 1, it.equip or "", 134400, it.sell or 0, it.class or 15, it.subclass or 0, it.bind or 0
    end,
    GetItemInfoInstant = function(link)
      local id, it = itemById(link); if not it then return nil end
      return id, it.type, it.sub, it.equip or "", 134400, it.class or 15, it.subclass or 0
    end,
    IsEquippableItem = function(link) local _, it = itemById(link); return it and it.equip and it.equip ~= "" end,
    GetDetailedItemLevelInfo = function(link) local _, it = itemById(link); return it and it.ilvl end,
    GetItemFamily = function() return 0 end,
    RequestLoadItemDataByID = noop,
  }
  env.C_AddOns = { GetNumAddOns = function() return 0 end, GetAddOnInfo = function() end, GetAddOnMetadata = function(_, k) return k == "Version" and "test" or nil end,
    IsAddOnLoaded = function() return false end }

  ---------------------------------------------------------------------------
  -- Merchant / buyback
  ---------------------------------------------------------------------------
  env.__buyback = {}
  env.GetNumBuybackItems = function() return #env.__buyback end
  env.GetBuybackItemLink = function(i) local b = env.__buyback[i]; return b and b.link end
  env.GetBuybackItemInfo = function(i) local b = env.__buyback[i]; if b then return nil, nil, b.price or 0, b.count or 1 end end
  env.BuybackItem = function(i) env.__bought = env.__bought or {}; env.__bought[#env.__bought + 1] = table.remove(env.__buyback, i) end

  return env
end
