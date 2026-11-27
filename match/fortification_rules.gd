extends RefCounted

const NEST := &"machine_gun_nest"
const MORTAR := &"mortar"
const SILO := &"missile_silo"
const MISSILE_RADIUS := 7.0
const MISSILE_CHARGE := 60.0
const RETALIATION_DURATION := 105.0
const MISSILE_FLIGHT := 2.4
const ANTI_TANK := &"anti_tank_gun"
const WALL := &"wall"
const WALL_SEGMENT_LENGTH := 1.0
const WALL_WIDTH := 0.44

const PROFILES := {
	NEST: {
		"label": "Machine gun nest", "description": "Rapid fire at one enemy",
		"cost": {MatchEconomy.ENERGY: 32, MatchEconomy.MATERIALS: 18},
		"hp": 30, "size": Vector2(1.3, 1.3),
		"range": 4.5, "interval": 0.25, "damage": 1.25, "splash": 0.0,
	},
	MORTAR: {
		"label": "Mortar", "description": "Long-range splash against enemies",
		"cost": {MatchEconomy.ENERGY: 45, MatchEconomy.MATERIALS: 24, MatchEconomy.FOOD: 8},
		"hp": 24, "size": Vector2(1.3, 1.3),
		"range": 7.0, "interval": 2.4, "damage": 5.0, "splash": 1.35,
	},
	ANTI_TANK: {
		"label": "Anti-Tank Gun", "description": "Slow, armor-piercing shots against Heavy units",
		"cost": {MatchEconomy.ENERGY: 54, MatchEconomy.MATERIALS: 34},
		"hp": 32, "size": Vector2(1.6, 1.6),
		"range": 6.0, "interval": 1.85, "damage": 4.0, "splash": 0.0,
		"damage_against": {MatchEconomy.UnitCatalog.HEAVY: 4.25, MatchEconomy.UnitCatalog.INFANTRY: 0.45},
		"prefer_damage_class": true,
	},
	SILO: {
		"label": "Missile Silo", "description": "One strategic strike · 4 building slots",
		"cost": {MatchEconomy.ENERGY: 390, MatchEconomy.MATERIALS: 270, MatchEconomy.FOOD: 45},
		"hp": 65, "size": Vector2(4.8, 4.4), "slots": 4,
	},
	WALL: {
		"label": "Wall", "description": "Drag to build a line of barriers",
		"cost_per_unit": {MatchEconomy.ENERGY: 3.0, MatchEconomy.MATERIALS: 2.0},
		"hp": 18, "size": Vector2(WALL_SEGMENT_LENGTH, WALL_WIDTH),
		"range": 0.0, "interval": 0.0, "damage": 0.0, "splash": 0.0,
	},
}


static func wall_count(length: float) -> int:
	return floori(snappedf(length, 0.00001) / WALL_SEGMENT_LENGTH)


static func wall_cost(count: int) -> Dictionary:
	var cost := {}
	var rates: Dictionary = PROFILES[WALL].cost_per_unit
	for resource_id in rates:
		cost[resource_id] = ceili(count * WALL_SEGMENT_LENGTH * rates[resource_id])
	return cost


static func footprint(center: Vector2, size: Vector2, angle := 0.0) -> PackedVector2Array:
	var corners := BattleNavigation.corners_of(Rect2(-size * 0.5, size))
	return Transform2D(angle, center) * corners



static func blast_hits(point: Vector2, center: Vector2, size: Vector2, angle := 0.0) -> bool:
	var local := (point - center).rotated(-angle)
	var closest := local.clamp(-size * 0.5, size * 0.5)
	return local.distance_squared_to(closest) <= MISSILE_RADIUS ** 2
