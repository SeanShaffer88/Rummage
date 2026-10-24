-- Rummage: lightweight diagnostics overlay.
--   /fdebug  or  /rum debug        toggle the overlay (zero cost while off)
--   /fdebug report                 print a summary to chat
--   /fdebug reset                  reset counters
-- Shows addon memory, Lua heap growth, frame time (avg/max/hitches), event and internal
-- message rates, profiled timings (Refresh / Render / ScanBag), pools and caches, and
-- CPU time when the scriptProfile CVar is enabled.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R
local API = R.API

local pairs, ipairs, format, floor, max, sort, wipe = pairs, ipairs, string.format, math.floor, math.max, table.sort, wipe
local collectgarbage, GetFramerate = collectgarbage, GetFramerate

local D = {}
R.Debug = D

local frame, text, ticker
local MEM_INTERVAL = 5 -- UpdateAddOnMemoryUsage walks every addon's heap; never call it per frame

-- per-second accumulators (filled by the overlay's own OnUpdate)
local ft = { n = 0, sum = 0, max = 0, hitches = 0 }
local lastEvents, lastMsgs, rates, msgRates = {}, {}, {}, {}
local lastHeap, heapRate = 0, 0
local addonMem, memAge = 0, MEM_INTERVAL
local sortBuf, lines = {}, {}

local function TopRates(src, last, out, limit)
	wipe(out)
	wipe(sortBuf)
	for k, v in pairs(src) do
		local d = v - (last[k] or 0)
		last[k] = v
		if d > 0 then out[k] = d; sortBuf[#sortBuf + 1] = k end
	end
	sort(sortBuf, function(a, b) return out[a] > out[b] end)
	local s = ""
	for i = 1, math.min(limit, #sortBuf) do
		local k = sortBuf[i]
		s = s .. format("\n  %-28s %4d/s", k, out[k])
	end
	return s
end

local function Timings()
	local s = ""
	for _, name in ipairs({ "UI:Refresh", "UI:Render", "Data:ScanBag" }) do
		local t = R.stats.timings[name]
		if t and t.n > 0 then
			s = s .. format("\n  %-14s n=%-5d avg %.2f ms  max %.2f ms", name, t.n, t.total / t.n, t.max)
		end
	end
	return s
end

local function CPU()
	if not (GetCVar and GetCVar("scriptProfile") == "1") then return "off (/console scriptProfile 1, reload)" end
	local update = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
	local get = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
	if not (update and get) then return "unavailable" end
	update()
	return format("%.1f ms total", get(R.name) or 0)
end

function D:Snapshot()
	-- addon memory (throttled)
	memAge = memAge + 1
	if memAge >= MEM_INTERVAL and API.UpdateAddOnMemoryUsage and API.GetAddOnMemoryUsage then
		memAge = 0
		API.UpdateAddOnMemoryUsage()
		addonMem = API.GetAddOnMemoryUsage(R.name) or 0
	end
	local heap = collectgarbage("count")
	heapRate = heap - lastHeap
	lastHeap = heap

	local avg = ft.n > 0 and (ft.sum / ft.n * 1000) or 0
	local evText = TopRates(R.stats.events, lastEvents, rates, 6)
	local msgText = TopRates(R.stats.messages, lastMsgs, msgRates, 4)
	local free, used, pairsFree = R.Items:PoolStats()

	wipe(lines)
	lines[1] = "|cffd9a441Rummage debug|r"
	lines[2] = format("Addon memory: %.0f KB  (refreshed every %ds)", addonMem, MEM_INTERVAL)
	lines[3] = format("Lua heap (all addons): %.1f MB  %+.0f KB/s", heap / 1024, heapRate)
	lines[4] = format("Frame: %.0f fps  avg %.1f ms  max %.1f ms  hitches(>50ms) %d", GetFramerate and GetFramerate() or 0,
		avg, ft.max * 1000, ft.hitches)
	lines[5] = "Events/s:" .. (evText ~= "" and evText or " none")
	lines[6] = "Internal messages/s:" .. (msgText ~= "" and msgText or " none")
	lines[7] = "Timings:" .. (Timings() ~= "" and Timings() or " none yet")
	lines[8] = format("Pools: entries %d free / %d live, slot pairs %d free", free, used, pairsFree)
	lines[9] = format("Item info cache %d, pending loads %d", R.Items:CacheCount(), R.Items:PendingCount())
	lines[10] = "CPU: " .. CPU()
	ft.n, ft.sum, ft.max, ft.hitches = 0, 0, 0, 0
	return table.concat(lines, "\n")
end

local function CreateOverlay()
	frame = CreateFrame("Frame", "RummageDebugFrame", UIParent, API.Backdrop)
	frame:SetSize(430, 300)
	frame:SetPoint("TOPLEFT", 20, -120)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		frame:SetBackdropColor(0, 0, 0, 0.75)
		frame:SetBackdropBorderColor(0.85, 0.64, 0.25, 0.8)
	end
	text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", 8, -8)
	text:SetPoint("BOTTOMRIGHT", -8, 8)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	-- Frame-time sampling: the only per-frame work, and only while the overlay is shown.
	frame:SetScript("OnUpdate", function(_, elapsed)
		ft.n = ft.n + 1
		ft.sum = ft.sum + elapsed
		if elapsed > ft.max then ft.max = elapsed end
		if elapsed > 0.05 then ft.hitches = ft.hitches + 1 end
	end)
	frame:Hide()
end

function D:Enable()
	if not frame then CreateOverlay() end
	R:SetDebug(true)
	wipe(lastEvents); wipe(lastMsgs)
	lastHeap = collectgarbage("count")
	memAge = MEM_INTERVAL
	frame:Show()
	text:SetText(self:Snapshot())
	ticker = C_Timer.NewTicker(1, function() text:SetText(D:Snapshot()) end)
	R:Print("Debug overlay on. /fdebug to turn off, /fdebug report for a chat summary.")
end

function D:Disable()
	if ticker then ticker:Cancel(); ticker = nil end
	if frame then frame:Hide() end
	R:SetDebug(false)
	R:Print("Debug overlay off.")
end

function D:Toggle()
	if R:IsDebug() then self:Disable() else self:Enable() end
end

function D:Report()
	if GetBuildInfo then
		local version, build = GetBuildInfo()
		R:Print("client " .. tostring(version) .. " (build " .. tostring(build) .. ")")
	end
	local was = R:IsDebug()
	if not was then R:SetDebug(true) end
	for line in (self:Snapshot() .. "\n"):gmatch("(.-)\n") do
		DEFAULT_CHAT_FRAME:AddMessage(line)
	end
	if not was then R:SetDebug(false) end
end

function D:Command(arg)
	arg = (arg or ""):lower()
	if arg == "report" then self:Report()
	elseif arg == "reset" then R:SetDebug(R:IsDebug()); R:Print("Debug counters reset.")
	else self:Toggle() end
end

SLASH_RUMMAGEDEBUG1 = "/fdebug"
SlashCmdList.RUMMAGEDEBUG = function(msg) D:Command(msg) end
