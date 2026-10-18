local addonName, ns = ...

-- Startup wiring and the slash command: /ilf opens the options, /ilf debug toggles diagnostics.
local Events = ns.Events
local L = ns.L

SLASH_ITEMLOCKFOREVER1 = "/ilf"
SLASH_ITEMLOCKFOREVER2 = "/itemlock"
SlashCmdList.ITEMLOCKFOREVER = function(message)
	local command = (message or ""):match("^%s*(%S*)"):lower()
	if command == "debug" then
		ns.debug = not ns.debug
		ns.Print(ns.debug and L.DEBUG_ON or L.DEBUG_OFF)
		return
	end
	ns.Options.Open()
end

Events.On("ADDON_LOADED", function(name)
	if name == addonName then
		ns.Database.Init()
	end
end)

-- The lock model connects first, and Holds before the modules that use it; each module separately,
-- so one failing module can't stop the others.
local MODULES = {
	ns.Locks,
	ns.Input,
	ns.Holds,
	ns.Merchant,
	ns.Disenchant,
	ns.Destroy,
	ns.Tooltip,
	ns.Badges,
	ns.Options,
}
for _, module in ipairs(MODULES) do
	Events.On("PLAYER_LOGIN", function()
		module.Init()
	end)
end
