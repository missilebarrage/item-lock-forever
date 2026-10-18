# Changelog

## 0.1.0 — 2026-10-17

First version.

- Alt+Click an item in the bags, the bank or the character window to lock or unlock it. Gear and
  single stacks are locked as that exact item (for every character); locks follow items when
  stacks merge or split. On an EllesmereUI Bags combined stack (All Items), Alt+Click locks every
  stack of the item (per character).
- Locked items are held with the game's item lock while a vendor is open, and bought back if
  something sells one anyway.
- Dropping a locked item outside the bags puts it back instead of destroying it.
- Locked items can't be disenchanted: they're held while Disenchant waits for its target.
- A blocked sale, disenchant or destroy shows red error text and plays a chosen error sound.
- Padlocks on Blizzard's bags, bank and character window and on EllesmereUI Bags; "Locked" line
  in item tooltips.
- Options in Esc > Options > AddOns > ItemLockForever: the click to use, Hold to unlock, a key
  binding for the item under the mouse, the lock, unlock and error sounds (or none), and the padlock's corner and size.
  `/ilf debug` diagnostics.
