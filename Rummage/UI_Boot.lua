-- Rummage: builds the two list windows (Bags and Bank) from the UI parts.
-- Added in 1.8.0 so the bank is its own window and items can be dragged between them.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local R = ns.R

R.UIList = {}

local function Make(kind)
	local UI = { kind = kind }
	for _, part in ipairs(R.UIParts) do part(UI) end
	R.UIList[#R.UIList + 1] = UI
	return UI
end

R.UI = Make("bags")
R.BankUI = Make("bank")

-- Calls fn(window) for every created window.
function R:EachUI(fn)
	for _, w in ipairs(R.UIList) do
		if w.frame then fn(w) end
	end
end
