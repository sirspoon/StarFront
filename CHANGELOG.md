# Changelog

## v0.26 (2026-11-11)
More battle effects.
- Ricochets: shots glancing off armour, walls and cover sometimes fly off as a bright streak.
- Blood: a hit sprays droplets and streaks away from the shooter, and wounded men leave smears as
  they move. Each body lies in its own pool, irregular in shape and size, sometimes with a smear or
  spatter around it.
- Small burn marks where shots strike the ground (more from heavy weapons).
- More smoke: shell bursts leave smoke hanging about, heavy weapons give a puff of gunsmoke, and
  burning wrecks smoke more.
- Ground marks are redrawn at most four times a second, and the oldest small ones are cleared once
  there are 700, so long battles don't slow down.

## v0.25 (2026-11-11)
Stances.
- Soldiers in cover now kneel (knee forward, foot tucked behind, lower outline), and a man firing
  from behind a wall corner or wreck leans out to the open side to take his shots, then ducks back.
- New Down stance (button on phones, G on PC): the squad lies flat, with legs stretched out behind.
  Flat men aim better (+25%), are harder to hit (-30%, and -30% more in rubble or a crater) and
  harder to spot until they fire. Anyone behind waist-high cover stays kneeling so he can see over it.
  Squads in the Down stance crawl slowly when ordered to move.
- Run is now Assault (button on phones, R on PC): faster movement, and men fire on the move, but
  badly until they stop. Turning it on or off with squads selected changes the orders they are
  already carrying out too. Assault and Down cancel each other.

## v0.24 (2026-11-11)
- When hold-dragging a line for a squad to spread along, pause at the end of the line: it locks
  (a blue ring shows) and further dragging sets the way they'll face, without lifting your finger.

## v0.23 (2026-11-11)
- Tapping a carrier selects it straight away instead of waiting to see if a double tap follows.
  Double-tapping it still sends the infantry that were selected aboard.

## v0.22 (2026-11-11)
- Hold on your selected squad, then drag: they turn to face that way. If they have a route planned,
  that's the way they'll face when they get to the end of it.
- Hold on the last waypoint of a selected squad's route, then drag: sets the way they'll face there.
- A blue arrow shows the direction while dragging, and the route shows the final facing.
- Hold-drag away from the squad still moves them and spreads them along the drag.

## v0.21 (2026-11-11)
- Fixed the game freezing for a moment when a big explosion hits a wall. Instead of repainting
  whole 20x20-cell map tiles (and copying them back from the graphics chip), only small 5x5-cell
  patches around the damage are repainted, one per frame, and laid over the map. In testing the
  stall per shell dropped from about 200 ms to about 40 ms.

## v0.20 (2026-11-11)
- Hold, then drag to move a squad and spread it along the drag (a ring shows when the hold has
  registered). Holding and letting go without dragging still adds a waypoint. Tap-then-drag scrolls.
- Tapping your carrier selects it. Double-tap it with infantry selected to make them climb aboard.

## v0.19 (2026-11-11)
Touch controls reworked.
- Drag always scrolls the map, even with a squad selected.
- Double-tap the ground: move there. Tap, then drag: move there, spread out along the drag.
- Tap and hold the ground: add a waypoint; hold again for more, and finish the route with a
  double-tap or tap-drag. The route shows as numbered points, and the squad follows it in order.
- The first order after selecting a squad replaces its old orders; waypoints then add on.

## v0.18 (2026-11-11)
- On phones the first tap switches the browser to full screen (no address bar) and locks it to
  landscape. Browsers only allow full screen after a tap, so it can't happen on load.
- The web version can be installed: Chrome's "Add to Home screen" gives a StarFront icon that always
  opens full screen, in landscape.

## v0.17 (2026-11-11)
- Double-tap the ground with a squad selected to move it there (dragging still works too). A lone
  tap on empty ground still clears the selection, just after a moment's wait for a second tap.
- Tapping a squad's card selects it and glides the camera over to it.

## v0.16 (2026-11-11)
- Loading screen: the menu shows straight away over a dark backdrop with a loading bar, and the
  battlefield only fades in once it is fully drawn. Picking a side before then starts the battle as
  soon as loading finishes.

## v0.15 (2026-11-11)
Touch controls refined.
- Tapping a soldier or vehicle always selects its squad (it no longer toggles off).
- Moving now always takes a drag: with a squad selected, drag to where it should go (infantry line
  up along the drag in cover; vehicles drive to where the drag ends).
- Tapping empty ground clears the selection, so a one-finger drag then scrolls the map. Taps on an
  enemy (focus fire) or a wall (shell it, with a tank or lance team) still give orders.
- Orders can be given while paused, and while paused every squad's planned route is shown.

## v0.14 (2026-11-11)
- Phones draw the detailed map one tile per frame with a short pause between (desktop still does
  four), since `?safe` showed the crash happens while drawing map tiles. `?batch=1/2/4/8` overrides it.

## v0.13 (2026-11-11)
More phone crash hunting.
- Turned off 2D anti-aliasing in the project: the renderer used on the web doesn't support it, and it
  may upset phone graphics chips.
- `?safe` now goes further: no detailed map at all (a plain flat one, `?bake=0` on its own), and fire
  lights off too. If that runs on a phone, the detailed map preparation is the problem.
- The crash breadcrumbs now note each step of preparing the map, and keep ticking while the menu is up.

## v0.12 (2026-11-11)
Finding what crashes phones.
- Graphics switches in the web address: `?safe` (everything heavy off), or one at a time with
  `?shadows=0/1`, `?normals=0`, `?lights=0`, `?detail=low/medium`. The menu shows what's in use.
- Wall shadows from fires and explosions are off by default on phones (`?shadows=1` turns them on).
- The game remembers in the browser how far it got; if the last visit stopped early, the menu says
  where, so a crash on a phone can be tracked down.

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
