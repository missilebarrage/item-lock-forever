local _, ns = ...

--- Padlocks on locked items: Blizzard's bags (separate or combined), bank and character slots,
--- and EllesmereUI Bags through its overlay API. Only this addon's own textures change: nothing
--- is written onto anyone's buttons (that taints item use) and nothing of Blizzard's is called.
---@class ItemLockForeverBadges
local Badges = ns.Badges
local Database = ns.Database
local Events = ns.Events
local Locks = ns.Locks

-- Inset from the chosen corner (Database: iconCorner, iconSize).
local INSETS = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function WeakKeys()
	return setmetatable({}, { __mode = "k" })
end
local badges = WeakKeys() -- button -> padlock texture
local readers = WeakKeys() -- button -> function(button): is its item locked?
local parents = WeakKeys() -- button -> frame the padlock belongs to (EllesmereUI's overlay)
local euiSlots = WeakKeys() -- EllesmereUI button -> { bag, slot, combined = itemID or nil } it shows

local function Place(badge, button)
	local corner = Database.Get("iconCorner")
	local inset = INSETS[corner] or INSETS.TOPRIGHT
	local size = Database.Get("iconSize")
	badge:SetSize(size, size)
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

--- The item ID when frame (the frame under the mouse, or one of its parents) is a combined
--- stack of EllesmereUI Bags, standing for every stack of the item; else nil.
function Badges.CombinedItemAt(frame)
	for _ = 1, 3 do
		if type(frame) ~= "table" then
			return nil
		end
		local shown = euiSlots[frame]
		if shown then
			return shown.combined
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

-- A lock changed: repaint the padlocks on screen (hidden buttons repaint when they show).
local function RefreshVisible()
	for button, read in pairs(readers) do
		if button:IsVisible() then
			SetBadge(button, read(button))
		end
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
	Events.On("ILF_LOCKS_CHANGED", RefreshVisible)
	-- A new corner or size moves every padlock at once, so the change shows while choosing it.
	Events.On("ILF_SETTINGS_CHANGED", function(key)
		if key == "iconCorner" or key == "iconSize" then
			for button, badge in pairs(badges) do
				Place(badge, button)
			end
		end
	end)
end
