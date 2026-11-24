-- The list of locked items: its own page under the options, a row for every lock with an Unlock
-- button, and the ways to open it.
local ITEMS = Harness.ITEMS
local UNLOCK_SOUND = 8938 -- Key ring, the default unlock sound
local SWORD_LINK = "|cffffffff|Hitem:2000::::::::|h[Sword]|h|r"
local ARROW_LINK = "|cffffffff|Hitem:2512::::::::|h[Arrow]|h|r"
local RING_LINK = "|cffffffff|Hitem:2001::::::::|h[Ring]|h|r"
local FANG_LINK = "|cffffffff|Hitem:3000::::::::|h[Broken Fang]|h|r"

local function Lock(ns, location, view)
	expect(ns.Locks.Toggle(location, view)).toBe(true)
end

-- The panel shows the page when it's picked.
local function Open(ns)
	ns.LockedItems.Page():Show()
end

-- "label | detail" for each row on the page, in order.
local function Shown(ns)
	local list = {}
	for _, row in ipairs(ns.LockedItems.Rows()) do
		if row.shown and row.entry then
			list[#list + 1] = row.label:GetText() .. " | " .. row.detail:GetText()
		end
	end
	return list
end

local function RowFor(ns, text)
	for _, row in ipairs(ns.LockedItems.Rows()) do
		if row.shown and row.entry and row.label:GetText() == text then
			return row
		end
	end
	return nil
end

-- A locked item that left this character (mailed to an alt): its lock stays.
local function LockElsewhere(world, ns, itemID)
	local item, location = world:Give(itemID)
	Lock(ns, location)
	world.bags[location.bagID][location.slotIndex] = nil
	return item
end

describe("Locked items list", function()
	it("lists every lock: every-stack locks, then items in the bags, worn, in the bank and elsewhere", function()
		local world, ns = Harness.Setup()
		local _, linenAt = world:Give(ITEMS.LINEN, { count = 4 })
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, arrowAt = world:Give(ITEMS.ARROW, { count = 50 })
		local _, ringAt = world:Equip(11, ITEMS.RING)
		local _, fangAt = world:Give(ITEMS.JUNK, { bag = 6, slot = 1, count = 3 })
		Lock(ns, linenAt, "all")
		Lock(ns, swordAt)
		Lock(ns, arrowAt)
		Lock(ns, ringAt)
		Lock(ns, fangAt)
		LockElsewhere(world, ns, ITEMS.RUSTY)
		Open(ns)
		expect(Shown(ns)).toEqual({
			"[Linen Cloth] | Every stack (this character)",
			ARROW_LINK .. " | Bags, stack of 50",
			SWORD_LINK .. " | Bags",
			RING_LINK .. " | Worn",
			FANG_LINK .. " | Bank, stack of 3",
			"[Rusty Blade] | Elsewhere",
		})
		expect(ns.LockedItems.Summary()).toBe("6 locks")
		-- A name without a link takes its quality's color (grey here); links carry their own.
		expect(RowFor(ns, "[Rusty Blade]").label.textColor).toEqual({ 0.62, 0.62, 0.62 })
		expect(RowFor(ns, SWORD_LINK).label.textColor).toEqual({ 1, 1, 1 })
		expect(RowFor(ns, SWORD_LINK).icon.texture).toBe(100000 + ITEMS.SWORD)
	end)

	it("says when nothing is locked", function()
		local _, ns = Harness.Setup()
		Open(ns)
		expect(ns.LockedItems.Summary()).toBe("Nothing is locked yet.")
		expect(Shown(ns)).toEqual({})
	end)

	it("unlocks from the list, with the unlock sound, and the row goes", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		local _, ringAt = world:Give(ITEMS.RING)
		Lock(ns, swordAt)
		Lock(ns, ringAt)
		Open(ns)
		world.sounds = {}
		RowFor(ns, SWORD_LINK).unlockButton:Click()
		expect(ns.Locks.IsLockedAt(swordAt)).toBe(false)
		expect(ns.Locks.IsLockedAt(ringAt)).toBe(true)
		expect(world.sounds).toEqual({ UNLOCK_SOUND })
		world:Advance(0)
		expect(Shown(ns)).toEqual({ RING_LINK .. " | Bags" })
		expect(ns.LockedItems.Summary()).toBe("1 lock")
	end)

	it("unlocks an item that isn't on this character", function()
		local world, ns = Harness.Setup()
		local blade = LockElsewhere(world, ns, ITEMS.RUSTY)
		Open(ns)
		RowFor(ns, "[Rusty Blade]").unlockButton:Click()
		world:Advance(0)
		expect(Shown(ns)).toEqual({})
		-- If it comes back, it's unlocked.
		local _, back = world:Give(ITEMS.RUSTY, { guid = blade.guid })
		expect(ns.Locks.IsLockedAt(back)).toBe(false)
	end)

	it("unlocks every stack from an every-stack row, stacks picked up later included", function()
		local world, ns = Harness.Setup()
		local _, firstAt = world:Give(ITEMS.LINEN, { count = 4 })
		local _, secondAt = world:Give(ITEMS.LINEN, { count = 6 })
		Lock(ns, firstAt, "all")
		expect(ns.Locks.Toggle(secondAt)).toBe(false) -- this stack unlocked on its own
		Open(ns)
		RowFor(ns, "[Linen Cloth]").unlockButton:Click()
		expect(ns.Locks.IsLockedAt(firstAt)).toBe(false)
		expect(ns.Locks.IsLockedAt(secondAt)).toBe(false)
		local _, laterAt = world:Give(ITEMS.LINEN, { count = 2 })
		expect(ns.Locks.IsLockedAt(laterAt)).toBe(false)
		world:Advance(0)
		expect(Shown(ns)).toEqual({})
	end)

	it("shows an item's number until the game has loaded it, then its name", function()
		local world, ns = Harness.Setup()
		LockElsewhere(world, ns, ITEMS.RUSTY)
		world.uncachedItems[ITEMS.RUSTY] = true
		Open(ns)
		expect(Shown(ns)).toEqual({ "Item 3001 | Elsewhere" })
		expect(world.itemRequests).toEqual({ ITEMS.RUSTY })
		world:Advance(0.1)
		expect(Shown(ns)).toEqual({ "[Rusty Blade] | Elsewhere" })
	end)

	it("shows the item in the tooltip: the item itself when it's here, else the item type", function()
		local world, ns = Harness.Setup()
		local sword, swordAt = world:Give(ITEMS.SWORD)
		Lock(ns, swordAt)
		LockElsewhere(world, ns, ITEMS.RUSTY)
		Open(ns)
		local tooltip = world.env.GameTooltip
		local row = RowFor(ns, SWORD_LINK)
		row.scripts.OnEnter(row)
		expect(tooltip.shownItem).toEqual({ guid = sword.guid })
		row = RowFor(ns, "[Rusty Blade]")
		row.scripts.OnEnter(row)
		expect(tooltip.shownItem).toEqual({ itemID = ITEMS.RUSTY })
		row.scripts.OnLeave(row)
		expect(tooltip.shown).toBe(false)
	end)

	it("only rebuilds while the page is shown", function()
		local world, ns = Harness.Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		Open(ns)
		ns.LockedItems.Page():Hide()
		Lock(ns, swordAt)
		world:Advance(0)
		expect(ns.LockedItems.Summary()).toBe("Nothing is locked yet.")
		Open(ns)
		expect(ns.LockedItems.Summary()).toBe("1 lock")
	end)

	it("can't unlock locks saved by a newer version", function()
		local saved = { schema = 99, settings = {}, items = { ["Item-1-0-0000BEEF"] = ITEMS.SWORD }, stacks = {} }
		local world, ns = Harness.Setup({ saved = { ItemLockForeverDB = saved } })
		Open(ns)
		local row = RowFor(ns, "[Sword]")
		expect(row.unlockButton:IsEnabled()).toBe(false)
		expect(ns.Locks.UnlockItem("Item-1-0-0000BEEF")).toBe(false)
		expect(world.env.ItemLockForeverDB.items["Item-1-0-0000BEEF"]).toBe(ITEMS.SWORD)
	end)

	it("opens from the options' first row and with /ilf list, out of combat only", function()
		local world = Harness.Setup()
		local category = world.settingsCategories[1]
		expect(category.subcategories[1].name).toBe("Locked items")
		local button = category.initializers[1]
		expect(button.name).toBe("Locked items")
		expect(button.buttonText).toBe("Show list")
		button.click()
		world.env.SlashCmdList.ITEMLOCKFOREVER("list")
		expect(world.openedSettings).toEqual({ 78, 78 })
		world.combat = true
		world.env.SlashCmdList.ITEMLOCKFOREVER("list")
		expect(#world.openedSettings).toBe(2)
		expect(world:Output()).toContain("combat")
	end)
end)
