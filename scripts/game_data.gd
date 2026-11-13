class_name GameData
extends RefCounted
## Factions, soldier types and weapons. Balance tuning lives here.

const VERSION := "0.96"

## range in pixels (16 px = 1 map cell); cooldown = seconds between bursts;
## acc = base hit chance; ap = how much infantry armour it ignores; supp = suppression per shot;
## dmg = wounds to infantry. Against vehicles: pen is compared with the armour of the side hit
## and vdmg is the hull damage if it gets through. blast = radius of the explosion (0 = none);
## wall = damage it does to walls in that blast (walls have 100, chapel walls 160).
const WEAPONS := {
	"lumen_rifle": {"name": "Lumen rifle", "range": 340.0, "cooldown": 1.5, "burst": 1, "gap": 0.0,
		"acc": 0.56, "ap": 0.0, "dmg": 1, "pen": 0, "supp": 7.0, "tracer": Color(1.0, 0.5, 0.25), "width": 1.6},
	"heavy_stubber": {"name": "Heavy stubber", "range": 430.0, "cooldown": 2.6, "burst": 6, "gap": 0.09,
		"acc": 0.3, "ap": 0.15, "dmg": 1, "pen": 2, "vdmg": 1, "supp": 10.0, "tracer": Color(1.0, 0.85, 0.45), "width": 1.3},
	"mass_carbine": {"name": "Mass-reactive carbine", "range": 360.0, "cooldown": 2.0, "burst": 4, "gap": 0.08,
		"acc": 0.155, "ap": 0.35, "dmg": 2, "pen": 3, "vdmg": 1, "supp": 7.0, "tracer": Color(0.6, 0.85, 1.0), "width": 2.2},
	"rotor_cannon": {"name": "Rotor cannon", "range": 440.0, "cooldown": 3.0, "burst": 5, "gap": 0.1,
		"acc": 0.26, "ap": 0.5, "dmg": 2, "pen": 4, "vdmg": 2, "supp": 18.0, "tracer": Color(0.55, 0.8, 1.0), "width": 2.6},
	"lance_launcher": {"name": "Lance launcher", "range": 400.0, "cooldown": 6.0, "burst": 1, "gap": 0.0,
		"acc": 0.42, "ap": 0.6, "dmg": 2, "pen": 8, "vdmg": 5, "blast": 18.0, "wall": 45.0, "supp": 20.0,
		"tracer": Color(1.0, 0.75, 0.4), "width": 3.0},
	"fusion_carbine": {"name": "Fusion carbine", "range": 210.0, "cooldown": 3.5, "burst": 1, "gap": 0.0,
		"acc": 0.6, "ap": 0.9, "dmg": 4, "pen": 9, "vdmg": 5, "supp": 20.0,
		"tracer": Color(0.75, 0.9, 1.0), "width": 4.0},
	"lumen_lance": {"name": "Lumen lance", "range": 600.0, "cooldown": 8.5, "burst": 1, "gap": 0.0,
		"acc": 0.9, "ap": 0.9, "dmg": 2, "pen": 9, "vdmg": 1, "supp": 30.0, "beam": 4.0, "dose": 0.325, "wall": 200.0,
		"tracer": Color(1.0, 0.45, 0.18), "width": 5.0, "mode": "Beam"},
	# the lance's other setting: short pulses, often, for men in the open
	"lumen_pulse": {"name": "Lumen lance (pulse)", "range": 560.0, "cooldown": 2.4, "burst": 4, "gap": 0.22,
		"acc": 0.3, "ap": 0.6, "dmg": 2, "pen": 5, "vdmg": 1, "supp": 16.0, "tracer": Color(1.0, 0.5, 0.22), "width": 3.4,
		"light": true, "mode": "Pulse"},
	# indirect fire: lobbed over walls at a spot (no sight needed), inaccurate; see Mortars
	"mortar": {"name": "Mortar", "range": 950.0, "min_range": 110.0, "cooldown": 9.0, "burst": 1, "gap": 0.0,
		"acc": 0.3, "ap": 0.35, "dmg": 2, "pen": 4, "vdmg": 2, "blast": 30.0, "wall": 45.0, "supp": 45.0,
		"indirect": true, "tracer": Color(0.9, 0.8, 0.6), "width": 2.0},
	# the Outriders' turret gun: a rapid-firing mass-reactive stubber
	"mass_stubber": {"name": "Mass stubber", "range": 420.0, "cooldown": 2.2, "burst": 6, "gap": 0.08,
		"acc": 0.2, "ap": 0.35, "dmg": 2, "pen": 3, "vdmg": 1, "supp": 11.0, "tracer": Color(0.6, 0.85, 1.0), "width": 2.0},
	"siege_cannon": {"name": "Siege cannon", "range": 620.0, "cooldown": 5.0, "burst": 1, "gap": 0.0,
		"acc": 0.5, "ap": 0.6, "dmg": 3, "pen": 9, "vdmg": 6, "blast": 42.0, "wall": 80.0, "supp": 40.0,
		"tracer": Color(1.0, 0.9, 0.6), "width": 3.5},
	"ripper_smg": {"name": "Ripper gun", "range": 180.0, "cooldown": 1.3, "burst": 4, "gap": 0.06,
		"acc": 0.22, "ap": 0.0, "dmg": 1, "pen": 1, "supp": 5.0, "tracer": Color(1.0, 0.8, 0.45), "width": 1.1},
	"mass_pistol": {"name": "Mass-reactive pistol", "range": 190.0, "cooldown": 1.5, "burst": 2, "gap": 0.12,
		"acc": 0.2, "ap": 0.3, "dmg": 2, "pen": 2, "supp": 6.0, "tracer": Color(0.6, 0.85, 1.0), "width": 1.8},
	"heavy_lumen": {"name": "Heavy lumen gun", "range": 620.0, "cooldown": 1.0, "burst": 12, "gap": 0.08,
		"acc": 0.085, "ap": 0.55, "dmg": 2, "pen": 3, "vdmg": 1, "supp": 10.0, "tracer": Color(1.0, 0.42, 0.2), "width": 2.2},
	"heavy_mass_gun": {"name": "Heavy mass-reactive gun", "range": 600.0, "cooldown": 1.1, "burst": 10, "gap": 0.09,
		"acc": 0.045, "ap": 0.45, "dmg": 2, "pen": 4, "vdmg": 2, "supp": 13.0, "tracer": Color(0.6, 0.85, 1.0), "width": 2.8},
	"pyre_projector": {"name": "Pyre projector", "range": 115.0, "cooldown": 2.2, "burst": 1, "gap": 0.0,
		"acc": 0.55, "ap": 0.5, "dmg": 1, "pen": 3, "vdmg": 1, "supp": 28.0, "flame": true, "cone": 0.35,
		"tracer": Color(1.0, 0.55, 0.15), "width": 4.0},
	"hail_cannon": {"name": "Hail cannon", "range": 380.0, "cooldown": 3.2, "burst": 10, "gap": 0.05,
		"acc": 0.1, "ap": 0.4, "dmg": 1, "pen": 4, "vdmg": 1, "supp": 8.0, "tracer": Color(0.6, 0.85, 1.0), "width": 1.6},
	"fusion_cannon": {"name": "Fusion cannon (AP)", "range": 540.0, "cooldown": 6.0, "burst": 1, "gap": 0.0,
		"acc": 0.6, "ap": 0.95, "dmg": 4, "pen": 10, "vdmg": 7, "blast": 10.0, "wall": 55.0, "supp": 30.0,
		"tracer": Color(0.7, 0.9, 1.0), "width": 5.0, "mode": "AP"},
	# high explosive: a wide burst for men and walls, little use against armour
	"fusion_cannon_he": {"name": "Fusion cannon (HE)", "range": 540.0, "cooldown": 6.0, "burst": 1, "gap": 0.0,
		"acc": 0.5, "ap": 0.45, "dmg": 2, "pen": 5, "vdmg": 2, "blast": 44.0, "wall": 90.0, "supp": 55.0,
		"tracer": Color(1.0, 0.85, 0.6), "width": 4.0, "mode": "HE"},
}

