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

## Baganator

From Baganator's public source (release 834, 2026-10-08, TOC Interface lists 16001), read in a mirror
(github.com/hippuli/Baganator), and rechecked in release 856 as installed on Forever (2026-11-14):

- `Baganator.API.RegisterCornerWidget(label, id, onUpdate, onInit, defaultPosition, isFast)`
  (`API/Main.lua` ~229). `onInit(itemButton)` returns the frame or texture to show; Baganator
  re-parents it, places it in the corner its settings give the widget and shows it when
  `onUpdate(widget, details)` returns true (false hides, nil means "not ready, ask again").
  `defaultPosition = {corner, priority}` is applied once per widget id. Only the first widget of a
  corner that shows is displayed. Default corners: top left junk + item level, top right empty,
  bottom left equipment set, bottom right quantity (`Core/Config.lua` 46-49).
- `details` is the button's `BGR` table, built by `GetInfo` (`ItemViewCommon/ItemButton.lua` ~192):
  Syndicator's `Search.GetBaseInfo` (`itemLink`, `itemID`, `quality`, `itemCount`, `isBound`,
  `hasLoot`, `tooltipGetter`; `Syndicator/Search/BaseInfo.lua`), then the live container button's
  early callback, which runs before the widgets and adds `guid` and
  `itemLocation = {bagID, slotIndex}` while the slot holds the item (`ItemButton.lua` ~675-681,
  and ~1241 for the classic button). **`BGR` has no `bagID` or `slotID`**: those are fields of the
  category views' item lists (`CategoryViews/BagLayout.lua` ~66-76), not of the button's details.
  Reading them made the 0.2.0 padlock never show (found in UAT). Offline views (other characters,
  the bank when away) use cached buttons without `itemLocation`.
- "Group identical items" (`category_item_grouping`, on by default) folds identical items into the
  first one's entry and adds up `itemCount` (`CategoryViews/BagLayout.lua` ~205-220): a button
  stands for several stacks when its `itemCount` is larger than its slot's stack. Grouping is off in
  live views while items are being transferred (bank, mail, vendor).
- `Baganator.API.RequestItemButtonsRefresh({Baganator.Constants.RefreshReason.ItemWidgets})`
  re-runs the widgets on the next frame. Its own icon widgets are textures created on the item
  button (`API/ItemButton.lua` ~307-322).

## Bagnon

From Bagnon 12.1.12 with its BagBrother core, as installed on Forever (2026-11-24). Bagnon's own
files and BagBrother's shared frame code (included by `Bagnon/src/main.xml`) run as the addon
`Bagnon`, a global (`WildAddon-1.1` `NewAddon`), so its classes are `Bagnon.Item`,
`Bagnon.ContainerItem`, `Bagnon.GuildItem` and `Bagnon.VaultItem`.

- Item buttons are classes on Blizzard's `ContainerFrameItemButtonTemplate`
  (`BagBrother/core/classes/item.lua` line 7), so Blizzard's click handling, and with it
  `HandleModifiedItemClick`, runs for them.
- `Item:Bind` copies every method of the class chain onto a new button, collected once per class
  on its first button ("required for secure frames", `item.lua` 75-92). A hook on a class
  method made after a class's first button doesn't reach that class's buttons.
- `ContainerItem:Update` (bag and bank buttons, `core/classes/containerItem.lua` 62-76) calls
  `self:Super(Item):Update(...)`, which Poncho looks up on the class when it runs
  (`libs/Poncho-2.0/Poncho-2.0.lua`, `SuperCall` and `Base:Super`): a hook on `Bagnon.Item.Update`
  reaches every bag and bank button, whenever it was built. `GuildItem` and `VaultItem` don't
  define `Update`, so their buttons carry a copy of `Item.Update` (hooked if built after the
  hook); their "bag" is a guild tab (`frames/guild/item.lua` 75).
- `Item:Update(info)` sets `self.info` from `self:GetItemInfo(bag, slot)` and runs on every layout
  (`core/classes/itemGroup.lua` 119) and slot change. A button's frame (`button.frame`,
  `core/classes/parented.lua`) has an id: `inventory`, `bank`, `guild` or `vault`
  (`core/api/frames.lua` 9-12).
