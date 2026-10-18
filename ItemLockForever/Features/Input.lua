local _, ns = ...

--- Locking and unlocking: the chosen click on an item in the bags, the bank or the character
--- window, and a key binding for the item whose tooltip is showing. A click on one stack locks
--- that stack; a click on a combined stack (EllesmereUI Bags' All Items) locks every stack of the
--- item. With "Hold to unlock", unlocking takes holding the click (or the key) for a second;
--- locking stays a quick click.
---@class ItemLockForeverInput
local Input = ns.Input
local Badges = ns.Badges
local Database = ns.Database
local Events = ns.Events
local Locks = ns.Locks
local Sounds = ns.Sounds
local L = ns.L

--- Click combos (Database.CHOICES.click): the modifiers that must be held, every other one
--- released, and the mouse button. Shift and Ctrl+Left aren't offered: the game already uses
--- them on items (chat links, splitting stacks, sockets, the dressing room).
Input.COMBOS = {
	["ALT-LeftButton"] = { alt = true, button = "LeftButton", label = L.CLICK_ALT_LEFT, hint = L.HINT_ALT_LEFT },
	["ALT-RightButton"] = { alt = true, button = "RightButton", label = L.CLICK_ALT_RIGHT, hint = L.HINT_ALT_RIGHT },
	["CTRL-ALT-RightButton"] = {
		ctrl = true,
		alt = true,
		button = "RightButton",
		label = L.CLICK_CTRL_ALT_RIGHT,
		hint = L.HINT_CTRL_ALT_RIGHT,
	},
	["CTRL-RightButton"] = { ctrl = true, button = "RightButton", label = L.CLICK_CTRL_RIGHT, hint = L.HINT_CTRL_RIGHT },
}

--- The key binding's action (Bindings.xml); its name shows in Key Bindings and the options.
Input.BINDING = "ITEMLOCKFOREVER_TOGGLE"
BINDING_NAME_ITEMLOCKFOREVER_TOGGLE = L.BINDING_TOGGLE

-- An Alt+drag reaches the click function as well: one toggle per gesture.
local REPEAT_WINDOW = 0.3
local lastKey, lastTime = nil, 0
local HOLD_TIME = 1 -- seconds to hold the click or the key to unlock, with "Hold to unlock"

--- A bag or bank slot, or a worn item (equipment slots 0-19; 0 is the ammo slot).
local function IsOwnedLocation(location)
	if type(location) ~= "table" or not location.IsBagAndSlot then
		return false
	end
	if location:IsBagAndSlot() then
		return true
	end
	local slot = location:IsEquipmentSlot() and location:GetEquipmentSlot()
	return type(slot) == "number" and slot >= 0 and slot <= 19
end

local function LocationKey(location)
	if location:IsBagAndSlot() then
		local bag, slot = location:GetBagAndSlot()
		return bag .. ":" .. slot
	end
	return "worn:" .. location:GetEquipmentSlot()
end

local MESSAGES = {
	[true] = { item = L.LOCKED, stack = L.LOCKED_STACK, all = L.LOCKED_STACKS },
	[false] = { item = L.UNLOCKED, stack = L.UNLOCKED_STACK, all = L.UNLOCKED_STACKS },
}

local function Announce(location, locked, kind)
	local link = C_Item.GetItemLink(location) or L.THIS_ITEM
	ns.Print(MESSAGES[locked][kind]:format(link))
	Sounds.Play(Database.Get(locked and "lockSound" or "unlockSound"))
end

--- Locks or unlocks the item at location (a bag, bank or equipment slot), with a chat line.
---@param view string? "stack" (one stack, the default) or "all" (every stack of the item)
function Input.Toggle(location, view)
	if not IsOwnedLocation(location) or not C_Item.DoesItemExist(location) then
		return
	end
	local key, now = LocationKey(location), GetTime()
	if key == lastKey and now - lastTime < REPEAT_WINDOW then
		return
	end
	lastKey, lastTime = key, now
	local locked, kind = Locks.Toggle(location, view)
	if locked ~= nil then
		Announce(location, locked, kind)
	end
end

-- "all" when the button under the mouse stands for every stack of an item (a combined stack in
-- EllesmereUI Bags), else "stack".
local function View()
	local foci = GetMouseFoci()
	return Badges.CombinedItemAt(type(foci) == "table" and foci[1] or nil) and "all" or "stack"
end

local function ModifiersMatch(combo)
	return IsAltKeyDown() == (combo.alt == true) and IsControlKeyDown() == (combo.ctrl == true) and not IsShiftKeyDown()
end

-- Times a click belongs to something else: an item on the cursor, a spell waiting for its
-- target, or the Auction House, where Auctionator picks items to post with Alt+Click.
local function Busy()
	return CursorHasItem() or SpellIsTargeting() or (AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown())
end

-- Hold to unlock ---------------------------------------------------------------------------

local hold -- the running hold: { guid, source = "click" | "key", view, combo, timer }
local swallowClick = false -- the click that ends a finished hold mustn't lock the item again
local progress -- cooldown swipe over the item while a hold runs

local function ShowProgress()
	local foci = GetMouseFoci()
	local anchor = (type(foci) == "table" and foci[1]) or GameTooltip:GetOwner()
	if not anchor then
		return
	end
	if not progress then
		progress = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
		progress:SetFrameStrata("FULLSCREEN_DIALOG")
		progress:SetHideCountdownNumbers(true)
		progress:SetDrawBling(false)
		progress:SetDrawEdge(true)
	end
	progress:ClearAllPoints()
	progress:SetAllPoints(anchor)
	progress:SetCooldown(GetTime(), HOLD_TIME)
	progress:Show()
end

local function StopHold()
	if hold then
		hold.timer:Cancel()
		hold = nil
	end
	if progress then
		progress:Clear()
		progress:Hide()
	end
end

-- The hold is done: unlock if the same item is still under the mouse and still locked (and, for
-- a click, the modifiers are still held).
local function FinishHold()
	local finished = hold
	hold = nil
	StopHold()
	local location = Input.HoveredLocation()
	if not finished or not location or ns.Str(C_Item.GetItemGUID(location)) ~= finished.guid then
		return
	end
	if finished.source == "click" then
		if not ModifiersMatch(finished.combo) then
			return
		end
		swallowClick = true
	end
	if Locks.IsLockedFor(location, finished.view) then
		Input.Toggle(location, finished.view)
	end
end

local function StartHold(location, source, view)
	StopHold()
	local guid = ns.Str(C_Item.GetItemGUID(location))
	if not guid then
		return
	end
	hold = {
		guid = guid,
		source = source,
		view = view,
		combo = Input.COMBOS[Database.Get("click")],
		timer = C_Timer.NewTimer(HOLD_TIME, FinishHold),
	}
	ShowProgress()
end

-- The mouse button goes down: with the combo held over a locked item, the hold starts.
local function OnMouseDown(button)
	swallowClick = false
	if not Database.Get("holdToUnlock") then
		return
	end
	local combo = Input.COMBOS[Database.Get("click")]
	if not combo or button ~= combo.button or not ModifiersMatch(combo) or Busy() then
		return
	end
	local location, view = Input.HoveredLocation(), View()
	if location and Locks.IsLockedFor(location, view) then
		StartHold(location, "click", view)
	end
end

local function OnMouseUp()
	if hold and hold.source == "click" then
		StopHold()
	end
end

-- Clicks -----------------------------------------------------------------------------------

-- Post-hook of HandleModifiedItemClick(link, itemLocation): Blizzard's bag, bank and character
-- buttons, and bag addons built on Blizzard's item button, call it on every modified click.
local function OnModifiedItemClick(link, location)
	if link == nil or not IsOwnedLocation(location) then
		return
	end
	local combo = Input.COMBOS[Database.Get("click")]
	if not combo or GetMouseButtonClicked() ~= combo.button or not ModifiersMatch(combo) or Busy() then
		return
	end
	if swallowClick then
		swallowClick = false
		return
	end
	local view = View()
	if Database.Get("holdToUnlock") and Locks.IsLockedFor(location, view) then
		-- A quick click on a locked item: say how to unlock it.
		UIErrorsFrame:AddMessage(Input.Hint(), 1, 0.82, 0)
		return
	end
	Input.Toggle(location, view)
end

--- The item location a tooltip was asked for: a bag or bank slot, or a worn item.
---@param info table? a tooltip info table (getterName, getterArgs)
function Input.LocationFromTooltipInfo(info)
	local args = type(info) == "table" and info.getterArgs
	if type(args) ~= "table" then
		return nil
	end
	if info.getterName == "GetBagItem" then
		local bag, slot = ns.Num(args[1]), ns.Num(args[2])
		return bag and slot and ItemLocation:CreateFromBagAndSlot(bag, slot) or nil
	elseif info.getterName == "GetInventoryItem" and ns.Str(args[1]) == "player" then
		local slot = ns.Num(args[2])
		return slot and ItemLocation:CreateFromEquipmentSlot(slot) or nil
	end
	return nil
end

--- The item whose tooltip is showing, when it's one of yours. Any bag addon that shows the
--- game's item tooltip works.
function Input.HoveredLocation()
	if not GameTooltip:IsShown() or not GameTooltip.GetPrimaryTooltipInfo then
		return nil
	end
	local info = GameTooltip:GetPrimaryTooltipInfo()
	local data = type(info) == "table" and info.tooltipData
	local guid = type(data) == "table" and ns.Str(data.guid)
	local location = guid and C_Item.GetItemLocation(guid) or Input.LocationFromTooltipInfo(info)
	if IsOwnedLocation(location) and C_Item.DoesItemExist(location) then
		return location
	end
	return nil
end

--- How to unlock, for the tooltip: the click combo, else the bound key, else nil; "Hold …"
--- with "Hold to unlock".
---@return string?
function Input.Hint()
	local combo = Input.COMBOS[Database.Get("click")]
	local hint = combo and combo.hint
	if not hint then
		local key = GetBindingKey(Input.BINDING)
		hint = key and L.HINT_KEY:format(GetBindingText(key))
	end
	if hint and Database.Get("holdToUnlock") then
		hint = L.HINT_HOLD:format(hint)
	end
	return hint or nil
end

--- The key binding (Bindings.xml, which also reports the key's release): locks or unlocks the
--- item under the mouse. With "Hold to unlock", unlocking waits until the key was held long enough.
---@param keystate string? "down" or "up"
function ItemLockForever_ToggleHovered(keystate)
	if keystate == "up" then
		if hold and hold.source == "key" then
			StopHold()
		end
		return
	end
	local location, view = Input.HoveredLocation(), View()
	if not location then
		return
	end
	if Database.Get("holdToUnlock") and Locks.IsLockedFor(location, view) then
		StartHold(location, "key", view)
	else
		Input.Toggle(location, view)
	end
end

function Input.Init()
	if HandleModifiedItemClick then
		hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
	end
	Events.On("GLOBAL_MOUSE_DOWN", OnMouseDown)
	Events.On("GLOBAL_MOUSE_UP", OnMouseUp)
end
