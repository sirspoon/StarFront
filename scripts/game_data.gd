class_name GameData
extends RefCounted
## Factions, soldier types and weapons. Balance tuning lives here.

const VERSION := "0.01"

## range in pixels (16 px = 1 map cell); cooldown = seconds between bursts;
## acc = base hit chance; ap = how much armour it ignores; supp = suppression per shot.
const WEAPONS := {
	"lumen_rifle": {"name": "Lumen rifle", "range": 340.0, "cooldown": 1.5, "burst": 1, "gap": 0.0,
		"acc": 0.5, "ap": 0.0, "dmg": 1, "supp": 7.0, "tracer": Color(1.0, 0.5, 0.25), "width": 1.6},
	"heavy_stubber": {"name": "Heavy stubber", "range": 430.0, "cooldown": 2.6, "burst": 6, "gap": 0.09,
		"acc": 0.3, "ap": 0.15, "dmg": 1, "supp": 10.0, "tracer": Color(1.0, 0.85, 0.45), "width": 1.3},
	"mass_carbine": {"name": "Mass-reactive carbine", "range": 360.0, "cooldown": 2.0, "burst": 2, "gap": 0.15,
		"acc": 0.36, "ap": 0.35, "dmg": 2, "supp": 14.0, "tracer": Color(0.6, 0.85, 1.0), "width": 2.2},
	"rotor_cannon": {"name": "Rotor cannon", "range": 440.0, "cooldown": 3.0, "burst": 5, "gap": 0.1,
		"acc": 0.26, "ap": 0.5, "dmg": 2, "supp": 18.0, "tracer": Color(0.55, 0.8, 1.0), "width": 2.6},
}

## nerve multiplies morale loss (higher = panics sooner).
const SOLDIERS := {
	"conscript": {"name": "Conscript", "hp": 1, "armor": 0.1, "speed": 46.0, "morale": 60.0, "nerve": 1.25,
		"radius": 7.0, "weapon": "lumen_rifle"},
	"gunner": {"name": "Stubber gunner", "hp": 1, "armor": 0.1, "speed": 40.0, "morale": 65.0, "nerve": 1.1,
		"radius": 7.0, "weapon": "heavy_stubber"},
	"sergeant": {"name": "Sergeant", "hp": 1, "armor": 0.2, "speed": 46.0, "morale": 80.0, "nerve": 0.9,
		"radius": 7.0, "weapon": "lumen_rifle", "leader": true},
	"brother": {"name": "Sworn Brother", "hp": 3, "armor": 0.55, "speed": 38.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "mass_carbine"},
	"cannoneer": {"name": "Sworn Cannoneer", "hp": 3, "armor": 0.55, "speed": 34.0, "morale": 95.0, "nerve": 0.5,
		"radius": 10.0, "weapon": "rotor_cannon"},
	"champion": {"name": "Sworn Champion", "hp": 4, "armor": 0.6, "speed": 38.0, "morale": 110.0, "nerve": 0.4,
		"radius": 10.0, "weapon": "mass_carbine", "leader": true},
}

const FACTIONS := {
	"legion": {
		"name": "Dominion Legion", "short": "Legion",
		"blurb": "Endless ranks of conscripts in rebreathers and greatcoats. Cheap, numerous and brittle: they win by weight of fire.",
		"coat": Color(0.37, 0.39, 0.28), "armour": Color(0.25, 0.26, 0.21), "trim": Color(0.75, 0.62, 0.32),
		"blood": Color(0.42, 0.04, 0.04), "ui": Color(0.62, 0.7, 0.42),
		"squads": [
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Conscript Squad", "members": ["sergeant", "conscript", "conscript", "conscript", "conscript", "conscript", "gunner"]},
			{"name": "Stubber Team", "members": ["sergeant", "gunner", "gunner"]},
		],
	},
	"sworn": {
		"name": "The Sworn", "short": "Sworn",
		"blurb": "A handful of armoured warrior-monks bound by oath. Very hard to kill and harder to break, but every loss hurts.",
		"coat": Color(0.45, 0.11, 0.1), "armour": Color(0.3, 0.07, 0.07), "trim": Color(0.86, 0.72, 0.42),
		"blood": Color(0.3, 0.03, 0.03), "ui": Color(0.85, 0.35, 0.3),
		"squads": [
			{"name": "Sworn Talon", "members": ["champion", "brother", "brother", "cannoneer"]},
			{"name": "Sworn Talon", "members": ["champion", "brother", "brother", "cannoneer"]},
			{"name": "Sworn Talon", "members": ["champion", "brother", "brother", "cannoneer"]},
		],
	},
}

const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