## Close-combat weapons. hit = chance a blow lands; parry = how much it spoils the enemy's
## blows (if he can see them coming); ap = how much armour it cuts through; cooldown =
## seconds between blows. Anyone without one fights with the butt of his gun.
const MELEE := {
	"gun_butt": {"name": "Gun butt", "cooldown": 1.5, "hit": 0.4, "parry": 0.1, "dmg": 1, "ap": 0.0, "sound": "melee_blunt", "blade": false},
	"trench_knife": {"name": "Trench knife", "cooldown": 0.75, "hit": 0.6, "parry": 0.25, "dmg": 1, "ap": 0.2, "sound": "melee_blade", "blade": true},
	"hook_sabre": {"name": "Hook sabre", "cooldown": 0.85, "hit": 0.65, "parry": 0.35, "dmg": 1, "ap": 0.3, "sound": "melee_blade", "blade": true},
	"edict_blade": {"name": "Edict blade", "cooldown": 0.85, "hit": 0.65, "parry": 0.4, "dmg": 2, "ap": 0.8, "sound": "melee_power", "blade": true},
	"gauntlet": {"name": "Bastion gauntlet", "cooldown": 1.6, "hit": 0.5, "parry": 0.1, "dmg": 2, "ap": 0.7, "sound": "melee_blunt", "blade": false},
	"edict_greatblade": {"name": "Edict greatblade", "cooldown": 1.0, "hit": 0.7, "parry": 0.45, "dmg": 3, "ap": 0.85, "sound": "melee_power", "blade": true},
}

