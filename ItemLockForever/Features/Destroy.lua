local _, ns = ...

--- Destroy protection. Dropping an item outside the bags makes the game ask whether to destroy it
--- (DELETE_ITEM_CONFIRM, then Blizzard's dialog). For a locked item the cursor is cleared instead:
--- the item goes back to its slot, and the dialog closes itself, since its own update code hides
--- it once the cursor is empty. The dialog is never touched: tainting it could block real deletes.
---@class ItemLockForeverDestroy
local Destroy = ns.Destroy
local Events = ns.Events
local Feedback = ns.Feedback
local Locks = ns.Locks

local function OnDeleteConfirm(_, _, _, _, itemGUID)
	local guid = ns.Str(itemGUID)
	local location = C_Cursor.GetCursorItem()
	if location and not C_Item.DoesItemExist(location) then
		location = nil
	end
	if not guid and location then
		guid = ns.Str(C_Item.GetItemGUID(location))
	end
	local itemID = (guid and C_Item.GetItemIDByGUID(guid)) or (location and C_Item.GetItemID(location))
	if not Locks.IsLocked(itemID, guid) then
		return
	end
	ClearCursor()
	Feedback.Blocked("destroy", guid and C_Item.GetItemLinkByGUID(guid))
end

function Destroy.Init()
	Events.On("DELETE_ITEM_CONFIRM", OnDeleteConfirm)
end
