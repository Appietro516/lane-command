class_name MatchEconomy
extends RefCounted

const ENERGY := FactionStats.ENERGY
const MATERIALS := FactionStats.MATERIALS
const FOOD := FactionStats.FOOD
const BASE_INCOME := FactionStats.BASELINE
const STARTING_ENERGY := 50.0
const RESOURCES := {
	ENERGY: {"label": "Energy", "starting_stock": STARTING_ENERGY, "baseline": 3.0},
	MATERIALS: {"label": "Materials", "starting_stock": 30.0, "baseline": 2.0},
	FOOD: {"label": "Food", "starting_stock": 20.0, "baseline": 1.0},
}
const BARRACKS_COST := {ENERGY: 40, MATERIALS: 20}
const UnitCatalog := preload("res://match/unit_catalog.gd")
const UNIT_COST := {FOOD: UnitCatalog.DEFINITIONS[UnitCatalog.BARRACKS_TYPE].food}
const UPGRADE_COST := {ENERGY: 60, FOOD: 15}
const CLAIM_COST := {ENERGY: 50}
const PRODUCTION_INTERVAL := 3.5
const UPGRADED_PRODUCTION_INTERVAL := 2.5
const PRODUCTION_UPGRADE := &"barracks_upgrade"

class SideState:
	var stockpiles: Dictionary[StringName, float] = {}
	var barracks_count := 0
	var upgraded := false

	func _init() -> void:
		for resource_id in RESOURCES:
			var definition: Dictionary = RESOURCES[resource_id]
			stockpiles[resource_id] = definition.starting_stock


var stats: FactionStats
var _sides: Dictionary[MatchRegion.Owner, SideState] = {}
var _eliminated: Dictionary[MatchRegion.Owner, bool] = {}


func _init(faction_stats: FactionStats = null, sides: Array = [
		MatchRegion.Owner.PLAYER, MatchRegion.Owner.CPU]) -> void:
	stats = faction_stats if faction_stats != null else FactionStats.new()
	for side: MatchRegion.Owner in sides:
		_sides[side] = SideState.new()


func is_active(side: MatchRegion.Owner) -> bool:
	return _sides.has(side) and not _eliminated.has(side)


func eliminate(side: MatchRegion.Owner) -> void:
	_eliminated[side] = true


func advance(delta: float) -> void:
	if delta <= 0.0:
		return

	for side in _sides:
		if not is_active(side):
			continue
		var state := _sides[side]
		for resource_id in RESOURCES:
			state.stockpiles[resource_id] = maxf(0.0,
				stockpile(side, resource_id) + income_rate(side, resource_id) * delta)


func stockpile(side: MatchRegion.Owner, resource_id: StringName) -> float:
	var amount := _sides[side].stockpiles[resource_id]
	# Fixed simulation steps can leave a stockpile a fraction below an exact price.
	var whole := roundf(amount)
	return whole if absf(amount - whole) < 1e-9 else amount


func energy(side: MatchRegion.Owner) -> float:
	return stockpile(side, ENERGY)


func income_rate(side: MatchRegion.Owner, resource_id: StringName) -> float:
	return stats.value(side, resource_id, RESOURCES[resource_id].baseline)


func income_stat(side: MatchRegion.Owner, resource_id: StringName) -> Dictionary:
	return stats.inspect(side, resource_id, RESOURCES[resource_id].baseline)


func income_sources(side: MatchRegion.Owner, resource_id: StringName) -> Dictionary:
	var sources := {}
	var prefix := _income_prefix(side)
	for entry: Dictionary in income_stat(side, resource_id).breakdown:
		if entry.active:
			var id := StringName(str(entry.source_id).trim_prefix(prefix))
			sources[id] = {"label": entry.source_name, "rate": entry.magnitude}
			if entry.has("building_id"):
				sources[id].merge({
					"building_id": entry.building_id, "region_id": entry.region_id,
					"owner": entry.owner,
				})
	return sources


# The original income API scopes IDs to each side and resource.
func set_income_source(side: MatchRegion.Owner, resource_id: StringName,
		source_id: StringName, label: String, rate: float, source_type := &"building") -> void:
	if not _sides.has(side) or not RESOURCES.has(resource_id) or source_id.is_empty() \
			or source_id == BASE_INCOME or not is_finite(rate):
		return

	var scoped_id := StringName(_income_prefix(side) + source_id)
	if rate == 0.0:
		stats.remove_source(scoped_id, resource_id)
	else:
		stats.set_modifier(scoped_id, side, resource_id, rate, source_type, label)


