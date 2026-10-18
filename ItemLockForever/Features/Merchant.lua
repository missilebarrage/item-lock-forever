local _, ns = ...

--- Vendor protection.
--- Hold: while a vendor is open, locked items in the bags are held (Holds), so the game won't sell
--- them or let them be picked up.
--- Backstop: whatever still sells a locked item (Blizzard's server-side Sell All Junk, an
--- auto-seller that ran before the hold, an item dragged from the character window) is bought
--- back, one at a time: an item or stack locked by its GUID, or a stack of an item locked for
--- every stack that wasn't in the buyback list yet.
---@class ItemLockForeverMerchant
local Merchant = ns.Merchant
local Events = ns.Events
local Feedback = ns.Feedback
local Holds = ns.Holds
local Locks = ns.Locks
local L = ns.L

local QUIET = 0.3 -- seconds without sales or bag changes before the buyback list is checked
local PENDING_TIMEOUT = 2 -- seconds for a buyback to leave the list before trying again
local MAX_TRIES = 2

local open = false
local known ---@type table<string, true>? buyback entries already checked (by GUID), kept all session
local tries = {} ---@type table<string, number>
local gaveUp = {} ---@type table<string, true>
local pending, pendingSince, pendingLink
local timer

local function BuybackGUID(index)
	local data = C_TooltipInfo.GetBuybackItem(index)
	return type(data) == "table" and ns.Str(data.guid) or nil
end

local function InBuyback(guid)
	for index = 1, GetNumBuybackItems() do
		if BuybackGUID(index) == guid then
			return true
		end
	end
	return false
end

local function ShouldRestore(itemID, guid)
	return Locks.IsGUIDLocked(guid) or (Locks.IsTypeLocked(itemID, guid) and not known[guid])
end

local Schedule

local function Restore(index, guid)
	local link = GetBuybackItemLink(index) or L.THIS_ITEM
	local count = (tries[guid] or 0) + 1
	local _, _, price = GetBuybackItemInfo(index)
	if count > MAX_TRIES or (ns.Num(price) or 0) > GetMoney() then
		gaveUp[guid] = true
		ns.Print(L.BUYBACK_FAILED:format(link))
		return
	end
	tries[guid] = count
	pending, pendingSince, pendingLink = guid, GetTime(), link
	Locks.ExpectReturn(guid, C_MerchantFrame.GetBuybackItemID(index))
	ns.Debug("buy back: entry", index, "item", C_MerchantFrame.GetBuybackItemID(index), "try", count)
	BuybackItem(index)
	Schedule(PENDING_TIMEOUT)
end

-- Checks the buyback list, newest first, and buys back one locked item at a time: a buyback
-- shifts the entries after it, so the next one waits until this one has left the list.
local function Check()
	timer = nil
	if not open then
		return
	end
	if pending then
		if not InBuyback(pending) then
			ns.Print(L.BOUGHT_BACK:format(pendingLink))
			Feedback.ErrorSound()
		else
			local waited = GetTime() - pendingSince
			if waited < PENDING_TIMEOUT - 0.05 then
				-- Still waiting for the server; check again when the wait is over.
				Schedule(PENDING_TIMEOUT - waited)
				return
			end
		end
		pending = nil
	end
	for index = GetNumBuybackItems(), 1, -1 do
		local guid = BuybackGUID(index)
		if guid and not gaveUp[guid] then
			if not ShouldRestore(C_MerchantFrame.GetBuybackItemID(index), guid) then
				known[guid] = true
			elseif not pending then
				Restore(index, guid)
			end
		end
	end
end

-- Checks once things have been quiet for a moment (sales and bag changes come in bursts).
function Schedule(delay)
	if timer then
		timer:Cancel()
	end
	timer = C_Timer.NewTimer(delay or QUIET, Check)
end

local function OnOpen()
	if open then
		return
	end
	open = true
	wipe(tries)
	wipe(gaveUp)
	if not known then
		-- First vendor this session: what's already in the buyback list was sold earlier.
		known = {}
		for index = 1, GetNumBuybackItems() do
			local guid = BuybackGUID(index)
			if guid then
				known[guid] = true
			end
		end
	end
	ns.Debug("vendor open, buyback entries", GetNumBuybackItems())
	Holds.Start("vendor")
	Schedule()
end

local function OnClose()
	if not open then
		return
	end
	open = false
	if timer then
		timer:Cancel()
		timer = nil
	end
	pending = nil
	Locks.ForgetReturns()
	Holds.Stop("vendor")
	ns.Debug("vendor closed")
end

---@return boolean
function Merchant.IsOpen()
	return open
end

function Merchant.Init()
	-- The interaction events can come before MERCHANT_SHOW, so whichever is first holds the
	-- items (auto-sellers act on MERCHANT_SHOW).
	local merchant = Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant
	if merchant then
		Events.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
			if kind == merchant then
				OnOpen()
			end
		end)
		Events.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
			if kind == merchant then
				OnClose()
			end
		end)
	end
	Events.On("MERCHANT_SHOW", OnOpen)
	Events.On("MERCHANT_CLOSED", OnClose)
	Events.On("MERCHANT_UPDATE", function()
		if open then
			Schedule()
		end
	end)
	-- Holds has already held what arrived (it registered first); then check the buyback list.
	Events.On("BAG_UPDATE_DELAYED", function()
		if open then
			Schedule()
		end
	end)
end
