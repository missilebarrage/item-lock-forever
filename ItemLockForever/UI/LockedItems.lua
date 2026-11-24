local _, ns = ...

--- Esc > Options > AddOns > ItemLockForever > Locked items: every lock this addon keeps, each with
--- an Unlock button. Items locked on their own are listed wherever they are: in the bags, worn, in
--- the bank, or elsewhere (the mail, another character, or the bank while you're away, where the
--- game can't look them up). Every-stack locks are this character's. The page is a canvas in the
--- settings panel; while it's shown it rebuilds when locks, the bags or item data change, and
--- hidden it does nothing.
---@class ItemLockForeverLockedItems
local LockedItems = ns.LockedItems
local Database = ns.Database
local Events = ns.Events
local Locks = ns.Locks
local Sounds = ns.Sounds
local L = ns.L

local ROW_HEIGHT = 30
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- the bags and the reagent bag
-- List order: every-stack locks first, then by where the item is.
local ORDER = { all = 1, bags = 2, worn = 3, bank = 4, elsewhere = 5 }
local WHERE = { bags = L.WHERE_BAGS, worn = L.WHERE_WORN, bank = L.WHERE_BANK, elsewhere = L.WHERE_ELSEWHERE }

local page, scroll, content, summary, category
local rows = {}
local pending = false

-- Where an item locked on its own is: "bags", "worn", "bank" or "elsewhere", and its location.
local function Find(guid)
	local location = C_Item.GetItemLocation(guid)
	if not location or not C_Item.DoesItemExist(location) then
		return "elsewhere", nil
	end
	if location:IsEquipmentSlot() then
		return "worn", location
	end
	local bag = location:GetBagAndSlot()
	if bag and bag >= 0 and bag <= LAST_BAG then
		return "bags", location
	end
	return "bank", location
end

-- What a row shows for a lock: the item's link when it's here, else its name in its quality's
-- color (nil until the game has loaded the item; GET_ITEM_INFO_RECEIVED then rebuilds the list).
local function Describe(lock)
	local entry = { itemID = lock.itemID, guid = lock.guid, where = "all" }
	if lock.guid then
		entry.where, entry.location = Find(lock.guid)
	end
	local link = entry.location and C_Item.GetItemLink(entry.location)
	local name = C_Item.GetItemNameByID(lock.itemID)
	if link then
		entry.text = link
	elseif name then
		entry.text = "[" .. name .. "]"
		local quality = C_Item.GetItemQualityByID(lock.itemID)
		if quality then
			entry.r, entry.g, entry.b = C_Item.GetItemQualityColor(quality)
		end
	else
		C_Item.RequestLoadItemDataByID(lock.itemID)
	end
	entry.sortName = (name or ""):lower()
	if entry.where == "all" then
		entry.detail = L.EVERY_STACK
	else
		local count = entry.location and C_Item.GetStackCount(entry.location) or 1
		entry.detail = count > 1 and L.WHERE_STACK:format(WHERE[entry.where], count) or WHERE[entry.where]
	end
	return entry
end

local function Before(a, b)
	if a.where ~= b.where then
		return ORDER[a.where] < ORDER[b.where]
	end
	if a.sortName ~= b.sortName then
		return a.sortName < b.sortName
	end
	if a.itemID ~= b.itemID then
		return a.itemID < b.itemID
	end
	return (a.guid or "") < (b.guid or "")
end

local function Entries()
	local entries = {}
	for _, lock in ipairs(Locks.List()) do
		entries[#entries + 1] = Describe(lock)
	end
	table.sort(entries, Before)
	return entries
end

local function ShowTooltip(row)
	local entry = row.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if entry.location then
		GameTooltip:SetItemByGUID(entry.guid)
	else
		GameTooltip:SetItemByID(entry.itemID)
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function Unlock(entry)
	local unlocked
	if entry.guid then
		unlocked = Locks.UnlockItem(entry.guid)
	else
		unlocked = Locks.UnlockEveryStack(entry.itemID)
	end
	if unlocked then
		Sounds.Play(Database.Get("unlockSound"))
	end
end

local function NewRow(index)
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", content, "RIGHT")
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.unlockButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.unlockButton:SetSize(90, 22)
	row.unlockButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.unlockButton:SetText(L.UNLOCK)
	row.unlockButton:SetScript("OnClick", function()
		if row.entry then
			Unlock(row.entry)
		end
	end)
	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.detail:SetWidth(170)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetPoint("RIGHT", row.unlockButton, "LEFT", -12, 0)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)
	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", HideTooltip)
	rows[index] = row
	return row
end

local function Fill(row, entry)
	row.entry = entry
	row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
	row.label:SetText(entry.text or L.ITEM_NUMBER:format(entry.itemID))
	row.label:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
	row.detail:SetText(entry.detail)
	row.unlockButton:SetEnabled(not Database.IsReadOnly())
	row:Show()
end

local function Refresh()
	local width = scroll:GetWidth()
	if width and width > 0 then
		content:SetWidth(width)
	end
	local entries = Entries()
	for index, entry in ipairs(entries) do
		Fill(rows[index] or NewRow(index), entry)
	end
	for index = #entries + 1, #rows do
		rows[index].entry = nil
		rows[index]:Hide()
	end
	content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
	if #entries == 0 then
		summary:SetText(L.LOCKED_NONE)
	else
		summary:SetText(#entries == 1 and L.LOCKED_COUNT_ONE or L.LOCKED_COUNT:format(#entries))
	end
end

local function RefreshIfShown()
	pending = false
	if page:IsVisible() then
		Refresh()
	end
end

-- Rebuilds on the next frame, once for a burst of changes, and only while the page is shown.
local function Schedule()
	if not pending and page:IsVisible() then
		pending = true
		C_Timer.After(0, RefreshIfShown)
	end
end

local function Build()
	page = CreateFrame("Frame")
	page:Hide()

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L.LOCKED_ITEMS)

	local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	help:SetPoint("RIGHT", page, "RIGHT", -24, 0)
	help:SetJustifyH("LEFT")
	help:SetText(L.LOCKED_ITEMS_HELP)

	summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	summary:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)

	scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -30, 16)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)

	page:SetScript("OnShow", Refresh)
end

--- Adds the page under the options' category. Called by Options at PLAYER_LOGIN, after the
--- category is registered.
function LockedItems.Register(parentCategory)
	Build()
	category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, page, L.LOCKED_ITEMS)
	Events.On("ILF_LOCKS_CHANGED", Schedule)
	Events.On("BAG_UPDATE_DELAYED", Schedule)
	Events.On("GET_ITEM_INFO_RECEIVED", Schedule)
end

--- Opens the page in the options window (not during combat).
function LockedItems.Open()
	if InCombatLockdown() then
		ns.Print(L.OPTIONS_IN_COMBAT)
		return
	end
	if category then
		pcall(Settings.OpenToCategory, category:GetID())
	end
end

-- For tests.
function LockedItems.Page()
	return page
end

function LockedItems.Rows()
	return rows
end

function LockedItems.Summary()
	return summary:GetText()
end
