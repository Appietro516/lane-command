extends RefCounted
## Provisional unit balance and presentation. IDs are shared by both factions.

const INFANTRY := &"infantry"
const RANGED := &"ranged"
const HEAVY := &"heavy"
const SCOUT := &"scout"
const COMBAT_TYPES := [INFANTRY, RANGED, HEAVY]

const DEFINITIONS := {
	SCOUT: {
		"label": "Scout",
		"hp": 10.0, "damage": 0.0, "cooldown": 1.0, "range": 0.0, "speed": 2.6,
		"clearance": 0.22, "food": 0, "structure_damage_multiplier": 1.0,
		"prefer_ready_shot": false,
		"scene": preload("res://match/scout.tscn"), "tint": Color.WHITE, "tint_weight": 0.0,
		"selection_scale": 1.0,
	},
	INFANTRY: {
		"label": "Infantry",
		"hp": 12.0, "damage": 3.0, "cooldown": 1.0, "range": 0.9, "speed": 1.8,
		"clearance": 0.0, "food": 4, "structure_damage_multiplier": 1.0,
		"attack_effect": {"style": &"swing", "duration": 0.23},
		"prefer_ready_shot": false,
		"scene": preload("res://match/unit.tscn"), "tint": Color.WHITE, "tint_weight": 0.0,
		"selection_scale": 1.0,
	},
	RANGED: {
		"label": "Ranged",
		"hp": 8.0, "damage": 1.5, "cooldown": 0.65, "range": 2.8, "speed": 2.2,
		"clearance": 0.10, "food": 5, "structure_damage_multiplier": 1.0,
		"attack_effect": {"style": &"tracer", "duration": 0.19},
		"prefer_ready_shot": true,
		"scene": preload("res://match/ranged_unit.tscn"), "tint": Color(0.95, 0.91, 0.99),
		"tint_weight": 0.35, "selection_scale": 1.1,
	},
	HEAVY: {
		"label": "Heavy",
		"hp": 26.0, "damage": 5.0, "cooldown": 1.45, "range": 1.1, "speed": 1.5,
		"clearance": 0.34, "food": 8, "structure_damage_multiplier": 1.25,
		"attack_effect": {"style": &"pulse", "duration": 0.38},
		"prefer_ready_shot": false,
		"scene": preload("res://match/heavy_unit.tscn"), "tint": Color(0.24, 0.32, 0.37),
		"tint_weight": 0.28, "selection_scale": 1.3,
	},
}

const BARRACKS_TYPE := INFANTRY
