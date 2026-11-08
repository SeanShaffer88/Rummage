-- UNVERIFIED: written for luacheck 1.x but never run (luacheck could not be installed
-- in the build environment). tools/check.py runs it automatically when it is on PATH.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "tests/*" }

-- Globals Rummage assigns.
globals = {
  "RummageDB", "RummageLocales", "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
  "Rummage_OnAddonCompartmentClick", "SLASH_RUMMAGE1", "SLASH_RUMMAGE2", "SLASH_RUMMAGEDEBUG1",
  "BINDING_HEADER_RUMMAGE", "BINDING_NAME_RUMMAGE_TOGGLE",
}

-- WoW API surface Rummage reads. Names are those used in the source; keep sorted when adding.
read_globals = {
  "AUCTION_CATEGORY_ARMOR", "BACKPACK_CONTAINER", "BANK_CONTAINER", "BackdropTemplateMixin", "BreakUpLargeNumbers",
  "BuybackItem", "C_AddOns", "C_Container", "C_Item", "C_SpecializationInfo", "C_Timer", "CLOSE", "CanGuildBankRepair",
  "CanMerchantRepair", "ChatFontNormal", "ClearCursor", "ClearOverrideBindings", "CreateFont", "CreateFrame",
  "CursorHasItem", "DEFAULT_CHAT_FRAME", "Enum", "GameFontHighlight", "GameTooltip", "GetBindingKey", "GetBuildInfo",
  "GetBuybackItemInfo", "GetBuybackItemLink", "GetCursorInfo", "GetCursorPosition", "GetInventoryItemLink", "GetItemStats",
  "GetLocale", "GetMoney", "GetNumAddOns", "GetNumBuybackItems", "GetRealmName", "GetRepairAllCost", "GetSpecialization",
  "GetTime", "HandleModifiedItemClick", "InCombatLockdown", "IsAltKeyDown", "IsControlKeyDown", "IsInInstance",
  "IsShiftKeyDown", "ItemRefTooltip", "MerchantFrame", "NO", "PlaySound", "RAID_CLASS_COLORS", "RepairAllItems",
  "SOUNDKIT", "StaticPopup_Show", "TooltipDataProcessor", "TooltipUtil", "UIParent", "UnitClass", "UnitName",
  "WorldFrame", "YES", "bit", "canaccessvalue", "date", "debugprofilestop", "format", "hooksecurefunc", "issecretvalue",
  "strsplit", "time", "tinsert", "tremove", "wipe",
}
