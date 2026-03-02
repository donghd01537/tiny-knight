# Player Controller — Feature Guide

## Overview

Breaker is now the **player-controlled** character.
VoidSpirit and Bull remain **sidekick AI** (unchanged auto-battle logic).

---

## How It Works

### Virtual Joystick (bottom-left)
- Touch and **drag** anywhere inside the joystick circle to move Breaker.
- Direction and speed are proportional to how far you drag from center.
- **Release** → Breaker stops and plays idle.
- The joystick base is 200×200 px. Max drag radius is 80 px.

### Skill Bar (bottom-right)
Two skill buttons stacked horizontally:

| Button | Skill | Effect |
|--------|-------|--------|
| **SKY DROP** | SkyDropSkill | Breaker teleports onto the nearest enemy within 180 px and deals damage |
| **THROW** | ThrowSkill | Throws the axe bouncing up to 4 enemies (up to 250 px range), then returns |

- Buttons are **greyed out** while their skill is on cooldown.
- Tapping a button when no valid target is in range = nothing happens (safe fail).

### No Auto-Attack
Breaker **does not auto-attack**. Damage output is entirely skill-based.
(Auto-attack can be added back later — see "Extending" below.)

---

## Files Changed / Added

| File | Change |
|------|--------|
| `scripts/actors/breaker_player_controller.gd` | **New** — player controller script |
| `scripts/ui/virtual_joystick.gd` | **New** — touch joystick logic |
| `scripts/ui/player_hud.gd` | **New** — HUD manager (connects joystick + buttons to player) |
| `scenes/ui/PlayerHUD.tscn` | **New** — HUD scene (joystick + skill bar, placeholder visuals) |
| `scenes/actors/Breaker.tscn` | Changed controller script to `breaker_player_controller.gd` |
| `scenes/world/Battle.tscn` | Added `PlayerHUD` instance |

VoidSpirit and Bull scripts are **untouched**.

---

## Replacing Placeholder Icons

Open `scenes/ui/PlayerHUD.tscn` in the editor:

1. Select `SkillBar/SkyDropBtn` — swap the `Button` for a `TextureButton` and assign `sky_drop_icon.png` as the normal texture.
2. Select `SkillBar/ThrowBtn` — same, assign `throw_icon.png`.
3. Select `Joystick/Base` — replace `ColorRect` with a `TextureRect` using your joystick base sprite.
4. Select `Joystick/Knob` — replace `ColorRect` with a `TextureRect` using your knob sprite.

The script references (`$Knob`, `$SkillBar/SkyDropBtn`, etc.) use node **names**, so keep the names unchanged.

---

## Extending Later

### Add auto-attack back
In `breaker_player_controller.gd`, add a `find_nearest_enemy()` call and `do_attack()` similar to the original `breaker_controller.gd`. The combatant and anim nodes are already wired.

### Select different player character
Currently hardcoded to Breaker. To switch:
1. Move `add_to_group("player_hero")` to whichever character you want controlled.
2. Give it a `joystick_direction` var and an `activate_skill(name)` method matching the same API.
3. `player_hud.gd` finds whoever is in the `"player_hero"` group — no other changes needed.

### Add more skill buttons
1. Add a new `Button` child inside `SkillBar` in `PlayerHUD.tscn`.
2. Connect its `pressed` signal to a new method in `player_hud.gd`.
3. Call `_player.activate_skill("YourSkillNodeName")`.

### Cooldown progress ring/bar
The `Skill` base class exposes `_cooldown_timer` and `cooldown`. In `player_hud.gd _process()` you can read `skill._cooldown_timer / skill.cooldown` to drive a progress overlay on each button.

---

## Testing on Desktop (Browser / Editor)

Enable **Emulate Touch From Mouse** in:
`Project → Project Settings → Input Devices → Pointing → Emulate Touch From Mouse`

This lets you test the joystick and skill buttons with a mouse click+drag in the browser or editor preview.
