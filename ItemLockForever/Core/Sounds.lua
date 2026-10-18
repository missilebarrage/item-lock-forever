local _, ns = ...

--- Plays the sound choices of the settings (Database.SOUNDS for locking and unlocking,
--- Database.ERROR_SOUNDS for blocked actions) by key.
---@class ItemLockForeverSounds
local Sounds = ns.Sounds
local Database = ns.Database

local kits = {} -- sound key -> SOUNDKIT name
for _, list in ipairs({ Database.SOUNDS, Database.ERROR_SOUNDS }) do
	for _, sound in ipairs(list) do
		kits[sound[1]] = sound[3]
	end
end

--- Plays a sound choice by key ("none" plays nothing).
function Sounds.Play(key)
	local kit = kits[key]
	local soundKitID = kit and SOUNDKIT and SOUNDKIT[kit]
	if soundKitID then
		PlaySound(soundKitID)
	end
end
