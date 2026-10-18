-- Loads the addon into a fresh sandbox the way the client does: files in TOC order, each
-- called with (addonName, namespace).

local Wow = dofile(HARNESS_DIR .. "/wow.lua")
local Inventory = dofile(HARNESS_DIR .. "/inventory.lua")
local Blizzard = dofile(HARNESS_DIR .. "/blizzard.lua")
local Addons = dofile(HARNESS_DIR .. "/addons.lua")
Blizzard.Init(Wow.Widgets, Inventory)
Addons.Init(Wow.Widgets, Blizzard)

local Loader = {}
Loader.Wow = Wow
Loader.SECRET = Wow.SECRET
Loader.Inventory = Inventory
Loader.Blizzard = Blizzard
Loader.Addons = Addons
Loader.ADDON = "ItemLockForever"
--- Every world created during the current test (errors in them fail the test).
Loader.created = {}

local ADDON_DIR = ROOT_DIR .. "/ItemLockForever"

-- Globals the addon is allowed to create.
local ALLOWED_GLOBALS = {
	ItemLockForeverDB = true,
	SLASH_ITEMLOCKFOREVER1 = true,
	SLASH_ITEMLOCKFOREVER2 = true,
	BINDING_NAME_ITEMLOCKFOREVER_TOGGLE = true,
	ItemLockForever_ToggleHovered = true,
}
Loader.ALLOWED_GLOBALS = ALLOWED_GLOBALS

--- The addon's files, in load order, as listed in the TOC.
function Loader.TocFiles()
	local files = {}
	for line in io.lines(ADDON_DIR .. "/ItemLockForever.toc") do
		line = line:gsub("\r$", "")
		if line ~= "" and not line:match("^#") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

--- The TOC's "## Key: Value" metadata.
function Loader.TocMetadata()
	local metadata = {}
	for line in io.lines(ADDON_DIR .. "/ItemLockForever.toc") do
		local key, value = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)%s*$")
		if key then
			metadata[key] = value
		end
	end
	return metadata
end

--- A file of the addon folder, as text.
function Loader.ReadAddonFile(name)
	local handle = assert(io.open(ADDON_DIR .. "/" .. name, "r"))
	local text = handle:read("*a")
	handle:close()
	return text
end

--- Item IDs the tests use (defined in every world).
Loader.ITEMS = {
	SWORD = 2000, -- gear
	RING = 2001, -- gear
	LINEN = 2589, -- stacks to 20
	ARROW = 2512, -- stacks to 200
	JUNK = 3000, -- grey, stacks to 10
	RUSTY = 3001, -- grey gear
}

local function DefineItems(world)
	local items = Loader.ITEMS
	world:DefineItem(items.SWORD, { name = "Sword", quality = 2, sellPrice = 500 })
	world:DefineItem(items.RING, { name = "Ring", quality = 3, sellPrice = 900 })
	world:DefineItem(items.LINEN, { name = "Linen Cloth", maxStack = 20, sellPrice = 13 })
	world:DefineItem(items.ARROW, { name = "Arrow", maxStack = 200, sellPrice = 1 })
	world:DefineItem(items.JUNK, { name = "Broken Fang", maxStack = 10, quality = 0, sellPrice = 40 })
	world:DefineItem(items.RUSTY, { name = "Rusty Blade", quality = 0, sellPrice = 75 })
end

local function RunFile(path, env, addonName, ns)
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk(addonName, ns)
end

--- Creates a world, loads every addon file into it and returns world, ns.
---@param options table? world options (saved, player, behavior, ellesmere, autoSeller, ...)
function Loader.Load(options)
	options = options or {}
	local world = Wow.NewWorld(options)
	Loader.created[#Loader.created + 1] = world
	local env = Wow.CreateEnvironment(world)
	Inventory.Install(world, env)
	DefineItems(world)
	Blizzard.Install(world, env)
	Addons.Install(world, env)
	if options.configure then
		options.configure(world, env)
	end
	world:CaptureBaseline()
	if options.saved then
		env.ItemLockForeverDB = Wow.RoundTrip(options.saved.ItemLockForeverDB)
	end
	local ns = {}
	for _, file in ipairs(Loader.TocFiles()) do
		RunFile(ADDON_DIR .. "/" .. file, env, Loader.ADDON, ns)
	end
	world.loadedAddons[Loader.ADDON] = true
	world.ns = ns
	return world, ns
end

--- Loads the addon and plays the login sequence.
function Loader.Boot(options)
	options = options or {}
	local world, ns = Loader.Load(options)
	world:Fire("ADDON_LOADED", Loader.ADDON)
	world:Fire("PLAYER_LOGIN")
	world:Fire("PLAYER_ENTERING_WORLD", true, false)
	world:Advance(1)
	return world, ns
end
Loader.Setup = Loader.Boot

--- Logs out, writes the saved variables through a serialization round trip, then logs in again
--- (as another character with { player = { guid = ... } }).
function Loader.Restart(world, restartOptions)
	world:Fire("PLAYER_LOGOUT")
	local options = {}
	for key, value in pairs(world.options) do
		options[key] = value
	end
	for key, value in pairs(restartOptions or {}) do
		options[key] = value
	end
	options.saved = { ItemLockForeverDB = world.env.ItemLockForeverDB }
	return Loader.Boot(options)
end

function Loader.LeakedGlobals(world)
	return world:LeakedGlobals(ALLOWED_GLOBALS)
end

--- Keys the addon wrote onto a Blizzard or EllesmereUI button.
Loader.ForeignKeys = Blizzard.ForeignKeys

return Loader
