# AutoRank

Keeps the highest rank of your spells on your action bars in **WoW Forever**, without
macros, and leaves the low ranks you chose on purpose alone.

![AutoRank in chat](docs/chat.png)

## What it does

- **New ranks go on your bars by themselves.** When you learn a new rank, every button that
  held your previous top rank is swapped to the new one. Buttons hold the real spell, so you
  keep full tooltips, icons, cooldowns and range colouring. If you're in combat, it waits
  until combat ends.
- **Low ranks stay where you put them.** Drag a lower rank from the spellbook onto a button
  (Life Tap rank 1, a cheap Frost Armor...) and that button is pinned: AutoRank never
  upgrades it until something else goes on the button. It also never touches a button that
  didn't hold your top rank before.
- **Healthstones**: a button holding a Healthstone is switched to the best Healthstone in
  your bags, out of combat. With none in your bags the button is left alone.
- **Plain /cast macros back to spells**: `/autorank unmacro` lists bar macros that only say
  `/cast Spell` (with or without `#showtooltip`); `/autorank unmacro apply` puts the real
  spell on those buttons. The macros themselves are kept.

It never moves anything while you're dragging something on the cursor.

## Commands

| Command | |
|---|---|
| `/autorank` | Status and the list of commands |
| `/autorank all` | Raise every unpinned button to your top rank now |
| `/autorank off`, `/autorank on` | Stop or resume upgrading |
| `/autorank pins` | Buttons kept at a low rank on purpose |
| `/autorank unpin [slot]` | Let one pinned button (or all of them) upgrade again |
| `/autorank stones off`, `/autorank stones on` | Stop or resume the Healthstone swap |
| `/autorank unmacro [apply]` | Preview, or do, the macro to spell swap |

## Install

Download this repository (green **Code** button, **Download ZIP**), and copy the
`addons\AutoRank` folder into `World of Warcraft\_forever_\Interface\AddOns`, so that you
end up with `AddOns\AutoRank\AutoRank.toc`. Restart WoW fully (a `/reload` doesn't find new
addons).

No other addons needed.

## Limits

- Ranks are read from the spell's "Rank N" text: made and tested on an English client.
- Pins are saved per character and per button slot. Moving a pinned spell to another slot
  pins it there instead.
- Only action slots 1 to 180 are looked at.

## Licence

[MIT](LICENSE)