## Grenades, thrown at a picked spot (see Grenades). he and ap burst like other explosives
## (blast, dmg, ap, supp, wall; pen and vdmg against vehicles); smoke makes a screen of
## radius r that blocks sight for `duration` seconds.
const THROW_RANGE := 150.0
const GRENADES := {
	"he": {"name": "Frag grenade", "blast": 20.0, "dmg": 1, "ap": 0.2, "pen": 2, "vdmg": 1, "supp": 30.0, "wall": 12.0},
	"ap": {"name": "Tank-breaker charge", "blast": 7.0, "dmg": 3, "ap": 0.85, "pen": 9, "vdmg": 4, "supp": 15.0, "wall": 40.0},
	"smoke": {"name": "Smoke grenade", "r": 42.0, "duration": 28.0},
}

## "heavy": true marks a heavy weapon gunner: it must be set up (next to cover or a window,
## or with the team Down) to fire well; see Soldier.SETUP_TIME and HEAVY_SET_UP / HEAVY_LOOSE.
const HEAVY_SET_UP := 2.4   # accuracy multiplier once set up
const HEAVY_LOOSE := 0.4    # ...and when firing it unbraced

## The share of wounding hits (shots, bursts, flames, blasts) that really wound; the rest only
## graze or tear through kit, frightening the man instead. Lower = longer, more tactical fights.
## (With ACCURACY and MELEE_LETHALITY these set the pace: computer-v-computer battles average
## about 8-9 minutes.)
const LETHALITY := 0.3
## All shooting's chance to hit is scaled by this (lower = slower, longer battles; misses still
## frighten men, so fire still pins them down).
const ACCURACY := 0.3
## Likewise for blows in close combat that would wound: the rest are fended off by kit or armour.
const MELEE_LETHALITY := 0.3

