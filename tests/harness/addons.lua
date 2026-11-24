-- Fake third-party addons: EllesmereUI Bags' overlay API and buttons, Baganator's corner widget
-- API and buttons, Bagnon's item button classes, Auctionator's Selling tab, and an auto-seller
-- that acts on MERCHANT_SHOW before this addon does (like EllesmereUI QoL's "sell junk").
local Addons = {}

local Widgets, Blizzard -- shared with the loader (Addons.Init)

function Addons.Init(widgets, blizzard)
	Widgets, Blizzard = widgets, blizzard
end

function Addons.Install(world, env)
	local options = world.options
	if options.ellesmere ~= false then
		world.loadedAddons.EllesmereUIBags = true
		local api = Widgets.Create(world, "Frame", "EUI_MainBagFrame")
		api.itemOverlayIcons = {}
		api.RegisterItemOverlayIcon = function(name, updateFn)
			api.itemOverlayIcons[name] = updateFn
		end
		api.RunItemOverlays = function(button, data)
			for _, fn in pairs(api.itemOverlayIcons) do
				env.securecallfunction(fn, button, data)
			end
		end
		env.EUI_Bags = api
	end
	if options.baganator then
		world.loadedAddons.Baganator = true
		world.baganator = { widgets = {}, refreshes = {}, plugins = {} }
		env.Baganator = {
			API = {
				RegisterCornerWidget = function(label, id, onUpdate, onInit, defaultPosition, isFast)
					assert(id and label and onUpdate and onInit and not world.baganator.widgets[id])
					world.baganator.widgets[id] = {
						label = label,
						onUpdate = onUpdate,
						onInit = onInit,
						defaultPosition = defaultPosition,
						isFast = isFast,
					}
				end,
				RequestItemButtonsRefresh = function(reasons)
					world.baganator.refreshes[#world.baganator.refreshes + 1] = reasons
				end,
			},
			Constants = { RefreshReason = { ItemWidgets = 4, Searches = 16 } },
		}
	end
	if options.autoSeller then
		Addons.InstallAutoSeller(world, env, options.autoSeller)
	end
	if options.auctionator then
		Addons.InstallAuctionator(world, env)
	end
	if options.bagnon then
		Addons.InstallBagnon(world, env)
	end
end

--- Bagnon 12.1.12 on its BagBrother core, modeled on BagBrother/libs/Poncho-2.0 and
--- core/classes/item.lua, containerItem.lua and parented.lua: Item:Bind copies every method of the
--- class chain onto a new button (collected once per class, on its first button), while
--- self:Super(class) looks a method up on the parent class when it runs. ContainerItem:Update
--- calls Item.Update that way; GuildItem buttons carry their own copy of Item.Update. A button's
--- frame is its Bagnon frame ("inventory", "bank", "guild").
function Addons.InstallBagnon(world, env)
	world.loadedAddons.Bagnon = true
	local ClassMeta = {
		__index = function(class, key)
			local super = rawget(class, "__super")
			return super and super[key]
		end,
	}
	local function NewClass(super)
		return setmetatable({ __super = super }, ClassMeta)
	end

	local Item = NewClass(nil)
	function Item:Bind(button)
		local list = rawget(self, "__bindList")
		if not list then
			list = {}
			self.__bindList = list
			local class = self
			while class do
				for key, value in pairs(class) do
					if list[key] == nil then
						list[key] = value
					end
				end
				class = rawget(class, "__super")
			end
		end
		for key, value in pairs(list) do
			button[key] = value
		end
		return button
	end
	function Item:Super(class)
		local frame = self
		return setmetatable({}, {
			__index = function(_, key)
				local value = rawget(class, "__super")[key]
				if type(value) == "function" then
					return function(_, ...)
						return value(frame, ...)
					end
				end
				return value
			end,
		})
	end
	function Item:Update(info)
		self.info = info or self.frame:GetItemInfo(self:GetBag(), self:GetID())
		self.hasItem = self.info.itemID and true
	end
	function Item:GetBag()
		return self.bag
	end

	local ContainerItem = NewClass(Item)
	function ContainerItem:Update(...)
		self:Super(ContainerItem):Update(...)
		self.cooldownChecked = true
	end
	function ContainerItem:IsCached()
		return self.frame:IsCached(self:GetBag())
	end

	local GuildItem = NewClass(Item)
	function GuildItem:GetBag()
		return 1 -- the guild bank tab shown
	end

	env.Bagnon = { Item = Item, ContainerItem = ContainerItem, GuildItem = GuildItem }
end

--- A Bagnon frame: id "inventory", "bank" or "guild". A cached frame (another character's bags,
--- the bank while you're away) shows Bagnon's records (frame.records[bag][slot] = info) instead of
--- the game's slots.
function Addons.NewBagnonFrame(world, id, cached)
	local frame = { id = id, cached = cached == true, records = {} }
	function frame:IsCached()
		return self.cached
	end
	function frame:GetItemInfo(bag, slot)
		if self.cached then
			return self.records[bag] and self.records[bag][slot] or {}
		end
		return world.env.C_Container.GetContainerItemInfo(bag, slot) or {}
	end
	return frame
end

--- A Bagnon item button of a class ("ContainerItem" by default) on a frame, for a bag and slot.
--- Bagnon runs button:Update() when it lays the frame out and whenever the slot changes.
function Addons.NewBagnonButton(world, frame, bag, slot, className)
	local class = world.env.Bagnon[className or "ContainerItem"]
	local button = Widgets.Create(world, "ItemButton", nil, world.env.UIParent)
	class:Bind(button)
	button.frame, button.bag = frame, bag
	-- Fields Bagnon's own update writes, so the seal counts them as Bagnon's.
	button.info, button.hasItem, button.cooldownChecked = {}, false, false
	button:SetID(slot)
	return Blizzard.Seal(button)
end

--- An EllesmereUI Bags item button (template-based, with the overlay frame it asks to use).
function Addons.NewEllesmereButton(world)
	local button = Widgets.Create(world, "ItemButton", nil, world.env.UIParent)
	button._textOverlay = Widgets.Create(world, "Frame", nil, button)
	return Blizzard.Seal(button)
end

--- EllesmereUI painting a slot: one reused data table, valid only during the call. merged: the
--- total count when the button stands for several stacks (All Items and category views).
local shared = {}
function Addons.PaintEllesmere(world, button, bagID, slot, merged)
	local item = world.bags[bagID] and world.bags[bagID][slot]
	shared.bag, shared.slot = bagID, slot
	shared.info = item and world.env.C_Container.GetContainerItemInfo(bagID, slot) or nil
	shared.itemLink = item and world:Link(item) or nil
	shared._mergedCount = merged
	world.env.EUI_Bags.RunItemOverlays(button, shared)
	shared.bag, shared.slot, shared.info, shared.itemLink, shared._mergedCount = nil, nil, nil, nil, nil
end

--- EllesmereUI painting a placeholder slot (bag 0, slot 0, no item).
function Addons.PaintEllesmerePlaceholder(world, button)
	world.env.EUI_Bags.RunItemOverlays(button, { bag = 0, slot = 0 })
end

--- A Baganator item button (Baganator keeps the item's details in its BGR field).
function Addons.NewBaganatorButton(world)
	local button = Widgets.Create(world, "ItemButton", nil, world.env.UIParent)
	button.BGR = {}
	return Blizzard.Seal(button)
end

-- The fields Baganator 856 puts in BGR before its corner widgets run: Syndicator's
-- Search.GetBaseInfo, then GetInfo and the live container button's early callback
-- (ItemViewCommon/ItemButton.lua). There is no bagID or slotID: the slot is in itemLocation.
-- Reading any other field fails the test, so the addon can't rely on details Baganator never
-- gives.
local BGR_FIELDS = {}
for _, key in ipairs({
	"itemLink",
	"itemID",
	"quality",
	"itemCount",
	"isBound",
	"hasLoot",
	"tooltipGetter",
	"earlyCallback",
	"finalCallback",
	"bagType",
	"guid",
	"setInfo",
	"itemLocation",
	"hasNoValue",
}) do
	BGR_FIELDS[key] = true
end
local STRICT_BGR = {
	__index = function(_, key)
		if not BGR_FIELDS[key] then
			error("Baganator never sets BGR." .. tostring(key), 2)
		end
	end,
}

--- Baganator showing an item the way its live container buttons do: BGR starts as Syndicator's
--- base info, the early callback adds the GUID and item location ({ bagID, slotIndex }) while
--- the slot holds the item, then the corner widgets run. Baganator creates the widget once and
--- shows it when the update says so. options.grouped: the total count of a "Group identical
--- items" button (the button's slot is its first stack); options.offline: a cached view (another
--- character, a bank you aren't at), which has no live slot.
function Addons.PaintBaganator(world, button, bagID, slot, options)
	options = options or {}
	local widget = world.baganator.widgets.itemlockforever_padlock
	local item = world.bags[bagID][slot]
	local details = setmetatable({
		itemLink = world:Link(item),
		itemID = item.id,
		quality = 1,
		itemCount = options.grouped or item.count or 1,
		isBound = false,
		hasLoot = false,
		tooltipGetter = function() end,
		bagType = 0,
	}, STRICT_BGR)
	if not options.offline then
		details.guid = item.guid
		details.itemLocation = { bagID = bagID, slotIndex = slot }
	end
	button.BGR = details
	local corner = world.baganator.plugins[button]
	if not corner then
		corner = widget.onInit(button)
		world.baganator.plugins[button] = corner
	end
	corner:Hide()
	if widget.onUpdate(corner, details) then
		corner:Show()
	end
	return corner
end

--- Auctionator 347's Selling tab (Source_ModernAH, which loads on Forever), modeled on its event
--- bus (Source/Utilities/EventBusMixin.lua), the selling events (Source/Selling/Events.lua) and
--- the sale item mixin (Source_ModernAH/Tabs/Selling/Mixins/SaleItem.lua): picking an item fires
--- BagItemClicked; the sale item takes it once the item key is known (at once, or after
--- world.auctionator.itemKeyDelay seconds), locks it with C_Item.LockItem and runs Update;
--- ClearBagItem resets it. The sale item frame is built from the mixin the first time the Auction
--- House opens (AuctionatorAHFrameMixin:OnShow), copying its functions as an XML mixin does.
function Addons.InstallAuctionator(world, env)
	world.loadedAddons.Auctionator = true
	local events = {
		BagItemClicked = "bag_item_clicked",
		BagItemRequest = "bag_item_request",
		ClearBagItem = "clear_bag_item",
		RequestPost = "selling_request_post",
		SkipItem = "selling_skip_item",
		AuctionCreated = "selling_auction_created",
	}
	local bus = { listeners = {}, sources = {} }
	function bus:Register(listener, names)
		assert(listener.ReceiveEvent, "Attempted to register an invalid listener! ReceiveEvent method must be defined.")
		for _, name in ipairs(names) do
			self.listeners[name] = self.listeners[name] or {}
			table.insert(self.listeners[name], listener)
		end
		return self
	end
	function bus:Unregister(listener, names)
		for _, name in ipairs(names) do
			local list = self.listeners[name] or {}
			for index = #list, 1, -1 do
				if list[index] == listener then
					table.remove(list, index)
				end
			end
		end
		return self
	end
	function bus:RegisterSource(source, name)
		self.sources[source] = name
		return self
	end
	function bus:Fire(source, name, ...)
		if self.sources[source] == nil then
			error("All sources must be registered (" .. name .. ")")
		end
		local listeners = {}
		for index, listener in ipairs(self.listeners[name] or {}) do
			listeners[index] = listener
		end
		for _, listener in ipairs(listeners) do
			listener:ReceiveEvent(name, ...)
		end
	end
	env.Auctionator = { EventBus = bus, Selling = { Events = events } }

	local SALE_ITEM_EVENTS = { events.BagItemClicked, events.ClearBagItem }
	local function IsValidItem(info)
		return info ~= nil and info.location ~= nil and env.C_Item.DoesItemExist(info.location)
	end
	local mixin = {}
	function mixin:OnShow()
		bus:Register(self, SALE_ITEM_EVENTS)
	end
	function mixin:OnHide()
		bus:Unregister(self, SALE_ITEM_EVENTS)
		self:UnlockItem()
	end
	function mixin:UnlockItem()
		if self.itemInfo ~= nil then
			if IsValidItem(self.itemInfo) then
				env.C_Item.UnlockItem(self.itemInfo.location)
			end
			self.itemInfo = nil
		end
	end
	function mixin:LockItem()
		if IsValidItem(self.itemInfo) then
			env.C_Item.LockItem(self.itemInfo.location)
		end
	end
	function mixin:Update()
		self.updates = (self.updates or 0) + 1
	end
	function mixin:Reset()
		self:UnlockItem()
		self:Update()
	end
	function mixin:ReceiveEvent(event, ...)
		if event == events.BagItemClicked then
			self:UnlockItem()
			local itemInfo = ...
			local function Selected()
				self.itemInfo = itemInfo
				self:LockItem()
				self:Update()
			end
			local delay = world.auctionator.itemKeyDelay
			if delay then
				world:After(delay, Selected)
			else
				Selected()
			end
		elseif event == events.ClearBagItem then
			self:Reset()
		end
	end
	function mixin:GetPostLimit()
		return math.min(env.C_AuctionHouse.GetAvailablePostCount(self.itemInfo.location), self.itemInfo.count)
	end
	--- The Post button (or Enter, or the post shortcut), with the default quantity: as many as
	--- possible, every one of the item in the bags.
	function mixin:PostItem()
		if self.itemInfo == nil or not env.C_Item.DoesItemExist(self.itemInfo.location) then
			return false
		end
		local quantity = self:GetPostLimit()
		if self.itemInfo.isCommodity then
			env.C_AuctionHouse.PostCommodity(self.itemInfo.location, 24, quantity, 100)
		else
			env.C_AuctionHouse.PostItem(self.itemInfo.location, 24, quantity, nil, 100)
		end
		return true
	end
	env.AuctionatorSaleItemMixin = mixin

	local state = { source = {} }
	world.auctionator = state
	bus:RegisterSource(state.source, "BagUse")
	world.auctionHouseShowHooks[#world.auctionHouseShowHooks + 1] = function()
		if state.saleItem then
			return
		end
		local tab = Widgets.Create(world, "Frame", "AuctionatorSellingFrame", env.AuctionHouseFrame)
		tab.shown = false
		local saleItem = Widgets.Create(world, "Frame", nil, tab)
		for key, value in pairs(env.AuctionatorSaleItemMixin) do
			saleItem[key] = value
		end
		tab.SaleItemFrame = saleItem
		env.AuctionatorSellingFrame = tab
		state.tab, state.saleItem = tab, saleItem
	end
	world.auctionHouseHideHooks[#world.auctionHouseHideHooks + 1] = function()
		if state.tab and state.tab.shown then
			state.saleItem:OnHide()
			state.tab:Hide()
		end
	end
end

--- Opens Auctionator's Selling tab; its sale item listens to the selling events while shown.
function Addons.ShowAuctionatorSelling(world)
	local state = world.auctionator
	if not state.tab.shown then
		state.tab:Show()
		state.saleItem:OnShow()
	end
	return state.saleItem
end

--- Picks an item for sale in Auctionator (its bag shortcut, its item list or a drag all fire
--- BagItemClicked) with what its bag cache knows (Groups.Utilities.ToPostingItem): count is every
--- one of the item in the bags.
function Addons.AuctionatorSelect(world, location)
	local env = world.env
	local saleItem = Addons.ShowAuctionatorSelling(world)
	local item = world:ItemAt(location)
	local info = {
		itemID = item.id,
		itemLink = world:Link(item),
		location = location,
		count = world:Count(item.id),
		isCommodity = env.C_Item.GetItemMaxStackSize(location) > 1,
	}
	env.Auctionator.EventBus:Fire(world.auctionator.source, env.Auctionator.Selling.Events.BagItemClicked, info)
	return saleItem
end

--- An addon loaded before this one that sells junk when a vendor opens. mode "useContainer"
--- sells each grey item with UseContainerItem and skips held ones (EllesmereUI's Sell Junk);
--- mode "sellAllJunk" calls the server-side C_MerchantFrame.SellAllJunkItems.
function Addons.InstallAutoSeller(world, env, mode)
	local frame = Widgets.Create(world, "Frame", nil)
	frame:RegisterEvent("MERCHANT_SHOW")
	frame:SetScript("OnEvent", function()
		if mode == "sellAllJunk" then
			env.C_MerchantFrame.SellAllJunkItems()
			return
		end
		for bagID = 0, 5 do
			for slot = 1, env.C_Container.GetContainerNumSlots(bagID) do
				local info = env.C_Container.GetContainerItemInfo(bagID, slot)
				if info and info.quality == 0 and not info.isLocked then
					env.C_Container.UseContainerItem(bagID, slot)
				end
			end
		end
	end)
end

return Addons