func _income_prefix(side: MatchRegion.Owner) -> String:
	return "income/%d/" % side


static func cost_text(cost: Dictionary) -> String:
	var prices := PackedStringArray()
	for resource_id in cost:
		prices.append("%d %s" % [cost[resource_id], RESOURCES[resource_id].label])
	return " + ".join(prices)


func cost_block_reason(side: MatchRegion.Owner, cost: Dictionary) -> String:
	if not is_active(side):
		return "Purchase unavailable"

	var missing := PackedStringArray()
	for resource_id in cost:
		var amount: Variant = cost[resource_id]
		if not RESOURCES.has(resource_id) or typeof(amount) != TYPE_INT or amount < 0:
			return "Invalid cost"
		if stockpile(side, resource_id) < amount:
			missing.append(RESOURCES[resource_id].label.to_lower())
	return "" if missing.is_empty() else "Need more %s" % ", ".join(missing)


func try_spend(side: MatchRegion.Owner, cost: Dictionary) -> bool:
	if not cost_block_reason(side, cost).is_empty():
		return false

	var state := _sides[side]
	for resource_id in cost:
		state.stockpiles[resource_id] = stockpile(side, resource_id) - cost[resource_id]
	return true


func grant_resource(side: MatchRegion.Owner, resource_id: StringName, amount: int) -> bool:
	if not is_active(side) or not RESOURCES.has(resource_id) or amount <= 0:
		return false
	_sides[side].stockpiles[resource_id] = stockpile(side, resource_id) + amount
	return true


func barracks_count(side: MatchRegion.Owner) -> int:
	return _sides[side].barracks_count


func production_interval(side: MatchRegion.Owner) -> float:
	return stats.value(side, FactionStats.BARRACKS_INTERVAL, PRODUCTION_INTERVAL)


## A shorter cycle increases production capacity. Paused barracks have zero capacity.
## Food is charged separately when a cycle deploys a unit.
func production_stat(side: MatchRegion.Owner, active: bool) -> Dictionary:
	var result := stats.inspect(side, FactionStats.BARRACKS_INTERVAL, PRODUCTION_INTERVAL)
	var interval := PRODUCTION_INTERVAL
	var rate := 1.0 / interval
	var breakdown: Array[Dictionary] = []
	for entry: Dictionary in result.breakdown:
		if entry.source_id == FactionStats.LIMIT:
			continue # The marginal rates already respect the minimum cycle time.
		entry.stat = &"barracks_rate"
		if entry.source_id == FactionStats.BASELINE:
			entry.magnitude = rate
			breakdown.append(entry)
			continue
		# Attribute each change in throughput in the same order as the cycle modifiers.
		var minimum: float = FactionStats.STAT_DEFINITIONS[FactionStats.BARRACKS_INTERVAL].minimum
		entry.configured_magnitude = 1.0 / maxf(interval + entry.configured_magnitude, minimum) - rate
		interval += entry.magnitude
		var next_rate := 1.0 / maxf(interval, minimum)
		entry.magnitude = next_rate - rate
		rate = next_rate
		breakdown.append(entry)
	if not active:
		breakdown.append({"source_name": "Territory lost", "source_type": &"rule",
			"magnitude": -rate, "active": true})
	return {"total": 1.0 / result.total if active else 0.0, "breakdown": breakdown}


func has_upgrade(side: MatchRegion.Owner) -> bool:
	return _sides[side].upgraded


func can_upgrade(side: MatchRegion.Owner) -> bool:
	return _sides.has(side) and not has_upgrade(side) and cost_block_reason(side, UPGRADE_COST).is_empty()


func try_build(side: MatchRegion.Owner, cost: Dictionary) -> bool:
	if not try_spend(side, cost):
		return false

	_sides[side].barracks_count += 1
	return true


func remove_barracks(side: MatchRegion.Owner) -> void:
	_sides[side].barracks_count -= 1


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if not _sides.has(side) or has_upgrade(side) or not try_spend(side, UPGRADE_COST):
		return false

	_sides[side].upgraded = true
	stats.set_modifier(StringName("%s/%d" % [PRODUCTION_UPGRADE, side]), side,
		FactionStats.BARRACKS_INTERVAL, UPGRADED_PRODUCTION_INTERVAL - PRODUCTION_INTERVAL,
		&"upgrade", "Barracks upgrade")
	return true
