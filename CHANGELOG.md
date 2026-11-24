# Changelog

## 0.3.0 — 2026-11-24

- Auction House: locked items can't be listed. A locked item put in the sell slot (Blizzard's Sell
  tab or Auctionator's Selling tab) is taken out again at once, with the error text and sound. An
  item also can't be listed while another one of it in your bags is locked, since a listing can
  take more than the stack you picked.
- The tooltip line now says locked items can't be auctioned either.
- Locked items: a list of every lock under Esc > Options > AddOns > ItemLockForever (or `/ilf
  list`), with where each item is and an Unlock button for each.
- Bagnon: locked items show the padlock, in the bags and in the bank while you're at it (not in
  views of other characters or of the bank from afar).

## 0.2.0 — 2026-11-14

- Baganator: locked items show the padlock. It starts in the Lock icon corner; after that,
  Baganator's own icon settings (Customise > Icons) place it. Alt+Click on a "Group identical
  items" button locks every stack.
- Lock icon color: pick any color for the padlock, like gold (white keeps its own colors).

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
