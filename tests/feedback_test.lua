-- Feedback: red error text and the error sound when something tries to sell, disenchant or destroy
-- a locked item.
local ITEMS = Harness.ITEMS
local DISENCHANT = 13262
local ERROR = 47355
local SWORD_LINK = "|cffffffff|Hitem:2000::::::::|h[Sword]|h|r"

local function Locked(world, ns)
	local _, swordAt = world:Give(ITEMS.SWORD)
	ns.Locks.Toggle(swordAt)
	world.sounds = {}
	return swordAt
end

describe("Feedback", function()
	it("says a locked item can't be sold when you right-click it at a vendor", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		world:OpenMerchant()
		world:RightClick(swordAt)
		world:Advance(2)
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be sold." })
		expect(world.sounds).toEqual({ ERROR })
		expect(world:ItemAt(swordAt)).toBeTruthy()
	end)

	it("says a locked item can't be disenchanted when you pick it", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		world:StartTargeting(DISENCHANT)
		world:TargetItem(swordAt)
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be disenchanted." })
		expect(world.sounds).toEqual({ ERROR })
		-- At a vendor, picking an item for Disenchant still counts as disenchanting.
		world:CancelTargeting()
		world:OpenMerchant()
		world:StartTargeting(DISENCHANT)
		world:Advance(1)
		world:TargetItem(swordAt)
		expect(world.uiErrors[2]).toBe(SWORD_LINK .. " is locked, so it can't be disenchanted.")
	end)

	it("says a locked item can't be destroyed, with the sound", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		world:DragToWorld(swordAt)
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be destroyed." })
		expect(world.sounds).toEqual({ ERROR })
	end)

	it("plays the chosen sound, or none, and still shows the text", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		ns.Database.Set("errorSound", "alarm")
		world.sounds = {}
		world:DragToWorld(swordAt)
		expect(world.sounds).toEqual({ 12889 })
		ns.Database.Set("errorSound", "none")
		world.sounds = {}
		world:Advance(1)
		world:DragToWorld(swordAt)
		expect(world.sounds).toEqual({})
		expect(#world.uiErrors).toBe(2)
	end)

	it("plays one sound for a burst of attempts", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		local _, ringAt = world:Give(ITEMS.RING)
		ns.Locks.Toggle(ringAt)
		world.sounds = {}
		world:OpenMerchant()
		world:RightClick(swordAt)
		world:RightClick(ringAt)
		expect(world.sounds).toEqual({ ERROR })
		expect(#world.uiErrors).toBe(2)
		world:Advance(1)
		world:RightClick(swordAt)
		expect(world.sounds).toEqual({ ERROR, ERROR })
	end)

	it("doesn't claim a sale was stopped when the item couldn't be held", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		world:PickUp(swordAt)
		world:OpenMerchant()
		world.env.ClearCursor()
		world:RightClick(swordAt)
		world:Advance(5)
		expect(world.uiErrors).toEqual({})
		expect(world:Output()).toContain("was bought back")
	end)

	it("stays quiet when locked or unlocked items are simply used", function()
		local world, ns = Harness.Setup()
		local swordAt = Locked(world, ns)
		local _, ringAt = world:Give(ITEMS.RING)
		world:RightClick(swordAt)
		world:OpenMerchant()
		world:RightClick(ringAt)
		world:Advance(2)
		expect(world.uiErrors).toEqual({})
		expect(world.sounds).toEqual({})
	end)

	it("plays the error sound when the vendor backstop buys a locked item back", function()
		local world, ns = Harness.Setup({ autoSeller = "sellAllJunk" })
		local _, rustyAt = world:Give(ITEMS.RUSTY)
		ns.Locks.Toggle(rustyAt)
		world.sounds = {}
		world:OpenMerchant()
		world:Advance(5)
		expect(world:Output()).toContain("was bought back")
		expect(world.sounds).toEqual({ ERROR })
	end)
end)
