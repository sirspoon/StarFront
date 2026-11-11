# StarFront

Real-time squad tactics in a ruined gothic future, in the spirit of the Close Combat games:
you give orders to squads, not individual men, and the battle turns on cover, line of sight,
suppression and morale. Soldiers who come under heavy fire get pinned down, and if they're
pushed too far they break and run.

![StarFront prototype](docs/screenshot.png)

Built with [Godot 4](https://godotengine.org/) (4.3 or newer). The art is placeholder for now,
drawn in code, so the game can be played and tuned before real sprites are made.

## Play it
1. Download Godot 4 (standard version, not .NET) from https://godotengine.org/download.
2. In the Project Manager choose **Import**, pick this folder's `project.godot`, then **Run** (F5).

## The prototype (v0.01)
- One procedurally generated ruined city map, different every battle, with the Ashen Chapel at its centre.
- Two factions: the **Dominion Legion** (many brittle conscripts) and **The Sworn** (a few armoured warrior-monks).
- Win by holding the chapel unchallenged for 3 minutes, by breaking the enemy, or by holding it when the 10 minutes run out.

### Controls
| Input | Action |
|---|---|
| Left click / drag | Select squads (Shift adds) |
| Right click ground | Move there (soldiers pick cover nearby). Shift + right click runs |
| Right click a visible enemy | Concentrate fire on that soldier |
| H | Halt selected squads |
| 1-9 | Select a squad and jump to it |
| Space | Pause |
| WASD / arrows / middle-drag, mouse wheel | Scroll, zoom |
| F1 | Show or hide help |

## How the battle works
- **Line of sight:** walls and wrecks block it. You only see enemies your men can see, and an enemy
  lying still in cover is only spotted at close range until they fire.
- **Cover:** rubble, craters and ruin floors cut the chance of being hit, as does rubble between a
  soldier and the shooter.
- **Suppression:** every shot near a man adds suppression, which fades when the firing stops. Heavily
  suppressed soldiers go prone (pinned): they won't move and fire less.
- **Morale:** falls under fire and when squad-mates die, especially the leader. A soldier at very low
  morale routs and flees to his own map edge. A nearby leader helps the squad recover.

## Project layout
- `scripts/game_data.gd`: factions, soldier types and weapons (the balance numbers).
- `scripts/battle_map.gd`: map generation, terrain, path-finding, line of sight, cover, and drawing the map.
- `scripts/soldier.gd`, `scripts/squad.gd`: soldiers, squads, morale and orders.
- `scripts/ai_commander.gd`: the computer opponent.
- `scripts/main.gd`: battle setup, the main loop, shooting, input and camera.
- `scripts/hud.gd`, `scripts/overlay.gd`, `scripts/effects.gd`: interface and effects.
- `docs/STYLE_GUIDE.md`: the setting and the art direction.
- `tools/autotest.sh`: plays computer-vs-computer battles without a window, for testing and balance.
