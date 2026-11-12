# Changelog

## v0.53 (2026-11-12)
Longer, more tactical battles (around 8-10 minutes instead of 2-3).
- Shooting hits far less often (all weapons), and fewer of the hits that land wound: most only graze
  a man or tear through his kit. Misses and grazes still frighten men, so fire pins them down as
  much as ever; it just kills much more slowly.
- Fewer blows in close combat wound (except on men pinned or lying Down).
- Nerve drains more slowly under fire, and men who break can rally: once clear of the fire they
  recover quickly and stop running instead of always fleeing the field.
- Holding the chapel unchallenged now takes 4 minutes to win (was 3), and a side is beaten when
  fewer than 15% of its men are still fighting (was 20%).
- In computer-v-computer test battles: about 8-9 minutes on average (from about 2.5), and the
  Legion now wins a little over half (they were winning about a quarter), mostly by holding the chapel.

## v0.52 (2026-11-12)
- Phones: far fewer combat lights, to stop the Android app crashing in heavy firefights. Every round
  fired used to light up a muzzle flash and a light travelling with it, and with the heavy guns'
  long bursts all 40 lights were lit at once, each making the phone redraw the lit map. Phones now
  have 8 lights, a muzzle flash for about one round in three and no travelling lights (explosions,
  fires and flashes still light up). PCs are unchanged.
- The Android app now notes what it's doing every 5 seconds of a battle (lights, tracers, marks on
  the ground). If a game doesn't finish, Options shows where it stopped, to help track down crashes.

## v0.51 (2026-11-12)
- Android: back to preparing the battlefield one map tile at a time. Four at once (v0.50) made the
  app crash as the battle map loaded, presumably running out of graphics memory. The menus and
  options from v0.50 stay; choosing lower map detail in Options is the way to load faster.

