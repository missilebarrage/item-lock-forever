-- Performance: bag scans, padlocks and tooltips answer from item IDs and only look up an item's
-- GUID when a gear lock uses its item ID.

local function FullBags(world)
	for bagID = 0, 4 do
		world.bags[bagID].size = 36
		for slot = 1, 36 do
			world:Give(5000 + bagID * 36 + slot, { bag = bagID, slot = slot })
		end
	end
end

local function ManyLocks()
	local items = {}
	for index = 1, 2000 do
		items[string.format("Item-1-0-F%07X", index)] = 90000 + index
	end
	return { schema = 1, settings = {}, items = items, stacks = {} }
end

describe("Performance", function()
	it("looks up no GUIDs for 180 slots when 2000 gear locks are on other items", function()
		local world = Harness.Setup({ saved = { ItemLockForeverDB = ManyLocks() } })
		FullBags(world)
		world:ShowCombinedBags()
		for bagID = 0, 4 do
			world:ShowBag(bagID)
		end
		local eui = Harness.Addons.NewEllesmereButton(world)
		for bagID = 0, 4 do
			for slot = 1, 36 do
				Harness.Addons.PaintEllesmere(world, eui, bagID, slot)
				world:Hover(Harness.Inventory.BagLocation(bagID, slot))
			end
		end
		world:OpenMerchant()
		world:Fire("BAG_UPDATE_DELAYED")
		world:Advance(1)
		expect(world.calls.GetItemGUID).toBe(0)
		expect(world.calls.LockItem).toBe(0)
	end)

	it("looks up GUIDs only for copies of locked gear", function()
		local saved = ManyLocks()
		local world, ns = Harness.Setup({ saved = { ItemLockForeverDB = saved } })
		FullBags(world)
		local copy = world:Give(5001, { bag = 0, slot = 1 })
		ns.Locks.Toggle(Harness.Inventory.BagLocation(0, 1))
		world.calls.GetItemGUID = 0
		world:ShowCombinedBags()
		expect(world.calls.GetItemGUID).toBe(1)
		expect(world.env.ItemLockForeverDB.items[copy.guid]).toBe(5001)
	end)
end)
