class_name RegionSpecialty
extends RefCounted

enum Kind { STANDARD, FERTILE, MINERAL, ENERGY, DEFENSIBLE }

const INCOME_FACTOR := 1.35
const DEFENSE_HP_FACTOR := 1.20
const TRAITS := {
	Kind.FERTILE: {"label": "Fertile", "detail": "+35% local Farm income", "building": &"farm",
		"color": Color("#a3ce63"), "height": 0.28},
	Kind.MINERAL: {"label": "Mineral-rich", "detail": "+35% local Mine income", "building": &"mine",
		"color": Color("#c6b7a3"), "height": 0.62},
	Kind.ENERGY: {"label": "Energy-rich", "detail": "+35% local Generator income", "building": &"generator",
		"color": Color("#50d8d5"), "height": 0.8},
	Kind.DEFENSIBLE: {"label": "Defensible", "detail": "+20% local outpost and defense HP", "building": &"",
		"color": Color("#a2b6c1"), "height": 1.2},
}


static func income_factor(kind: Kind, building: StringName) -> float:
	return INCOME_FACTOR if kind != Kind.STANDARD and TRAITS[kind].building == building else 1.0


static func defense_factor(kind: Kind) -> float:
	return DEFENSE_HP_FACTOR if kind == Kind.DEFENSIBLE else 1.0
