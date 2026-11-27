extends RefCounted
## Provisional unit balance and presentation. IDs are shared by both factions.

const INFANTRY := &"infantry"
const RANGED := &"ranged"
const HEAVY := &"heavy"
const SCOUT := &"scout"
const MEDIC := &"medic"
const RAIDER := &"raider"
const OFFENSIVE_TYPES := [INFANTRY, RANGED, HEAVY, RAIDER]
const COMBAT_TYPES := [INFANTRY, RANGED, HEAVY, MEDIC, RAIDER]

const DEFINITIONS := {
	SCOUT: {
		"class": SCOUT,
		"label": "Scout",
		"hp": 10.0, "damage": 0.0, "cooldown": 1.0, "range": 0.0, "speed": 2.288,
		"clearance": 0.22, "food": 0, "structure_damage_multiplier": 1.0,
		"scene": preload("res://match/scout.tscn"), "tint": Color.WHITE, "tint_weight": 0.0,
		"selection_scale": 1.0,
	},
	INFANTRY: {
		"class": INFANTRY,
		"label": "Infantry",
		"hp": 12.0, "damage": 3.0, "cooldown": 1.0, "range": 0.9, "speed": 1.584,
		"clearance": 0.0, "food": 4, "structure_damage_multiplier": 0.85,
		"attack_effect": {"style": &"swing", "duration": 0.23},
		"scene": preload("res://match/unit.tscn"), "tint": Color.WHITE, "tint_weight": 0.0,
		"selection_scale": 1.0,
	},
	RANGED: {
		"class": RANGED,
		"label": "Ranged",
		"damage_against": {RAIDER: 2.25},
		"hp": 8.0, "damage": 1.5, "cooldown": 0.65, "range": 2.8, "speed": 1.936,
		"clearance": 0.10, "food": 5, "structure_damage_multiplier": 0.72,
		"attack_effect": {"style": &"tracer", "duration": 0.19},
		"scene": preload("res://match/ranged_unit.tscn"), "tint": Color(0.95, 0.91, 0.99),
		"tint_weight": 0.35, "selection_scale": 1.1,
	},
	HEAVY: {
		"class": HEAVY,
		"label": "Heavy",
		"damage_against": {RAIDER: 1.75},
		"hp": 26.0, "damage": 5.0, "cooldown": 1.45, "range": 1.1, "speed": 1.32,
		"clearance": 0.34, "food": 9, "structure_damage_multiplier": 1.85,
		"attack_effect": {"style": &"pulse", "duration": 0.38},
		"scene": preload("res://match/heavy_unit.tscn"), "tint": Color(0.24, 0.32, 0.37),
		"tint_weight": 0.28, "selection_scale": 1.3,
	},
	MEDIC: {
		"class": MEDIC, "label": "Medic",
		"hp": 9.0, "damage": 0.0, "cooldown": 1.2, "range": 0.0, "speed": 1.76,
		"clearance": 0.10, "food": 6, "structure_damage_multiplier": 1.0,
		"support": {"radius": 2.0, "heal": 2.5, "follow_range": 7.0, "recovery": 0.85},
		"attack_effect": {"style": &"heal", "duration": 0.45},
		"scene": preload("res://match/medic_unit.tscn"), "tint": Color("#ddffdf"),
		"tint_weight": 0.4, "selection_scale": 1.05,
	},
	RAIDER: {
		"class": RAIDER, "label": "Raider",
		"damage_against": {INFANTRY: 2.25, HEAVY: 0.65},
		"hp": 9.0, "damage": 2.7, "cooldown": 0.8, "range": 0.8, "speed": 2.64,
		"clearance": 0.10, "food": 5, "structure_damage_multiplier": 0.55,
		"attack_effect": {"style": &"slash", "duration": 0.27},
		"scene": preload("res://match/raider_unit.tscn"), "tint": Color("#f3bc7e"),
		"tint_weight": 0.32, "selection_scale": 1.08,
	},
}

const BARRACKS_TYPE := INFANTRY



static func damage_multiplier(source: Dictionary, target: Dictionary) -> float:
	var modifiers: Dictionary = source.get("damage_against", {})
	return modifiers.get(target.get("class", &""), 1.0)
