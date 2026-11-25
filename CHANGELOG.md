# MeioAutoRank

## 1.1.1

- Renamed from AutoRank. Your settings carry over if you log in once with the old AutoRank
  folder still enabled (until you disable it, MeioAutoRank stays idle and says so in
  chat); if your addon manager removed it, copy
  `WTF\Account\<account>\SavedVariables\AutoRank.lua` (and the per-character file,
  `WTF\Account\<account>\<realm>\<character>\SavedVariables\AutoRank.lua`) to
  `MeioAutoRank.lua` before logging in.
- Fixed: Felsteed to Dreadsteed, Warhorse to Charger and Bear Form to Dire Bear Form never
  moved up on their own
- Fixed: `/autorank unpin` with something other than a slot number unpinned every button

## 1.1.0

- A spell that replaces another counts as its next rank: Demon Skin to Demon Armor, Frost
  Armor to Ice Armor, Lesser Heal to Heal to Greater Heal, Bear Form to Dire Bear Form,
  Felsteed to Dreadsteed, Warhorse to Charger. Drag the old spell back to keep it
- Conjured items beyond Healthstones: Soulstone, Spellstone, Firestone, mana gems, conjured
  food and water, only ones you can use at your level; each can be turned off
- Pet bar buttons move up to the pet's new ranks, with autocast
- Settings panel: Esc > Options > AddOns > AutoRank, also from the addon compartment
- `/autorank help`, `status`, `<item> on|off`, `debug`

## 1.0.0

- First version: highest spell ranks on your bars, low ranks you chose kept, Healthstone
  swap, `/autorank unmacro`
