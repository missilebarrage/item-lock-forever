-- Fake third-party addons: EllesmereUI Bags' overlay API and buttons, Baganator's corner widget
-- API and buttons, and an auto-seller that acts on MERCHANT_SHOW before this addon does (like
-- EllesmereUI QoL's "sell junk").
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
