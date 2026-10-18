-- Fake third-party addons: EllesmereUI Bags' overlay API and buttons, and an auto-seller that
-- acts on MERCHANT_SHOW before this addon does (like EllesmereUI QoL's "sell junk").
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
