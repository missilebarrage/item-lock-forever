# In-game verification

Checks only the game can answer, riskiest first. Before starting: install with
`scripts/install.sh`, restart the game fully (a new addon folder isn't picked up by `/reload`),
open BugSack, and run `/console taintLog 1` (the log is written to `Logs/taint.log`).
`/ilf debug` prints what the vendor code decides (item IDs and counts only).

Test items: a cheap piece of gear, a stack of something (cloth, potions), a grey item, and a
copy of the gear piece if you have one.

## 1. Vendor hold

1. Lock the gear piece, the stack and the grey item (Alt+Click each). Talk to a vendor.
2. Expected: the locked items look greyed out in your bags (EllesmereUI Bags too), and
   `/ilf debug` showed `hold: locked items 3 newly held 3`.
3. Right-click each locked item: nothing is sold, red text says it's locked and can't be sold,
   and the error sound plays. Try to drag one onto the vendor: it can't be
   picked up. With EllesmereUI's auto-sell on, the locked grey item stays.
4. Buy one more of the stack's item from the vendor (if it sells it): the purchase works.
5. Close the vendor: the items aren't grey any more and can be used and moved.

Fallbacks: if held items still sell, rely on the buy-back (section 2) or add click-blocking
covers on Blizzard's and EllesmereUI's slots. If buying more of a locked stack breaks, hold gear
only.

## 2. Buy-back

1. Lock a grey item and press the vendor's Sell All Junk button.
2. Expected: the grey item comes back within a second, a chat line says it was bought back, and
   it's still locked (tooltip, padlock). `/ilf debug` shows `buy back: entry …`.
3. Drag a locked item from the character window onto the vendor: it comes back to your bags.

Fallbacks: if nothing comes back and `/ilf debug` shows no `buy back` line, buyback tooltips
have no GUID: compare the buyback list before and after instead, and move the lock to the
returned item's GUID. If a `buy back` line shows but nothing returns, `BuybackItem` needs a real
click: print where the item is instead.

## 3. Disenchant

1. Lock an item you could disenchant, and keep an unlocked one. Cast Disenchant.
2. Expected: the locked items show greyed out while the cursor waits for a target. Click the
   locked item: it isn't disenchanted, the cursor keeps waiting, red text says it can't be
   disenchanted and the error sound plays. Press Escape: the items look normal
   again.
3. Cast Disenchant and pick the unlocked item: it's disenchanted as usual, and the locked items
   stop being grey when the cast starts.
4. Cast Disenchant and click a locked item you're wearing in the character window: the game
   refuses (worn items can't be disenchanted).
5. If you have an enchant or a poison: apply it to a locked item. It works.

Fallbacks: if a held item can still be disenchanted, cover locked bag slots with click-catching
frames while Disenchant waits (Blizzard's bags and EllesmereUI Bags). If worn items can be
disenchanted, hold worn locked items too.

## 4. Destroy

1. Drag a locked common item out of your bags onto the game world.
2. Expected: no destroy dialog (or one that disappears at once), the item is back in its slot,
   a red message says it's locked, and the error sound plays.
3. Repeat with a locked rare or better item (the dialog that asks you to type DELETE) and with a
   stack of a locked type.
4. Drag an unlocked item out: the normal dialog appears and destroying works.

Fallback: if the dialog stays open, keep the message only and document it. Never patch
StaticPopup.

## 5. Locking

1. Alt+Click items in Blizzard's bags (separate and combined), the bank, the character window and
   EllesmereUI Bags (grid and list view, and its bank).
2. Expected: one chat line per click ("Locked [item]." / "Locked every stack of [item]."), a
   lock sound, the padlock in the item's top-right corner, and the tooltip lines.
3. Alt+drag an item: it toggles once.
4. Open the Auction House and Alt+Click a bag item: Auctionator selects it, the lock doesn't
   change.

Fallback: if clicks don't toggle reliably, also check that the mouse button is still down.

## 6. Stacks

1. In Blizzard's bags (or EllesmereUI's OneBag view) with two stacks of the same item, Alt+Click
   one: "Locked this stack of …", and only that stack shows the padlock.
2. In EllesmereUI's All Items view (both stacks on one button), Alt+Click the button: "Locked
   every stack of …" (or "Unlocked every stack" if one was locked), and both stacks follow.
3. With every stack locked, Alt+Click one stack in OneBag: only that stack unlocks.
4. Drag a locked stack onto an unlocked one: the combined stack is locked. Split a locked stack
   (Shift+Click): both parts are locked. Sort the bags: locked items are still locked.

Fallback: if All Items clicks lock one stack only, EllesmereUI changed how it marks combined
stacks (`_mergedCount`).

## 7. Options and key binding

Hold to unlock (turn it on first):

1. Alt+Click an unlocked item: it locks at once.
2. Alt+Click a locked item quickly: it stays locked and "Hold Alt+Click to unlock" shows on screen.
3. Hold Alt and the mouse button on a locked item: a swipe fills over it and after a second it
   unlocks; letting go doesn't lock it again.
4. Start a hold and let go of Alt, or slide to another item, before the second is up: nothing
   unlocks.
5. With the key binding: a quick press on a locked item does nothing; holding the key a second
   unlocks it.

Everything else:

1. Esc > Options > AddOns > ItemLockForever: set "Lock with click" to Ctrl + Right Click. Alt+Click
   does nothing now; Ctrl+Right Click toggles; the tooltip hint follows.
2. Set a key in the "Lock/unlock hovered item" row, close the options, reopen them: the key is
   still there, and also under Key Bindings > ItemLockForever. Hover an item and press the key.
3. `/ilf` opens the options.
4. Pick each Lock sound and Unlock sound: each plays when picked, and locking/unlocking plays the
   chosen one. None is silent.

Fallback: if the row doesn't save, leave it out; Key Bindings still works. Drop any sound that
plays nothing.

## 8. Across sessions and characters

1. Log out and back in: the locks are still there.
2. Mail a locked gear piece to an alt: it's locked there too. The alt's stacks of a type you
   locked on the first character are not locked.

Fallback: if gear locks are lost after a relog, item GUIDs aren't stable and gear needs another
identity.

## 9. Taint

1. With some items locked: use a potion from your bags in combat, deposit and withdraw at the
   bank, sell unlocked items, destroy an unlocked item.
2. Expected: no "Interface action failed because of an AddOn" message and nothing about
   ItemLockForever in `Logs/taint.log`. Sesh's gold numbers at the vendor look right.

Fallback: remove the hook that causes it; the padlocks are optional.

## 10. Looks

1. The padlock doesn't cover other markers (junk coin, quest marker, item level) in Blizzard's
   bags or EllesmereUI Bags, and the tooltip lines read well.
2. With the bags open, change Lock icon corner and Lock icon size in the options: the padlocks
   move and resize right away, and keep the new place after closing and reopening the bags.
3. The addon list shows the padlock icon.

Fallback: move the padlock to another corner.

## Results

- 2026-10-17, build 1.60.1.70450: user acceptance test passed ("everything is working well"). Sections weren't reported one by one.
