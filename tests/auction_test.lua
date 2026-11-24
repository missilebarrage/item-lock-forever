-- Auction House protection: a locked item, or one whose twin in the bags is locked, is taken out of
-- Blizzard's and Auctionator's sell slots before it can be posted.
local ITEMS = Harness.ITEMS
local Addons = Harness.Addons
local ERROR = 47355
local SWORD_LINK = "|cffffffff|Hitem:2000::::::::|h[Sword]|h|r"
local RING_LINK = "|cffffffff|Hitem:2001::::::::|h[Ring]|h|r"
local LINEN_LINK = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"

local function Lock(ns, location, view)
	expect(ns.Locks.Toggle(location, view)).toBe(true)
end

local function Unlock(ns, location)
	expect(ns.Locks.Toggle(location)).toBe(false)
end

-- The next frame: the check runs once the code that filled a sell slot has finished.
local function NextFrame(world)
	world:Advance(0)
end

describe("Auction House", function()
	local function Setup(options)
		local world, ns = Harness.Setup(options)
		world.sounds, world.uiErrors = {}, {}
		return world, ns
	end

	it("takes a locked item out of the sell slot before it can be posted", function()
		local world, ns = Setup()
		local sword, swordAt = world:Give(ITEMS.SWORD)
		local ring, ringAt = world:Give(ITEMS.RING)
		Lock(ns, swordAt)
		world.sounds = {}
		world:OpenAuctionHouse()
		local sell = world.env.AuctionHouseFrame.ItemSellFrame
		world:RightClick(swordAt)
		expect(sell:GetItem()).toBe(swordAt)
		NextFrame(world)
		expect(sell:GetItem()).toBeNil()
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be listed." })
		expect(world.sounds).toEqual({ ERROR })
		expect(world.holds[sword.guid]).toBeNil()
		expect(sell:PostItem()).toBe(false)
		-- An unlocked item stays and posts.
		world:RightClick(ringAt)
		NextFrame(world)
		expect(sell:GetItem()).toBe(ringAt)
		expect(sell:PostItem()).toBe(true)
		expect(world.posts).toEqual({ { itemID = ITEMS.RING, quantity = 1, guids = { ring.guid } } })
		expect(#world.uiErrors).toBe(1)
		expect(world.violations).toEqual({})
	end)

	it("won't list an item while another one of it in the bags is locked, since a post can take it too", function()
		local world, ns = Setup()
		local locked, lockedAt = world:Give(ITEMS.LINEN, { count = 9 })
		local free, freeAt = world:Give(ITEMS.LINEN, { count = 12 })
		Lock(ns, lockedAt)
		world:OpenAuctionHouse()
		local sell = world.env.AuctionHouseFrame.CommoditiesSellFrame
		world:RightClick(freeAt)
		NextFrame(world)
		expect(sell:GetItem()).toBeNil()
		expect(world.uiErrors).toEqual({ LINEN_LINK .. " can't be listed while another one in your bags is locked." })
		expect(sell:PostItem()).toBe(false)
		expect(world.posts).toEqual({})
		-- Unlocked, both stacks can go, and a post of all of them takes the other stack too.
		Unlock(ns, lockedAt)
		world:RightClick(freeAt)
		NextFrame(world)
		expect(sell:PostItem()).toBe(true)
		expect(world.posts).toEqual({ { itemID = ITEMS.LINEN, quantity = 21, guids = { free.guid, locked.guid } } })
	end)

	it("treats a stack unlocked on its own as blocked while the item's other stacks are locked", function()
		local world, ns = Setup()
		local _, firstAt = world:Give(ITEMS.LINEN, { count = 4 })
		local _, secondAt = world:Give(ITEMS.LINEN, { count = 6 })
		Lock(ns, firstAt, "all")
		Unlock(ns, secondAt) -- this stack only
		world:OpenAuctionHouse()
		world:RightClick(secondAt)
		NextFrame(world)
		expect(world.env.AuctionHouseFrame.CommoditiesSellFrame:GetItem()).toBeNil()
		expect(world.uiErrors).toEqual({ LINEN_LINK .. " can't be listed while another one in your bags is locked." })
	end)

	it("lets a bag copy be listed when the locked one is worn or in the bank", function()
		local world, ns = Setup()
		local _, wornAt = world:Equip(11, ITEMS.RING)
		local _, bankedAt = world:Give(ITEMS.LINEN, { bag = 6, slot = 1, count = 5 })
		local _, ringAt = world:Give(ITEMS.RING)
		local _, linenAt = world:Give(ITEMS.LINEN, { count = 8 })
		Lock(ns, wornAt)
		Lock(ns, bankedAt)
		world:OpenAuctionHouse()
		local frame = world.env.AuctionHouseFrame
		world:RightClick(ringAt)
		NextFrame(world)
		expect(frame.ItemSellFrame:GetItem()).toBe(ringAt)
		world:RightClick(linenAt)
		NextFrame(world)
		expect(frame.CommoditiesSellFrame:GetItem()).toBe(linenAt)
		expect(world.uiErrors).toEqual({})
	end)

	it("takes an item out when it, or another one of it, gets locked while it's in the slot", function()
		local world, ns = Setup()
		local _, ringAt = world:Give(ITEMS.RING)
		local _, firstAt = world:Give(ITEMS.LINEN, { count = 3 })
		local _, secondAt = world:Give(ITEMS.LINEN, { count = 5 })
		world:OpenAuctionHouse()
		local frame = world.env.AuctionHouseFrame
		world:RightClick(ringAt)
		NextFrame(world)
		Lock(ns, ringAt) -- the key binding works at the Auction House
		NextFrame(world)
		expect(frame.ItemSellFrame:GetItem()).toBeNil()
		expect(world.uiErrors).toEqual({ RING_LINK .. " is locked, so it can't be listed." })
		world:RightClick(firstAt)
		NextFrame(world)
		Lock(ns, secondAt)
		NextFrame(world)
		expect(frame.CommoditiesSellFrame:GetItem()).toBeNil()
		expect(world.uiErrors[2]).toBe(LINEN_LINK .. " can't be listed while another one in your bags is locked.")
	end)

	it("catches an item another addon puts straight into a sell frame", function()
		local world, ns = Setup()
		local _, swordAt = world:Give(ITEMS.SWORD)
		Lock(ns, swordAt)
		world:OpenAuctionHouse()
		local sell = world.env.AuctionHouseFrame.ItemSellFrame
		sell:SetItem(swordAt)
		NextFrame(world)
		expect(sell:GetItem()).toBeNil()
		expect(#world.uiErrors).toBe(1)
	end)

	it("works when the Auction House UI was already loaded at login", function()
		local world, ns = Setup({ auctionHouse = true })
		local _, swordAt = world:Give(ITEMS.SWORD)
		Lock(ns, swordAt)
		world:OpenAuctionHouse()
		world:RightClick(swordAt)
		NextFrame(world)
		expect(world.env.AuctionHouseFrame.ItemSellFrame:GetItem()).toBeNil()
		local hooked = 0
		for _, hook in ipairs(world.hooks) do
			if hook.name == "SetItem" then
				hooked = hooked + 1
			end
		end
		expect(hooked).toBe(2)
	end)

	it("reads no GUIDs and says nothing for items that aren't locked anywhere", function()
		local world = Setup()
		local _, ringAt = world:Give(ITEMS.RING)
		world:OpenAuctionHouse()
		local reads = world.calls.GetItemGUID
		world:RightClick(ringAt)
		NextFrame(world)
		expect(world.calls.GetItemGUID).toBe(reads)
		expect(world.uiErrors).toEqual({})
		expect(world.sounds).toEqual({})
	end)
end)

describe("Auction House with Auctionator", function()
	local function Setup(options)
		options = options or {}
		options.auctionator = true
		local world, ns = Harness.Setup(options)
		world.sounds, world.uiErrors = {}, {}
		return world, ns
	end

	it("takes a locked item out of Auctionator's sale slot before it can be posted", function()
		local world, ns = Setup()
		local sword, swordAt = world:Give(ITEMS.SWORD)
		local ring, ringAt = world:Give(ITEMS.RING)
		Lock(ns, swordAt)
		world.sounds = {}
		world:OpenAuctionHouse()
		local saleItem = Addons.AuctionatorSelect(world, swordAt)
		expect(saleItem.itemInfo.location).toBe(swordAt)
		NextFrame(world)
		expect(saleItem.itemInfo).toBeNil()
		expect(world.holds[sword.guid]).toBeNil()
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be listed." })
		expect(world.sounds).toEqual({ ERROR })
		expect(saleItem:PostItem()).toBe(false)
		Addons.AuctionatorSelect(world, ringAt)
		NextFrame(world)
		expect(saleItem:PostItem()).toBe(true)
		expect(world.posts).toEqual({ { itemID = ITEMS.RING, quantity = 1, guids = { ring.guid } } })
	end)

	it("won't list a stack while another stack of the item is locked: its default posts them all", function()
		local world, ns = Setup()
		local locked, lockedAt = world:Give(ITEMS.LINEN, { count = 9 })
		local free, freeAt = world:Give(ITEMS.LINEN, { count = 12 })
		world:OpenAuctionHouse()
		-- Without a lock, the default quantity is every Linen Cloth in the bags.
		local saleItem = Addons.AuctionatorSelect(world, freeAt)
		NextFrame(world)
		expect(saleItem:PostItem()).toBe(true)
		expect(world.posts[1].guids).toEqual({ free.guid, locked.guid })
		world.posts = {}
		Lock(ns, lockedAt)
		Addons.AuctionatorSelect(world, freeAt)
		NextFrame(world)
		expect(saleItem.itemInfo).toBeNil()
		expect(world.uiErrors).toEqual({ LINEN_LINK .. " can't be listed while another one in your bags is locked." })
		expect(saleItem:PostItem()).toBe(false)
		expect(world.posts).toEqual({})
	end)

	it("waits for Auctionator to finish picking an item it has to look up first", function()
		local world, ns = Setup()
		local sword, swordAt = world:Give(ITEMS.SWORD)
		Lock(ns, swordAt)
		world:OpenAuctionHouse()
		world.auctionator.itemKeyDelay = 0.5
		local saleItem = Addons.AuctionatorSelect(world, swordAt)
		NextFrame(world)
		expect(saleItem.itemInfo).toBeNil() -- still looking the item up
		expect(world.uiErrors).toEqual({})
		-- Picked half a second later; the check runs on the frame after (this harness runs that
		-- zero-delay timer inside the same Advance).
		world:Advance(0.5)
		expect(saleItem.itemInfo).toBeNil()
		expect(world.holds[sword.guid]).toBeNil()
		expect(world.uiErrors).toEqual({ SWORD_LINK .. " is locked, so it can't be listed." })
	end)

	it("takes Auctionator's item out when it gets locked in the slot", function()
		local world, ns = Setup()
		local _, ringAt = world:Give(ITEMS.RING)
		world:OpenAuctionHouse()
		local saleItem = Addons.AuctionatorSelect(world, ringAt)
		NextFrame(world)
		expect(saleItem.itemInfo.location).toBe(ringAt)
		Lock(ns, ringAt)
		NextFrame(world)
		expect(saleItem.itemInfo).toBeNil()
		expect(world.uiErrors).toEqual({ RING_LINK .. " is locked, so it can't be listed." })
	end)

	it("stays out of the way of an Auctionator without the selling events it uses", function()
		local world, ns = Setup({
			configure = function(_, env)
				env.Auctionator.Selling = nil
			end,
		})
		local _, swordAt = world:Give(ITEMS.SWORD)
		Lock(ns, swordAt)
		world:OpenAuctionHouse()
		local saleItem = Addons.ShowAuctionatorSelling(world)
		expect(saleItem.updates).toBeNil()
		world:RightClick(swordAt)
		NextFrame(world)
		expect(world.env.AuctionHouseFrame.ItemSellFrame:GetItem()).toBeNil()
		expect(world.errors).toEqual({})
	end)
end)