## nerve multiplies morale loss (higher = panics sooner). Optional traits for later units:
## "steadfast": true ignores being flanked or caught in crossfire; "flank_bonus": 1.5 makes
## their fire from a flank count for more.
const SOLDIERS := {
	"conscript": {"name": "Conscript", "hp": 1, "armor": 0.1, "speed": 46.0, "morale": 70.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "lumen_rifle", "grenades": {"he": 1}},
	"gunner": {"name": "Stubber gunner", "hp": 1, "armor": 0.1, "speed": 40.0, "morale": 65.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "heavy_stubber", "grenades": {}},
	"sergeant": {"name": "Sergeant", "hp": 1, "armor": 0.2, "speed": 46.0, "morale": 80.0, "nerve": 0.9,
		"radius": 7.0, "weapon": "lumen_rifle", "leader": true, "grenades": {"he": 1, "smoke": 2}},
	"lancer": {"name": "Lancer", "hp": 1, "armor": 0.1, "speed": 42.0, "morale": 65.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "lance_launcher", "grenades": {"ap": 1}},
	"raider": {"name": "Trench Raider", "hp": 1, "armor": 0.15, "speed": 54.0, "morale": 78.0, "nerve": 0.9,
		"radius": 7.0, "weapon": "ripper_smg", "melee": "trench_knife", "charger": true, "grenades": {"he": 1, "ap": 1}},
	"raider_sgt": {"name": "Raider Sergeant", "hp": 1, "armor": 0.2, "speed": 54.0, "morale": 85.0, "nerve": 0.8,
		"radius": 7.0, "weapon": "ripper_smg", "melee": "hook_sabre", "charger": true, "leader": true, "grenades": {"he": 1, "smoke": 2, "ap": 1}},
	"hw_gunner": {"name": "Heavy Gunner", "hp": 1, "armor": 0.1, "speed": 36.0, "morale": 70.0, "nerve": 1.0,
		"radius": 7.0, "weapon": "heavy_lumen", "heavy": true, "grenades": {}},
	"hw_loader": {"name": "Loader", "hp": 1, "armor": 0.1, "speed": 42.0, "morale": 70.0, "nerve": 1.0,
		"radius": 7.0, "weapon": "lumen_rifle", "loader": true, "grenades": {"he": 1}},
	"mortar_gunner": {"name": "Mortar Gunner", "hp": 1, "armor": 0.1, "speed": 38.0, "morale": 70.0, "nerve": 1.0,
		"radius": 7.0, "weapon": "mortar", "mortar": true, "grenades": {}},
	"mortar_loader": {"name": "Mortar Loader", "hp": 1, "armor": 0.1, "speed": 42.0, "morale": 70.0, "nerve": 1.0,
		"radius": 7.0, "weapon": "lumen_rifle", "mortar_loader": true, "grenades": {"he": 1}},
	"mortar_sgt": {"name": "Mortar Sergeant", "hp": 1, "armor": 0.2, "speed": 42.0, "morale": 80.0, "nerve": 0.9,
		"radius": 7.0, "weapon": "lumen_rifle", "leader": true, "mortar_loader": true, "grenades": {"he": 1, "smoke": 2}},
	"brother": {"name": "Sworn Brother", "hp": 3, "armor": 0.5, "speed": 38.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "mass_carbine", "grenades": {"he": 1, "ap": 1}},
	"cannoneer": {"name": "Sworn Cannoneer", "hp": 3, "armor": 0.5, "speed": 34.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "rotor_cannon", "grenades": {}},
	"breacher": {"name": "Sworn Breacher", "hp": 3, "armor": 0.5, "speed": 38.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "fusion_carbine", "grenades": {"ap": 1}},
	"champion": {"name": "Sworn Champion", "hp": 4, "armor": 0.6, "speed": 38.0, "morale": 110.0, "nerve": 0.4,
		"radius": 10.0, "weapon": "mass_carbine", "leader": true, "grenades": {"he": 1, "smoke": 2}},
	"hw_gunner_s": {"name": "Sworn Heavy Gunner", "hp": 2, "armor": 0.4, "speed": 32.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "heavy_mass_gun", "heavy": true, "grenades": {}},
	"hw_loader_s": {"name": "Sworn Loader", "hp": 2, "armor": 0.4, "speed": 36.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "mass_pistol", "loader": true, "grenades": {"he": 1}},
	"pyre_warden": {"name": "Pyre Warden", "hp": 4, "armor": 0.75, "speed": 26.0, "morale": 120.0, "nerve": 0.3,
		"radius": 12.0, "weapon": "pyre_projector", "melee": "gauntlet", "bastion": true, "grenades": {}},
	"bastion": {"name": "Bastion Brother", "hp": 4, "armor": 0.75, "speed": 26.0, "morale": 120.0, "nerve": 0.3,
		"radius": 12.0, "weapon": "hail_cannon", "melee": "gauntlet", "bastion": true, "grenades": {}},
	"oathblade": {"name": "Sworn Oathblade", "hp": 3, "armor": 0.5, "speed": 47.0, "morale": 100.0, "nerve": 0.45,
		"radius": 10.0, "weapon": "mass_pistol", "melee": "edict_blade", "charger": true, "grenades": {"he": 1, "ap": 1}},
	"blade_champion": {"name": "Oathblade Champion", "hp": 4, "armor": 0.6, "speed": 47.0, "morale": 115.0, "nerve": 0.4,
		"radius": 10.0, "weapon": "mass_pistol", "melee": "edict_greatblade", "charger": true, "leader": true, "grenades": {"he": 1, "smoke": 1, "ap": 1}},
}

