local _, ns = ...

--- Disenchant protection: while Disenchant waits for its target, locked items are held (Holds),
--- so clicking one, or a macro's /use, can't pick it. The event comes the moment targeting
--- starts, even inside a macro. A cast can't be stopped once it runs (SpellStopCasting is
--- protected), so the hold is the protection. Other spells that target items (enchants, poisons,
--- lockpicking) are left alone.
---@class ItemLockForeverDisenchant
local Disenchant = ns.Disenchant
local Events = ns.Events
local Holds = ns.Holds

local DISENCHANT = 13262

local function Update()
	if SpellCanTargetItem() and C_Spell.IsCurrentSpell(DISENCHANT) then
		Holds.Start("disenchant")
	else
		Holds.Stop("disenchant")
	end
end

function Disenchant.Init()
	Events.On("CURRENT_SPELL_CAST_CHANGED", Update)
end
