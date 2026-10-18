local _, ns = ...

--- The lock model.
--- * Gear (items that don't stack) and single stacks are locked as that exact item, by item GUID
---   (`items`): a second copy stays sellable, and the lock follows the item to other characters.
--- * "Every stack" locks an item ID for this character (`stacks`), stacks picked up later
---   included. It comes from views that combine stacks into one button (EllesmereUI Bags' All
---   Items). One stack can still be unlocked on its own (`free`).
--- * Stacks merge and split (dragging, bag sorting). When a bag update leaves fewer locked items
---   of an ID than before and other stacks of that ID grew or appeared, those stacks are locked
---   too: locked items keep their lock wherever they go (a few too many beats losing one).
--- In this addon "locked" always means our lock; the game's own item lock is called "held".
---@class ItemLockForeverLocks
local Locks = ns.Locks
local Database = ns.Database
local Events = ns.Events
local L = ns.L

local EMPTY = {}
-- Bags whose stacks are followed: the bags, the reagent bag and the character bank tabs.
local FOLLOW_BAGS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }

local items = {} ---@type table<string, number> itemGUID -> itemID (Database.Items)
local free = {} ---@type table<string, number> itemGUID -> itemID (Database.Free)
local stacks = {} ---@type table<number, true> this character's every-stack locks (Database.Stacks)
local lockedByID = {} ---@type table<number, table<string, true>> itemID -> its GUIDs in items
local freeByID = {} ---@type table<number, table<string, true>> itemID -> its GUIDs in free
local stackable = {} ---@type table<number, boolean> itemID -> does it stack (learned in the bags)
local snapshot = {} -- itemID -> { [guid] = { count, locked } }: followed stacks at the last update

local function Index(index, itemID, guid, present)
	local set = index[itemID]
	if present then
		if not set then
			set = {}
			index[itemID] = set
		end
		set[guid] = true
	elseif set then
		set[guid] = nil
		if next(set) == nil then
			index[itemID] = nil
		end
	end
end

local function SetLocked(guid, itemID, locked)
	if items[guid] then
		Index(lockedByID, items[guid], guid, false)
	end
	items[guid] = locked and itemID or nil
	if locked then
		Index(lockedByID, itemID, guid, true)
	end
end

local function SetFree(guid, itemID, isFree)
	if free[guid] then
		Index(freeByID, free[guid], guid, false)
	end
	free[guid] = isFree and itemID or nil
	if isFree then
		Index(freeByID, itemID, guid, true)
	end
end

local function Copy(set)
	local copy = {}
	for key in pairs(set or EMPTY) do
		copy[key] = true
	end
	return copy
end

--- Locked as that exact item or stack.
---@param guid string?
function Locks.IsGUIDLocked(guid)
	return guid ~= nil and items[guid] ~= nil
end

--- Locked because every stack of its item is (and this stack wasn't unlocked on its own).
---@param itemID number?
---@param guid string?
function Locks.IsTypeLocked(itemID, guid)
	return itemID ~= nil and stacks[itemID] == true and not (guid ~= nil and free[guid] ~= nil)
end

--- True when the item with this ID and GUID is locked (either may be nil when unknown).
function Locks.IsLocked(itemID, guid)
	return Locks.IsGUIDLocked(guid) or Locks.IsTypeLocked(itemID, guid)
end

-- Whether an item ID's lock depends on which item or stack it is, so its GUID must be read.
local function NeedsGUID(itemID)
	return lockedByID[itemID] ~= nil or freeByID[itemID] ~= nil
end

--- True when an item with this ID could be locked. Everything else is answered without looking
--- up a GUID.
function Locks.MayBeLocked(itemID)
	return itemID ~= nil and (stacks[itemID] ~= nil or lockedByID[itemID] ~= nil)
end

--- Whether the item in a bag (or bank) slot is locked.
---@return boolean locked
function Locks.IsLockedInBag(bag, slot)
	local itemID = C_Container.GetContainerItemID(bag, slot)
	if not itemID then
		return false
	end
	if not NeedsGUID(itemID) then
		return stacks[itemID] == true
	end
	return Locks.IsLocked(itemID, ns.Str(C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))))
end

