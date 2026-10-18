local addonName, ns = ...

ns.NAME = addonName
ns.TITLE = "ItemLockForever"
--- Saved-variables schema (ItemLockForeverDB.schema).
ns.SCHEMA = 1

-- Every module table exists before any module file runs, so files can capture each other
-- as locals regardless of load order.
ns.Events = {}
ns.Database = {}
ns.Sounds = {}
ns.Locks = {}
ns.Input = {}
ns.Feedback = {}
ns.Holds = {}
ns.Merchant = {}
ns.Disenchant = {}
ns.Destroy = {}
ns.Tooltip = {}
ns.Badges = {}
ns.Options = {}

--- Localized strings. Locales/enUS.lua is the source of truth; a missing key shows the key itself.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

--- The padlock drawn on locked items, in the tooltip line and as the addon's icon.
ns.LOCK_ATLAS = "QuestSharing-Padlock"

do
	local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version")
	-- An unpackaged checkout still carries the packager token (e.g. "@project-version@").
	if type(version) ~= "string" or version == "" or version:find("^@") then
		version = "dev"
	end
	ns.VERSION = version
end

local issecretvalue = issecretvalue

--- Returns the value when it is a readable, finite number; otherwise nil.
---@return number?
function ns.Num(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

--- Returns the value when it is a readable, non-empty string; otherwise nil.
---@return string?
function ns.Str(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

function ns.Print(...)
	print("|cffe6b85cItemLockForever|r", ...)
end

--- Diagnostics for the first in-game tests (/ilf debug). Prints IDs and counts only.
ns.debug = false

function ns.Debug(...)
	if ns.debug then
		ns.Print("|cff999999debug|r", ...)
	end
end
