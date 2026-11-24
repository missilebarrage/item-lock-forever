# ItemLockForever

Lock your items so they can't be sold to a vendor, listed on the Auction House, destroyed or
disenchanted by accident, for **World of Warcraft: Forever**.

## Features

- **Alt+Click to lock**: Alt+Click an item in your bags, the bank or the character window to
  lock it; Alt+Click it again to unlock it. You can pick another click, or use a key binding,
  in the options.
- **Gear is locked as that exact item.** A second copy of the same sword stays sellable, and the
  lock follows the item if you mail it to an alt.
- **Stacks are locked one at a time** in Blizzard's bags, OneBag/MultiBag views, the bank and the
  character window. Locked items keep their lock when stacks merge or split: merging a locked
  stack into another locks that one, and both halves of a split stay locked.
- **Every stack at once** from EllesmereUI Bags' All Items (and category) views and Baganator's
  "Group identical items", where one button stands for all your stacks of an item: Alt+Click
  there locks or unlocks every stack, including stacks you pick up later (per character). You can
  still unlock one of those stacks on its own in a normal view.
- **Can't be sold.** While a vendor is open, locked items are held with the game's own item lock
  (they show greyed out): right-clicking or dragging them does nothing, and auto-sellers that
  respect the game's lock leave them alone. If something still sells one, like the Sell All Junk
  button, it's bought back straight away.
- **Can't be destroyed.** Dropping a locked item outside your bags puts it back in its slot
  instead of asking to destroy it.
- **Can't be disenchanted.** While Disenchant waits for you to pick an item, locked items are held
  the same way (greyed out), so clicking one does nothing. Other spells that target items, like
  enchants and poisons, still work on locked items.
- **Can't be listed on the Auction House.** Put a locked item in the sell slot, in Blizzard's Sell
  tab or Auctionator's Selling tab, and it's taken out again at once. An item also can't be listed
  while another one of it in your bags is locked: a listing can take more than the stack you
  picked (Auctionator lists all of them by default), so the locked one could go too.
- **Tells you why.** Trying to sell, list, disenchant or destroy a locked item shows red error text
  ("… is locked, so it can't be sold.") and plays an error sound you can choose (or turn off).
- **Easy to see.** A padlock marks locked items in Blizzard's bags, bank and character window, in
  EllesmereUI Bags, Baganator and Bagnon, and the item tooltip says "Locked" whatever bag addon you
  use. Its corner, size and color are up to you.
- **No setup.** Works with the default UI and with bag addons built on Blizzard's item buttons.

## Commands and options

| Command | |
| --- | --- |
| `/ilf` | Open the options (`/itemlock` works too) |
| `/ilf debug` | Show what the addon does at vendors and the Auction House (item IDs and counts only) |

**Esc > Options > AddOns > ItemLockForever** has:

- **Lock with click**: Alt + Left Click (default), Alt + Right Click, Ctrl + Alt + Right Click,
  Ctrl + Right Click, or Off.
- **Hold to unlock** (off by default): unlocking takes holding the click, or the key, for a
  second; a swipe fills over the item while you hold. Letting go early, letting go of the
  modifier or moving to another item cancels it. Locking stays a quick click.
- **Lock/unlock hovered item**: a key binding that locks or unlocks the item under the mouse.
  It's also under Key Bindings > ItemLockForever.
- **Lock sound** and **Unlock sound** (Guild bank and Key ring by default): None, Lock, Unlock,
  Key ring, Chain, Chest, Guild bank, Forge lock, Click, Coins, Gems or Map ping. Picking one
  plays it.
- **Error sound** (Error by default): None, Error, Denied, Decline, Invalid, Warning, Abandon,
  Blip, Raid warning or Alarm, for a blocked sale, disenchant or destroy. Picking one plays it.
- **Lock icon corner** (top right by default), **Lock icon size** (8 to 32, 14 by default) and
  **Lock icon color** (a color picker; white keeps the padlock's own colors): where the padlock
  sits on a slot, how big it is and its color. Padlocks on screen change as you pick. In
  Baganator, the corner is the one Baganator's own icon settings give the padlock (it starts in
  this addon's corner).

At the Auction House the click is left to Auctionator, which uses Alt+Click to pick items to
post; the key binding still works there.

## Good to know

- While a vendor window is open, or Disenchant waits for a target, locked items can't be used,
  equipped or moved either. Unlock an item (or leave the vendor) to use it.
- The buy-back can only reach the vendor's buyback list, which holds the last 12 sales.
- Locks protect against selling, listing, destroying and disenchanting only. Mailing and trading
  still work, and addons that delete items themselves (without the game's destroy dialog) aren't
  stopped.
- At the Auction House a locked item shows in the sell slot for a moment before it's taken out.
  Blizzard's Sell tab and Auctionator are covered; other auction addons with their own sell slot
  aren't.
- The gamepad UI's destroy dialog isn't covered.
- Bagnon's and Baganator's views of other characters' bags, and of the bank while you're away,
  show no padlocks: they show saved records, not the items themselves.
- In Bagnon, Alt+Left Click also flashes every copy of the item (Bagnon's Flash Find, on by
  default). Turn it off in Bagnon's options, or pick another click, if that's in the way.

## Privacy

Locks and settings are kept in your saved variables. ItemLockForever sends nothing anywhere.

## Development

Requirements: bash, curl, gcc/make and Python 3 (for unzipping). Everything else is pinned and
installed into the git-ignored `.tools/` folder.

```sh
scripts/bootstrap.sh   # Lua 5.1.5, luacheck and StyLua
scripts/test.sh        # lint, tests and the distribution check
scripts/install.sh     # copy ItemLockForever/ into your AddOns folder(s): $ILF_ADDONS_DIR, or one per line in .tools/addons-path
scripts/package.sh     # build a zip for manual installation
```

- `ItemLockForever/` is the addon; only this folder ships. `tests/` runs the addon in a sandbox
  against a fake game client (`tests/harness/`): bags, the bank, worn items, the cursor, a vendor
  with its buyback list, the Auction House, Blizzard's item buttons, EllesmereUI Bags, Baganator,
  Bagnon and Auctionator. `docs/API-NOTES.md`
  records the client facts the code relies on; `docs/VERIFICATION.md` is the in-game checklist.
- Code is formatted with StyLua and must pass luacheck. Every bug fix gets a regression test.
- Releases: tag `vX.Y.Z` and push; the GitHub workflow packages with the BigWigs packager and
  uploads to CurseForge (project 1751300, set in the TOC; needs the `CF_API_KEY` repository
  secret). `docs/CURSEFORGE.html` is the CurseForge project description, updated there by hand.

## License

MIT, see [LICENSE](LICENSE). Not affiliated with Blizzard Entertainment or EllesmereUI.