--- Whether the item worn in an equipment slot is locked.
---@return boolean locked
function Locks.IsLockedEquipped(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then
		return false
	end
	if not NeedsGUID(itemID) then
		return stacks[itemID] == true
	end
	return Locks.IsLocked(itemID, ns.Str(C_Item.GetItemGUID(ItemLocation:CreateFromEquipmentSlot(slot))))
end

--- Whether the item at an item location is locked.
---@return boolean locked
function Locks.IsLockedAt(location)
	if not location or not C_Item.DoesItemExist(location) then
		return false
	end
	local itemID = C_Item.GetItemID(location)
	if not NeedsGUID(itemID) then
		return stacks[itemID] == true
	end
	return Locks.IsLocked(itemID, ns.Str(C_Item.GetItemGUID(location)))
end

--- Whether any stack of an item is locked on this character: every stack, or one you have.
function Locks.AnyLocked(itemID)
	if stacks[itemID] then
		return true
	end
	for guid in pairs(lockedByID[itemID] or EMPTY) do
		if C_Item.GetItemLocation(guid) then
			return true
		end
	end
	return false
end

--- Whether the item at location counts as locked for a toggle in a view: "all" (a combined
--- stack) asks about every stack of the item, "stack" about this one.
function Locks.IsLockedFor(location, view)
	if view == "all" then
		return location ~= nil and C_Item.DoesItemExist(location) and Locks.AnyLocked(C_Item.GetItemID(location))
	end
	return Locks.IsLockedAt(location)
end

-- Following stacks ---------------------------------------------------------------------------

-- The stacks of the item IDs whose locks depend on the stack: itemID -> { [guid] = count }.
local function ScanStacks()
	local found = {}
	for _, bag in ipairs(FOLLOW_BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID and NeedsGUID(itemID) and stackable[itemID] ~= false then
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				if stackable[itemID] == nil then
					local maxStack = C_Item.GetItemMaxStackSize(location)
					stackable[itemID] = maxStack ~= nil and maxStack > 1
				end
				local info = stackable[itemID] and C_Container.GetContainerItemInfo(bag, slot)
				local guid = info and ns.Str(C_Item.GetItemGUID(location))
				if guid then
					local list = found[itemID] or {}
					found[itemID] = list
					list[guid] = ns.Num(info.stackCount) or 1
				end
			end
		end
	end
	return found
end

local function TakeSnapshot(found)
	snapshot = {}
	for itemID, list in pairs(found or ScanStacks()) do
		local entries = {}
		for guid, count in pairs(list) do
			entries[guid] = { count = count, locked = Locks.IsLocked(itemID, guid) }
		end
		snapshot[itemID] = entries
	end
end

local returning = {} ---@type table<string, number> itemGUID -> itemID: locked stacks being bought back

--- The vendor backstop is buying back a locked stack: the game may stack it onto another stack
--- of the item, and then that stack gets its lock.
function Locks.ExpectReturn(guid, itemID)
	if Locks.IsGUIDLocked(guid) then
		returning[guid] = itemID
	end
end

--- The vendor closed: what didn't come back isn't expected any more.
function Locks.ForgetReturns()
	wipe(returning)
end

-- After a bag update: locked items that moved into other stacks lock those stacks. A locked
-- stack that went into other stacks is gone for good, so its lock is dropped; one that only
-- disappeared (used up, mailed, or in a closed bank) keeps it.
local function FollowStacks()
	if Database.IsReadOnly() then
		return
	end
	if not next(lockedByID) and not next(freeByID) then
		snapshot = {}
		return
	end
	local found = ScanStacks()
	local changed = {}
	for itemID, before in pairs(snapshot) do
		local after = found[itemID] or EMPTY
		local lockedBefore, lockedAfter = 0, 0
		for _, entry in pairs(before) do
			if entry.locked then
				lockedBefore = lockedBefore + entry.count
			end
		end
		for guid, count in pairs(after) do
			if Locks.IsLocked(itemID, guid) then
				lockedAfter = lockedAfter + count
			end
		end
		-- A bought-back locked stack that came back stacked onto another one.
		local merged = {}
		for guid, id in pairs(returning) do
			if id == itemID then
				if after[guid] then
					returning[guid] = nil
				else
					merged[#merged + 1] = guid
				end
			end
		end
		if lockedAfter < lockedBefore or #merged > 0 then
			local grew = false
			for guid, count in pairs(after) do
				local old = before[guid]
				if not Locks.IsLocked(itemID, guid) and count > (old and old.count or 0) then
					SetFree(guid, itemID, false)
					if not Locks.IsLocked(itemID, guid) then
						SetLocked(guid, itemID, true)
					end
					lockedAfter = lockedAfter + count
					grew = true
				end
			end
			if grew then
				changed[itemID] = true
				for _, guid in ipairs(merged) do
					returning[guid] = nil
					SetLocked(guid, itemID, false)
				end
			end
		end
		-- Locked stacks whose items all went into other locked stacks (a merge, bag sorting).
		if lockedAfter >= lockedBefore then
			for guid, entry in pairs(before) do
				if entry.locked and not after[guid] and items[guid] then
					SetLocked(guid, itemID, false)
				end
			end
		end
	end
	TakeSnapshot(found)
	for itemID in pairs(changed) do
		Events.Fire("ILF_LOCKS_CHANGED", itemID, nil, true)
	end
end

-- Toggling ------------------------------------------------------------------------------------

local function Changed(itemID, guid, locked)
	TakeSnapshot()
	Events.Fire("ILF_LOCKS_CHANGED", itemID, guid, locked)
end

--- Locks or unlocks the item at location. In the "stack" view gear is locked as that item and a
--- stackable item as that stack; in the "all" view (a combined button) every stack or copy of
--- the item is. Fires ILF_LOCKS_CHANGED(itemID, itemGUID or nil for every stack, locked).
---@param view string? "stack" (default) or "all"
---@return boolean? locked nil when nothing changed
---@return string? kind "item", "stack" or "all"
function Locks.Toggle(location, view)
	if Database.IsReadOnly() then
		ns.Print(L.READ_ONLY)
		return nil
	end
	if not location or not C_Item.DoesItemExist(location) then
		return nil
	end
	local itemID = C_Item.GetItemID(location)
	if not itemID then
		return nil
	end
	local maxStack = C_Item.GetItemMaxStackSize(location)
	local isStack = maxStack ~= nil and maxStack > 1
	if isStack then
		stackable[itemID] = true
	end
	-- From a combined button: every stack, or every copy of an item that doesn't stack.
	if view == "all" then
		local locked = not Locks.AnyLocked(itemID)
		stacks[itemID] = locked or nil
		for guid in pairs(Copy(freeByID[itemID])) do
			SetFree(guid, itemID, false)
		end
		if not locked then
			-- Unlocking every stack takes the single-stack locks on what you carry too.
			for guid in pairs(Copy(lockedByID[itemID])) do
				if C_Item.GetItemLocation(guid) then
					SetLocked(guid, itemID, false)
				end
			end
		end
		Changed(itemID, nil, locked)
		return locked, "all"
	end
	local guid = ns.Str(C_Item.GetItemGUID(location))
	if not guid then
		return nil
	end
	local locked = not Locks.IsLocked(itemID, guid)
	if locked then
		SetFree(guid, itemID, false)
		if not Locks.IsTypeLocked(itemID, guid) then
			SetLocked(guid, itemID, true)
		end
	else
		SetLocked(guid, itemID, false)
		if Locks.IsTypeLocked(itemID, guid) then
			SetFree(guid, itemID, true)
		end
	end
	Changed(itemID, guid, locked)
	return locked, isStack and "stack" or "item"
end

--- Connects to the saved locks. Called at PLAYER_LOGIN, before the other modules start, so stacks
--- are followed before anything else handles a bag update.
function Locks.Init()
	items = Database.Items()
	free = Database.Free()
	stacks = Database.Stacks(ns.Str(UnitGUID("player")))
	wipe(lockedByID)
	wipe(freeByID)
	for guid, itemID in pairs(items) do
		if type(itemID) == "number" then
			Index(lockedByID, itemID, guid, true)
		end
	end
	for guid, itemID in pairs(free) do
		if type(itemID) == "number" then
			Index(freeByID, itemID, guid, true)
		end
	end
	TakeSnapshot()
	Events.On("BAG_UPDATE_DELAYED", FollowStacks)
end