- Cached slots (another character, or the bank while you're away: `Bank:IsCached`,
  `frames/bank/bank.lua` 93) get their info from Bagnon's records (`core/classes/frameBase.lua`
  169-199), which carry no `cached` flag: `button:IsCached()` (ContainerItem,
  `containerItem.lua` 132) is the test.
- Bagnon builds its inventory frame at `PLAYER_ENTERING_WORLD`, showing and hiding it once
  (`core/core.lua` ~74-84), so its first bag buttons exist before the bags are ever opened.
- Alt+Left Click on an item also plays Bagnon's Flash Find when `flashFind` is on, as it is by
  default (`item.lua` ~102, `core/api/settings.lua` 20).

## Auction House

From the Forever UI source (Gethe/wow-ui-source `forever`, build 1.60.1.70959) and Auctionator 347
as installed on Forever (2026-11-18); the Auctionator lines cited are unchanged in 352 (2026-11-24):

- Forever has the modern Auction House, `Blizzard_AuctionHouseUI`, loaded on demand when the
  Auction House first opens (its TOC allows `mainline`; Forever's game type `camelot` counts as
  mainline). `AuctionHouseFrame` exists only after that.
- Every way into Blizzard's sell slot ends in a sell frame's `SetItem`: a right-click in the bags
  (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua` ~1555-1561, when the item passes
  `C_AuctionHouse.IsSellItemValid(itemLocation, false)` or the Sell tab is showing), a drop on the
  slot (the item display's `onItemChangedCallback`) and a drop on the sell frame's overlay all call
  `AuctionHouseFrame:SetPostItem(itemLocation)` (`Shared/Blizzard_AuctionHouseFrame.lua` 608),
  which calls `ClearPostItem()` and then `ItemSellFrame:SetItem` or `CommoditiesSellFrame:SetItem`
  (`Shared/Blizzard_AuctionHouseSellFrame.lua` 374; `GetItem()` returns the item location).
- The sell slot locks the item it shows with `C_Item.LockItem` and unlocks the one it lets go
  (`Shared/Blizzard_AuctionHouseSharedTemplates.lua` 546-566), and Auctionator's sale slot does the
  same (`Source_ModernAH/Tabs/Selling/Mixins/SaleItem.lua` 131-146). Both then post the item they
  locked, so the game's item lock doesn't stop a listing, and either slot would undo a hold: there
  is no Auction House hold.
- `CanPostItem` doesn't check the item again (`Shared/Blizzard_AuctionHouseSellFrame.lua` 471).
  `C_AuctionHouse.PostItem` and `PostCommodity` have `HasRestrictions = true`
  (`AuctionHouseDocumentation.lua` 864-899): addons can't wrap them, but Auctionator calls them from
  its own button, so they need a hardware event, not Blizzard's code.
- Closing the Auction House empties the sell slots (`AuctionHouseFrameMixin:OnHide`, line 456).
- Auctionator's TOC loads files by game type; on Forever: `Libs_ModernAH`, `Source`,
  `Source_Mainline`, `Source_ModernAH` and `Source_Forever/Constants.lua`.
- Every way into Auctionator's sale slot fires `Auctionator.Selling.Events.BagItemClicked`
  (`"bag_item_clicked"`, `Source/Selling/Events.lua`): its bag shortcut (Alt+Click by default,
  `Source_ModernAH/Selling/Hooks.lua`, checks `IsSellItemValid`), its item list and a drop on its
  item slot (`Source/Tabs/Selling/Mixins/BagItemSelected.lua`). `AuctionatorSaleItemMixin:ReceiveEvent`
  waits for the item key (`Auctionator.AH.GetItemKeyInfo`, sometimes a moment later), then sets
  `itemInfo` (with `location`), calls `LockItem()` and `Update()` (`SaleItem.lua` 205-216).
  `ClearBagItem` (`"clear_bag_item"`) runs `Reset()`, which unlocks the item and empties the slot;
  Auctionator fires it itself (`Source/Tabs/Selling/Mixins/BagUse.lua` 42). Its event bus raises an
  error for a source that wasn't registered with `RegisterSource` (`Source/Utilities/EventBusMixin.lua`).
- Auctionator's default quantity is `GetPostLimit()`, `min(GetAvailablePostCount(location),
  itemInfo.count)`, where `count` adds up every stack of the item in the bags (`SaleItem.lua`
  177-183 and 376-388, `Source/Groups/BagCache.lua` 47): a listing takes all of them.
- The sale slot is `AuctionatorSellingFrame.SaleItemFrame`, built from the mixin when the Auction
  House first shows (`Source_ModernAH/Core/Mixin.lua` `InitializeAuctionHouseTabs`,
  `Tabs/Mixins/TabContainer.lua`), so a hook on the mixin made at login reaches it.
- Auctionator clears Blizzard's sell frames from its own code (`ItemSellFrame:SetItem(nil, nil,
  false)`, `Source_ModernAH/Selling/Hooks.lua` 7-8).
- Unknown until tested in game: whether `IsSellItemValid` turns down an item the game holds, and
  which stacks the server takes when a listing is bigger than the stack picked (assumed: any).

## Locked items page

From the Forever UI source (build 1.60.1.71037):

- `Settings.RegisterCanvasLayoutSubcategory(category, frame, name)` returns the subcategory and its
  layout (`Blizzard_Settings_Shared/Blizzard_Settings.lua` 166, through `SettingsInbound` 99). When
  the page is picked the panel parents the frame to its canvas, anchors it to fill it (unless the
  layout has anchor points), shows it and calls `frame:OnRefresh()` if there is one
  (`Blizzard_SettingsPanel.lua`, `DisplayLayout`). `OnDefault` would run for the Defaults button:
  the page has none, so Defaults never unlocks anything (`Blizzard_ImplementationReadme.lua`).
- `CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags)` is a row
  with a button (`Blizzard_SettingControls.lua` 1040; `addSearchTags` must be given, 1045), whose
  click is set straight as the button's `OnClick` (979). `Settings.OpenToCategory(categoryID)` goes
  through `C_SettingsUtil.OpenSettingsPanel` (`Blizzard_Settings.lua` 144). TimmyUI opens its own
  subcategory pages the same way.
- `GameTooltip:SetItemByID` and `SetItemByGUID` are TooltipDataHandler accessors
  (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` 525, 601).
