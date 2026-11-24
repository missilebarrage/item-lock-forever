local _, ns = ...

--- Padlocks on locked items: Blizzard's bags (separate or combined), bank and character slots,
--- EllesmereUI Bags through its overlay API, Baganator through its corner widgets and Bagnon
--- through its item buttons' update. Only this addon's own textures change: nothing is written
--- onto anyone's buttons (that taints item use) and nothing of Blizzard's is called.
---@class ItemLockForeverBadges
local Badges = ns.Badges
local Database = ns.Database
local Events = ns.Events
local Locks = ns.Locks
local L = ns.L

-- Inset from the chosen corner (Database: iconCorner, iconSize, iconColor).
local INSETS = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function WeakKeys()
	return setmetatable({}, { __mode = "k" })
end
local badges = WeakKeys() -- button -> padlock texture
local readers = WeakKeys() -- button -> function(button): is its item locked?
local parents = WeakKeys() -- button -> frame the padlock belongs to (EllesmereUI's overlay)
local euiSlots = WeakKeys() -- EllesmereUI button -> { bag, slot, combined = itemID or nil } it shows

-- Size and color. White keeps the padlock's own colors; any other color tints a grey copy of
-- it, so a gold padlock looks gold whatever colors the texture has.
local function Style(badge)
	local size = Database.Get("iconSize")
	badge:SetSize(size, size)
	local hex = Database.Get("iconColor")
	local r = tonumber(hex:sub(3, 4), 16) / 255
	local g = tonumber(hex:sub(5, 6), 16) / 255
	local b = tonumber(hex:sub(7, 8), 16) / 255
	badge:SetDesaturated(not (r == 1 and g == 1 and b == 1))
	badge:SetVertexColor(r, g, b)
end

local function Place(badge, button)
	Style(badge)
	local corner = Database.Get("iconCorner")
	local inset = INSETS[corner] or INSETS.TOPRIGHT
	badge:ClearAllPoints()
	badge:SetPoint(corner, button, corner, inset[1], inset[2])
end

local function SetBadge(button, locked)
	local badge = badges[button]
	if not locked then
		if badge then
			badge:Hide()
		end
		return
	end
	if not badge then
		badge = (parents[button] or button):CreateTexture(nil, "OVERLAY", nil, 7)
		badge:SetAtlas(ns.LOCK_ATLAS)
		Place(badge, button)
		badges[button] = badge
	end
	badge:Show()
end

local function Paint(button, read)
	readers[button] = read
	SetBadge(button, read(button))
end

local function ReadBagButton(button)
	return Locks.IsLockedInBag(button:GetBagID(), button:GetID())
end

local function ReadBankButton(button)
	return Locks.IsLockedAt(button:GetItemLocation())
end

local function ReadCharacterSlot(button)
	return Locks.IsLockedEquipped(button:GetID())
end

local function ReadEllesmereButton(button)
	local shown = euiSlots[button]
	if not shown then
		return false
	end
	-- A combined stack shows the padlock when any of its stacks is locked.
	if shown.combined then
		return Locks.AnyLocked(shown.combined)
	end
	return Locks.IsLockedInBag(shown[1], shown[2])
end

local function OnContainerUpdate(frame)
	for _, button in frame:EnumerateValidItems() do
		Paint(button, ReadBagButton)
	end
end

local function HookContainer(frame)
	if type(frame) == "table" and frame.UpdateItems and frame.EnumerateValidItems then
		hooksecurefunc(frame, "UpdateItems", OnContainerUpdate)
	end
end

local function OnBankButtonRefresh(button)
	Paint(button, ReadBankButton)
end

local function OnCharacterSlotUpdate(button)
	Paint(button, ReadCharacterSlot)
end

-- EllesmereUI Bags' painter: runs for every slot it draws; data = { bag, slot, info, itemLink }
-- is only valid during the call. Empty and placeholder slots (bag 0, slot 0) have no info. In
-- its All Items and category views, one button can stand for several stacks of an item: the
-- data then carries their total in _mergedCount (EllesmereUIBags.lua, MergeDuplicates).
local function OnEllesmerePaint(button, data)
	local bag = type(data) == "table" and ns.Num(data.bag)
	local slot = type(data) == "table" and ns.Num(data.slot)
	if not bag or not slot or slot < 1 or not data.info then
		euiSlots[button] = nil
		SetBadge(button, false)
		return
	end
	local shown = euiSlots[button]
	if shown then
		shown[1], shown[2] = bag, slot
	else
		shown = { bag, slot }
		euiSlots[button] = shown
	end
	shown.combined = data._mergedCount ~= nil and ns.Num(data.info.itemID) or nil
	parents[button] = button._textOverlay
	Paint(button, ReadEllesmereButton)
end

-- Baganator: a corner widget (Baganator.API). Baganator puts it in the corner picked in its own
-- settings (this addon's corner the first time), shows it when the update says so, and passes the
-- item button's details (its BGR field). Items you have with you carry an itemLocation
-- ({ bagID, slotIndex }); offline views (other characters, a bank you aren't at) don't. There
-- are no bagID or slotID fields. With "Group identical items" one button stands for several
-- stacks: its slot is the first stack's, and its itemCount is their total.
local BAGANATOR_WIDGET = "itemlockforever_padlock"
local BAGANATOR_CORNERS = {
	TOPLEFT = "top_left",
	TOPRIGHT = "top_right",
	BOTTOMLEFT = "bottom_left",
	BOTTOMRIGHT = "bottom_right",
}
local baganatorBadges = WeakKeys() -- padlock texture -> true

-- The bag and slot of the item Baganator's details show, when it's an item you have with you.
local function BaganatorSlot(details)
	local location = type(details) == "table" and details.itemLocation
	if type(location) ~= "table" then
		return nil
	end
	local bag, slot = ns.Num(location.bagID), ns.Num(location.slotIndex)
	if bag and slot then
		return bag, slot
	end
	return nil
end

-- The item ID when Baganator's details stand for more than the stack in their slot.
local function BaganatorCombined(details)
	local bag, slot = BaganatorSlot(details)
	local count = bag and ns.Num(details.itemCount)
	if not count then
		return nil
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and count > (ns.Num(info.stackCount) or 1) then
		return ns.Num(details.itemID)
	end
	return nil
end

local function OnBaganatorInit(itemButton)
	local badge = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
	badge:SetAtlas(ns.LOCK_ATLAS)
	Style(badge)
	baganatorBadges[badge] = true
	return badge
end

local function OnBaganatorUpdate(_, details)
	local bag, slot = BaganatorSlot(details)
	if not bag then
		return false
	end
	local combined = BaganatorCombined(details)
	if combined then
		return Locks.AnyLocked(combined)
	end
	return Locks.IsLockedInBag(bag, slot)
end

-- Bagnon (12.x, on its BagBrother core): item buttons are classes on Blizzard's item button
-- template, and Item:Update runs whenever a button shows an item. Bag and bank buttons
-- (ContainerItem) reach Item.Update through a call that looks it up when it runs, so a hook on it
-- covers buttons built before or after this one; guild bank and void storage buttons pass through
-- it too, but show other slots, so only the inventory and bank frames get padlocks. A cached frame
-- (another character's bags, the bank while you're away) shows Bagnon's records, not the game's
-- slots: no padlock there.
local BAGNON_FRAMES = { inventory = true, bank = true }

local function ReadBagnonButton(button)
	if not button.IsCached or button:IsCached() then
		return false
	end
	local bag = ns.Num(button.GetBag and button:GetBag())
	local slot = ns.Num(button:GetID())
	return bag ~= nil and slot ~= nil and Locks.IsLockedInBag(bag, slot)
end

local function OnBagnonUpdate(button)
	local frame = type(button) == "table" and button.frame
	if type(frame) == "table" and BAGNON_FRAMES[frame.id] then
		Paint(button, ReadBagnonButton)
	end
end

--- The item ID when frame (the frame under the mouse, or one of its parents) is a button standing
--- for every stack of an item (EllesmereUI Bags' All Items, Baganator's grouped items); else nil.
function Badges.CombinedItemAt(frame)
	for _ = 1, 3 do
		if type(frame) ~= "table" then
			return nil
		end
		local shown = euiSlots[frame]
		if shown then
			return shown.combined
		end
		-- Baganator keeps an item button's details in its BGR field.
		local details = Baganator and rawget(frame, "BGR")
		if type(details) == "table" then
			return BaganatorCombined(details)
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

-- A lock changed: repaint the padlocks on screen (hidden buttons repaint when they show), and
-- have Baganator run its widgets again.
local function RefreshVisible()
	for button, read in pairs(readers) do
		if button:IsVisible() then
			SetBadge(button, read(button))
		end
	end
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh({ Baganator.Constants.RefreshReason.ItemWidgets })
	end
end

function Badges.Init()
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	if type(frames) == "table" then
		for _, frame in ipairs(frames) do
			HookContainer(frame)
		end
	end
	HookContainer(ContainerFrameCombinedBags)
	if BankPanelItemButtonMixin and BankPanelItemButtonMixin.Refresh then
		hooksecurefunc(BankPanelItemButtonMixin, "Refresh", OnBankButtonRefresh)
	end
	if PaperDollItemSlotButton_Update then
		hooksecurefunc("PaperDollItemSlotButton_Update", OnCharacterSlotUpdate)
	end
	if EUI_Bags and EUI_Bags.RegisterItemOverlayIcon then
		EUI_Bags.RegisterItemOverlayIcon(ns.NAME, OnEllesmerePaint)
	end
	if Baganator and Baganator.API and Baganator.API.RegisterCornerWidget then
		local corner = BAGANATOR_CORNERS[Database.Get("iconCorner")] or "top_right"
		Baganator.API.RegisterCornerWidget(
			L.BAGANATOR_WIDGET,
			BAGANATOR_WIDGET,
			OnBaganatorUpdate,
			OnBaganatorInit,
			{ corner = corner, priority = 1 },
			true
		)
	end
	local bagnonItem = Bagnon and Bagnon.Item
	if type(bagnonItem) == "table" and type(bagnonItem.Update) == "function" then
		hooksecurefunc(bagnonItem, "Update", OnBagnonUpdate)
	end
	Events.On("ILF_LOCKS_CHANGED", RefreshVisible)
	-- A new corner, size or color changes every padlock at once, so the change shows while
	-- choosing it. (Baganator keeps the corner its own settings give the widget.)
	Events.On("ILF_SETTINGS_CHANGED", function(key)
		if key == "iconCorner" or key == "iconSize" or key == "iconColor" then
			for button, badge in pairs(badges) do
				Place(badge, button)
			end
			for badge in pairs(baganatorBadges) do
				Style(badge)
			end
		end
	end)
end
