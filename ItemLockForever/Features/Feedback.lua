local _, ns = ...

--- Feedback when something tries to sell, disenchant or destroy a locked item: red text in the
--- error frame, like the game's own errors, and the chosen error sound.
---@class ItemLockForeverFeedback
local Feedback = ns.Feedback
local Database = ns.Database
local Sounds = ns.Sounds
local L = ns.L

local TEXT = { sell = L.CANT_SELL, disenchant = L.CANT_DISENCHANT, destroy = L.CANT_DESTROY }
-- One sound for a burst of attempts (a double click, an auto-seller working through the bags).
local SOUND_GAP = 0.3
local lastSound = -math.huge

--- Plays the error sound, at most once in a short burst.
function Feedback.ErrorSound()
	local now = GetTime()
	if now - lastSound >= SOUND_GAP then
		lastSound = now
		Sounds.Play(Database.Get("errorSound"))
	end
end

--- Says that an action on a locked item was stopped.
---@param action string "sell", "disenchant" or "destroy"
---@param link string? the item's link
function Feedback.Blocked(action, link)
	UIErrorsFrame:AddExternalErrorMessage(TEXT[action]:format(link or L.THIS_ITEM_START))
	Feedback.ErrorSound()
end
