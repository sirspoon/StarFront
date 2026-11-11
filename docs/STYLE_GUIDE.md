# StarFront style guide

A brief for anyone making art, sound or writing for the game, including prompts for AI image tools.
StarFront is an original setting: gothic, grim and industrial, in the same broad genre as other
grimdark science fiction, but every name, faction, emblem and design is our own.

## The world
Humanity's worlds are ruled by the **Dominion**, a vast, ancient and decaying empire held together
by faith, bureaucracy and endless war. Its cities are **hives**: kilometre-high stacks of factories,
cathedrals and slums. The first battles take place in the ruins of the hive-city of **Vell**, fought
over street by street.

## Look and feel
- **Gothic industrial:** pointed arches, buttresses, statues of saints with their faces worn away,
  pipework and cabling bolted onto old stone.
- **Ruin everywhere:** collapsed floors, craters, scorched rubble, burnt-out vehicles, drifting ash and smoke.
- **Colours:** mostly ash grey, soot, rust, bone and dull bronze. Strong colour is rare and means
  something: firelight, weapon glow, faction colours, stained glass.
- **Light:** low and moody, with warm pools from fires and cold blue-white from energy weapons.
- **Camera:** straight top-down (or very slightly angled) at about 2-3 cm of screen per soldier.
  Silhouettes must read clearly from above: heads, shoulders, weapons and packs.

## Factions

### Dominion Legion
Mass conscript infantry raised from the hives.
- Long drab olive greatcoats, dark helmets with rebreather masks and goggles, bedrolls and packs.
- Lumen rifles (long, simple energy rifles with an orange-red beam), heavy stubbers (belt-fed guns).
- Sergeants: a brass crest on the helmet. Officers: peaked caps and long coats.
- Accent colour: olive with dull brass. Their emblem is a **seven-pointed sunburst**.
- Feel: numerous, tired, frightened, brave in groups.

### The Sworn
Small orders of warrior-monks in heavy powered armour, each bound to a lifelong oath.
- Bulky deep-red armour with bone-coloured trim, big rounded shoulder plates, helmets with
  narrow glowing red eye-lenses, a power pack on the back with orange vents.
- Mass-reactive carbines (short, heavy guns with blue-white tracers) and rotor cannons.
- Champions wear a tattered bone-coloured cape and carry oath scrolls on chains.
- Emblem: a **broken chain inside a circle**.
- Feel: few, slow, relentless, almost impossible to break.

### Later factions (ideas)
- **The Hollowed:** a machine cult that rebuilds the dead as cyborg troops. Grey flesh, brass
  machinery, green lenses.
- **The Swarm:** fast alien raiders, chitin and bone, in packs.

## Unit sprites (the plan for real art)
- Make 3D models (or buy and restyle them), animate them, and render them top-down in Blender to
  sprite sheets: **8 facing directions** at 128 x 128 px per frame.
- Animations: idle, walk, run, fire (rifle and heavy weapon), prone/crawl, hit, die (2 variants), corpse.
- A separate shadow pass, and a team-colour mask so one set of sprites can carry different markings.

## Map art
- Tile-based ground (16 px cells, drawn at 2x), with hand-placed decals over it: craters,
  scorch marks, bodies, debris, puddles, blood.
- Walls and ruins as separate sprites with a lit top edge and a dark south face, so they read as raised.
- Light sources (fires, lamps, burning vehicles) as real 2D lights with flicker.

## Naming
Latin-flavoured, worn-down and bureaucratic for the Dominion (Vell, the Ashen Chapel, Lumen rifle,
Conscript Squad II). Short, oath-like words for the Sworn (Talon, Champion, Brother).
