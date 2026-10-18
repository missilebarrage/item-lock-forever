-- Fake inventory: item info, bags (and bank tabs), worn equipment, the cursor, the game's own
-- item locks ("holds"), money, and a vendor with a buyback list. Sales and buybacks go to a fake
-- server and come back LATENCY seconds later with the events the client fires.
--
-- world.itemInfo[itemID] = { name, maxStack, quality, sellPrice }
-- world.bags[bagID] = { size = n, [slot] = item };  world.equipped[slot] = item
-- item = { id = itemID, guid = "Item-...", count = n }
-- world.holds[guid] = "addon" | "game";  world.cursor = location or nil
-- world.buyback = { { item = item, price = copper }, ... } newest last, at most 12
-- world.spellTargeting / world.currentSpell: a spell waiting for its target (StartTargeting)
-- world.behavior: switches for client behavior the addon can't know in advance.

local Inventory = {}

local LATENCY = 0.05
local BUYBACK_SIZE = 12
-- GUIDs are unique across worlds, as on a realm: an alt's items never share a GUID with a main's.
local nextGUID = 0
local DISENCHANT = 13262
local CAST_TIME = 3

local DEFAULT_BEHAVIOR = {
	holdsBlockSales = true, -- the client refuses to sell or pick up a held item
	holdsBlockTargeting = true, -- the client refuses to cast a targeting spell on a held item
	junkHonorsHolds = false, -- the server's Sell All Junk skips held items
	buybackKeepsGUID = true, -- a bought-back item keeps its GUID
	buybackTooltipGUID = true, -- buyback tooltips carry the item's GUID
	tooltipGUID = true, -- bag and equipment tooltips carry the item's GUID
	deleteGUID = true, -- DELETE_ITEM_CONFIRM carries the item's GUID
	buybackMerges = false, -- a bought-back stack goes onto a stack of the same item with room
}

local LocationMixin = {}
LocationMixin.__index = LocationMixin

function LocationMixin:IsBagAndSlot()
	return self.bagID ~= nil and self.slotIndex ~= nil
end
function LocationMixin:IsEquipmentSlot()
	return self.equipmentSlotIndex ~= nil
end
function LocationMixin:GetBagAndSlot()
	return self.bagID, self.slotIndex
end
function LocationMixin:GetEquipmentSlot()
	return self.equipmentSlotIndex
end

local function BagLocation(bag, slot)
	return setmetatable({ bagID = bag, slotIndex = slot }, LocationMixin)
end
local function EquipmentLocation(slot)
	return setmetatable({ equipmentSlotIndex = slot }, LocationMixin)
end
Inventory.BagLocation = BagLocation
Inventory.EquipmentLocation = EquipmentLocation

