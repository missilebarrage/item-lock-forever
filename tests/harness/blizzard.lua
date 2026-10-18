-- Fake Blizzard item UI: the modified-click function, bag frames (separate and combined), the
-- bank, character slots, the item tooltip with its data processor, and the Auction House frame.
-- Tripwires record calls the addon must never make (world.violations), and buttons remember
-- their own keys so tests can prove the addon wrote nothing onto them.

local Blizzard = {}

local Widgets, Inventory -- shared with the loader (Blizzard.Init)

-- Keys the fake widget system itself adds to a button when something is parented to it.
local HARNESS_KEYS = { regions = true, children = true, scripts = true, points = true, shown = true }

--- Keys written onto a button after it was built, apart from the widget system's own.
function Blizzard.ForeignKeys(button)
	local foreign = {}
	for key in pairs(button) do
		if not button.ownKeys[key] and not HARNESS_KEYS[key] then
			foreign[#foreign + 1] = tostring(key)
		end
	end
	table.sort(foreign)
	return foreign
end

local function Seal(button)
	local own = { ownKeys = true }
	for key in pairs(button) do
		own[key] = true
	end
	button.ownKeys = own
	return button
end
Blizzard.Seal = Seal

--- Called once by the loader with its widget system and the inventory fake.
function Blizzard.Init(widgets, inventory)
	Widgets, Inventory = widgets, inventory
	-- Tooltip data methods (TooltipDataHandlerMixin) and refreshers the addon must never call.
	Widgets.Define("GetPrimaryTooltipInfo", function(self)
		return self.primaryInfo
	end)
	Widgets.Define("GetPrimaryTooltipData", function(self)
		return self.primaryInfo and self.primaryInfo.tooltipData
	end)
	Widgets.Define("GetProcessingTooltipInfo", function(self)
		return self.processingInfo
	end)
	Widgets.Define("RefreshData SetBagItem SetInventoryItem", function(self)
		self.world:Violation("tooltip refresh")
	end)
end

local function BagButton(world, parent)
	local button = Widgets.Create(world, "ItemButton", nil, parent)
	button.GetBagID = function(self)
		return self.bagID
	end
	button.bagID = 0
	button.id = 0
	return Seal(button)
end

function Blizzard.Install(world, env)
	world.tooltipPostCalls = {}
	local function Fire(...)
		world:Fire(...)
	end

	-- Base behavior for an Alt/Ctrl click: nothing in Blizzard's code handles those.
	env.HandleModifiedItemClick = function()
		return false
	end
	env.SpellIsTargeting = function()
		return world.spellTargeting == true
	end
	-- Every targeting spell in these tests targets items.
	env.SpellCanTargetItem = function()
		return world.spellTargeting == true
	end
	-- Only in C_Spell on Forever: the global IsCurrentSpell was removed with 11.0's spell API.
	env.C_Spell = {
		IsCurrentSpell = function(spellID)
			return world.currentSpell ~= nil and world.currentSpell == spellID
		end,
	}
	env.StaticPopup_Show = function()
		world:Violation("StaticPopup_Show")
	end
	env.StaticPopup_Hide = function()
		world:Violation("StaticPopup_Hide")
	end
	env.ContainerFrameUtil_EnumerateContainerFrames = function()
		world:Violation("ContainerFrameUtil_EnumerateContainerFrames")
		return ipairs({})
	end
	env.TooltipDataProcessor = {
		AddTooltipPostCall = function(dataType, callback)
			world.tooltipPostCalls[#world.tooltipPostCalls + 1] = { dataType = dataType, callback = callback }
		end,
	}

	-- Bag frames: ContainerFrameContainer.ContainerFrames[1..6] (backpack, bags 1-4, reagent
	-- bag) and the combined bags. Buttons are pooled and reassigned, like Blizzard's.
	local function ContainerFrame(name)
		local frame = Widgets.Create(world, "Frame", name)
		frame.pool, frame.valid = {}, {}
		frame.UpdateItems = function()
			if not world.harnessUpdating then
				world:Violation("UpdateItems")
			end
		end
		frame.EnumerateValidItems = function(self)
			return ipairs(self.valid)
		end
		env[name] = frame
		return frame
	end
	local frames = {}
	for index = 1, 6 do
		frames[index] = ContainerFrame("ContainerFrame" .. index)
	end
	env.ContainerFrameContainer = { ContainerFrames = frames }
	ContainerFrame("ContainerFrameCombinedBags")

	-- Bank (Camelot): pooled buttons whose Refresh calls through BankPanelItemButtonMixin.
	env.BankPanelItemButtonMixin = {
		Refresh = function() end,
	}
	world.bankButtons = {}

	-- Character window slots (0 ammo .. 19 tabard).
	env.PaperDollItemSlotButton_Update = function() end
	world.characterSlots = {}
	for slot = 0, 19 do
		local button = Widgets.Create(world, "Button", nil, env.UIParent)
		button.id = slot
		world.characterSlots[slot] = Seal(button)
	end

	if world.options.auctionHouse then
		env.AuctionHouseFrame = Widgets.Create(world, "Frame", "AuctionHouseFrame")
		env.AuctionHouseFrame.shown = false
	end

	-- Helpers for tests -------------------------------------------------------------

	local function Fill(frame, slots)
		for index, location in ipairs(slots) do
			local button = frame.pool[index] or BagButton(world, frame)
			frame.pool[index] = button
			button.bagID, button.id = location[1], location[2]
			frame.valid[index] = button
		end
		for index = #slots + 1, #frame.valid do
			frame.valid[index] = nil
		end
		world.harnessUpdating = true
		frame:UpdateItems()
		world.harnessUpdating = false
		return frame.valid
	end

	--- Opens a bag in its own frame (backpack = bag 0 in ContainerFrame1); returns its buttons.
	function world:ShowBag(bagID)
		local slots = {}
		for slot = 1, self.bags[bagID].size do
			slots[#slots + 1] = { bagID, slot }
		end
		return Fill(frames[bagID + 1], slots)
	end

	--- Opens the combined bags frame; returns its buttons.
	function world:ShowCombinedBags()
		local slots = {}
		for bagID = 0, 5 do
			for slot = 1, self.bags[bagID].size do
				slots[#slots + 1] = { bagID, slot }
			end
		end
		return Fill(env.ContainerFrameCombinedBags, slots)
	end

	--- Opens the bank on a tab (bag 6 by default); returns its buttons.
	function world:ShowBank(tab)
		tab = tab or 6
		for slot = 1, self.bags[tab].size do
			local button = self.bankButtons[slot]
			if not button then
				button = Widgets.Create(world, "ItemButton", nil, env.UIParent)
				button.GetItemLocation = function(own)
					return Inventory.BagLocation(own.tabID, own.slotID)
				end
				-- Camelot's Refresh calls BankPanelItemButtonMixin.Refresh(self) through the table.
				button.Refresh = function(own)
					env.BankPanelItemButtonMixin.Refresh(own)
				end
				button.tabID, button.slotID = tab, slot
				self.bankButtons[slot] = Seal(button)
			end
			button:Refresh()
		end
		return self.bankButtons
	end

	--- Opens the character window: every slot updates.
	function world:ShowCharacter()
		for slot = 0, 19 do
			env.PaperDollItemSlotButton_Update(self.characterSlots[slot])
		end
		return self.characterSlots
	end

	--- A click with modifiers held on an item: Blizzard's OnModifiedClick for bag, bank and
	--- character buttons calls HandleModifiedItemClick(link, itemLocation). over: the button
	--- under the mouse, when it matters (an EllesmereUI combined stack).
	function world:ModifiedClick(location, button, modifiers, over)
		self.modifiers = modifiers or { alt = true }
		self.mouseButton = button or "LeftButton"
		self.mouseFoci = over and { over } or nil
		local item = self:ItemAt(location)
		env.HandleModifiedItemClick(item and self:Link(item), location)
		self.modifiers, self.mouseButton = {}, nil
	end

	--- Presses a mouse button with modifiers held (GLOBAL_MOUSE_DOWN); they stay held until
	--- MouseUp.
	function world:MouseDown(button, modifiers)
		self.modifiers = modifiers or { alt = true }
		Fire("GLOBAL_MOUSE_DOWN", button or "LeftButton")
	end

	--- Releases the mouse button (and the modifiers).
	function world:MouseUp(button)
		Fire("GLOBAL_MOUSE_UP", button or "LeftButton")
		self.modifiers = {}
	end

	--- Shows the tooltip for an item, as a bag, bank or character button would; the mouse is over
	--- owner (a button), when given.
	function world:Hover(location, owner)
		self.mouseFoci = owner and { owner } or nil
		local tooltip = env.GameTooltip
		local item = self:ItemAt(location)
		local info
		if location.bagID then
			info = { getterName = "GetBagItem", getterArgs = { location.bagID, location.slotIndex, n = 2 } }
		else
			info = { getterName = "GetInventoryItem", getterArgs = { "player", location.equipmentSlotIndex, n = 2 } }
		end
		info.tooltipData = {
			type = 0,
			id = item and item.id,
			guid = item and self.behavior.tooltipGUID and item.guid or nil,
			lines = {},
		}
		tooltip.shown = true
		tooltip.lines = {}
		tooltip.primaryInfo = info
		tooltip.processingInfo = info
		for _, postCall in ipairs(self.tooltipPostCalls) do
			if postCall.dataType == 0 then
				postCall.callback(tooltip, info.tooltipData)
			end
		end
		tooltip.processingInfo = nil
		return tooltip
	end

	function world:HideTooltip()
		env.GameTooltip.shown = false
		env.GameTooltip.primaryInfo = nil
	end

	--- Text of the tooltip lines, in order.
	function world:TooltipText()
		local texts = {}
		for _, line in ipairs(env.GameTooltip.lines or {}) do
			texts[#texts + 1] = line.text
		end
		return texts
	end
end

return Blizzard
