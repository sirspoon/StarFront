# StarFront

A real-time squad tactics game (Close Combat style) in an original grimdark gothic sci-fi
setting, made with Godot 4 (4.3+, GL Compatibility renderer, GDScript). See `README.md` for the
layout and `docs/STYLE_GUIDE.md` for the setting.

## Workflow
- Commit and push straight to `main`. The owner pulls and runs it in the Godot editor on their PC.
- Every change to the game bumps the version by 0.01: `VERSION` in `scripts/game_data.gd` and
  `config/version` in `project.godot`. Add an entry at the top of `CHANGELOG.md` (version, date,
  what changed in plain words).
- The setting must stay original: no Warhammer 40,000 (Games Workshop) names, factions, symbols or
  designs. Keep the gothic grimdark feel, but with our own names and looks.

## Code
- Scenes are built in code from `scenes/main.tscn` -> `scripts/main.gd`, so there is little to edit in
  the editor. Classes use `class_name`. Map units: 1 cell = 16 px.
- The art is placeholder, drawn with `_draw()`. Real sprites are expected to replace `Soldier._draw`
  and the map drawing later (see the style guide).
- The map is painted by `MapPainter` into 20x20-cell tiles at 2x resolution (`MapView`), repainted when
  `BattleMap.cells_changed` fires. Painting must stay deterministic per cell (hash-seeded), so a
  repaint only changes what was destroyed. Nothing is painted in headless runs.

## Testing (in a cloud session)
- Get Godot: download `Godot_v4.3-stable_linux.x86_64.zip` from the godotengine/godot GitHub releases.
- Check scripts: `godot --headless --import`, then run the game headless.
- `GODOT=path/to/godot tools/autotest.sh [first_seed] [count]` plays computer-vs-computer battles
  (~10 s each) and prints the winner, shots, hits, dead and fled per side, and any script errors.
- Screenshots: `xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --fixed-fps 20 -- --autotest --seed=3 --shot=out.png --shot-time=40 --shot-zoom=2`
  (centres on the fighting at the given battle time). Add `--shot-vehicles` to centre on a vehicle,
  `--shot-tank` for a tank, `--shot-team=0|1` to pick a side, `--shot-at=x,y` for a map position,
  `--shot-wall` for the last wall to fall. `--demo-damage` shells the chapel's west wall at the start
  (to see every damage stage); `--log-walls` prints where walls fall. Rendering under xvfb is software,
  so a full battle there takes a minute or two.
- Lighting checks: `--test-light=x,y` adds a strong light at a map position; `--debug-normals` shows
  the normal maps instead of the map colours. Normal maps come from `HeightPainter` +
  `scripts/normal_from_height.gdshader` (Godot reads green as "facing up the screen", hence `flip_y`).