function Inventory.Install(world, env)
	local options = world.options
	world.itemInfo = {}
	world.bags = {
		[0] = { size = 16 },
		[1] = { size = 0 },
		[2] = { size = 0 },
		[3] = { size = 0 },
		[4] = { size = 0 },
		[5] = { size = 0 },
		[6] = { size = 0 }, -- first character bank tab
	}
	world.equipped = {}
	world.holds = {}
	world.cursor = nil
	world.money = options.money or 100000
	world.buyback = {}
	world.merchantOpen = false
	world.behavior = {}
	for key, value in pairs(DEFAULT_BEHAVIOR) do
		world.behavior[key] = value
	end
	for key, value in pairs(options.behavior or {}) do
		world.behavior[key] = value
	end
	world.calls = { LockItem = 0, UnlockItem = 0, GetItemGUID = 0, BuybackItem = 0 }

	local function Info(itemID)
		return world.itemInfo[itemID] or { name = "Item " .. itemID, maxStack = 1, quality = 1, sellPrice = 10 }
	end
	local function Link(item)
		return string.format("|cffffffff|Hitem:%d::::::::|h[%s]|h|r", item.id, Info(item.id).name)
	end
	world.Link = function(_, item)
		return Link(item)
	end

	local function At(location)
		if type(location) ~= "table" then
			return nil
		end
		if location.bagID ~= nil then
			local bag = world.bags[location.bagID]
			return bag and bag[location.slotIndex]
		end
		if location.equipmentSlotIndex ~= nil then
			return world.equipped[location.equipmentSlotIndex]
		end
		return nil
	end
	world.ItemAt = function(_, location)
		return At(location)
	end

	local function Find(guid)
		for bagID, bag in pairs(world.bags) do
			for slot = 1, bag.size do
				if bag[slot] and bag[slot].guid == guid then
					return BagLocation(bagID, slot), bag[slot]
				end
			end
		end
		for slot, item in pairs(world.equipped) do
			if item.guid == guid then
				return EquipmentLocation(slot), item
			end
		end
		return nil
	end
	world.Find = function(_, guid)
		return Find(guid)
	end

	local function NewGUID()
		nextGUID = nextGUID + 1
		return string.format("Item-1-0-%08X", nextGUID)
	end

	local function FreeSlot()
		for bagID = 0, 5 do
			local bag = world.bags[bagID]
			for slot = 1, bag.size do
				if not bag[slot] then
					return bagID, slot
				end
			end
		end
		return nil
	end

	local function Fire(...)
		world:Fire(...)
	end

	local function BagsChanged(bags)
		for bagID in pairs(bags) do
			Fire("BAG_UPDATE", bagID)
		end
		Fire("BAG_UPDATE_DELAYED")
	end

	local function SetHold(item, kind)
		world.holds[item.guid] = kind
		local location = Find(item.guid)
		if location and location.bagID then
			Fire("ITEM_LOCK_CHANGED", location.bagID, location.slotIndex)
		elseif location then
			Fire("ITEM_LOCK_CHANGED", location.equipmentSlotIndex)
		end
	end

	-- World helpers for tests ------------------------------------------------------

	--- Defines an item: { name, maxStack, quality, sellPrice }.
	function world:DefineItem(itemID, info)
		self.itemInfo[itemID] = {
			name = info.name or ("Item " .. itemID),
			maxStack = info.maxStack or 1,
			quality = info.quality or 1,
			sellPrice = info.sellPrice or 10,
		}
	end

	--- Puts an item in a bag slot (the first free one by default). Returns item, location.
	function world:Give(itemID, placement)
		placement = placement or {}
		local bagID, slot = placement.bag, placement.slot
		if not bagID then
			bagID, slot = FreeSlot()
		end
		assert(bagID, "no free bag slot")
		local bag = self.bags[bagID]
		bag.size = math.max(bag.size, slot)
		local item = { id = itemID, guid = placement.guid or NewGUID(), count = placement.count or 1 }
		bag[slot] = item
		return item, BagLocation(bagID, slot)
	end

	--- Wears an item in an equipment slot. Returns item, location.
	function world:Equip(slot, itemID, placement)
		placement = placement or {}
		local item = { id = itemID, guid = placement.guid or NewGUID(), count = 1 }
		self.equipped[slot] = item
		return item, EquipmentLocation(slot)
	end

	--- Moves an item to another bag slot (keeps its GUID), as dragging it would.
	function world:Move(from, toBag, toSlot)
		local item = At(from)
		self.bags[from.bagID][from.slotIndex] = nil
		self.bags[toBag].size = math.max(self.bags[toBag].size, toSlot)
		self.bags[toBag][toSlot] = item
		return BagLocation(toBag, toSlot)
	end

	--- Drags one stack onto another of the same item: the first stack is gone, the second grows.
	function world:MergeStacks(from, to)
		local source, target = At(from), At(to)
		assert(source and target and source.id == target.id, "MergeStacks: two stacks of one item")
		target.count = target.count + source.count
		self.bags[from.bagID][from.slotIndex] = nil
		BagsChanged({ [from.bagID] = true, [to.bagID] = true })
	end

	--- Splits count items off a stack into an empty slot: a new stack with a new GUID.
	function world:SplitStack(from, count, toBag, toSlot)
		local source = At(from)
		assert(source and source.count > count, "SplitStack: not enough to split")
		source.count = source.count - count
		self.bags[toBag].size = math.max(self.bags[toBag].size, toSlot)
		local piece = { id = source.id, guid = NewGUID(), count = count }
		self.bags[toBag][toSlot] = piece
		BagsChanged({ [from.bagID] = true, [toBag] = true })
		return piece, BagLocation(toBag, toSlot)
	end

	--- Uses up count items of a stack (drinking a potion...).
	function world:UseUp(location, count)
		local item = At(location)
		item.count = item.count - count
		if item.count <= 0 then
			self.bags[location.bagID][location.slotIndex] = nil
		end
		BagsChanged({ [location.bagID] = true })
	end

	--- Talks to a vendor. order: "interactionFirst" (default), "showFirst" or "showOnly".
	function world:OpenMerchant(order)
		self.merchantOpen = true
		order = order or "interactionFirst"
		if order == "interactionFirst" then
			Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
			Fire("MERCHANT_SHOW")
		elseif order == "showFirst" then
			Fire("MERCHANT_SHOW")
			Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
		else
			Fire("MERCHANT_SHOW")
		end
	end

	--- Leaves the vendor; MERCHANT_CLOSED can fire twice in the client.
	function world:CloseMerchant(twice)
		self.merchantOpen = false
		Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
		Fire("MERCHANT_CLOSED")
		if twice then
			Fire("MERCHANT_CLOSED")
		end
	end

	--- A plain right-click on a bag item: Blizzard's handler calls UseContainerItem.
	function world:RightClick(location)
		env.C_Container.UseContainerItem(location.bagID, location.slotIndex)
	end

	--- Picks an item up like a left-click; returns false when the client refuses (held item).
	function world:PickUp(location)
		local item = At(location)
		if not item or self.cursor then
			return false
		end
		if self.holds[item.guid] and self.behavior.holdsBlockSales then
			return false
		end
		self.cursor = location
		SetHold(item, "game")
		return true
	end

	--- Drags an item onto the vendor window (PickupMerchantItem(0) sells the cursor item).
	function world:DragToMerchant(location)
		if not self:PickUp(location) then
			return false
		end
		local item = At(self.cursor)
		self.cursor = nil
		world:After(LATENCY, function()
			self:ServerSell(item)
		end)
		return true
	end

	--- Drops an item outside the bags: the game asks whether to destroy it. Blizzard's dialog
	--- (world.popup) closes itself on the next frame when the cursor is empty.
	function world:DragToWorld(location)
		if not self:PickUp(location) then
			return false
		end
		local item = At(location)
		local info = Info(item.id)
		self.popup = {
			which = info.quality >= 3 and "DELETE_GOOD_ITEM" or "DELETE_ITEM",
			data = { itemGUID = item.guid },
		}
		Fire("DELETE_ITEM_CONFIRM", info.name, info.quality, 0, 0, self.behavior.deleteGUID and item.guid or nil)
		self:Frame()
		return true
	end

	--- One rendered frame: the delete dialogs' OnUpdate hides them once the cursor is empty.
	function world:Frame()
		if self.popup and not self.cursor then
			self.popup = nil
		end
	end

	--- Accepts the delete dialog, if it's still open.
	function world:AcceptPopup()
		local popup = self.popup
		if not popup then
			return false
		end
		self.popup = nil
		local location, item = Find(popup.data.itemGUID)
		if item then
			self.bags[location.bagID][location.slotIndex] = nil
			self.cursor = nil
			self.holds[item.guid] = nil
		end
		return item ~= nil
	end

	--- The server's half of a sale: the item goes to the buyback list.
	function world:ServerSell(item)
		local location = Find(item.guid)
		if not location then
			return
		end
		local changed = {}
		if location.bagID then
			self.bags[location.bagID][location.slotIndex] = nil
			changed[location.bagID] = true
		else
			self.equipped[location.equipmentSlotIndex] = nil
		end
		if self.cursor and At(self.cursor) == nil then
			self.cursor = nil
		end
		self.holds[item.guid] = nil
		local price = Info(item.id).sellPrice * item.count
		self.money = self.money + price
		table.insert(self.buyback, { item = item, price = price })
		while #self.buyback > BUYBACK_SIZE do
			table.remove(self.buyback, 1)
		end
		BagsChanged(changed)
		Fire("MERCHANT_UPDATE")
	end

	--- Casts a spell that targets an item (Disenchant, an enchant...): the cursor waits for a target.
	function world:StartTargeting(spellID)
		self.spellTargeting, self.currentSpell = true, spellID
		Fire("CURRENT_SPELL_CAST_CHANGED", false)
	end

	--- Right-click or Escape while the cursor waits for a target.
	function world:CancelTargeting()
		self.spellTargeting, self.currentSpell = false, nil
		Fire("CURRENT_SPELL_CAST_CHANGED", true)
	end

	--- Clicks a bag item while a spell waits for its target: Blizzard's handler calls
	--- UseContainerItem, which casts on the item. Disenchant destroys it when the cast ends.
	function world:TargetItem(location)
		env.C_Container.UseContainerItem(location.bagID, location.slotIndex)
	end

	function world:CastOnItem(item)
		if self.holds[item.guid] and self.behavior.holdsBlockTargeting then
			self.refusedTargets = (self.refusedTargets or 0) + 1
			return false
		end
		local spellID = self.currentSpell
		self.spellTargeting = false
		SetHold(item, "game")
		Fire("CURRENT_SPELL_CAST_CHANGED", false)
		world:After(CAST_TIME, function()
			self.currentSpell = nil
			local location = Find(item.guid)
			self.holds[item.guid] = nil
			if location and spellID == DISENCHANT then
				self.bags[location.bagID][location.slotIndex] = nil
				BagsChanged({ [location.bagID] = true })
			end
			Fire("CURRENT_SPELL_CAST_CHANGED", false)
		end)
		return true
	end

	--- Every item that is in the bags, the bank or worn (for assertions).
	function world:Has(guid)
		return Find(guid) ~= nil
	end

	--- Number of items with this ID in the bags, counting stacks.
	function world:Count(itemID)
		local total = 0
		for bagID = 0, 5 do
			local bag = self.bags[bagID]
			for slot = 1, bag.size do
				if bag[slot] and bag[slot].id == itemID then
					total = total + bag[slot].count
				end
			end
		end
		return total
	end

	-- Game API --------------------------------------------------------------------

	env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5

	env.ItemLocation = {
		CreateFromBagAndSlot = function(_, bag, slot)
			return BagLocation(bag, slot)
		end,
		CreateFromEquipmentSlot = function(_, slot)
			return EquipmentLocation(slot)
		end,
	}

	local function Exists(location)
		return At(location) ~= nil
	end
	local function Need(location)
		local item = At(location)
		if not item then
			error("item location has no item", 3)
		end
		return item
	end

	env.C_Item = {
		DoesItemExist = Exists,
		GetItemID = function(location)
			return Need(location).id
		end,
		GetItemGUID = function(location)
			world.calls.GetItemGUID = world.calls.GetItemGUID + 1
			return Need(location).guid
		end,
		GetItemLink = function(location)
			local item = At(location)
			return item and Link(item)
		end,
		GetItemMaxStackSize = function(location)
			return Info(Need(location).id).maxStack
		end,
		IsLocked = function(location)
			return world.holds[Need(location).guid] ~= nil
		end,
		LockItem = function(location)
			world.calls.LockItem = world.calls.LockItem + 1
			SetHold(Need(location), "addon")
		end,
		UnlockItem = function(location)
			world.calls.UnlockItem = world.calls.UnlockItem + 1
			SetHold(Need(location), nil)
		end,
		UnlockItemByGUID = function(guid)
			world.calls.UnlockItem = world.calls.UnlockItem + 1
			local _, item = Find(guid)
			assert(item, "UnlockItemByGUID: no such item")
			SetHold(item, nil)
		end,
		GetItemLocation = function(guid)
			return (Find(guid))
		end,
		GetItemIDByGUID = function(guid)
			local _, item = Find(guid)
			if item then
				return item.id
			end
			for _, entry in ipairs(world.buyback) do
				if entry.item.guid == guid then
					return entry.item.id
				end
			end
			return nil
		end,
		GetItemLinkByGUID = function(guid)
			local _, item = Find(guid)
			return item and Link(item)
		end,
	}

	env.GetInventoryItemID = function(unit, slot)
		assert(unit == "player", "GetInventoryItemID: player expected")
		local item = world.equipped[slot]
		return item and item.id
	end

	env.C_Container = {
		GetContainerNumSlots = function(bagID)
			local bag = world.bags[bagID]
			return bag and bag.size or 0
		end,
		GetContainerItemID = function(bagID, slot)
			local bag = world.bags[bagID]
			local item = bag and bag[slot]
			return item and item.id
		end,
		GetContainerItemLink = function(bagID, slot)
			local bag = world.bags[bagID]
			local item = bag and bag[slot]
			return item and Link(item)
		end,
		GetContainerItemInfo = function(bagID, slot)
			local bag = world.bags[bagID]
			local item = bag and bag[slot]
			if not item then
				return nil
			end
			return {
				itemID = item.id,
				stackCount = item.count,
				quality = Info(item.id).quality,
				isLocked = world.holds[item.guid] ~= nil,
				hyperlink = Link(item),
			}
		end,
		-- With a spell waiting for its target this casts on the item; at a vendor it sells. The
		-- client refuses held items.
		UseContainerItem = function(bagID, slot)
			local item = world.bags[bagID] and world.bags[bagID][slot]
			if item and world.spellTargeting then
				world:CastOnItem(item)
				return
			end
			if not item or not world.merchantOpen then
				return
			end
			if world.holds[item.guid] and world.behavior.holdsBlockSales then
				return
			end
			world.holds[item.guid] = world.holds[item.guid] or "game"
			world:After(LATENCY, function()
				world:ServerSell(item)
			end)
		end,
	}

	env.C_Cursor = {
		GetCursorItem = function()
			return world.cursor
		end,
	}
	env.CursorHasItem = function()
		return world.cursor ~= nil
	end
	env.ClearCursor = function()
		local item = At(world.cursor)
		world.cursor = nil
		if item and world.holds[item.guid] == "game" then
			SetHold(item, nil)
		end
	end

	-- Vendor and buyback.
	env.GetMoney = function()
		return world.money
	end
	env.GetNumBuybackItems = function()
		return #world.buyback
	end
	env.GetBuybackItemLink = function(index)
		local entry = world.buyback[index]
		return entry and Link(entry.item)
	end
	env.GetBuybackItemInfo = function(index)
		local entry = world.buyback[index]
		if entry then
			return Info(entry.item.id).name, 134400, entry.price, entry.item.count, -1, true, false
		end
	end
	env.C_TooltipInfo = {
		GetBuybackItem = function(index)
			local entry = world.buyback[index]
			if not entry then
				return nil
			end
			local guid = world.behavior.buybackTooltipGUID and entry.item.guid or nil
			return { type = 0, id = entry.item.id, guid = guid, lines = {} }
		end,
	}
	env.C_MerchantFrame = {
		GetBuybackItemID = function(index)
			local entry = world.buyback[index]
			return entry and entry.item.id or 0
		end,
		-- Server-side: sells every grey item in the bags in one go.
		SellAllJunkItems = function()
			world:After(LATENCY, function()
				for bagID = 0, 5 do
					local bag = world.bags[bagID]
					for slot = 1, bag.size do
						local item = bag[slot]
						if item and Info(item.id).quality == 0 then
							if not (world.behavior.junkHonorsHolds and world.holds[item.guid]) then
								world:ServerSell(item)
							end
						end
					end
				end
			end)
		end,
	}
	-- The server buys back whatever is at this index when the request arrives.
	env.BuybackItem = function(index)
		world.calls.BuybackItem = world.calls.BuybackItem + 1
		world:After(LATENCY, function()
			local entry = world.buyback[index]
			if not entry or not world.merchantOpen then
				return
			end
			if world.money < entry.price then
				world.uiErrors[#world.uiErrors + 1] = "You don't have enough money."
				return
			end
			local item = entry.item
			if world.behavior.buybackMerges then
				for bagID = 0, 5 do
					local bag = world.bags[bagID]
					for slot = 1, bag.size do
						local other = bag[slot]
						if other and other.id == item.id and other.count + item.count <= Info(item.id).maxStack then
							table.remove(world.buyback, index)
							world.money = world.money - entry.price
							other.count = other.count + item.count
							BagsChanged({ [bagID] = true })
							Fire("MERCHANT_UPDATE")
							return
						end
					end
				end
			end
			local bagID, slot = FreeSlot()
			if not bagID then
				world.uiErrors[#world.uiErrors + 1] = "Inventory is full."
				return
			end
			table.remove(world.buyback, index)
			world.money = world.money - entry.price
			if not world.behavior.buybackKeepsGUID then
				item.guid = NewGUID()
			end
			world.bags[bagID][slot] = item
			BagsChanged({ [bagID] = true })
			Fire("MERCHANT_UPDATE")
		end)
	end
end

return Inventory
