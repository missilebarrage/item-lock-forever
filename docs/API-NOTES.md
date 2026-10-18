# Client notes

Facts about the WoW Forever client (Interface 16001, game type `camelot`, Mainline-family UI)
that ItemLockForever relies on. Unless noted, they come from Blizzard's UI source as mirrored in
Gethe/wow-ui-source, branch `forever`, build 1.60.1.70374 (commit 735496de); paths are relative
to `Interface/AddOns/`. "Unverified" means only the game can confirm it: see VERIFICATION.md.

## Clicks on items

- Bag item buttons (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`):
  `ContainerFrameItemButtonMixin:OnClick` sends every modified click to `OnModifiedClick` (line
  1669), which calls the global `HandleModifiedItemClick(link, itemLocation)` (line 1788) before
  split-stack. There is no early return for a locked (held) item, so unlocking a held item works.
  `OnDragStart` calls `OnClick("LeftButton")`, so an Alt+drag arrives as a modified click too.
- The bank (`Mainline/BankFrameTemplates.lua:460`) and the character slots
  (`Camelot/PaperDollFrame.lua:2138`) call `HandleModifiedItemClick` with an item location as
  well; bag addons built on `ContainerFrameItemButtonTemplate` (EllesmereUI Bags, Baganator,
  Bagnon…) inherit the bag path. Item links without a location (loot, merchant goods, chat)
  reach it with a nil location and are ignored.
- Default modified clicks (`Blizzard_FrameXML/Bindings_Camelot.xml`, lines 1537-1556):
  CHATLINK = Shift+Left, DRESSUP = Ctrl+Left, EXPANDITEM = Shift+Right, SPLITSTACK and
  AUTOLOOTTOGGLE = Shift. Nothing handles Alt or Ctrl+Right on items. Holding Alt over a
  character slot opens the equipment flyout (SHOWITEMFLYOUT = Alt); the slot still gets the click.
  Unverified: whether Ctrl+Alt counts as Ctrl for DRESSUP (Ctrl+Alt+Left isn't offered).
- `GetMouseButtonClicked()` is documented (`Blizzard_APIDocumentationGenerated/InputDocumentation.lua`).
- Auctionator (installed version) post-hooks `HandleModifiedItemClick` too and selects bag items
  for posting with Alt+Left (configurable) while the Auction House is shown, so ItemLockForever
  ignores clicks while `AuctionHouseFrame` is shown.

## Selling and buyback

- Plain right-click at a vendor: `ContainerFrameItemButton_OnClick` → `C_Container.UseContainerItem`
  (ContainerFrame.lua ~1609). Dropping a cursor item on the vendor: `PickupMerchantItem`
  (`Mainline/MerchantFrame.xml` 628-639). Sell All Junk: `MerchantSellAllJunkButton`
  (MerchantFrame.lua 211, 482) → `C_MerchantFrame.SellAllJunkItems()`, a single request handled
  by the server.
- `C_Item.LockItem`, `UnlockItem`, `LockItemByGUID`, `UnlockItemByGUID`, `IsLocked`
  (`ItemDocumentation.lua` from line 1596) have no restriction flags. Blizzard uses `LockItem` to
  hold the item in the Auction House sell slot (`Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSharedTemplates.lua:554`).
  Unverified: whether a held item refuses selling, pickup and Sell All Junk.
- Buyback: `GetNumBuybackItems`, `GetBuybackItemInfo` (3rd return: price), `GetBuybackItemLink`
  and `BuybackItem` are used by MerchantFrame.lua; `C_MerchantFrame.GetBuybackItemID` and
  `C_TooltipInfo.GetBuybackItem` (`TooltipInfoDocumentation.lua:172`) are documented. The newest
  sale is the last index. Unverified: buyback tooltip data carries the item's GUID, the item keeps
  its GUID when bought back, and `BuybackItem` works outside a click.
- The vendor frame opens through the interaction manager
  (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE`, `Enum.PlayerInteractionType.Merchant` = 5);
  `MERCHANT_SHOW`, `MERCHANT_CLOSED` and `MERCHANT_UPDATE` are documented. EllesmereUI QoL sells
  junk on `MERCHANT_SHOW` and loads before ItemLockForever, so its handler runs first.
  Unverified: which of the two opening events comes first.

