# Changelog

## v0.06 (2026-11-11)
Concrete walls.
- Walls are now cast concrete instead of bricks: weathered slabs with the same gritty texture as
  the ground, damp and bleached patches, aggregate showing through, panel joints where the formwork
  met, and a front face with rain streaks and tie holes. Each building has its own batch of
  concrete; the chapel's is paler and older.
- Where a wall has collapsed the standing part ends in a torn, jagged edge with rusty reinforcing
  bars sticking out. Damaged walls have chunks blown out showing the rebar inside.
- Collapsed walls leave a broken concrete footing, slab chunks and twisted rebar instead of bricks.

## v0.05 (2026-11-11)
Textured floors and deeper cracks.
- Floor slabs now have a worn stone surface like the ground outside (each slab gets its own patch,
  so no two match), with grain and pitting, bevelled edges, chipped corners and the odd stain of
  soot, damp or old blood. The chapel's marble and the tops of walls get the same treatment, lighter.
- Cracks have depth: a dark gap that is widest in the middle, a lit lip on one side, small chips
  knocked out along it, and branches. Damaged walls use the same cracks.

## v0.04 (2026-11-11)
Ruins that look ruined.
- Where a wall has collapsed, the wall left standing next to it now breaks off raggedly: each course
  of stones stops at a different point, with shadowed broken ends, loose stones hanging off and
  fallen ones lying in the gap.
- Collapsed walls leave their outline behind: a dark footing in line with the rest of the wall, its
  lowest stones broken off unevenly, a few still standing, and masonry thrown out to either side.
- The gaps the ruins start the battle with are drawn the same way, so every building shows the full
  outline of its old walls. The chapel's doorways stay clean.

## v0.03 (2026-11-11)
Sharper battlefield and walls that can be destroyed.
- The map is now painted at twice the detail, in tiles: textured ground with stones, cracks, dead
  grass, puddles and stray bricks; craters with rims, thrown-out earth and water at the bottom;
  roads with kerbs, worn markings and potholes; flagstone floors with soot and cracks; rubble heaps
  with shaded stones, bricks and rebar.
- Walls now look raised: brick coping on top, a shaded front face and lit edges. The chapel has a
  marble floor, a torn red runner, a mosaic sunburst and shattered stained glass.
- Walls can be destroyed. Explosions (tank shells, lance rockets) chip them: first cracks, then
  missing stones, then they collapse into rubble you can walk and see through. Chapel walls are tougher.
- New order: select a tank or the Lance Team and right-click a wall to shell it until it falls.
- Stray shells now burst on the first wall in their way instead of passing through.
- Scorch marks no longer pile up into black blots.

## v0.02 (2026-11-11)
Vehicles.
- Each side gets a troop carrier and a tank: the Legion's Drudge Carrier and Vigil Tank, the
  Sworn's Pilgrim Carrier and Verdict Tank. They drive on tracks, turn before moving, and tank
  turrets swing round to aim.
- Carriers start the battle with a squad inside. Right-click your carrier with infantry selected
  to climb in, press U to unload. Ordering a squad that's aboard drives its carrier. If a carrier
  is destroyed, the men inside bail out, shaken, and some don't make it.
- Armour depends on which side is hit (front, side, rear). Only weapons with enough penetration
  can hurt vehicles; rifles just bounce off.
- New anti-tank infantry: the Legion's Lance Team (rocket launchers) and the Sworn's Breacher Talon
  (short-ranged fusion carbines). The Legion also gets a fourth Conscript Squad.
- Tank guns fire high explosive: blasts that kill, pin and leave scorch marks, and hit friends too.
- Destroyed vehicles become burning wrecks that block movement and sight.
- Fix: dead soldiers were hidden under the map; their bodies now stay on the battlefield.

## v0.01 (2026-11-11)
First playable prototype.
- Godot 4 project with a procedurally generated ruined city: buildings, a central chapel, craters,
  rubble, burning wrecks with smoke and firelight, and falling ash.
- Two factions: Dominion Legion (4 squads of conscripts) and The Sworn (3 talons of armoured warrior-monks).
- Squad orders (move, run, focus fire, halt), soldiers that pick cover near their destination.
- Line of sight with fog of war, cover, suppression, pinning, morale and routing.
- Computer opponent that advances on the chapel and fights from cover.
- Win by holding the chapel, breaking the enemy, or holding it when time runs out.
- Headless autotest and screenshot mode for testing.
