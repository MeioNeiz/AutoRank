# Meio Auto Rank

The game leaves old ranks on your bars when you learn new ones. With Meio Auto Rank your bars
move up by themselves; low ranks you put there on purpose stay.

For WoW Forever.

![Before: a warlock learns Shadow Bolt rank 4 but the bar's Shadow Bolt is still rank 3; with
Meio Auto Rank, the same button is rank 4](docs/before-after.png)

Renamed from AutoRank: see [Keeping your settings](#keeping-your-settings).

## What it does

- New ranks replace the old ones on your bars (after combat if you're fighting)
- Conjured items too: Healthstones, Soulstones, Spellstones, Firestones, mana gems, conjured
  food and water, the best one in your bags
- Replacement spells count: Demon Skin to Demon Armor, Lesser Heal to Heal
- Your pet's bar and autocast move up too
- Drag a low rank onto a button and it stays there (Life Tap rank 1)

Settings: Esc > Options > AddOns > MeioAutoRank, or `/autorank`. `/autorank help` lists the commands.

## Keeping your settings

Renamed from AutoRank. Your settings carry over if you log in once with the old AutoRank
folder still enabled (until you disable it, MeioAutoRank stays idle and says so in chat); if
your addon manager removed it, copy `WTF\Account\<account>\SavedVariables\AutoRank.lua` (and
the per-character file,
`WTF\Account\<account>\<realm>\<character>\SavedVariables\AutoRank.lua`) to
`MeioAutoRank.lua` before logging in.

## Install

Use your addon manager (CurseForge, Wago), or unzip a GitHub release into
`World of Warcraft\_forever_\Interface\AddOns` and restart WoW fully.

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/MeioNeiz/MeioAutoRank/issues)

## More Meio addons

[Meio Trainer Compare](https://www.curseforge.com/wow/addons/trainercompare) | [Meio Next Stop](https://www.curseforge.com/wow/addons/leavebutton) | [Meio Meter Hover](https://www.curseforge.com/wow/addons/meterhover) | [Meio Map](https://addons.wago.io/addons/meiomap) | [Meio Alts](https://addons.wago.io/addons/meioalts) | [Meio DPS](https://addons.wago.io/addons/meiodps) | [Meio Plates](https://addons.wago.io/addons/meioplates) | [Meio Hub](https://addons.wago.io/addons/meiohub) | [Meio Pets](https://addons.wago.io/addons/meiopets) | [Meio Stats](https://addons.wago.io/addons/meiostats) | [Meio Bags](https://addons.wago.io/addons/meiobags) | [Meio Fixes](https://addons.wago.io/addons/meiofixes) | [Meio Flight Times](https://addons.wago.io/addons/meioflighttimes) | [Meio Tooltip Fold](https://addons.wago.io/addons/meiotooltipfold) | [Meio Auto Run Turn](https://addons.wago.io/addons/meioautorunturn) | [Meio Mail](https://addons.wago.io/addons/meiomail) | [Meio QoL](https://addons.wago.io/addons/meioqol) | [Meio TSM Browse](https://addons.wago.io/addons/tsmbrowse)

## Licence

[MIT](LICENSE)
