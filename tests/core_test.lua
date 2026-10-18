-- Core: loading, saved variables, the options page and the slash command.
local ITEMS = Harness.ITEMS

describe("Loading", function()
	it("loads every TOC file without errors or leaked globals", function()
		local world = Harness.Boot()
		expect(#world.errors).toBe(0)
		expect(Harness.LeakedGlobals(world)).toEqual({})
		expect(world.violations).toEqual({})
	end)

	it("lists exactly the files that exist", function()
		for _, file in ipairs(Harness.TocFiles()) do
			local handle = io.open(ROOT_DIR .. "/ItemLockForever/" .. file, "r")
			expect(handle ~= nil).toBe(true)
			if handle then
				handle:close()
			end
		end
	end)

	it("declares the metadata the client and the packager need", function()
		local toc = Harness.TocMetadata()
		expect(toc.Interface).toBe("16001")
		expect(toc.Title).toBe("ItemLockForever")
		expect(toc.Author).toBe("Tim")
		expect(toc.SavedVariables).toBe("ItemLockForeverDB")
		expect(toc.IconAtlas).toBe("QuestSharing-Padlock")
		expect(toc.Version).toBe("@project-version@")
		expect(toc["X-Curse-Project-ID"]).toBe("1751300")
	end)

	it("binds the key binding to the global the addon defines", function()
		local world = Harness.Boot()
		local bindings = Harness.ReadAddonFile("Bindings.xml")
		expect(bindings).toContain('name="ITEMLOCKFOREVER_TOGGLE"')
		expect(bindings).toContain('runOnUp="true"')
		expect(bindings).toContain("ItemLockForever_ToggleHovered(keystate)")
		expect(type(world.env.ItemLockForever_ToggleHovered)).toBe("function")
		expect(world.env.BINDING_NAME_ITEMLOCKFOREVER_TOGGLE).toBe("Lock/unlock hovered item")
	end)

	it("opens the options with /ilf and /itemlock, out of combat only", function()
		local world = Harness.Boot()
		expect(world.env.SLASH_ITEMLOCKFOREVER1).toBe("/ilf")
		expect(world.env.SLASH_ITEMLOCKFOREVER2).toBe("/itemlock")
		world.env.SlashCmdList.ITEMLOCKFOREVER("")
		expect(world.openedSettings).toEqual({ 77 })
		world.combat = true
		world.env.SlashCmdList.ITEMLOCKFOREVER("")
		expect(#world.openedSettings).toBe(1)
		expect(world:Output()).toContain("combat")
	end)

	it("toggles diagnostics with /ilf debug", function()
		local world, ns = Harness.Boot()
		world.env.SlashCmdList.ITEMLOCKFOREVER(" debug ")
		expect(ns.debug).toBe(true)
		world.env.SlashCmdList.ITEMLOCKFOREVER("DEBUG")
		expect(ns.debug).toBe(false)
		expect(#world.openedSettings).toBe(0)
	end)
end)

describe("Database", function()
	it("creates the saved variables with defaults", function()
		local world, ns = Harness.Boot()
		local db = world.env.ItemLockForeverDB
		expect(db.schema).toBe(ns.SCHEMA)
		expect(db.settings).toEqual({
			click = "ALT-LeftButton",
			holdToUnlock = false,
			lockSound = "vault",
			unlockSound = "keys",
			errorSound = "error",
			iconCorner = "TOPRIGHT",
			iconSize = 14,
		})
		expect(db.items).toEqual({})
		expect(type(db.stacks)).toBe("table")
	end)

	it("repairs invalid settings, drops unknown ones and damaged locks", function()
		local world = Harness.Boot({
			saved = {
				ItemLockForeverDB = {
					schema = 1,
					settings = {
						click = "SHIFT-LeftButton",
						lockSound = "gong",
						unlockSound = "chain",
						iconCorner = "MIDDLE",
						iconSize = 12.5,
						removed = true,
					},
					items = { ["Item-1-0-00000001"] = 2000, [5] = 2000, ["Item-1-0-00000002"] = "x" },
					stacks = { ["Player-1-0000AAAA"] = { [2589] = true, [2590] = "yes" }, [7] = {}, bad = 3 },
				},
			},
		})
		local db = world.env.ItemLockForeverDB
		expect(db.settings).toEqual({
			click = "ALT-LeftButton",
			holdToUnlock = false,
			lockSound = "vault",
			unlockSound = "chain",
			errorSound = "error",
			iconCorner = "TOPRIGHT",
			iconSize = 14,
		})
		expect(db.items).toEqual({ ["Item-1-0-00000001"] = 2000 })
		expect(db.stacks).toEqual({ ["Player-1-0000AAAA"] = { [2589] = true } })
	end)

	it("starts over when the saved variable isn't a table", function()
		local world = Harness.Boot({ saved = { ItemLockForeverDB = "broken" } })
		expect(world.env.ItemLockForeverDB.settings.click).toBe("ALT-LeftButton")
	end)

	it("keeps protecting with locks from a newer version, without changing them", function()
		local saved = {
			schema = 99,
			settings = { click = "CTRL-RightButton" },
			items = { ["Item-1-0-0000BEEF"] = ITEMS.SWORD },
			stacks = {},
			future = { kept = true },
		}
		local world, ns = Harness.Setup({ saved = { ItemLockForeverDB = saved } })
		expect(ns.Database.IsReadOnly()).toBe(true)
		expect(world:Output()).toContain("newer version")
		local _, location = world:Give(ITEMS.SWORD, { guid = "Item-1-0-0000BEEF" })
		expect(ns.Locks.IsLockedAt(location)).toBe(true)
		expect(ns.Database.Get("click")).toBe("CTRL-RightButton")
		-- Toggling is refused, so the lock can't be lost.
		world:ModifiedClick(location, "RightButton", { ctrl = true })
		expect(ns.Locks.IsLockedAt(location)).toBe(true)
		expect(world:Output()).toContain("can't be changed")
		local db = world.env.ItemLockForeverDB
		expect(db.schema).toBe(99)
		expect(db.future.kept).toBe(true)
		expect(db.stacks).toEqual({})
	end)

	it("refuses invalid values and signals changes", function()
		local _, ns = Harness.Boot()
		local seen = {}
		ns.Events.On("ILF_SETTINGS_CHANGED", function(key, value)
			seen[#seen + 1] = key .. "=" .. tostring(value)
		end)
		expect(ns.Database.Set("click", "SHIFT-LeftButton")).toBe(false)
		expect(ns.Database.Set("click", 3)).toBe(false)
		expect(ns.Database.Set("unknown", true)).toBe(false)
		expect(ns.Database.Set("click", "NONE")).toBe(true)
		expect(ns.Database.Set("click", "NONE")).toBe(true)
		expect(ns.Database.Set("iconSize", 7)).toBe(false)
		expect(ns.Database.Set("iconSize", 33)).toBe(false)
		expect(ns.Database.Set("iconSize", "big")).toBe(false)
		expect(ns.Database.Set("iconSize", 19.6)).toBe(true)
		expect(ns.Database.Get("iconSize")).toBe(20)
		expect(seen).toEqual({ "click=NONE", "iconSize=20" })
	end)

	it("survives a save and reload, dropping characters without stack locks", function()
		local world, ns = Harness.Boot()
		ns.Database.Set("click", "ALT-RightButton")
		local other = Harness.Restart(world, { player = { guid = "Player-1-0000BBBB" } })
		local db = other.env.ItemLockForeverDB
		expect(db.settings.click).toBe("ALT-RightButton")
		Harness.Restart(other)
		expect(db.stacks["Player-1-0000AAAA"]).toBeNil()
		expect(other.env.ItemLockForeverDB.stacks["Player-1-0000BBBB"]).toBeNil()
	end)
end)

describe("Options", function()
	local function Category(world)
		return world.settingsCategories[1]
	end

	it("registers ItemLockForever under AddOns with the click dropdown and the key binding", function()
		local world = Harness.Boot()
		local category = Category(world)
		expect(category.name).toBe("ItemLockForever")
		expect(category.registered).toBe(true)
		local click = category.settings.click
		expect(click.control).toBe("dropdown")
		expect(click.default).toBe("ALT-LeftButton")
		local labels = {}
		for _, option in ipairs(click.getOptions()) do
			labels[#labels + 1] = option.value .. "=" .. option.label
		end
		expect(labels).toEqual({
			"ALT-LeftButton=Alt + Left Click",
			"ALT-RightButton=Alt + Right Click",
			"CTRL-ALT-RightButton=Ctrl + Alt + Right Click",
			"CTRL-RightButton=Ctrl + Right Click",
			"NONE=Off (key binding only)",
		})
		local binding = category.initializers[1]
		expect(binding.kind).toBe("keybinding")
		expect(binding.bindingIndex).toBe(412)
		expect(binding.tags).toEqual({ "Lock/unlock hovered item" })
	end)

	it("keeps the dropdown and the saved setting in sync", function()
		local world, ns = Harness.Boot()
		local click = Category(world).settings.click
		click:SetValue("CTRL-RightButton")
		expect(ns.Database.Get("click")).toBe("CTRL-RightButton")
		expect(click:GetValue()).toBe("CTRL-RightButton")
		local before = click.notified or 0
		ns.Database.Set("click", "NONE")
		expect(click.notified).toBe(before + 1)
		click:SetValue("not a combo")
		expect(ns.Database.Get("click")).toBe("NONE")
	end)

	it("leaves the key binding row out when the client doesn't know the binding", function()
		local world = Harness.Boot({
			configure = function(w)
				w.bindingActions = {}
			end,
		})
		expect(#Category(world).initializers).toBe(0)
		expect(Category(world).settings.click).toBeTruthy()
	end)

	it("offers the same sounds for locking and unlocking, None first", function()
		local world = Harness.Boot()
		local settings = Category(world).settings
		expect(settings.lockSound.default).toBe("vault")
		expect(settings.unlockSound.default).toBe("keys")
		for _, key in ipairs({ "lockSound", "unlockSound" }) do
			local labels = {}
			for _, option in ipairs(settings[key].getOptions()) do
				labels[#labels + 1] = option.value .. "=" .. option.label
			end
			expect(labels).toEqual({
				"none=None",
				"lock=Lock",
				"unlock=Unlock",
				"keys=Key ring",
				"chain=Chain",
				"chest=Chest",
				"vault=Guild bank",
				"forge=Forge lock",
				"click=Click",
				"coins=Coins",
				"gems=Gems",
				"ping=Map ping",
			})
		end
	end)

	it("plays a sound when you pick it, and nothing for None", function()
		local world = Harness.Boot()
		local settings = Category(world).settings
		settings.lockSound:SetValue("keys")
		world:Advance(1)
		settings.unlockSound:SetValue("chain")
		world:Advance(1)
		settings.unlockSound:SetValue("none")
		settings.lockSound:SetValue("not a sound")
		expect(world.sounds).toEqual({ 8938, 1212 })
		expect(settings.lockSound:GetValue()).toBe("keys")
		expect(settings.unlockSound:GetValue()).toBe("none")
		-- The Defaults button resets several sounds at once: one preview.
		world.sounds = {}
		world:Advance(1)
		settings.lockSound:SetValue("vault")
		settings.unlockSound:SetValue("keys")
		settings.errorSound:SetValue("alarm")
		expect(world.sounds).toEqual({ 12189 })
	end)

	it("offers Hold to unlock as a checkbox, off by default", function()
		local world, ns = Harness.Boot()
		local hold = Category(world).settings.holdToUnlock
		expect(hold.control).toBe("checkbox")
		expect(hold.default).toBe(false)
		hold:SetValue(true)
		expect(ns.Database.Get("holdToUnlock")).toBe(true)
	end)

	it("offers the padlock's corner and a size slider", function()
		local world = Harness.Boot()
		local settings = Category(world).settings
		local corners = {}
		for _, option in ipairs(settings.iconCorner.getOptions()) do
			corners[#corners + 1] = option.value .. "=" .. option.label
		end
		expect(corners).toEqual({
			"TOPLEFT=Top left",
			"TOPRIGHT=Top right",
			"BOTTOMLEFT=Bottom left",
			"BOTTOMRIGHT=Bottom right",
		})
		expect(settings.iconCorner.default).toBe("TOPRIGHT")
		local size = settings.iconSize
		expect(size.control).toBe("slider")
		expect(size.default).toBe(14)
		expect(size.options.minimum).toBe(8)
		expect(size.options.maximum).toBe(32)
		expect(size.options.step).toBe(1)
		expect(size.options.labelType).toBe(2)
		size:SetValue(23.9999)
		expect(size:GetValue()).toBe(24)
	end)

	it("gives every sound a different game sound", function()
		local world, ns = Harness.Boot()
		local seen = {}
		for _, list in ipairs({ ns.Database.SOUNDS, ns.Database.ERROR_SOUNDS }) do
			for _, sound in ipairs(list) do
				world.sounds = {}
				ns.Sounds.Play(sound[1])
				if sound[1] == "none" then
					expect(world.sounds).toEqual({})
				else
					expect(#world.sounds).toBe(1)
					expect(seen[world.sounds[1]]).toBeNil()
					seen[world.sounds[1]] = true
				end
			end
		end
	end)

	it("offers the error sound, None first, and plays it when picked", function()
		local world = Harness.Boot()
		local errorSound = Category(world).settings.errorSound
		expect(errorSound.default).toBe("error")
		local labels = {}
		for _, option in ipairs(errorSound.getOptions()) do
			labels[#labels + 1] = option.value .. "=" .. option.label
		end
		expect(labels).toEqual({
			"none=None",
			"error=Error",
			"denied=Denied",
			"decline=Decline",
			"invalid=Invalid",
			"warning=Warning",
			"abandon=Abandon",
			"blip=Blip",
			"raidWarning=Raid warning",
			"alarm=Alarm",
		})
		errorSound:SetValue("denied")
		expect(world.sounds).toEqual({ 17341 })
	end)
end)
