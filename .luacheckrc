-- luacheck configuration: Lua 5.1 (the game's Lua) plus an explicit list of the game API
-- ItemLockForever is allowed to use, so typos and accidental globals fail the lint.
std = "lua51"
max_line_length = 120
codes = true
self = false
exclude_files = { ".tools/**", ".release/**" }

files["ItemLockForever/**/*.lua"] = {
	globals = {
		-- Saved variables, slash command and key binding registration.
		"ItemLockForeverDB",
		"SLASH_ITEMLOCKFOREVER1",
		"SLASH_ITEMLOCKFOREVER2",
		"SlashCmdList",
		"BINDING_NAME_ITEMLOCKFOREVER_TOGGLE",
		"ItemLockForever_ToggleHovered",
	},
	read_globals = {
		-- Lua extensions and helpers provided by the client.
		"wipe",
		"issecretvalue",
		"securecallfunction",
		"hooksecurefunc",
		-- Frames and UI framework.
		"CreateFrame",
		"UIParent",
		"GameTooltip",
		"UIErrorsFrame",
		"Settings",
		"CreateKeybindingEntryInitializer",
		"MinimalSliderWithSteppersMixin",
		"TooltipDataProcessor",
		"InCombatLockdown",
		"PlaySound",
		"SOUNDKIT",
		-- Blizzard UI this addon hooks or looks at.
		"HandleModifiedItemClick",
		"ContainerFrameContainer",
		"ContainerFrameCombinedBags",
		"BankPanelItemButtonMixin",
		"PaperDollItemSlotButton_Update",
		"AuctionHouseFrame",
		"NUM_TOTAL_EQUIPPED_BAG_SLOTS",
		-- Input.
		"GetMouseButtonClicked",
		"GetMouseFoci",
		"IsAltKeyDown",
		"IsControlKeyDown",
		"IsShiftKeyDown",
		"GetBindingKey",
		"GetBindingText",
		"C_KeyBindings",
		-- Items, cursor and merchants.
		"C_Item",
		"C_Container",
		"C_Cursor",
		"C_TooltipInfo",
		"C_MerchantFrame",
		"ItemLocation",
		"GetInventoryItemID",
		"CursorHasItem",
		"ClearCursor",
		"SpellIsTargeting",
		"SpellCanTargetItem",
		"GetNumBuybackItems",
		"GetBuybackItemInfo",
		"GetBuybackItemLink",
		"BuybackItem",
		"GetMoney",
		-- Game API.
		"C_AddOns",
		"C_Spell",
		"C_Timer",
		"Enum",
		"GetTime",
		"UnitGUID",
		-- Optional addons.
		"EUI_Bags",
	},
}

files["ItemLockForever/Locales/*.lua"] = {
	ignore = { "631" }, -- long strings read better unbroken
}

files["tests/**/*.lua"] = {
	globals = { "ROOT_DIR", "HARNESS_DIR", "describe", "it", "expect", "Harness" },
	read_globals = { "newproxy" },
	ignore = { "631" }, -- long literal lines in fixtures are fine
}
