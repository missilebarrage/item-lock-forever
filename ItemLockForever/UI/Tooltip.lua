local _, ns = ...

--- The "Locked" lines in item tooltips. Only real items (in the bags, the bank, worn or in the
--- buyback list) have a GUID, so item links and vendor goods never show them.
---@class ItemLockForeverTooltip
local Tooltip = ns.Tooltip
local Input = ns.Input
local Locks = ns.Locks
local L = ns.L

local LINE = "|A:" .. ns.LOCK_ATLAS .. ":14:14|a " .. L.TOOLTIP_LOCKED

local function GUIDOf(tooltip, data)
	local guid = ns.Str(data.guid)
	if guid then
		return guid
	end
	-- No GUID in the data: ask the slot the tooltip was built for.
	local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
	local location = Input.LocationFromTooltipInfo(info)
	if location and C_Item.DoesItemExist(location) then
		return ns.Str(C_Item.GetItemGUID(location))
	end
	return nil
end

local function OnItemTooltip(tooltip, data)
	if type(data) ~= "table" then
		return
	end
	local itemID = ns.Num(data.id)
	-- Most items: answered without a GUID lookup.
	if not Locks.MayBeLocked(itemID) then
		return
	end
	local guid = GUIDOf(tooltip, data)
	if not guid or not Locks.IsLocked(itemID, guid) then
		return
	end
	tooltip:AddLine(LINE, 1, 0.82, 0)
	local hint = Input.Hint()
	if hint then
		tooltip:AddLine(hint, 0.6, 0.6, 0.6)
	end
end

function Tooltip.Init()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	end
end
