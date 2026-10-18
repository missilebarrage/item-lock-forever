local _, ns = ...

--- Holds: the game's own item lock (C_Item.LockItem, which the Auction House uses for the item in
--- its sell slot) on every locked item in the bags while something could sell or destroy it: a
--- vendor window (Merchant) or Disenchant waiting for its target (Disenchant). Held items show
--- greyed out, and the game won't sell them, let them be picked up or target them. Several
--- reasons can be active at once; items stay held until the last one ends. Only this addon's own
--- holds are ever released.
---@class ItemLockForeverHolds
local Holds = ns.Holds
local Events = ns.Events
local Feedback = ns.Feedback
local Locks = ns.Locks

local FIRST_BAG = 0 -- the backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- the bags and the reagent bag

local reasons = {} ---@type table<string, true>
local held = {} ---@type table<string, number> itemGUID -> itemID of the items this addon holds

---@return boolean
function Holds.IsActive()
	return next(reasons) ~= nil
end

--- Holds every locked item in the bags that isn't held yet.
function Holds.Scan()
	if not next(reasons) then
		return
	end
	local found, newlyHeld = 0, 0
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if Locks.IsLockedInBag(bag, slot) then
				found = found + 1
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				local guid = ns.Str(C_Item.GetItemGUID(location))
				-- An item the game already holds (being moved, sold or cast on) is left alone and
				-- tried again at the next bag update.
				if guid and not C_Item.IsLocked(location) then
					C_Item.LockItem(location)
					held[guid] = C_Container.GetContainerItemID(bag, slot)
					newlyHeld = newlyHeld + 1
				end
			end
		end
	end
	ns.Debug("hold: locked items", found, "newly held", newlyHeld)
end

local function Release(guid)
	held[guid] = nil
	-- Nothing to release once the item is gone (sold or destroyed).
	if C_Item.GetItemLocation(guid) then
		C_Item.UnlockItemByGUID(guid)
	end
end

--- Starts holding for a reason ("vendor", "disenchant").
function Holds.Start(reason)
	if reasons[reason] then
		return
	end
	reasons[reason] = true
	ns.Debug("hold for", reason)
	Holds.Scan()
end

--- Ends a reason; the items are released when no reason is left.
function Holds.Stop(reason)
	if not reasons[reason] then
		return
	end
	reasons[reason] = nil
	ns.Debug("hold ends for", reason)
	if next(reasons) then
		return
	end
	for guid in pairs(held) do
		Release(guid)
	end
end

-- Locking or unlocking while holding takes effect at once.
local function OnLocksChanged(itemID, guid, locked)
	if not next(reasons) then
		return
	end
	if locked then
		Holds.Scan()
	elseif guid then
		if held[guid] then
			Release(guid)
		end
	else
		for heldGUID, heldID in pairs(held) do
			if heldID == itemID then
				Release(heldGUID)
			end
		end
	end
end

-- Post-hook of C_Container.UseContainerItem: a click on a bag item (or a macro's /use) while
-- Disenchant waits for its target picks the item, and a right-click at a vendor sells it. The
-- game refuses an item this addon holds without a word, so say why. (An item it couldn't hold
-- goes through; the vendor backstop reports that one.)
local function OnUseContainerItem(bag, slot)
	if not next(reasons) or not Locks.IsLockedInBag(bag, slot) then
		return
	end
	if not held[ns.Str(C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))) or ""] then
		return
	end
	local action = (reasons.disenchant and SpellCanTargetItem()) and "disenchant" or (reasons.vendor and "sell")
	if action then
		Feedback.Blocked(action, C_Container.GetContainerItemLink(bag, slot))
	end
end

function Holds.Init()
	-- Items that arrive (looted, bought back) are held too.
	Events.On("BAG_UPDATE_DELAYED", Holds.Scan)
	Events.On("ILF_LOCKS_CHANGED", OnLocksChanged)
	hooksecurefunc(C_Container, "UseContainerItem", OnUseContainerItem)
end
