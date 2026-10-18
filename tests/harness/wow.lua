-- Fake WoW client: a table-driven "world" (clock, timers, events, player, settings, key
-- bindings) plus the generic game API, installed into a sandbox environment. Items, bags and
-- vendors come from inventory.lua, Blizzard's item UI from blizzard.lua, other addons from
-- addons.lua.

local Widgets = dofile(HARNESS_DIR .. "/widgets.lua")

local Wow = {}
Wow.Widgets = Widgets

-- Tooltip methods.
Widgets.Define("SetOwner", function(self, owner, anchor)
	self.owner, self.anchor = owner, anchor
	self.lines = {}
end)
Widgets.Define("AddLine", function(self, text, r, g, b)
	self.lines = self.lines or {}
	self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b }
end)
Widgets.Define("AddDoubleLine", function(self, left, right)
	self.lines = self.lines or {}
	self.lines[#self.lines + 1] = { text = left, right = right }
end)
Widgets.Define("NumLines", function(self)
	return #(self.lines or {})
end)
Widgets.Define("GetOwner", function(self)
	return self.owner
end)

-- Cooldown frames.
Widgets.Define("SetHideCountdownNumbers SetDrawBling SetDrawEdge SetSwipeColor SetReverse")
Widgets.Define("SetCooldown", function(self, start, duration)
	self.cooldown = { start = start, duration = duration }
end)
Widgets.Define("Clear", function(self)
	self.cooldown = nil
end)

-- Event registration keeps the order frames registered in, like the client: a frame created
-- earlier (another addon loaded first) handles an event before this addon's frame.
Widgets.Define("RegisterEvent", function(self, event)
	local world = self.world
	if world.unknownEvents[event] then
		error('Attempt to register unknown event "' .. event .. '"')
	end
	local list = world.eventFrames[event] or {}
	world.eventFrames[event] = list
	for _, frame in ipairs(list) do
		if frame == self then
			return true
		end
	end
	list[#list + 1] = self
	return true
end)
Widgets.Define("UnregisterEvent", function(self, event)
	local list = self.world.eventFrames[event]
	for index = #(list or {}), 1, -1 do
		if list[index] == self then
			table.remove(list, index)
		end
	end
end)
Widgets.Define("UnregisterAllEvents", function(self)
	for event in pairs(self.world.eventFrames) do
		self:UnregisterEvent(event)
	end
end)
Widgets.Define("IsEventRegistered", function(self, event)
	for _, frame in ipairs(self.world.eventFrames[event] or {}) do
		if frame == self then
			return true
		end
	end
	return false
end)

--- A value the game would hide from addons. Any attempt to inspect it raises.
local SECRET = newproxy(true)
do
	local meta = getmetatable(SECRET)
	local function Forbidden()
		error("attempt to inspect a secret value", 2)
	end
	meta.__index = Forbidden
	meta.__newindex = Forbidden
	meta.__call = Forbidden
	meta.__concat = Forbidden
	meta.__len = Forbidden
	meta.__lt = Forbidden
	meta.__le = Forbidden
	meta.__tostring = Forbidden
end
Wow.SECRET = SECRET

local World = {}
World.__index = World

---@return table world
function Wow.NewWorld(options)
	options = options or {}
	local player = options.player or {}
	local world = setmetatable({
		options = options,
		clock = { server = options.now or 1790000000, uptime = 5000 },
		timers = {},
		nextTimerId = 0,
		eventFrames = {},
		unknownEvents = {},
		createdObjects = 0,
		errors = {},
		printed = {},
		player = { guid = player.guid or "Player-1-0000AAAA", name = player.name or "Tester" },
		loadedAddons = {},
		settingsCategories = {},
		openedSettings = {},
		combat = false,
		modifiers = {},
		hooks = {},
		bindingActions = { ITEMLOCKFOREVER_TOGGLE = 412 },
		boundKeys = {},
		sounds = {},
		uiErrors = {},
		violations = {},
	}, World)
	return world
end

--- Fires a game event at every frame that registered it, in registration order.
function World:Fire(event, ...)
	-- Snapshot first: handlers may register or unregister while dispatching.
	local list = {}
	for index, frame in ipairs(self.eventFrames[event] or {}) do
		list[index] = frame
	end
	for _, frame in ipairs(list) do
		Widgets.RunScript(frame, "OnEvent", event, ...)
	end
end

--- Advances the clock and runs every timer that comes due, in order.
function World:Advance(seconds)
	local target = self.clock.uptime + seconds
	while true do
		local nextTimer
		for _, timer in ipairs(self.timers) do
			if not timer.cancelled and timer.due <= target and (not nextTimer or timer.due < nextTimer.due) then
				nextTimer = timer
			end
		end
		if not nextTimer then
			break
		end
		local delta = nextTimer.due - self.clock.uptime
		self.clock.uptime = nextTimer.due
		self.clock.server = self.clock.server + delta
		nextTimer.cancelled = true
		nextTimer.callback(nextTimer.handle)
	end
	self.clock.server = self.clock.server + (target - self.clock.uptime)
	self.clock.uptime = target
	local kept = {}
	for _, timer in ipairs(self.timers) do
		if not timer.cancelled then
			kept[#kept + 1] = timer
		end
	end
	self.timers = kept
end

--- Runs fn after delay seconds of game time (used by the fakes for server replies).
function World:After(delay, fn)
	self.nextTimerId = self.nextTimerId + 1
	self.timers[#self.timers + 1] = { id = self.nextTimerId, due = self.clock.uptime + delay, callback = fn }
end

--- Everything the addon printed, joined.
function World:Output()
	return table.concat(self.printed, "\n")
end

--- Records a call the addon must never make (see blizzard.lua).
function World:Violation(what)
	self.violations[#self.violations + 1] = what
end

local function Copy(source, into)
	into = into or {}
	for key, value in pairs(source) do
		into[key] = value
	end
	return into
end
Wow.Copy = Copy

--- Builds a sandbox environment exposing the fake API backed by the given world.
function Wow.CreateEnvironment(world)
	local options = world.options
	local env = {}
	world.env = env

	-- Lua standard library (no io/os/require/load*: addons can't use them either).
	for _, name in ipairs({
		"assert",
		"error",
		"ipairs",
		"next",
		"pairs",
		"pcall",
		"rawequal",
		"rawget",
		"rawset",
		"select",
		"setmetatable",
		"getmetatable",
		"tonumber",
		"tostring",
		"type",
		"unpack",
		"xpcall",
	}) do
		env[name] = _G[name]
	end
	env.string = Copy(string)
	env.table = Copy(table)
	env.math = Copy(math)
	env._G = env
	env.print = function(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		world.printed[#world.printed + 1] = table.concat(parts, " ")
	end
	env.wipe = function(t)
		for key in pairs(t) do
			t[key] = nil
		end
		return t
	end

	-- Secrets and error isolation.
	env.issecretvalue = function(value)
		return rawequal(value, SECRET)
	end
	env.securecallfunction = function(fn, ...)
		local results = { pcall(fn, ...) }
		if not results[1] then
			world.errors[#world.errors + 1] = results[2]
			return
		end
		return unpack(results, 2, table.maxn(results))
	end

	-- hooksecurefunc([table,] name, hook): the hook runs after the original, with the same
	-- arguments; its return values are ignored.
	env.hooksecurefunc = function(target, name, hook)
		if type(target) == "string" then
			target, name, hook = env, target, name
		end
		local original = target[name]
		assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
		target[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results, 1, table.maxn(results))
		end
		world.hooks[#world.hooks + 1] = { target = target, name = name }
	end

	-- Time.
	env.GetTime = function()
		return world.clock.uptime
	end
	local function AddTimer(delay, callback)
		world.nextTimerId = world.nextTimerId + 1
		local timer = { id = world.nextTimerId, due = world.clock.uptime + delay, callback = callback }
		local handle = {
			Cancel = function()
				timer.cancelled = true
			end,
			IsCancelled = function()
				return timer.cancelled == true
			end,
		}
		timer.handle = handle
		world.timers[#world.timers + 1] = timer
		return handle
	end
	env.C_Timer = {
		After = function(delay, callback)
			AddTimer(delay, callback)
		end,
		NewTimer = AddTimer,
	}

	-- Frames.
	env.CreateFrame = function(frameType, name, parent, template)
		local frame = Widgets.Create(world, frameType, name, parent, { template = template })
		if name then
			env[name] = frame
		end
		return frame
	end
	env.UIParent = Widgets.Create(world, "Frame", "UIParent")
	env.GameTooltip = Widgets.Create(world, "GameTooltip", "GameTooltip")
	env.GameTooltip.shown = false
	env.SlashCmdList = {}
	env.InCombatLockdown = function()
		return world.combat
	end
	env.IsShiftKeyDown = function()
		return world.modifiers.shift == true
	end
	env.IsControlKeyDown = function()
		return world.modifiers.ctrl == true
	end
	env.IsAltKeyDown = function()
		return world.modifiers.alt == true
	end
	env.GetMouseButtonClicked = function()
		return world.mouseButton or ""
	end
	env.GetMouseFoci = function()
		return world.mouseFoci or {}
	end

	-- Settings panel.
	env.Settings = {
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function(name)
			local category = { name = name, settings = {}, initializers = {} }
			function category:GetID()
				return 77
			end
			local layout = {}
			function layout:AddInitializer(initializer)
				category.initializers[#category.initializers + 1] = initializer
			end
			world.settingsCategories[#world.settingsCategories + 1] = category
			return category, layout
		end,
		RegisterAddOnCategory = function(category)
			category.registered = true
		end,
		RegisterProxySetting = function(category, variable, variableType, name, default, getValue, setValue)
			local setting = {
				variable = variable,
				type = variableType,
				name = name,
				default = default,
				proxy = true,
			}
			function setting:SetValue(value)
				setValue(value)
			end
			function setting:GetValue()
				return getValue()
			end
			function setting:NotifyUpdate()
				self.notified = (self.notified or 0) + 1
			end
			category.settings[(variable:gsub("^ITEMLOCKFOREVER_", ""))] = setting
			return setting
		end,
		CreateDropdown = function(_, setting, getOptions, tooltip)
			setting.control = "dropdown"
			setting.getOptions = getOptions
			setting.tooltip = tooltip
		end,
		CreateCheckbox = function(_, setting, tooltip)
			setting.control = "checkbox"
			setting.tooltip = tooltip
		end,
		CreateSlider = function(_, setting, sliderOptions, tooltip)
			setting.control = "slider"
			setting.options = sliderOptions
			setting.tooltip = tooltip
		end,
		CreateSliderOptions = function(minimum, maximum, step)
			local sliderOptions = { minimum = minimum, maximum = maximum, step = step }
			function sliderOptions:SetLabelFormatter(labelType, formatter)
				self.labelType, self.formatter = labelType, formatter
			end
			return sliderOptions
		end,
		CreateControlTextContainer = function()
			local container = { data = {} }
			function container:Add(value, label)
				self.data[#self.data + 1] = { value = value, label = label }
			end
			function container:GetData()
				return self.data
			end
			return container
		end,
		OpenToCategory = function(categoryID)
			world.openedSettings[#world.openedSettings + 1] = categoryID
		end,
	}

	-- Key bindings: world.bindingActions[action] = index (the client knows the action),
	-- world.boundKeys[action] = key.
	env.C_KeyBindings = {
		GetBindingIndex = function(action)
			return world.bindingActions[action]
		end,
	}
	env.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
	env.CreateKeybindingEntryInitializer = function(bindingIndex, search)
		local initializer = { kind = "keybinding", bindingIndex = bindingIndex, search = search, tags = {} }
		function initializer:AddSearchTags(...)
			for index = 1, select("#", ...) do
				self.tags[#self.tags + 1] = (select(index, ...))
			end
		end
		return initializer
	end
	env.GetBindingKey = function(action)
		return world.boundKeys[action]
	end
	env.GetBindingText = function(key)
		return "<" .. key .. ">"
	end

	-- Sounds and the error frame.
	env.SOUNDKIT = {
		TRADING_POST_UI_ITEM_LOCKING = 218229,
		TRADING_POST_UI_ITEM_UNLOCKING = 218517,
		KEY_RING_OPEN = 8938,
		PUT_DOWN_SMALL_CHAIN = 1212,
		UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK = 44331,
		GUILD_VAULT_CLOSE = 12189,
		UI_70_ARTIFACT_FORGE_APPEARANCE_LOCKED = 54131,
		IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
		LOOT_WINDOW_COIN_SOUND = 120,
		PUT_DOWN_GEMS = 1204,
		MAP_PING = 3175,
		UI_GARRISON_ARCHITECT_TABLE_BUILDING_PLACEMENT_ERROR = 47355,
		LFG_DENIED = 17341,
		QUEST_SESSION_DECLINE = 139830,
		HOUSING_INVALID_PLACEMENT = 286118,
		GM_CHAT_WARNING = 15273,
		IG_QUEST_LOG_ABANDON_QUEST = 846,
		INTERFACE_SOUND_LOST_TARGET_UNIT = 684,
		RAID_WARNING = 8959,
		ALARM_CLOCK_WARNING_3 = 12889,
	}
	env.PlaySound = function(soundKitID)
		world.sounds[#world.sounds + 1] = soundKitID
	end
	env.UIErrorsFrame = Widgets.Create(world, "MessageFrame", "UIErrorsFrame")
	env.UIErrorsFrame.AddExternalErrorMessage = function(_, message)
		world.uiErrors[#world.uiErrors + 1] = message
	end
	world.uiMessages = {}
	env.UIErrorsFrame.AddMessage = function(_, message)
		world.uiMessages[#world.uiMessages + 1] = message
	end

	env.UnitGUID = function(unit)
		if unit == "player" then
			return world.player.guid
		end
	end

	env.Enum = {
		TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
		PlayerInteractionType = { Merchant = 5, Banker = 8 },
	}

	env.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			if field == "Version" then
				return options.version or "@project-version@"
			end
		end,
		IsAddOnLoaded = function(name)
			return world.loadedAddons[name] == true
		end,
	}

	return env
end

--- Remembers every global that exists before the addon loads (after all fakes are installed).
function World:CaptureBaseline()
	self.baselineGlobals = {}
	for key in pairs(self.env) do
		self.baselineGlobals[key] = true
	end
end

--- Globals the addon created that it isn't allowed to.
function World:LeakedGlobals(allowed)
	local leaked = {}
	for key in pairs(self.env) do
		if not self.baselineGlobals[key] and not allowed[key] then
			leaked[#leaked + 1] = key
		end
	end
	table.sort(leaked)
	return leaked
end

-- Saved variables round trip -------------------------------------------------------

local function SerializeSaved(value)
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("non-finite number in saved variables")
		end
		return string.format("%.17g", value)
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		local parts = {}
		for key, inner in pairs(value) do
			if type(key) ~= "string" and type(key) ~= "number" then
				error("unsupported key type in saved variables: " .. type(key))
			end
			parts[#parts + 1] = "[" .. SerializeSaved(key) .. "]=" .. SerializeSaved(inner)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot save a " .. kind)
end

--- Writes a saved variable out and reads it back, the way the client does at logout.
function Wow.RoundTrip(value)
	if value == nil then
		return nil
	end
	local chunk = assert(loadstring("return " .. SerializeSaved(value)))
	return chunk()
end

Wow.World = World
return Wow