- `C_Item.GetItemNameByID`, `GetItemIconByID`, `GetItemQualityByID`, `GetItemQualityColor` (r, g, b
  and a quality string), `RequestLoadItemDataByID` and `GetStackCount` are documented in
  `ItemDocumentation.lua`; a requested item's data comes with `GET_ITEM_INFO_RECEIVED`.
- Unknown until tested in game: whether `C_Item.GetItemLocation(guid)` finds bank items while
  you're away from the bank (if not, they're listed as Elsewhere).

## Options and key binding

- `CreateKeybindingEntryInitializer(bindingIndex, search)`
  (`Blizzard_Settings_Shared/Blizzard_Keybindings.lua:532`) builds a key binding row; Blizzard
  adds one to a normal settings page the same way (`Blizzard_SettingsDefinitions_Frame/Controls.lua`
  89-94). `C_KeyBindings.GetBindingIndex(action)` is documented. The settings panel saves
  bindings when it closes (`Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua:224-239`).
- `Settings.CreateColorSwatch(category, setting, tooltip)` (`Blizzard_Settings_Shared/Blizzard_Settings.lua:398`)
  is the game's color picker row: its setting holds an `AARRGGBB` hex string, read with
  `CreateColorFromHexString` and written with `GenerateHexColor` (`Blizzard_SettingControls.lua`
  ~1054-1112). Build 1.60.1.70938.
- `Bindings.xml` in the addon folder is loaded by the client without being listed in the TOC. The
  key binding page groups bindings by their `category` attribute, shown as `_G[category]` when
  that's a string, else the text itself.