## Disenchanting

- Disenchant is spell 13262 on Forever (SpellName table, build 1.60.1.70374, wago.tools export).
- While a spell waits for its target, a left-click on a bag item calls
  `C_Container.UseContainerItem` (`ContainerFrameItemButton_OnClick`, ContainerFrame.lua 1505-1508),
  the same call a vendor sale uses, so a held item should refuse it too. Unverified.
- `CURRENT_SPELL_CAST_CHANGED(cancelledCast)` is a synchronous event
  (`SpellBookDocumentation.lua:839`); Blizzard's gamepad bags open on it when `SpellCanTargetItem()`
  turns true (ContainerFrame.lua:630). `C_Spell.IsCurrentSpell(spellID)` is documented
  (`SpellDocumentation.lua:741`, namespace C_Spell). The old global `IsCurrentSpell` doesn't exist
  on Forever (`Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua:115`): calling it was the
  first version's bug, verified in game on 2026-10-15. Because the event comes the moment targeting starts, a macro that
  casts and then `/use`s an item finds it already held.
- `SpellStopCasting` and `SpellStopTargeting` back the secure `/stopcasting` and `/stopspelltarget`
  commands (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua` 390-399): addons can't stop a cast, so
  the hold before the click is the only protection.
- Unverified: worn items can't be disenchanted (only bag items are held).

## Destroying

- `DELETE_ITEM_CONFIRM(itemName, qualityID, bonding, questWarn, itemGUID?)`
  (`ItemDocumentation.lua:1789`), routed by `Blizzard_Game/Camelot/EventRouting.lua:7` to
  `GameEvent.HandleDeleteItemConfirm` (`Camelot/EventImplementation.lua:48`), which shows
  DELETE_ITEM / DELETE_QUEST_ITEM (`Blizzard_StaticPopup_Game/GameDialogDefs.lua` 1552, 1581) or
  DELETE_GOOD_ITEM / DELETE_GOOD_QUEST_ITEM (`Mainline/GameDialogDefs.lua` 570, 711).
- Their `OnUpdate` hides the dialog when `not CursorHasItem()` (except with the gamepad UI), so
  `ClearCursor()` closes it without addon code touching StaticPopup. `OnAccept` deletes by
  `data.itemGUID` with `C_Item.DeleteItem`, which is restricted: tainting the dialog could block
  real deletes.

## Tooltips

- `GameTooltip:SetBagItem` / `SetInventoryItem` are Lua wrappers that call
  `C_TooltipInfo.GetBagItem` / `GetInventoryItem` (getterName "GetBagItem" with (bag, slot);
  "GetInventoryItem" with ("player", slot)). Bank items use `SetBagItem(bankTabID, slot)`.
- `GetPrimaryTooltipInfo`, `GetPrimaryTooltipData`, `GetProcessingTooltipInfo`
  (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` 393-411);
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn(tooltip, data))`.
  Item data has `id` and, for real items, `guid` (Unverified in game; the code falls back to the
  tooltip's slot). Blizzard warns that addon-tainted tooltip info breaks tooltips with secret
  lines (`Blizzard_GameTooltip/Mainline/GameTooltip.lua:1003`), so the addon never refreshes them.

## Padlock hook points

- Bags: `ContainerFrameContainer.ContainerFrames` (parentArray) and `ContainerFrameCombinedBags`
  exist from load; each has `UpdateItems` (ContainerFrame.lua:1192) and `EnumerateValidItems`.
  Buttons are pooled and reassigned. `ContainerFrameUtil_EnumerateContainerFrames` builds a
  Blizzard table on first use (ContainerFrame.lua ~2267-2320), so the addon doesn't call it.
- Bank: `CamelotBankPanelItemButtonMixin:Refresh` calls `BankPanelItemButtonMixin.Refresh(self)`
  through the table (`Camelot/BankFrame.lua:254`).
- Character slots: `PaperDollItemSlotButton_Update(button)` (Camelot/PaperDollFrame.lua).
- The padlock atlas `QuestSharing-Padlock` is used by Forever's action buttons
  (`Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml:66`). The addon list reads the TOC's
  `IconAtlas` (`Blizzard_AddOnList/AddonList.lua:391`).
- EllesmereUI Bags 9.5.5 (installed): `EUI_Bags.RegisterItemOverlayIcon(name, fn(btn, data))`,
  with `data.bag`, `data.slot`, `data.info`, `data.itemLink` valid during the call only;
  placeholder slots pass bag 0 / slot 0. It asks addons to keep their state off its buttons and
  parent their frames to `btn._textOverlay`.
- In its All Items and category views EllesmereUI combines stacks of an item into one button
  (`MergeDuplicates`, EllesmereUIBags.lua ~801): the painted data is then a copy carrying the total
  in `_mergedCount`, and `bag`/`slot` are the first stack's. OneBag/MultiBag never combine, and
  nothing combines while a vendor, bank, mail, trade or auction window is open, or with
  `bagMergeDuplicates` off. A click there reaches `HandleModifiedItemClick` with the first stack's
  location; the button under the mouse (`GetMouseFoci()[1]`) tells the two apart.

## Error text and sound

- `UIErrorsFrame:AddExternalErrorMessage(text)` shows red text like the game's errors but plays
  no sound (`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua` ~150-170; game errors get theirs
  from `GetGameMessageInfo`), so the addon plays its own error sound.
- A held item is refused without a message. The click that tries it still calls
  `C_Container.UseContainerItem` (a bag click while Disenchant waits, ContainerFrame.lua 1505-1508;
  a right-click at a vendor, ~1609; secure item buttons, `Blizzard_FrameXML/SecureTemplates.lua:774`),
  and no Blizzard code keeps its own copy of that function, so a `hooksecurefunc` post-hook sees
  each attempt. It returns at once unless something is held.

## Sounds

- The sound choices are `SOUNDKIT` constants from `Blizzard_SharedXML/Mainline/SoundKitConstants.lua`
  (Lock 218229 and Unlock 218517 at lines 617-618; Key ring 8938, Chain 1212, Chest 44331,
  Guild bank 12189, Forge lock 54131, Click 856, Coins 120, Gems 1204, Map ping 3175). That file
  is shared with retail, so each ID was checked against Forever's own data: every one is in the
  SoundKit table and has a file in SoundKitEntry for build 1.60.1.70374 (wago.tools DB2 export).
- Error sounds (checked the same way for build 1.60.1.70450, together with the ones above): Error
  47355, Denied 17341, Decline 139830, Invalid 286118, Warning 15273, Abandon 846, Blip 684, Raid
  warning 8959, Alarm 12889.

## Hold to unlock

- `GLOBAL_MOUSE_DOWN(button)` / `GLOBAL_MOUSE_UP(button)` (`SystemDocumentation.lua:64`) come for
  every mouse press anywhere; the item is the one the tooltip shows (as for the key binding).
  `GetMouseFoci()` and `IsMouseButtonDown()` are global (`InputDocumentation.lua`, no namespace).
- The swipe is a `Cooldown` frame from `CooldownFrameTemplate`
  (`Blizzard_FrameXMLUtil/Mainline/Cooldown.xml`, loaded as `[Family]\Cooldown.xml`); its methods
  are in `FrameAPICooldownDocumentation.lua`. It's parented to UIParent and only anchored over the
  item, so nothing is added to anyone's button.
- A binding with `runOnUp="true"` runs on press and release with `keystate` "down"/"up", as
  Blizzard's movement bindings do (`Blizzard_FrameXML/Bindings_Camelot.xml` line 4 onward).
- Item buttons click on mouse up, after the hold: the click that ends a finished hold is ignored
  so it doesn't lock the item again.

## Options and key binding

- `CreateKeybindingEntryInitializer(bindingIndex, search)`
  (`Blizzard_Settings_Shared/Blizzard_Keybindings.lua:532`) builds a key binding row; Blizzard
  adds one to a normal settings page the same way (`Blizzard_SettingsDefinitions_Frame/Controls.lua`
  89-94). `C_KeyBindings.GetBindingIndex(action)` is documented. The settings panel saves
  bindings when it closes (`Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua:224-239`).
- `Bindings.xml` in the addon folder is loaded by the client without being listed in the TOC. The
  key binding page groups bindings by their `category` attribute, shown as `_G[category]` when
  that's a string, else the text itself.
