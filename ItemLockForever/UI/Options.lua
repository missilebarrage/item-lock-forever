local _, ns = ...

--- Esc > Options > AddOns > ItemLockForever: the click that locks items, Hold to unlock, the key
--- binding (the same one as on the Key Bindings page; the game saves bindings when the panel
--- closes), the lock, unlock and error sounds, and the padlock's corner and size.
---@class ItemLockForeverOptions
local Options = ns.Options
local Database = ns.Database
local Events = ns.Events
local Input = ns.Input
local Sounds = ns.Sounds
local L = ns.L

local category ---@type table?
local settings = {} ---@type table<string, table>
local notifying = false

local function Register(key, varType, name)
	-- A proxy setting reads and writes through Database, so a change made in the panel (or by
	-- its Defaults button) is validated and announced like any other.
	local setting = Settings.RegisterProxySetting(
		category,
		"ITEMLOCKFOREVER_" .. key,
		varType,
		name,
		Database.DEFAULTS[key],
		function()
			return Database.Get(key)
		end,
		function(value)
			Database.Set(key, value)
		end
	)
	settings[key] = setting
	return setting
end

--- A dropdown of { value, label } entries.
local function Dropdown(key, name, tooltip, entries)
	Settings.CreateDropdown(category, Register(key, Settings.VarType.String, name), function()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(entries) do
			container:Add(entry[1], entry[2])
		end
		return container:GetData()
	end, tooltip)
end

local function Build(layout)
	local clicks = {}
	for _, value in ipairs(Database.CHOICES.click) do
		local combo = Input.COMBOS[value]
		clicks[#clicks + 1] = { value, combo and combo.label or L.CLICK_NONE }
	end
	Dropdown("click", L.OPTION_CLICK, L.OPTION_CLICK_TOOLTIP, clicks)
	Settings.CreateCheckbox(
		category,
		Register("holdToUnlock", Settings.VarType.Boolean, L.OPTION_HOLD),
		L.OPTION_HOLD_TOOLTIP
	)

	local index = C_KeyBindings and C_KeyBindings.GetBindingIndex and C_KeyBindings.GetBindingIndex(Input.BINDING)
	if index and CreateKeybindingEntryInitializer then
		local initializer = CreateKeybindingEntryInitializer(index, true)
		initializer:AddSearchTags(L.BINDING_TOGGLE)
		layout:AddInitializer(initializer)
	end

	Dropdown("lockSound", L.OPTION_LOCK_SOUND, L.OPTION_LOCK_SOUND_TOOLTIP, Database.SOUNDS)
	Dropdown("unlockSound", L.OPTION_UNLOCK_SOUND, L.OPTION_UNLOCK_SOUND_TOOLTIP, Database.SOUNDS)
	Dropdown("errorSound", L.OPTION_ERROR_SOUND, L.OPTION_ERROR_SOUND_TOOLTIP, Database.ERROR_SOUNDS)

	Dropdown("iconCorner", L.OPTION_ICON_CORNER, L.OPTION_ICON_CORNER_TOOLTIP, {
		{ "TOPLEFT", L.CORNER_TOPLEFT },
		{ "TOPRIGHT", L.CORNER_TOPRIGHT },
		{ "BOTTOMLEFT", L.CORNER_BOTTOMLEFT },
		{ "BOTTOMRIGHT", L.CORNER_BOTTOMRIGHT },
	})
	local range = Database.RANGES.iconSize
	local sizes = Settings.CreateSliderOptions(range[1], range[2], 1)
	sizes:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	local size = Register("iconSize", Settings.VarType.Number, L.OPTION_ICON_SIZE)
	Settings.CreateSlider(category, size, sizes, L.OPTION_ICON_SIZE_TOOLTIP)
end

-- Picking a sound plays it, so you hear what you chose. The Defaults button changes several at
-- once: only the first plays.
local SOUND_SETTINGS = { lockSound = true, unlockSound = true, errorSound = true }
local lastPreview = -math.huge
Events.On("ILF_SETTINGS_CHANGED", function(key, value)
	if SOUND_SETTINGS[key] and GetTime() - lastPreview > 0.2 then
		lastPreview = GetTime()
		Sounds.Play(value)
	end
end)

-- A setting changed somewhere else: the panel's control reads it again.
Events.On("ILF_SETTINGS_CHANGED", function(key)
	if notifying or not settings[key] then
		return
	end
	notifying = true
	settings[key]:NotifyUpdate()
	notifying = false
end)

--- Registers the options page. Called at PLAYER_LOGIN.
function Options.Init()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	Build(layout)
	Settings.RegisterAddOnCategory(category)
end

--- Opens Esc > Options > AddOns > ItemLockForever (not possible during combat).
function Options.Open()
	if InCombatLockdown() then
		ns.Print(L.OPTIONS_IN_COMBAT)
		return
	end
	if category then
		pcall(Settings.OpenToCategory, category:GetID())
	end
end