## armour = [front, side, rear]. Carriers hold a squad; one starts the battle inside.
## Weapons marked turret turn with the turret; the others can fire all round.
const VEHICLES := {
	"drudge": {"name": "Drudge Carrier", "role": "carrier", "hp": 9, "armour": [6, 5, 4], "speed": 56.0, "launcher": true,
		"turn": 1.6, "length": 50.0, "width": 30.0, "capacity": 8,
		"weapons": [{"weapon": "heavy_stubber", "mount": Vector2(10, -7)}]},
	"vigil": {"name": "Vigil Tank", "role": "tank", "hp": 14, "armour": [9, 7, 5], "speed": 36.0,
		"turn": 1.0, "length": 62.0, "width": 38.0, "capacity": 0,
		"weapons": [{"weapon": "lumen_lance", "alt": "lumen_pulse", "turret": true}, {"weapon": "heavy_stubber", "mount": Vector2(22, 9)}]},
	"pilgrim": {"name": "Pilgrim Carrier", "role": "carrier", "hp": 9, "armour": [6, 5, 4], "speed": 50.0, "launcher": true,
		"turn": 1.5, "length": 52.0, "width": 32.0, "capacity": 6,
		"weapons": [{"weapon": "rotor_cannon", "mount": Vector2(8, 0)}]},
	# a fast, lightly armoured recon buggy: four wheels, a roll cage, a turret stubber; they come
	# as a squad of three (an Outrider Squadron)
	"outrider": {"name": "Outrider", "role": "buggy", "hp": 6, "armour": [5, 4, 4], "speed": 82.0, "strength": 2,
		"turn": 2.6, "length": 34.0, "width": 22.0, "capacity": 0,
		"weapons": [{"weapon": "mass_stubber", "turret": true}]},
	"verdict": {"name": "Verdict Tank", "role": "tank", "hp": 14, "armour": [9, 8, 6], "speed": 32.0,
		"turn": 0.9, "length": 64.0, "width": 40.0, "capacity": 0,
		"weapons": [{"weapon": "fusion_cannon", "alt": "fusion_cannon_he", "turret": true}, {"weapon": "rotor_cannon", "mount": Vector2(18, -13)}]},
}

