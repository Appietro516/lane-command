class_name NeutralObjectives
extends RefCounted
## Camps use normal battle units. Drops and buffs are match-local timed state.

signal boon_collected(side: MatchRegion.Owner, camp_id: int, cycle: int)

enum Reward { RESOURCES, RANGED_DAMAGE, DEFENSE, SIEGE }

const PICKUP_RADIUS := 1.25
const DROP_DURATION := 30.0
const OBSERVATION_INTERVAL := 0.2
const MINOR_RESPAWN := 82.0
const MAJOR_RESPAWN := 175.0

class Camp:
	var id: int
	var point: Vector2
	var major: bool
	var reward: Reward
	var guard_id := MatchBattle.NO_TARGET
	var drop_until := 0.0
	var pickup_at := 0.0
	var respawns_at := 0.0
	var cycle := 0
	var observed: Dictionary = {}

	func _init(camp_id: int, site: Vector2, is_major: bool) -> void:
		id = camp_id
		point = site
		major = is_major
		reward = Reward.SIEGE if major else (id % 3) as Reward

var camps: Array[Camp] = []
var _buffs: Dictionary = {}
var _next_observation := 0.0
var defeated := 0
var pickups := 0
var stronghold_pickups := 0


func add_camp(point: Vector2, major: bool) -> void:
	camps.append(Camp.new(camps.size() + 1, point, major))


func advance(battle: MatchBattle, economy: MatchEconomy, now: float) -> void:
	if camps.is_empty():
		return
	for camp in camps:
		if camp.guard_id != MatchBattle.NO_TARGET:
			if battle.get_unit(camp.guard_id) == null:
				camp.guard_id = MatchBattle.NO_TARGET
				camp.pickup_at = now + 0.40
				camp.drop_until = now + DROP_DURATION
				camp.respawns_at = now + (MAJOR_RESPAWN if camp.major else MINOR_RESPAWN)
				defeated += 1
		elif now + MatchBattle.TIME_EPSILON >= camp.respawns_at:
			var guard := battle.spawn_neutral_guard(camp.point, camp.major)
			if guard != null:
				camp.guard_id = guard.id
				camp.cycle += 1
			else:
				camp.respawns_at = now + 1.0
	if now + MatchBattle.TIME_EPSILON < _next_observation:
		return
	_next_observation = now + OBSERVATION_INTERVAL
	for camp in camps:
		if now >= camp.pickup_at and camp.drop_until > now:
			var taker := _collector(battle, camp.point)
			if taker != null:
				camp.drop_until = 0.0
				_award(economy, taker.side, camp, now)
		for side in battle._bases:
			if not battle.can_see(side, camp.point):
				continue
			var guard := battle.get_unit(camp.guard_id)
			camp.observed[side] = {"guard": camp.guard_id, "drop": camp.drop_until > now,
				"hp_fraction": guard.hp / guard.definition.hp if guard != null else 0.0,
				"seen_at": now}


func reserves_footprint(footprint: PackedVector2Array) -> bool:
	for camp in camps:
		if Geometry2D.is_point_in_polygon(camp.point, footprint):
			return true
	return false


func _collector(battle: MatchBattle, point: Vector2) -> MatchBattle.Unit:
	var nearest := PICKUP_RADIUS ** 2
	var winner: MatchBattle.Unit
	for unit in battle.nearby_units(battle.active_units(), point, PICKUP_RADIUS):
		if unit.hp <= 0.0 or not battle.is_side_active(unit.side):
			continue
		var distance := point.distance_squared_to(unit.position)
		if distance < nearest or (distance == nearest and (winner == null or unit.id < winner.id)):
			winner = unit
			nearest = distance
	return winner


func _award(economy: MatchEconomy, side: MatchRegion.Owner, camp: Camp, now: float) -> void:
	if camp.reward == Reward.RESOURCES:
		economy.grant_resource(side, MatchEconomy.ENERGY, 34)
		economy.grant_resource(side, MatchEconomy.MATERIALS, 24)
		economy.grant_resource(side, MatchEconomy.FOOD, 18)
	else:
		var effects := _buffs.get_or_add(side, {}) as Dictionary
		effects[camp.reward] = now + (75.0 if camp.major else 48.0)
	pickups += 1
	stronghold_pickups += int(camp.major)
	boon_collected.emit(side, camp.id, camp.cycle)


func has_boon(side: MatchRegion.Owner, reward: Reward, now: float) -> bool:
	return now < _buffs.get(side, {}).get(reward, 0.0)


func active_boons(side: MatchRegion.Owner, now: float) -> PackedStringArray:
	var names := PackedStringArray()
	for reward: Reward in _buffs.get(side, {}):
		var duration: float = _buffs[side][reward] - now
		if duration > 0.0:
			names.append("%s %.0fs" % [Reward.keys()[reward].capitalize(), duration])
	return names
