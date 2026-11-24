local _, ns = ...

--- Auction House protection: locked items can't be listed. Blizzard's Sell tab and Auctionator's
--- Selling tab each post the item in their sell slot, and a post can take more than that one
--- stack: other stacks and copies of the same item in the bags (Auctionator's default quantity is
--- all of them). So when either slot takes an item that is locked, or another one of the same item
--- in the bags is, the item is taken out again with the error text and sound. Items go in through
--- Blizzard's and Auctionator's own code (a right-click, a drag, Auctionator's shortcut or list),
--- which can't be stopped, so the check runs on the next frame, before a post can be made (that
--- takes another click or key press). Locking an item that sits in a slot takes it out too.
--- Taking an item out uses the calls the two use themselves: Blizzard's ClearPostItem (which
--- Auctionator also calls from its own code) and Auctionator's ClearBagItem event.
---@class ItemLockForeverAuction
local Auction = ns.Auction
local Events = ns.Events
local Feedback = ns.Feedback
local Locks = ns.Locks

local FIRST_BAG = 0 -- the backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- the bags and the reagent bag, where posts take items from
-- Blizzard's sell frames on AuctionHouseFrame (Blizzard_AuctionHouseUI, loaded with the Auction House).
local SELL_FRAMES = { "ItemSellFrame", "CommoditiesSellFrame" }

local auctionatorSlots = setmetatable({}, { __mode = "k" }) -- Auctionator's sale item frames
local busSource = {} -- this addon, as a source of events on Auctionator's event bus
local hookedBlizzard = false
local pending = false

--- Why the item at location can't be listed: "locked" when it is locked, "other" when another one
--- of the same item in the bags is (a post could take that one too), or nil.
---@return string?
function Auction.BlockedReason(location)
	if not location or not C_Item.DoesItemExist(location) then
		return nil
	end
	if Locks.IsLockedAt(location) then
		return "locked"
	end
	local itemID = C_Item.GetItemID(location)
	if not Locks.MayBeLocked(itemID) then
		return nil
	end
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if C_Container.GetContainerItemID(bag, slot) == itemID and Locks.IsLockedInBag(bag, slot) then
				return "other"
			end
		end
	end
	return nil
end

-- True, after saying why, when the item at location has to leave its sell slot.
local function Refuse(location)
	local reason = Auction.BlockedReason(location)
	if not reason then
		return false
	end
	ns.Debug("auction: took out item", C_Item.GetItemID(location), reason)
	Feedback.Blocked(reason == "locked" and "list" or "listOther", C_Item.GetItemLink(location))
	return true
end

local function CheckSlots()
	pending = false
	local frame = AuctionHouseFrame
	if hookedBlizzard and frame then
		for _, key in ipairs(SELL_FRAMES) do
			local sell = frame[key]
			if sell and sell.GetItem and Refuse(sell:GetItem()) then
				frame:ClearPostItem()
				break
			end
		end
	end
	for saleItem in pairs(auctionatorSlots) do
		local info = saleItem.itemInfo
		if type(info) == "table" and Refuse(info.location) then
			Auctionator.EventBus:Fire(busSource, Auctionator.Selling.Events.ClearBagItem)
		end
	end
end

-- Checks the sell slots on the next frame, once the code that filled them has finished.
local function Schedule()
	if not pending then
		pending = true
		C_Timer.After(0, CheckSlots)
	end
end

-- Blizzard's sell slots: every way in (a right-click in the bags, a drag, another addon) ends in
-- the sell frame's SetItem.
local function HookBlizzard()
	local frame = AuctionHouseFrame
	if hookedBlizzard or not frame or not frame.ClearPostItem then
		return
	end
	hookedBlizzard = true
	ns.Debug("auction: watching Blizzard's sell slots")
	for _, key in ipairs(SELL_FRAMES) do
		local sell = frame[key]
		if sell and sell.SetItem then
			hooksecurefunc(sell, "SetItem", function(_, itemLocation)
				if itemLocation then
					Schedule()
				end
			end)
		end
	end
end

-- Auctionator's sale slot: every way in (its bag shortcut, its item list, a drag) ends in its
-- BagItemClicked event, after which the slot runs Update with the item picked. Auctionator copies
-- the mixin into the slot when the Auction House first opens, after this hook is in place.
local function HookAuctionator()
	local mixin = AuctionatorSaleItemMixin
	local bus = Auctionator and Auctionator.EventBus
	local events = Auctionator and Auctionator.Selling and Auctionator.Selling.Events
	if type(mixin) ~= "table" or type(mixin.Update) ~= "function" then
		return
	end
	if not bus or not bus.RegisterSource or not bus.Fire or not events or not events.ClearBagItem then
		return
	end
	bus:RegisterSource(busSource, ns.NAME)
	hooksecurefunc(mixin, "Update", function(saleItem)
		auctionatorSlots[saleItem] = true
		if saleItem.itemInfo ~= nil then
			Schedule()
		end
	end)
end

function Auction.Init()
	HookAuctionator()
	HookBlizzard()
	Events.On("ADDON_LOADED", function(name)
		if name == "Blizzard_AuctionHouseUI" then
			HookBlizzard()
		end
	end)
	-- Locking an item, or another one of the same item, while it sits in a sell slot.
	Events.On("ILF_LOCKS_CHANGED", function()
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			Schedule()
		end
	end)
end
