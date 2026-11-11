# Changelog

## v0.11 (2026-11-11)
Phone fixes.
- The map is now prepared four tiles at a time instead of all forty at once. Doing them all together
  needed a big burst of graphics memory that made a phone's browser give up ("WebGL context lost").
- Map detail can be chosen from the web address: add `?detail=medium` or `?detail=low` for phones
  that still struggle (full detail is the default).
- Fire, smoke, dust and ash are drawn by the game itself: Godot's built-in particles lost their red
  in web browsers, so ash showed up cyan and flames green.

## v0.10 (2026-11-11)
Play it on a phone.
- A web version, built and published to GitHub Pages automatically on every push, playable in a
  phone's browser (full detail kept for now).
- Touch controls, switched on automatically on touch screens: tap a soldier to select his squad
  (tap again to deselect), tap the ground to move, drag to line a selected squad up in cover (the
  preview shows where each man goes), drag with nothing selected or use two fingers to scroll,
  pinch to zoom. Tap an enemy to focus fire, your carrier to board, a wall to shell it.
- A button bar: Run, Face (then tap where to look), Pick (then tap single soldiers), Halt,
  Unload, Squads (show or hide the squad cards), Pause and help.
- On phones the interface is laid out for a smaller screen so text and buttons are a usable size.
- The camera no longer shows the empty space past the edge of the map, and a battle starts
  looking at your own troops. "Preparing the battlefield..." shows while the map is drawn.

## v0.09 (2026-11-11)
Cover and squad control.
- New low cover: sandbag emplacements (lines, L-shapes and horseshoes), steel-and-plank barricades
  across the roads and in the open, and stretches of the ruins' walls crumbled to waist height.
  It stops most fire from its far side (sandbags best, then low walls, then barricades) but troops
  can see and shoot over it. Infantry can clamber over it slowly; vehicles go round.
- Low cover is tougher than a full wall: it takes more shelling to destroy, and shots that miss a
  man behind it chew into it (sandbags burst, planks splinter) until it gives way. What's left is
  drawn as burst bags, broken planks or chunks of concrete.
- Troops use cover: when they move they pick spots behind cover facing the threat, idle men caught
  in the open hop into nearby cover, and men in cover crouch.
- Right-drag to line a squad up along the line you draw: each man snaps to cover near his spot and
  they face away from where they came from. A preview shows where each man will go (green = in cover).
  Several selected squads share the line out between them.
- Ctrl + right-click sets the direction a squad watches; they prefer targets in that arc.
- Alt + click picks out individual soldiers so you can move just them.
- Squad coherency, as in Epik: every man must stay within reach of a squad-mate. Orders to picked-out
  men are limited to keep that, and stragglers make their way back. Selected squads show their links
  (red when a man is out of contact).
- Balance: Legion rifles a little more accurate, Sworn carbines a little less, Sworn armour a little
  thinner (computer v computer was about 70% Sworn wins; now about even).

## v0.08 (2026-11-11)
Normal-mapped lighting.
- Every map tile now has a normal map, worked out from a height pass (raised walls with sloping
  front faces, rubble mounds, sunken craters, wreck hulls) plus the fine detail in the tile's colours
  (stones, cracks, slab edges). Lights now pick out the relief: the side of a rubble heap facing a
  fire glows while the far side stays dark, wall faces light up only from in front, and stones and
  crater rims catch the light.
- Lights now have a height (fires stand above the ground, bolts skim low, big explosions come from
  higher up), so they strike surfaces at an angle.
- A faint cold moonlight from the north-west shows the relief across the whole map.
- Wall shadows now match the raised tops of the walls, so a light in front of a wall reaches its face.

## v0.07 (2026-11-11)
Lighting, soot and smoke.
- The battlefield is darker, and combat lights it up: muzzle flashes, laser bolts and tracers that
  light the ground as they fly, rockets with a moving glow, and explosions that flare and fade.
  Exploding vehicles light up the whole area.
- Walls cast shadows: fires and explosions throw shadows past them, and light spills through
  doorways and breaches.
- Shelled walls are blackened with soot, scorch streaks and shrapnel pits. Footings of walls
  that were blown down are scorched too.
- Hit walls smoulder, with smoke rising for 20-35 seconds; collapsing walls throw up a dust cloud.
- Pausing now freezes flashes, tracers and explosions instead of letting them fade.

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
