-- The tooltip lines and the padlocks on Blizzard's and EllesmereUI's item buttons.
local ITEMS = Harness.ITEMS
local Addons = Harness.Addons
local LOCKED_LINE = "|A:QuestSharing-Padlock:14:14|a Locked: can't be sold, destroyed or disenchanted"

local function Badge(button)
	local owner = button._textOverlay or button
	for _, region in ipairs(owner.regions or {}) do
		if region.atlas == "QuestSharing-Padlock" then
			return region
		end
	end
	return nil
end

local function HasBadge(button)
	local badge = Badge(button)
	return badge ~= nil and badge.shown == true
end

describe("Tooltip", function()
	it("adds the Locked lines to locked items, gear and stacks", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, linenAt = world:Give(ITEMS.LINEN, { count = 2 })
		local _, ringAt = world:Give(ITEMS.RING)
		ns.Locks.Toggle(swordAt)
		ns.Locks.Toggle(linenAt)
		world:Hover(swordAt)
		expect(world:TooltipText()).toEqual({ LOCKED_LINE, "Alt+Click to unlock" })
		world:Hover(linenAt)
		expect(world:TooltipText()).toEqual({ LOCKED_LINE, "Alt+Click to unlock" })
		world:Hover(ringAt)
		expect(world:TooltipText()).toEqual({})
		expect(world.violations).toEqual({})
	end)

	it("shows how to unlock with the chosen click or the bound key", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		ns.Locks.Toggle(swordAt)
		ns.Database.Set("click", "CTRL-RightButton")
		world:Hover(swordAt)
		expect(world:TooltipText()[2]).toBe("Ctrl+Right-Click to unlock")
		ns.Database.Set("click", "NONE")
		world.boundKeys.ITEMLOCKFOREVER_TOGGLE = "L"
		world:Hover(swordAt)
		expect(world:TooltipText()[2]).toBe("<L> to unlock")
		ns.Database.Set("holdToUnlock", true)
		world:Hover(swordAt)
		expect(world:TooltipText()[2]).toBe("Hold <L> to unlock")
		ns.Database.Set("click", "ALT-LeftButton")
		world:Hover(swordAt)
		expect(world:TooltipText()[2]).toBe("Hold Alt+Click to unlock")
		ns.Database.Set("click", "NONE")
		world.boundKeys.ITEMLOCKFOREVER_TOGGLE = nil
		world:Hover(swordAt)
		expect(world:TooltipText()).toEqual({ LOCKED_LINE })
	end)

	it("falls back to the tooltip's slot when its data has no GUID", function()
		local world, ns = Harness.Setup({ behavior = { tooltipGUID = false } })
		local _, wornAt = world:Equip(2, ITEMS.RING)
		ns.Locks.Toggle(wornAt)
		world:Hover(wornAt)
		expect(world:TooltipText()[1]).toBe(LOCKED_LINE)
	end)

	it("stays quiet for links, other tooltips and another character's stack locks", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, linenAt = world:Give(ITEMS.LINEN, { count = 2 })
		ns.Locks.Toggle(swordAt)
		ns.Locks.Toggle(linenAt, "all")
		-- An item link: no GUID and no slot.
		local tooltip = world.env.GameTooltip
		tooltip.lines = {}
		for _, postCall in ipairs(world.tooltipPostCalls) do
			postCall.callback(tooltip, { type = 0, id = ITEMS.SWORD })
			postCall.callback(tooltip, nil)
		end
		expect(#tooltip.lines).toBe(0)
		local alt = Harness.Restart(world, { player = { guid = "Player-1-0000BBBB" } })
		local _, altLinen = alt:Give(ITEMS.LINEN, { count = 2 })
		alt:Hover(altLinen)
		expect(alt:TooltipText()).toEqual({})
	end)
end)

describe("Padlocks", function()
	it("marks locked items in Blizzard's bags and follows pooled buttons", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		world:Give(ITEMS.RING)
		ns.Locks.Toggle(swordAt)
		local buttons = world:ShowBag(0)
		expect(HasBadge(buttons[1])).toBe(true)
		expect(HasBadge(buttons[2])).toBe(false)
		world:Move(swordAt, 0, 5)
		buttons = world:ShowBag(0)
		expect(HasBadge(buttons[1])).toBe(false)
		expect(HasBadge(buttons[5])).toBe(true)
		local badge = Badge(buttons[5])
		expect(badge.width).toBe(14)
		expect(badge.points[1][1]).toBe("TOPRIGHT")
	end)

	it("marks locked items in the combined bags, the bank and the character window", function()
		local world, ns = Harness.Setup()
		world.bags[1].size = 4
		world.bags[6].size = 6
		local _, linenAt = world:Give(ITEMS.LINEN, { bag = 1, slot = 2, count = 4 })
		local _, bankAt = world:Give(ITEMS.SWORD, { bag = 6, slot = 3 })
		local _, wornAt = world:Equip(11, ITEMS.RING)
		ns.Locks.Toggle(linenAt)
		ns.Locks.Toggle(bankAt)
		ns.Locks.Toggle(wornAt)
		local combined = world:ShowCombinedBags()
		local marked = {}
		for _, button in ipairs(combined) do
			if HasBadge(button) then
				marked[#marked + 1] = button.bagID .. ":" .. button.id
			end
		end
		expect(marked).toEqual({ "1:2" })
		local bank = world:ShowBank()
		expect(HasBadge(bank[3])).toBe(true)
		expect(HasBadge(bank[2])).toBe(false)
		local slots = world:ShowCharacter()
		expect(HasBadge(slots[11])).toBe(true)
		expect(HasBadge(slots[12])).toBe(false)
	end)

	it("marks EllesmereUI Bags slots on its overlay frame", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		ns.Locks.Toggle(swordAt)
		local button = Addons.NewEllesmereButton(world)
		Addons.PaintEllesmere(world, button, 0, swordAt.slotIndex)
		expect(HasBadge(button)).toBe(true)
		expect(Badge(button).points[1][2]).toBe(button)
		Addons.PaintEllesmerePlaceholder(world, button)
		expect(HasBadge(button)).toBe(false)
		Addons.PaintEllesmere(world, button, 0, 9)
		expect(HasBadge(button)).toBe(false)
		Addons.PaintEllesmere(world, button, 0, swordAt.slotIndex)
		expect(HasBadge(button)).toBe(true)
	end)

	it("marks an EllesmereUI combined stack when any of its stacks is locked", function()
		local world, ns = Harness.Setup()
		local _, first = world:Give(ITEMS.LINEN, { count = 4 })
		local _, second = world:Give(ITEMS.LINEN, { count = 9 })
		local combined = Addons.NewEllesmereButton(world)
		Addons.PaintEllesmere(world, combined, 0, first.slotIndex, 13)
		expect(HasBadge(combined)).toBe(false)
		ns.Locks.Toggle(second)
		expect(HasBadge(combined)).toBe(true)
		ns.Locks.Toggle(second)
		expect(HasBadge(combined)).toBe(false)
		ns.Locks.Toggle(first, "all")
		expect(HasBadge(combined)).toBe(true)
	end)

	it("updates padlocks on screen when a lock changes, without calling Blizzard", function()
		local world = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		local buttons = world:ShowBag(0)
		local eui = Addons.NewEllesmereButton(world)
		Addons.PaintEllesmere(world, eui, 0, swordAt.slotIndex)
		world:ModifiedClick(swordAt, "LeftButton", { alt = true })
		expect(HasBadge(buttons[1])).toBe(true)
		expect(HasBadge(eui)).toBe(true)
		world:Advance(1)
		world:ModifiedClick(swordAt, "LeftButton", { alt = true })
		expect(HasBadge(buttons[1])).toBe(false)
		expect(HasBadge(eui)).toBe(false)
		expect(world.violations).toEqual({})
	end)

	it("writes nothing onto Blizzard's or EllesmereUI's buttons", function()
		local world, ns = Harness.Setup()
		world.bags[6].size = 2
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, bankAt = world:Give(ITEMS.RING, { bag = 6, slot = 1 })
		local _, wornAt = world:Equip(1, ITEMS.RING)
		for _, location in ipairs({ swordAt, bankAt, wornAt }) do
			ns.Locks.Toggle(location)
		end
		local buttons = {}
		for _, button in ipairs(world:ShowBag(0)) do
			buttons[#buttons + 1] = button
		end
		for _, button in ipairs(world:ShowCombinedBags()) do
			buttons[#buttons + 1] = button
		end
		for _, button in ipairs(world:ShowBank()) do
			buttons[#buttons + 1] = button
		end
		for slot = 0, 19 do
			buttons[#buttons + 1] = world:ShowCharacter()[slot]
		end
		local eui = Addons.NewEllesmereButton(world)
		Addons.PaintEllesmere(world, eui, 0, swordAt.slotIndex)
		buttons[#buttons + 1] = eui
		world:ModifiedClick(swordAt, "LeftButton", { alt = true })
		for _, button in ipairs(buttons) do
			expect(Harness.ForeignKeys(button)).toEqual({})
		end
	end)

	it("moves and resizes every padlock when the corner or size changes", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, ringAt = world:Give(ITEMS.RING)
		ns.Locks.Toggle(swordAt)
		local buttons = world:ShowBag(0)
		local eui = Addons.NewEllesmereButton(world)
		Addons.PaintEllesmere(world, eui, 0, swordAt.slotIndex)
		ns.Database.Set("iconCorner", "BOTTOMLEFT")
		ns.Database.Set("iconSize", 20)
		for _, button in ipairs({ buttons[1], eui }) do
			local badge = Badge(button)
			expect(badge.width).toBe(20)
			expect(badge.height).toBe(20)
			expect(badge.points).toEqual({ { "BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1 } })
		end
		-- Padlocks drawn later use the new settings too.
		ns.Database.Set("iconCorner", "BOTTOMRIGHT")
		ns.Locks.Toggle(ringAt)
		buttons = world:ShowBag(0)
		expect(Badge(buttons[2]).points).toEqual({ { "BOTTOMRIGHT", buttons[2], "BOTTOMRIGHT", -1, 1 } })
		expect(Badge(buttons[2]).width).toBe(20)
		expect(world.violations).toEqual({})
	end)

	it("works without EllesmereUI Bags", function()
		local world, ns = Harness.Setup({ ellesmere = false })
		local _, swordAt = world:Give(ITEMS.SWORD)
		ns.Locks.Toggle(swordAt)
		expect(HasBadge(world:ShowBag(0)[1])).toBe(true)
		expect(#world.errors).toBe(0)
	end)
end)