## v0.50 (2026-11-12)
Options, a battle menu, and quicker loading on Android.
- The Android app prepares the battlefield four map tiles at a time instead of one (the one-at-a-time
  pace is only needed in a phone's web browser, which otherwise runs out of graphics memory).
- Options (on the title screen, and in the battle menu): map detail (high, medium or low: lower
  prepares the battlefield faster), wall shadows from fires and explosions (off by default on phones),
  normal maps, combat lights and moonlight, and sound. They're saved on the device. Applying them
  prepares the battlefield again (restarting the battle if one is going).
- A Menu button (Esc on a PC) pauses the battle and offers: Resume, Restart this battle (the same
  battlefield and side), New battle (back to the title screen) and Options.

## v0.49 (2026-11-12)
Smoother, and Windows and Android versions.
- Much less work drawing soldiers: each man is only redrawn when how he looks changes (turning,
  stance, firing, being hit or selected), and a walking man's stride is redrawn a few times a
  second rather than every frame. With the whole army on the move this cuts the drawing work to
  about a quarter, which was what made the game stutter when everyone moved at once. Zoomed right
  out, soldiers are drawn simply.
- Windows and Android versions are built automatically with every update and put on the
  repository's "Latest build" release (Releases, on the GitHub page). Windows: unzip and run
  StarFront.exe. Android: open the release page on the phone, download the .apk and open it.

## v0.48 (2026-11-12)
The Legion's new look, heavy guns that hose, selection while paused.
- The Legion are redrawn in detail like the Sworn: long greatcoats with their skirts flaring
  behind, webbing straps and ammunition pouches, a pack with a rolled blanket, sleeves and gloved
  hands on the weapon, and a steel helmet with a brim over goggles and a rebreather mask whose hose
  runs back to the pack. Sergeants wear a red sash and a gilded crest; raiders have no packs,
  darker coats and bandoliers. Weapons redrawn: lumen rifles with wooden stocks and a glowing power
  cell, the heavy stubber with its ammo box, the lance launcher carried over the shoulder with its
  warhead showing.
- Heavy guns now fire long, sustained streams: a dozen (Legion) or ten (Sworn) rounds a burst, a
  new burst every second or so, five bursts to a load before the loader changes it. Each round is
  less accurate, but the sheer volume pins men down. Their reach is longer (about 38 cells), a set-up
  gun covers a wider arc and keeps to targets inside it, and a gun team watching its arc spots men in
  cover further off, so they find targets far more often. New, longer burst sounds.
- Selecting soldiers while the game is paused now shows the green selection rings straight away.

## v0.47 (2026-11-12)
Tougher troops, clearer heavy guns, new look for the Sworn.
- Everyone is a little harder to kill: about three hits in ten that would have wounded (from
  shots, bursts, blasts and flames) now only graze a man or tear through his kit. He isn't hurt
  but it frightens him, so fire pins men down more and kills them less. Battles last about a
  quarter longer. (Close combat is as deadly as before.)
- Heavy guns are much easier to see: longer and thicker, in lighter metal with a dark outline,
  a perforated cooling jacket, a carry handle, a muzzle brake, a shadow under them and a bigger
  tripod. The Sworn gun has an ammunition box with its belt feeding in; the Legion's a glowing lens
  and a power cable.
- The Sworn are redrawn in much more detail: a power plant on their backs with glowing exhausts
  and cooling vanes, a sculpted breastplate with their sunburst sigil, great rounded shoulder plates
  rimmed in gold (the sigil on the left, a rank stripe for leaders), armoured arms holding the weapon,
  and a helmet with a grilled faceplate and glowing eye lenses. Leaders wear a cloak with a gilded
  hem and a red crest. Every weapon is redrawn too (drum-fed carbines, triple-barrelled rotor cannons,
  fusion carbines with glowing coils), the Pyre Warden carries twin fuel tanks, and the heavy-armoured
  warriors are bulkier with extra plates and an armoured collar. Wounded Sworn show gouges and
  scorching on their armour.
- Balance: in test battles the Legion now wins about one in four (was about one in six).

## v0.46 (2026-11-12)
A proper city to fight in.
- The map is laid out like a city: four avenues running north-south and two cross streets, with
  pavements along them and kerbs that stop at the junctions. The chapel stands in a paved square
  in the middle. Each city block between the streets is one of:
  - built up: rows of buildings facing the streets, with alleys between them and yards behind;
  - a park: dead grass, gravel paths, clumps of bushes and hedges, a low wall (or a hedge) round it;
  - a walled compound: a tall wall round the block with vehicle-wide gates and a breach or two,
    usually with a building inside;
  - a bombed-out lot of rubble and craters.
  The deployment strips at either end stay open. Burnt-out vehicles now mostly lie in the streets.
- Sandbags and barricades can run at angles as well as straight, and there are a few ring-shaped
  sandbagged positions (with angled sides and a way in at the back) with barbed wire in front.
- New ground:
  - Bushes: a man keeping still in them is hard to spot, and they spoil aim a little.
  - Hedges: block sight completely; men can push through, slowly.
  - Barbed wire: no cover, and very slow to get through (men path round it if they can).
  Vehicles flatten all three as they drive over them, and shell bursts blow them apart.

## v0.45 (2026-11-12)
Tracks, running men down, and more blood.
- Vehicles leave track marks in the dirt wherever they drive (two treads with the plates' imprint).
- Vehicles shove men out of their way. Driving fast (a carrier at normal speed, a tank in Assault)
  into enemy soldiers, they knock them down and can kill them; the crews steer round their own men.
- Blood sprays much further from a hit, so it's easier to see, and a man shot or cut down with a
  wall close behind him splashes it up the wall (a splat, droplets and runs).

## v0.44 (2026-11-12)
- The Pyre Warden's flame jet looks like fire now: soft billowing flames with a hot yellow core near
  the nozzle, orange further out and smoky red at the edges, instead of a flat yellow wedge.

## v0.43 (2026-11-12)
Grenade fix, two heavy Sworn warriors, more Legion heavy guns.
- Grenades no longer blow up the men who threw them. Before, a man with a wall right in front of
  him would throw straight into it and it dropped at his feet. Now only a man with a clear throw
  does it (the squad moves up to find one if needed), nobody throws a frag or tank-breaker so
  close that he or a friend is in the blast, and a throw's scatter can't land it at his feet.
- New for the Sworn, both in very heavy armour (four wounds, hard to hurt with rifles) but slow:
  - Pyre Warden: a flame projector. Each jet fills a narrow cone out to about 7 cells, licks round
    cover, burns everyone in it and terrifies them. Walls stop it.
  - Bastion Brother: a hail cannon, a multi-barrelled gun that spins up and sprays ten rounds.
- The Legion now has three Heavy Gun Teams.
- Balance: in test battles the Legion still wins about one in six, as before.

## v0.42 (2026-11-12)
Heavy Gun Team crews.
- The gunner works the gun; the loader changes the ammunition. A load lasts six bursts, then the
  loader swaps in a new belt or power cell in about 3 seconds. Without him (dead, pinned, fighting
  or away from the gun) the gunner takes about 7.5 seconds. The squad card shows "Reloading".
- The loader stays at the gunner's shoulder instead of finding his own cover.
- (Replaces the old rule that the gun simply fired slower without its loader.)

## v0.41 (2026-11-12)
Heavy Gun Teams.
- Each side gets a two-man Heavy Gun Team: a gunner and a loader. The Legion's heavy lumen gun
  fires bursts of searing laser bolts; the Sworn's heavy mass-reactive gun fires bursts of
  exploding rounds.
- The gun has to be set up to fire well. Stopped next to a window, low cover, rubble or a wall
  edge (or in a crater), or with the team in the Down stance, the gunner sets it on its tripod
  over about 2.5 seconds (longer without his loader). Set up, it's far more accurate (about six
  times as accurate as firing it loose); it can't be fired at all on the move.
- A set-up gun covers an arc in front of it; a target well outside it (or a Face order well away)
  means shifting the gun round first, which takes a moment. Moving packs it up.
- Without the loader beside him the gunner fires more slowly. If the gunner falls, the loader
  picks up the gun.
- The squad card shows "Setting up" and "Set up". The computer stops its team in range of the
  enemy and sets up, lying Down if there's nothing to rest the gun on.
- The Sworn gun crew wear lighter armour than other Sworn (two wounds each) to keep the sides
  balanced.

## v0.40 (2026-11-12)
- Crash tracking: the game notes how far it got every 20 seconds during a battle too (not just
  while loading). Add `?debug` to the address to see where the last visit got to on the title
  screen (hidden otherwise).

## v0.39 (2026-11-12)
- The version on the title screen is now a link: click it for a short "What's new" summary of
  the game's improvements (scripts/whats_new.gd).
- Removed the orange note on the title screen about where the last visit stopped loading.

## v0.38 (2026-11-12)
Grenades, and close combat that punishes men on the ground.
- Grenades: press Grenade (T on a PC), then click or tap a spot. Each selected squad throws what
  suits it: tank-breaker charges at enemy armour, frag grenades at enemy infantry, and smoke
  grenades on open ground (two side by side, a screen across the line of sight). If they're too
  far away they move up until a man with the right grenade can reach (about 9 cells), then throw.
  A new move order cancels a throw that hasn't happened yet.
- Most men carry one or two: conscripts a frag, sergeants and champions smoke, lancers and
  breachers a tank-breaker, raiders and Sworn brothers a frag and a tank-breaker. The squad cards
  show what's left (F frag, T tank-breaker, S smoke). Gunners and cannoneers carry none.
- Smoke screens last about half a minute and block sight and shots through them (men can still
  see each other at very close range).
- While picking a spot (PC), rings show how far your men can throw and the marker says what
  would be thrown there.
- The computer throws tank-breakers at armour in reach, and frags at infantry nearby, more
  often when they're dug in or lying low.
- Close combat: men who are pinned, or lying flat in the Down stance, can't fend off blows.
  Assault troops hit them far more often, blades wound them more deeply, and charges into them
  rattle them more. Assault troops go for men on the ground first. Fighting back from the
  ground is slow and clumsy, so get up (turn off Down) when blades are coming.

## v0.37 (2026-11-12)
Close combat and assault squads.
- New Legion Raider Squad: eight fast trench raiders with short-ranged ripper guns, trench
  knives and a sergeant with a hook sabre.
- New Sworn Oathblade Talon: three armoured warriors with pistols and crackling edict blades
  (a two-handed greatblade for their champion). Few, but deadly up close.
- Assault troops charge any enemy foot soldier who comes within about 8 cells (if there's a
  short way to him and they're not in the Down stance). Men charging in are a little harder to
  hit, and their first blow lands harder. Crashing into the enemy rattles them.
- Anyone else who ends up at arm's length fights with the butt of his gun. Blades strike faster
  and land more often, and parry blows they see coming. A blow from behind, or on a man pinned
  down, lands more easily. Armour can turn a blow; edict blades cut through most of it.
- Men locked in a fight can't simply walk off (an Assault order lets them break away at a run).
  Others won't shoot at an enemy grappling with one of their own.
- New sounds: ripper gun, pistol, blade clashes, gun-butt blows and the edict blade's crackle.
- The computer's assault squads close in from cover to cover, then rush the last stretch.

## v0.36 (2026-11-12)
Less square roof damage.
- Holes in roofs have ragged, wandering edges with broken slates hanging over them, a dark torn
  lip and a shadow falling into the hole, instead of following the map's square cells.
- Shell damage shows as soft round soot stains and a few scattered missing slates, not dark squares.
- Fires and weapon flashes no longer light the roofs: their light was picking out blocky orange
  patches on the slates. The moonlight still does.
- Fixed errors when lights are switched off (lights=0).

## v0.35 (2026-11-12)
Windows and roofs.
- Building walls now have windows (the chapel has a row of stained-glass ones). Men can see and
  fire through a window, and a man standing just inside one is in good cover against fire from
  outside (a little less than ducking behind solid wall would be, but he can shoot back). Nobody can
  climb through. Windows weaken a wall a little, and they fall with it.
- Buildings have roofs (slate, the chapel old lead) drawn over everything inside. A roof fades
  away while any of your soldiers is inside the building or just outside it, so you can see in.
  Spotted enemies under a roof show as red markers.
- Shells and grenades knock holes in roofs: battered slates first, then torn holes with rafters
  showing. When walls fall away beneath a roof, that part of it collapses.

## v0.34 (2026-11-12)
Flanking.
- Each squad braces against the direction its fight is coming from. Fire from well off that front
  (more than about 60 degrees, most from behind) with no cover in the way hits a little more often
  (up to +25%) and frightens the men more (up to +30% suppression). Cover facing the original
  attackers keeps its full strength. The squad slowly turns to face a sustained new threat, so a
  flank attack pays off for a while rather than for ever. Nothing on screen announces it.
- A squad under sustained fire from two clearly opposite directions recovers from fear a little
  slower and loses its nerve a little faster.
- The computer's squads try it too: a free squad swings round to the side of an enemy another of
  its squads is already fighting.
- Ready for later units: a "steadfast" trait ignores flanking, a "flank_bonus" trait strengthens it.
- Conscripts are a little steadier (morale 70, nerve 1.1), since flanking hurts brittle troops most.

## v0.33 (2026-11-12)
- Fixed squad members getting stuck behind squad-mates who arrived first (worst for the big Sworn):
  a man standing still now steps aside for one who is walking, and a man held up for a moment
  squeezes past.
- Spots picked for a squad's men are always within reach of each other, and lines are spaced a little
  tighter, so squads stay in contact when they arrive.

## v0.32 (2026-11-12)
- "Your will" is now said with the stress on "your", so it no longer sounds like "you will".
- New Sworn death sounds: instead of spoken words, a strained, breaking grunt ("uhh", "aargh" or a
  clenched "ngh") through the helmet vox, then the clank of heavy armour hitting the ground.

## v0.31 (2026-11-12)
- The Sworn answer your orders in a deep, armoured, robotic British voice over the vox: "Confirmed",
  "On our way" or "Your will" for a move, and "On my mark", "Fire!" or "Unleash hell!" when told to
  target an enemy or shell a wall. Sworn infantry grunt as they die.
- The voices are made by `tools/make_voices.py` (a neural text-to-speech voice, then processed).

## v0.30 (2026-11-12)
PC controls brought in line with the phone.
- Right click: move. Shift + right click: add a waypoint (Shift + right-drag adds a line at the end
  of the route).
- Right-drag: spread the squad along the line, in cover. Pause at the end of the line, then keep
  dragging to set the way they'll face.
- Right-drag starting on the selected squad, or on the last waypoint of its route: turn them to face
  that way (at the end of the route if they have one).
- Right click an enemy (focus fire), your carrier (board) or a wall (shell it) as before.
- Scrolling also works by pushing the mouse against the screen edge; the wheel zooms towards the cursor.
- The button bar now shows on PC too, with each button's key (Assault R, Down G, Halt H, Unload U,
  Pause Space, help F1). The help panel starts hidden; the ? button shows it.

## v0.29 (2026-11-12)
- Fixed every infantry weapon playing the Legion's laser sound: the Sworn's carbines and rotor cannon,
  the stubbers, lance rockets and fusion carbines now make their own sounds.
- Fixed squads leaving men behind: pinned soldiers ignored move orders, so part of a squad walked off
  and lost contact. Pinned men given an order now crawl after the squad (unless the fire is very
  heavy), the order steadies them a little, and a man who gets out of contact ahead of slower
  squad-mates waits for them to catch up.
- No time limit on the battle for now (win by holding the chapel or breaking the enemy).

## v0.28 (2026-11-11)
Sound changes.
- Armour hits are now a heavy thud on a hollow hull, with booming hull tones ringing inside it.
- Bullet weapons (stubbers, carbines, rotor and tank cannon) have their own ricochet: a sharp crack
  and a gritty, tumbling whizz. Lumen and fusion weapons keep the electric whine.
- Vehicle engines are lower and heavier, and groan as they pull away from a standstill.

## v0.27 (2026-11-11)
Sound.
- Sound effects, made from scratch by `tools/make_sounds.py` (no recordings): heavy explosions with
  rumble and falling debris, the tank's siege cannon echoing round the ruins, crackling fusion zaps,
  the Legion's lumen rifles popping, stubbers rattling, the Sworn's mass-reactive carbines firing
  rapid bursts with the bolts bursting downrange, the rotor cannon spinning up, lance rockets
  whooshing off, ricochet whines, rounds clanging off armour, and walls collapsing into rubble.
- Tanks and carriers rumble and clatter, revving up when they move (the tank deeper than the carrier).
- Sounds come from where things happen on the map: they pan and fade with distance from the camera.
- The Sworn's mass-reactive carbines now fire 4-round bursts (same firepower overall).
- `?sound=0` in the web address turns sound off.

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