const FACTIONS := {
	"legion": {
		"name": "Dominion Legion", "short": "Legion",
		"blurb": "Endless ranks of conscripts in rebreathers and greatcoats. Cheap, numerous and brittle: they win by weight of fire.",
		"coat": Color(0.37, 0.39, 0.28), "armour": Color(0.25, 0.26, 0.21), "trim": Color(0.75, 0.62, 0.32),
		"blood": Color(0.42, 0.04, 0.04), "ui": Color(0.62, 0.7, 0.42),
		"squads": [
			{"name": "Conscript Squad", "carrier": "drudge", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Raider Squad", "members": ["raider_sgt", "raider", "raider", "raider", "raider", "raider", "raider", "raider"]},
			{"name": "Heavy Gun Team", "members": ["hw_gunner", "hw_loader"]},
			{"name": "Heavy Gun Team", "members": ["hw_gunner", "hw_loader"]},
			{"name": "Heavy Gun Team", "members": ["hw_gunner", "hw_loader"]},
			{"name": "Stubber Team", "members": ["sergeant", "gunner", "gunner"]},
			{"name": "Lance Team", "members": ["sergeant", "lancer", "lancer"]},
			{"name": "Mortar Team", "members": ["mortar_gunner", "mortar_sgt", "mortar_gunner", "mortar_loader", "mortar_gunner", "mortar_loader"]},
			{"vehicle": "vigil"},
		],
	},
	"sworn": {
		"name": "The Sworn", "short": "Sworn",
		"blurb": "A handful of armoured warrior-monks bound by oath. Very hard to kill and harder to break, but every loss hurts.",
		"coat": Color(0.45, 0.11, 0.1), "armour": Color(0.3, 0.07, 0.07), "trim": Color(0.86, 0.72, 0.42),
		"blood": Color(0.3, 0.03, 0.03), "ui": Color(0.85, 0.35, 0.3),
		"squads": [
			{"name": "Sworn Talon", "carrier": "pilgrim", "members": ["champion", "brother", "brother", "cannoneer"]},
			{"name": "Sworn Talon", "members": ["champion", "brother", "brother", "cannoneer"]},
			{"name": "Oathblade Talon", "members": ["blade_champion", "oathblade", "oathblade"]},
			{"name": "Heavy Gun Team", "members": ["hw_gunner_s", "hw_loader_s"]},
			{"name": "Pyre Warden", "members": ["pyre_warden"]},
			{"name": "Bastion Brother", "members": ["bastion"]},
			{"name": "Breacher Talon", "members": ["champion", "brother", "breacher", "breacher"]},
			{"name": "Outrider Squadron", "vehicles": ["outrider", "outrider", "outrider"]},
			{"vehicle": "verdict"},
		],
	},
}

## Forces: what each unit costs, how many of it a force may have, and the points each side
## has to spend. Units are the squads in FACTIONS (matched by name, and carrier if any).
const BUDGET := 1300
const MAX_UNITS := 14
const COSTS := {
	"legion": [
		["Conscript Squad", "drudge", 170, 2, "Seven conscripts with lumen rifles and a stubber, riding a Drudge carrier"],
		["Conscript Squad", "", 100, 5, "Seven conscripts: a sergeant, five lumen rifles and a stubber gunner"],
		["Raider Squad", "", 130, 2, "Eight trench raiders with ripper guns and knives: assault troops"],
		["Heavy Gun Team", "", 70, 4, "A heavy lumen gun and its loader: long-range fire once set up"],
		["Stubber Team", "", 60, 3, "A sergeant and two stubber gunners"],
		["Lance Team", "", 70, 3, "A sergeant and two lance launchers: anti-armour"],
		["Mortar Team", "", 110, 2, "Three mortars and their loaders: indirect fire, HE and smoke"],
		["vigil", "", 250, 2, "Vigil Tank: the lumen lance (beam or pulse) and a heavy stubber"],
	],
	"sworn": [
		["Sworn Talon", "pilgrim", 200, 2, "A champion, two brothers and a cannoneer, riding a Pilgrim carrier"],
		["Sworn Talon", "", 130, 4, "A champion, two brothers with carbines and a cannoneer"],
		["Oathblade Talon", "", 120, 2, "A champion and two oathblades: assault troops with power blades"],
		["Heavy Gun Team", "", 80, 3, "A heavy mass-reactive gun and its loader"],
		["Pyre Warden", "", 90, 2, "A bastion-armoured flamer"],
		["Bastion Brother", "", 90, 2, "A bastion-armoured hail cannon"],
		["Breacher Talon", "", 140, 2, "A champion, a brother and two breachers with fusion carbines: anti-armour"],
		["Outrider Squadron", "", 200, 2, "Three fast gun buggies"],
		["verdict", "", 250, 2, "Verdict Tank: the fusion cannon (AP or HE) and a rotor cannon"],
	],
}


## The units a faction can field: [{id, name, cost, max, about, def}], def as in FACTIONS.squads.
static func units(faction: String) -> Array:
	var out: Array = []
	for c in COSTS[faction]:
		var def := {}
		for sq in FACTIONS[faction].squads:
			var nm: String = sq.get("name", "")
			if sq.has("vehicle") and sq.vehicle == c[0]:
				def = sq
			elif nm == c[0] and str(sq.get("carrier", "")) == c[1]:
				def = sq
		var label: String = VEHICLES[c[0]].name if VEHICLES.has(c[0]) else c[0]
		if c[1] != "":
			label += " + " + VEHICLES[c[1]].name.split(" ")[0]
		out.append({"id": c[0] + ("+" + c[1] if c[1] != "" else ""), "name": label, "cost": c[2], "max": c[3], "about": c[4], "def": def})
	return out


## The standard force (the squads listed in FACTIONS), as unit ids.
static func default_army(faction: String) -> Array:
	var ids: Array = []
	for sq in FACTIONS[faction].squads:
		if sq.has("vehicle"):
			ids.append(sq.vehicle)
		else:
			ids.append(sq.name + ("+" + sq.carrier if sq.has("carrier") else ""))
	return ids


static func army_cost(faction: String, ids: Array) -> int:
	var by := {}
	for u in units(faction):
		by[u.id] = u.cost
	var t := 0
	for i in ids:
		t += int(by.get(i, 0))
	return t


## A force the computer picks for itself: a core of infantry, then whatever it can afford,
## at random, within each unit's limit (seeded, so a restarted battle gets the same force).
static func random_army(faction: String, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var us := units(faction)
	var ids: Array = []
	var spent := 0
	var count := func(id: String) -> int: return ids.filter(func(x): return x == id).size()
	# two or three line infantry squads first (the cheapest that isn't in a vehicle)
	var line: Dictionary = us[1]
	for k in rng.randi_range(2, 3):
		ids.append(line.id)
		spent += int(line.cost)
	for tries in 200:
		var u: Dictionary = us[rng.randi() % us.size()]
		if spent + int(u.cost) <= BUDGET and count.call(u.id) < int(u.max) and ids.size() < MAX_UNITS:
			ids.append(u.id)
			spent += int(u.cost)
		if BUDGET - spent < 60:
			break
	return ids


## Squad definitions (for spawning) from unit ids, in a sensible order: infantry, then vehicles.
static func army_defs(faction: String, ids: Array) -> Array:
	var by := {}
	for u in units(faction):
		by[u.id] = u.def
	var out: Array = []
	for i in ids:
		if by.has(i) and not by[i].has("vehicle") and not by[i].has("vehicles"):
			out.append(by[i])
	for i in ids:
		if by.has(i) and (by[i].has("vehicle") or by[i].has("vehicles")):
			out.append(by[i])
	return out


const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
