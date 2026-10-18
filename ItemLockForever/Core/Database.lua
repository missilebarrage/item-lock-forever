local _, ns = ...

--- SavedVariables: ItemLockForeverDB, account-wide.
---   settings = { click = "ALT-LeftButton", ... }
---   items    = { [itemGUID] = itemID }                 locked items and single stacks, on any character
---   stacks   = { [playerGUID] = { [itemID] = true } }  every stack of an item locked, per character
---   free     = { [itemGUID] = itemID }                 stacks unlocked one at a time while every stack
---                                                      of their item is locked
--- Locks saved by a newer version keep protecting items but are never changed (read-only mode):
--- protection must not disappear because of a downgrade.
---@class ItemLockForeverDatabase
local Database = ns.Database
local Events = ns.Events
local L = ns.L

--- Sounds to choose from for locking and unlocking, in menu order: key, label and SOUNDKIT name
--- ("none" is silent). Every one exists in Forever's sound data (see docs/API-NOTES.md).
Database.SOUNDS = {
	{ "none", L.SOUND_NONE },
	{ "lock", L.SOUND_LOCK, "TRADING_POST_UI_ITEM_LOCKING" },
	{ "unlock", L.SOUND_UNLOCK, "TRADING_POST_UI_ITEM_UNLOCKING" },
	{ "keys", L.SOUND_KEYS, "KEY_RING_OPEN" },
	{ "chain", L.SOUND_CHAIN, "PUT_DOWN_SMALL_CHAIN" },
	{ "chest", L.SOUND_CHEST, "UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK" },
	{ "vault", L.SOUND_VAULT, "GUILD_VAULT_CLOSE" },
	{ "forge", L.SOUND_FORGE, "UI_70_ARTIFACT_FORGE_APPEARANCE_LOCKED" },
	{ "click", L.SOUND_CLICK, "IG_MAINMENU_OPTION_CHECKBOX_ON" },
	{ "coins", L.SOUND_COINS, "LOOT_WINDOW_COIN_SOUND" },
	{ "gems", L.SOUND_GEMS, "PUT_DOWN_GEMS" },
	{ "ping", L.SOUND_PING, "MAP_PING" },
}

--- Sounds for a blocked sale, disenchant or destroy, in menu order (same shape as SOUNDS).
Database.ERROR_SOUNDS = {
	{ "none", L.SOUND_NONE },
	{ "error", L.ERROR_SOUND_ERROR, "UI_GARRISON_ARCHITECT_TABLE_BUILDING_PLACEMENT_ERROR" },
	{ "denied", L.ERROR_SOUND_DENIED, "LFG_DENIED" },
	{ "decline", L.ERROR_SOUND_DECLINE, "QUEST_SESSION_DECLINE" },
	{ "invalid", L.ERROR_SOUND_INVALID, "HOUSING_INVALID_PLACEMENT" },
	{ "warning", L.ERROR_SOUND_WARNING, "GM_CHAT_WARNING" },
	{ "abandon", L.ERROR_SOUND_ABANDON, "IG_QUEST_LOG_ABANDON_QUEST" },
	{ "blip", L.ERROR_SOUND_BLIP, "INTERFACE_SOUND_LOST_TARGET_UNIT" },
	{ "raidWarning", L.ERROR_SOUND_RAID_WARNING, "RAID_WARNING" },
	{ "alarm", L.ERROR_SOUND_ALARM, "ALARM_CLOCK_WARNING_3" },
}

local function Keys(list)
	local keys = {}
	for index, sound in ipairs(list) do
		keys[index] = sound[1]
	end
	return keys
end
local SOUND_KEYS = Keys(Database.SOUNDS)

--- Default value of every setting. Keys here are the only settings ItemLockForever knows about.
Database.DEFAULTS = {
	click = "ALT-LeftButton",
	holdToUnlock = false,
	lockSound = "vault",
	unlockSound = "keys",
	errorSound = "error",
	iconCorner = "TOPRIGHT",
	iconSize = 14,
}

--- Allowed values of the settings that are a choice.
Database.CHOICES = {
	click = { "ALT-LeftButton", "ALT-RightButton", "CTRL-ALT-RightButton", "CTRL-RightButton", "NONE" },
	lockSound = SOUND_KEYS,
	unlockSound = SOUND_KEYS,
	errorSound = Keys(Database.ERROR_SOUNDS),
	iconCorner = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
}

--- Allowed ranges of whole-number settings.
Database.RANGES = {
	iconSize = { 8, 32 },
}

