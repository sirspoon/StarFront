# Changelog

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
