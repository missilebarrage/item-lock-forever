local _, ns = ...

local L = ns.L

-- Locking and unlocking (chat).
L.LOCKED = "Locked %s."
L.LOCKED_STACK = "Locked this stack of %s."
L.LOCKED_STACKS = "Locked every stack of %s."
L.UNLOCKED = "Unlocked %s."
L.UNLOCKED_STACK = "Unlocked this stack of %s."
L.UNLOCKED_STACKS = "Unlocked every stack of %s."
L.THIS_ITEM = "this item"
L.THIS_ITEM_START = "This item"
L.READ_ONLY = "Locks can't be changed: they were saved by a newer version of ItemLockForever."
L.DATA_FROM_NEWER_VERSION =
	"Your locks were saved by a newer version of ItemLockForever. They still protect your items, but can't be changed until you update."

-- Tooltip.
L.TOOLTIP_LOCKED = "Locked: can't be sold, destroyed or disenchanted"
L.HINT_ALT_LEFT = "Alt+Click to unlock"
L.HINT_ALT_RIGHT = "Alt+Right-Click to unlock"
L.HINT_CTRL_ALT_RIGHT = "Ctrl+Alt+Right-Click to unlock"
L.HINT_CTRL_RIGHT = "Ctrl+Right-Click to unlock"
L.HINT_KEY = "%s to unlock"
L.HINT_HOLD = "Hold %s"

-- Protection.
L.CANT_SELL = "%s is locked, so it can't be sold."
L.CANT_DISENCHANT = "%s is locked, so it can't be disenchanted."
L.CANT_DESTROY = "%s is locked, so it can't be destroyed."
L.BOUGHT_BACK = "%s is locked, so it was bought back."
L.BUYBACK_FAILED = "Couldn't buy back %s. It's still in the vendor's Buyback tab."

-- Options and key binding.
L.BINDING_TOGGLE = "Lock/unlock hovered item"
L.OPTION_CLICK = "Lock with click"
L.OPTION_CLICK_TOOLTIP =
	"Click an item in your bags, bank or character window with this to lock or unlock it. Locked items can't be sold to a vendor, destroyed or disenchanted."
L.CLICK_ALT_LEFT = "Alt + Left Click"
L.CLICK_ALT_RIGHT = "Alt + Right Click"
L.CLICK_CTRL_ALT_RIGHT = "Ctrl + Alt + Right Click"
L.CLICK_CTRL_RIGHT = "Ctrl + Right Click"
L.CLICK_NONE = "Off (key binding only)"
L.OPTION_HOLD = "Hold to unlock"
L.OPTION_HOLD_TOOLTIP =
	"Unlocking takes holding the click (or the key) for a second, so a stray click can't unlock an item. Locking stays a quick click."
L.OPTION_LOCK_SOUND = "Lock sound"
L.OPTION_LOCK_SOUND_TOOLTIP = "Played when you lock an item. Picking one plays it."
L.OPTION_UNLOCK_SOUND = "Unlock sound"
L.OPTION_UNLOCK_SOUND_TOOLTIP = "Played when you unlock an item. Picking one plays it."
L.SOUND_NONE = "None"
L.SOUND_LOCK = "Lock"
L.SOUND_UNLOCK = "Unlock"
L.SOUND_KEYS = "Key ring"
L.SOUND_CHAIN = "Chain"
L.SOUND_CHEST = "Chest"
L.SOUND_VAULT = "Guild bank"
L.SOUND_FORGE = "Forge lock"
L.SOUND_CLICK = "Click"
L.SOUND_COINS = "Coins"
L.SOUND_GEMS = "Gems"
L.SOUND_PING = "Map ping"
L.OPTION_ERROR_SOUND = "Error sound"
L.OPTION_ERROR_SOUND_TOOLTIP =
	"Played when something tries to sell, disenchant or destroy a locked item. Picking one plays it."
L.ERROR_SOUND_ERROR = "Error"
L.ERROR_SOUND_DENIED = "Denied"
L.ERROR_SOUND_DECLINE = "Decline"
L.ERROR_SOUND_INVALID = "Invalid"
L.ERROR_SOUND_WARNING = "Warning"
L.ERROR_SOUND_ABANDON = "Abandon"
L.ERROR_SOUND_BLIP = "Blip"
L.ERROR_SOUND_RAID_WARNING = "Raid warning"
L.ERROR_SOUND_ALARM = "Alarm"
L.OPTION_ICON_CORNER = "Lock icon corner"
L.OPTION_ICON_CORNER_TOOLTIP = "The corner of an item's slot that shows the padlock."
L.CORNER_TOPLEFT = "Top left"
L.CORNER_TOPRIGHT = "Top right"
L.CORNER_BOTTOMLEFT = "Bottom left"
L.CORNER_BOTTOMRIGHT = "Bottom right"
L.OPTION_ICON_SIZE = "Lock icon size"
L.OPTION_ICON_SIZE_TOOLTIP = "The size of the padlock on item slots."
L.OPTIONS_IN_COMBAT = "Options can't be opened during combat."

-- Diagnostics.
L.DEBUG_ON = "Debug output on (item IDs and counts only). /ilf debug turns it off."
L.DEBUG_OFF = "Debug output off."
