class_name FactionStrength
extends RefCounted
## Public scores contain only faction totals. Bounty eligibility uses a slower trend.

const PERIOD := 3.0
const BOUNTY_DELAY := 36.0
const BOUNTY_COOLDOWN := 90.0
const BOUNTY_LIMIT := 6
const SCORE_LIMIT := 1000.0

var scores: Dictionary[MatchRegion.Owner, float] = {}
var revision := 0
var awarded := 0
var _next_update := 0.0
var _trend: Dictionary = {}
var _peak: Dictionary = {}
var _behind_since: Dictionary = {}
var _last_reward: Dictionary = {}
var _rewards: Dictionary = {}


static func score(military: float, economy: float, territory: float, defense: float) -> float:
	return SCORE_LIMIT * (0.35 * clampf(military, 0.0, 1.0) + 0.30 * clampf(economy, 0.0, 1.0)
		+ 0.20 * clampf(territory, 0.0, 1.0) + 0.15 * clampf(defense, 0.0, 1.0))


func advance(scene: Node3D) -> void:
	var battle: MatchBattle = scene._battle
	var now := battle.elapsed_time()
	if not battle.is_finished() and now + MatchBattle.TIME_EPSILON < _next_update:
		return
	_next_update = now + PERIOD
	var economy: MatchEconomy = scene.economy
	var military := {}
	var production := {}
	var consumption := {}
	var strategic := {}
	var defense := {}
	for unit in battle.active_units():
		if not battle.is_side_active(unit.side) or unit.hp <= 0.0:
			continue
		var weight: float = maxf(0.5, float(unit.definition.food))
		military[unit.side] = military.get(unit.side, 0.0) + weight * clampf(unit.hp / unit.definition.hp, 0.0, 1.25)
	for fort in battle._fortifications.values():
		if not fort.active or fort.hp <= 0.0:
			continue
		if fort is MatchBattle.ProductionTimer:
			var interval: float = fort.interval(economy)
			production[fort.side] = production.get(fort.side, 0.0) + 1.0 / interval
			consumption[fort.side] = consumption.get(fort.side, 0.0) + MatchEconomy.UnitCatalog.DEFINITIONS[fort.unit_type].food / interval
		elif fort.profile.has("range"):
			defense[fort.side] = defense.get(fort.side, 0.0) + fort.hp
		elif fort.kind in [BattleRadar.WATCHTOWER, BattleRadar.RADAR, BattleRadar.COUNTERINTELLIGENCE, &"missile_silo"]:
			strategic[fort.side] = strategic.get(fort.side, 0.0) + 0.35
	for region: MatchRegion in scene._regions_by_id.values():
		if region.ruined or region.region_owner == MatchRegion.Owner.NEUTRAL:
			continue
		var value := 1.0 + (0.25 if region.specialty != RegionSpecialty.Kind.STANDARD else 0.0)
		var landmark: LegendaryLandmark = scene._landmarks.get(region.region_id)
		if landmark != null and battle._landmark_footprints.has(landmark.footprint):
			value += 0.5
		strategic[region.region_owner] = strategic.get(region.region_owner, 0.0) + value
	for outpost in battle._outposts.values():
		defense[outpost.side] = defense.get(outpost.side, 0.0) + outpost.hp
	for side in battle._bases:
		if not battle.is_side_active(side):
			scores[side] = 0.0
			_trend.erase(side)
			_behind_since.erase(side)
			continue
		var food := maxf(0.0, economy.income_rate(side, MatchEconomy.FOOD))
		var energy := economy.income_rate(side, MatchEconomy.ENERGY)
		var materials := economy.income_rate(side, MatchEconomy.MATERIALS)
		var sustainable: float = production.get(side, 0.0) * minf(1.0, food / maxf(0.1, consumption.get(side, 0.0)))
		var income_value := (clampf(energy / 10.0, 0.0, 1.0) + clampf(materials / 8.0, 0.0, 1.0)
			+ clampf(food / 10.0, 0.0, 1.0)) / 3.0
		scores[side] = score(military.get(side, 0.0) / 205.0, 0.60 * income_value + 0.40 * minf(1.0, sustainable / 1.15),
			strategic.get(side, 0.0) / 7.0, (battle.base_hp(side) + defense.get(side, 0.0)) / 680.0)
	_update_trends(now)
	revision += 1


func _update_trends(now: float) -> void:
	for side in scores:
		if scores[side] <= 0.0:
			continue
		_trend[side] = lerpf(_trend.get(side, scores[side]), scores[side], 0.20)
		_peak[side] = maxf(_trend[side], _peak.get(side, 0.0) * 0.96)
	for side in _trend:
		var leading_rival := 0.0
		for rival in _trend:
			if rival != side:
				leading_rival = maxf(leading_rival, _trend[rival])
		if leading_rival >= 200.0 and _peak[side] <= leading_rival * 0.72 and leading_rival - _peak[side] >= 90.0:
			_behind_since.get_or_add(side, now)
		else:
			_behind_since.erase(side)


func ranked() -> Array[MatchRegion.Owner]:
	var sides := scores.keys()
	sides.sort_custom(func(a: MatchRegion.Owner, b: MatchRegion.Owner) -> bool:
		return a < b if scores[a] == scores[b] else scores[a] > scores[b])
	var result: Array[MatchRegion.Owner] = []
	result.assign(sides)
	return result


func award(economy: MatchEconomy, side: MatchRegion.Owner, objective: StringName,
		now: float, landmark := false) -> bool:
	var rewards := _rewards.get_or_add(side, {}) as Dictionary
	if not economy.is_active(side) or rewards.has(objective) or rewards.size() >= BOUNTY_LIMIT \
			or now - _behind_since.get(side, INF) < BOUNTY_DELAY \
			or now - _last_reward.get(side, -INF) < BOUNTY_COOLDOWN:
		return false
	rewards[objective] = true
	_last_reward[side] = now
	economy.grant_resource(side, MatchEconomy.ENERGY, 30 if landmark else 22)
	economy.grant_resource(side, MatchEconomy.MATERIALS, 22 if landmark else 15)
	economy.grant_resource(side, MatchEconomy.FOOD, 18 if landmark else 12)
	awarded += 1
	return true