-- Numbered migrations: MIGRATIONS[n] upgrades data from schema n - 1 to n.
local MIGRATIONS = {}

local account ---@type table
local readOnly = false

local function IsValid(key, value)
	local default = Database.DEFAULTS[key]
	if default == nil or type(value) ~= type(default) then
		return false
	end
	local choices = Database.CHOICES[key]
	if choices then
		for _, choice in ipairs(choices) do
			if choice == value then
				return true
			end
		end
		return false
	end
	local range = Database.RANGES[key]
	if range then
		return value >= range[1] and value <= range[2] and value == math.floor(value)
	end
	return true
end

local function FillDefaults(settings)
	for key, default in pairs(Database.DEFAULTS) do
		if not IsValid(key, settings[key]) then
			settings[key] = default
		end
	end
	-- Settings that a later version removed.
	for key in pairs(settings) do
		if Database.DEFAULTS[key] == nil then
			settings[key] = nil
		end
	end
end

local function Table(value)
	return type(value) == "table" and value or nil
end

-- Drops entries a damaged or hand-edited file could hold, so lookups can trust the types.
local function CleanItems(items)
	for guid, itemID in pairs(items) do
		if type(guid) ~= "string" or type(itemID) ~= "number" then
			items[guid] = nil
		end
	end
end

local function CleanStacks(stacks)
	for owner, list in pairs(stacks) do
		if type(owner) ~= "string" or type(list) ~= "table" then
			stacks[owner] = nil
		else
			for itemID, locked in pairs(list) do
				if type(itemID) ~= "number" or locked ~= true then
					list[itemID] = nil
				end
			end
		end
	end
end

--- Loads the saved variables. Called once, at ADDON_LOADED.
function Database.Init()
	local data = ItemLockForeverDB
	if type(data) ~= "table" then
		data = { schema = ns.SCHEMA }
		ItemLockForeverDB = data
	end
	local schema = data.schema
	if type(schema) == "number" and schema > ns.SCHEMA then
		readOnly = true
		account = {
			settings = {},
			items = Table(data.items) or {},
			stacks = Table(data.stacks) or {},
			free = Table(data.free) or {},
		}
		for key, value in pairs(Table(data.settings) or {}) do
			account.settings[key] = value
		end
		FillDefaults(account.settings)
		ns.Print(L.DATA_FROM_NEWER_VERSION)
		return
	end
	for version = (type(schema) == "number" and schema or ns.SCHEMA) + 1, ns.SCHEMA do
		if MIGRATIONS[version] then
			MIGRATIONS[version](data)
		end
	end
	data.schema = ns.SCHEMA
	data.settings = Table(data.settings) or {}
	data.items = Table(data.items) or {}
	data.stacks = Table(data.stacks) or {}
	data.free = Table(data.free) or {}
	FillDefaults(data.settings)
	CleanItems(data.items)
	CleanItems(data.free)
	CleanStacks(data.stacks)
	account = data
end

---@return boolean
function Database.IsReadOnly()
	return readOnly
end

function Database.Get(key)
	return account.settings[key]
end

--- Stores a setting and notifies listeners with ILF_SETTINGS_CHANGED(key, value). Whole-number
--- settings are rounded (sliders can hand over 13.999...); invalid values are refused.
---@return boolean stored
function Database.Set(key, value)
	if Database.RANGES[key] and type(value) == "number" then
		value = math.floor(value + 0.5)
	end
	if not IsValid(key, value) then
		return false
	end
	if account.settings[key] == value then
		return true
	end
	account.settings[key] = value
	Events.Fire("ILF_SETTINGS_CHANGED", key, value)
	return true
end

--- Locked items and single stacks: itemGUID -> itemID, shared by every character.
---@return table<string, number>
function Database.Items()
	return account.items
end

--- Stacks unlocked one by one while every stack of their item is locked: itemGUID -> itemID.
---@return table<string, number>
function Database.Free()
	return account.free
end

--- A character's stack locks: itemID -> true. The table is created on first use (only in
--- memory in read-only mode); empty ones are dropped at logout.
---@param playerGUID string?
---@return table<number, true>
function Database.Stacks(playerGUID)
	local list = playerGUID and account.stacks[playerGUID]
	if type(list) ~= "table" then
		list = {}
		if playerGUID and not readOnly then
			account.stacks[playerGUID] = list
		end
	end
	return list
end

Events.On("PLAYER_LOGOUT", function()
	if not account or readOnly then
		return
	end
	for owner, list in pairs(account.stacks) do
		if next(list) == nil then
			account.stacks[owner] = nil
		end
	end
end)
