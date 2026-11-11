class_name GameData
extends RefCounted
## Factions, soldier types and weapons. Balance tuning lives here.

const VERSION := "0.20"

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
	"mass_carbine": {"name": "Mass-reactive carbine", "range": 360.0, "cooldown": 2.0, "burst": 2, "gap": 0.15,
		"acc": 0.31, "ap": 0.35, "dmg": 2, "pen": 3, "vdmg": 1, "supp": 14.0, "tracer": Color(0.6, 0.85, 1.0), "width": 2.2},
	"rotor_cannon": {"name": "Rotor cannon", "range": 440.0, "cooldown": 3.0, "burst": 5, "gap": 0.1,
		"acc": 0.26, "ap": 0.5, "dmg": 2, "pen": 4, "vdmg": 2, "supp": 18.0, "tracer": Color(0.55, 0.8, 1.0), "width": 2.6},
	"lance_launcher": {"name": "Lance launcher", "range": 400.0, "cooldown": 6.0, "burst": 1, "gap": 0.0,
		"acc": 0.42, "ap": 0.6, "dmg": 2, "pen": 8, "vdmg": 5, "blast": 18.0, "wall": 45.0, "supp": 20.0,
		"tracer": Color(1.0, 0.75, 0.4), "width": 3.0},
	"fusion_carbine": {"name": "Fusion carbine", "range": 210.0, "cooldown": 3.5, "burst": 1, "gap": 0.0,
		"acc": 0.6, "ap": 0.9, "dmg": 4, "pen": 9, "vdmg": 5, "supp": 20.0,
		"tracer": Color(0.75, 0.9, 1.0), "width": 4.0},
	"siege_cannon": {"name": "Siege cannon", "range": 620.0, "cooldown": 5.0, "burst": 1, "gap": 0.0,
		"acc": 0.5, "ap": 0.6, "dmg": 3, "pen": 9, "vdmg": 6, "blast": 42.0, "wall": 80.0, "supp": 40.0,
		"tracer": Color(1.0, 0.9, 0.6), "width": 3.5},
	"fusion_cannon": {"name": "Fusion cannon", "range": 540.0, "cooldown": 6.0, "burst": 1, "gap": 0.0,
		"acc": 0.55, "ap": 0.9, "dmg": 4, "pen": 9, "vdmg": 6, "blast": 24.0, "wall": 70.0, "supp": 40.0,
		"tracer": Color(0.7, 0.9, 1.0), "width": 5.0},
}

## nerve multiplies morale loss (higher = panics sooner).
const SOLDIERS := {
	"conscript": {"name": "Conscript", "hp": 1, "armor": 0.1, "speed": 46.0, "morale": 60.0, "nerve": 1.25,
		"radius": 7.0, "weapon": "lumen_rifle"},
	"gunner": {"name": "Stubber gunner", "hp": 1, "armor": 0.1, "speed": 40.0, "morale": 65.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "heavy_stubber"},
	"sergeant": {"name": "Sergeant", "hp": 1, "armor": 0.2, "speed": 46.0, "morale": 80.0, "nerve": 0.9,
		"radius": 7.0, "weapon": "lumen_rifle", "leader": true},
	"lancer": {"name": "Lancer", "hp": 1, "armor": 0.1, "speed": 42.0, "morale": 65.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "lance_launcher"},
	"brother": {"name": "Sworn Brother", "hp": 3, "armor": 0.5, "speed": 38.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "mass_carbine"},
	"cannoneer": {"name": "Sworn Cannoneer", "hp": 3, "armor": 0.5, "speed": 34.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "rotor_cannon"},
	"breacher": {"name": "Sworn Breacher", "hp": 3, "armor": 0.5, "speed": 38.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "fusion_carbine"},
	"champion": {"name": "Sworn Champion", "hp": 4, "armor": 0.6, "speed": 38.0, "morale": 110.0, "nerve": 0.4,
		"radius": 10.0, "weapon": "mass_carbine", "leader": true},
}

## armour = [front, side, rear]. Carriers hold a squad; one starts the battle inside.
## Weapons marked turret turn with the turret; the others can fire all round.
const VEHICLES := {
	"drudge": {"name": "Drudge Carrier", "role": "carrier", "hp": 9, "armour": [6, 5, 4], "speed": 56.0,
		"turn": 1.6, "length": 50.0, "width": 30.0, "capacity": 8,
		"weapons": [{"weapon": "heavy_stubber", "mount": Vector2(10, -7)}]},
	"vigil": {"name": "Vigil Tank", "role": "tank", "hp": 14, "armour": [9, 7, 5], "speed": 36.0,
		"turn": 1.0, "length": 62.0, "width": 38.0, "capacity": 0,
		"weapons": [{"weapon": "siege_cannon", "turret": true}, {"weapon": "heavy_stubber", "mount": Vector2(22, 9)}]},
	"pilgrim": {"name": "Pilgrim Carrier", "role": "carrier", "hp": 9, "armour": [6, 5, 4], "speed": 50.0,
		"turn": 1.5, "length": 52.0, "width": 32.0, "capacity": 6,
		"weapons": [{"weapon": "rotor_cannon", "mount": Vector2(8, 0)}]},
	"verdict": {"name": "Verdict Tank", "role": "tank", "hp": 14, "armour": [9, 8, 6], "speed": 32.0,
		"turn": 0.9, "length": 64.0, "width": 40.0, "capacity": 0,
		"weapons": [{"weapon": "fusion_cannon", "turret": true}, {"weapon": "rotor_cannon", "mount": Vector2(18, -13)}]},
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
			{"name": "Stubber Team", "members": ["sergeant", "gunner", "gunner"]},
			{"name": "Lance Team", "members": ["sergeant", "lancer", "lancer"]},
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
			{"name": "Breacher Talon", "members": ["champion", "brother", "breacher", "breacher"]},
			{"vehicle": "verdict"},
		],
	},
}

const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
