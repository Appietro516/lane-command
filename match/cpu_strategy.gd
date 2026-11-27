extends RefCounted
## Economic decisions and tactical orders for one CPU faction.

const Rules := preload("res://match/fortification_rules.gd")
const ScoutExpeditions := preload("res://match/scout_expeditions.gd")
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS
const FOOD := MatchEconomy.FOOD
const BARRACKS := &"barracks"
const UnitCatalog := preload("res://match/unit_catalog.gd")
const DifficultyProfile := preload("res://match/difficulty_profile.gd")
const CpuTactics := preload("res://match/cpu_tactics.gd")
const RESPONSE_RESERVE := {ENERGY: 10, MATERIALS: 6}
const REGION_SITE_BUDGET := 5
const DEFENSE_HUB_BUDGET := 8
const GUN_TARGET_BUDGET := 16
const WALL_SEGMENTS := 2
const WALL_BYPASS := Vector2(0.45, 0.18)
const MIN_MORTAR_TARGETS := 2
const MIN_WALL_TARGETS := 2
const CLAIM_INTERRUPTION_RETRY := 24.0
const SILO_MIN_TIME := 100.0
const SILO_MIN_VALUE := 12.0
const SILO_SITE_BUDGET := 18


class Production:
	var active := 0
	var total := 0
	var counts := {}
	var opposition := {}
	var food_per_cycle := 0
	var food_per_second := 0.0
	var upgraded := 0
	var upgrade_candidate: MatchBattle.ProductionTimer

	func _init(battle: MatchBattle, economy: MatchEconomy, side: MatchRegion.Owner) -> void:
		for timer in battle._timers:
			if timer.hp <= 0.0:
				continue
			if timer.side != side:
				if timer.active and battle.can_see(side, timer.position):
					opposition[timer.unit_type] = opposition.get(timer.unit_type, 0) + 1
				continue
			total += 1
			if not timer.active:
				continue
			active += 1
			counts[timer.kind] = counts.get(timer.kind, 0) + 1
			var food: int = UnitCatalog.DEFINITIONS[timer.unit_type].food
			var interval := timer.interval(economy)
			food_per_cycle += food
			food_per_second += food / interval
			if timer.level == 2:
				upgraded += 1
			if timer.level == 1 and (upgrade_candidate == null or (timer.kind == BARRACKS
					and upgrade_candidate.kind != BARRACKS)):
				upgrade_candidate = timer


var side: MatchRegion.Owner
var time_until_decision: float
var difficulty: Dictionary
var _rng := RandomNumberGenerator.new()
var _retry_at := {}
var _next_defense := 0.0
var _next_claim := 0.0
var _next_replacement := 0.0
var _claim_retry_at: Dictionary[StringName, float] = {}
var _tactics := CpuTactics.new()


func _init(map_seed: int, level := DifficultyProfile.DEFAULT_LEVEL,
		owner := MatchRegion.Owner.CPU) -> void:
	side = owner
	difficulty = DifficultyProfile.get_profile(level)
	_rng.seed = map_seed ^ 46 ^ ((side - MatchRegion.Owner.CPU) * 0x9E3779B9)


func decide(scene: Node3D) -> void:
	var battle: MatchBattle = scene._battle
	if battle.is_finished() or not battle.is_side_active(side):
		return
	var now := battle.elapsed_time()
	var owned: Array[MatchRegion] = []
	for region: MatchRegion in scene._regions_by_id.values():
		if region.region_owner == side:
			owned.append(region)
	var units := battle.visible_units(side)
	var threats := _threats(scene, owned, units)
	_plan_economy(scene, owned, units, threats, now)
	_tactics.decide(scene, side, difficulty, owned, units, threats, now)
	for structure in battle._fortifications.values():
		if structure.side == side and structure.kind == BattleRadar.COUNTERINTELLIGENCE:
			var rival := battle.nearest_hostile_base(side, structure.position)
			var toward: Vector2 = battle._bases[rival]
			var point: Vector2 = structure.position.lerp(toward, 0.42).lerp(battle._bases[side], 0.1)
			battle.deploy_decoy(side, structure.id, point)


func _plan_economy(scene: Node3D, owned: Array[MatchRegion], units: Array[MatchBattle.Unit],
		threats: Array[CpuTactics.Threat], now: float) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var base: Vector2 = battle._bases[side]
	var frontiers: Dictionary[StringName, MatchRegion] = {}
	var claims := 0
	for region in owned:
		if region.region_id not in scene._layout.starting_territories[side - MatchRegion.Owner.PLAYER]:
			claims += 1
		for id in region.neighbor_ids:
			var neighbor: MatchRegion = scene.get_region(id)
			var point := Vector2(neighbor.position.x, neighbor.position.z)
			if battle.can_see(side, point) and neighbor.region_owner == NEUTRAL and not neighbor.ruined:
				frontiers[id] = neighbor

	var sites := owned.duplicate()
	sites.sort_custom(func(a: MatchRegion, b: MatchRegion) -> bool:
		return _site(a).distance_squared_to(base) < _site(b).distance_squared_to(base))

	var catalog: Dictionary = scene.BUILDINGS
	var production := Production.new(battle, economy, side)
	var food_rate := economy.income_rate(side, FOOD)
	var food_stock := economy.stockpile(side, FOOD)
	var allies := {}
	var enemies := {}
	var army := 0
	for unit in units:
		if unit.type_id == UnitCatalog.SCOUT:
			continue
		if unit.side == NEUTRAL:
			continue
		var counts := allies if unit.side == side else enemies
		counts[unit.type_id] = counts.get(unit.type_id, 0) + 1
		if unit.side == side:
			army += 1
	for contact in battle.radar.contacts_for(side):
		if battle.can_see(side, contact.point):
			continue
		for unit_type in contact.composition:
			enemies[unit_type] = enemies.get(unit_type, 0) + contact.composition[unit_type]
	var front: CpuTactics.Threat = threats.front() if not threats.is_empty() else null
	var under_pressure := front != null and front.score > float(difficulty.threat_threshold)

	var expeditions: ScoutExpeditions = scene._expeditions
	for expedition in expeditions.assignments.values():
		if expedition.side == side:
			claims += 1
	var covered := under_pressure and CpuTactics.has_cover(scene, side, front.hub)
	var options := _military_options(scene, production, allies, enemies, front, covered, now)
	var food_producer := _producer_for(catalog, FOOD)
	if (production.active == 0 and production.total < scene.cpu_production_limit
			and _build_military(scene, options, food_producer, sites, now)):
		return

	# Protect the next few deployments before paying for anything that takes Food.
	var reserve: float = production.food_per_cycle * scene.cpu_food_buffer_cycles * difficulty.food_buffer
	if (food_rate < production.food_per_second
			and (food_stock < reserve or (now >= 65.0 and not under_pressure))
			and _want_build(scene, food_producer, sites, now)):
		return

	if now >= _next_defense and _defend(scene, threats, production.food_per_cycle, now):
		_next_defense = now + scene.cpu_defense_cooldown * difficulty.defense_delay
		return

	var opening_goal: int = mini(difficulty.opening_producers, scene.cpu_production_limit)
	if (production.active > 0 and production.total < opening_goal
			and _build_military(scene, options, food_producer, sites, now)):
		return

	var upgrade := production.upgrade_candidate
	if upgrade != null and production.active >= opening_goal and not under_pressure:
		var food: int = UnitCatalog.DEFINITIONS[upgrade.unit_type].food
		var upgraded_demand := production.food_per_second + food * (
			1.0 / upgrade.cycle_interval(economy, 2) - 1.0 / upgrade.interval(economy))
		var first_upgrade := production.upgraded == 0
		if first_upgrade and food_rate < upgraded_demand and production.active > 1 \
				and _want_build(scene, food_producer, sites, now):
			return
		if (first_upgrade or (now >= 65.0 and production.active >= scene.cpu_production_target)) \
				and food_rate >= upgraded_demand and food_stock >= MatchEconomy.UPGRADE_COST[FOOD] + production.food_per_cycle:
			if scene.try_upgrade(side, upgrade.id):
				return
			# Accumulate the upgrade's Energy before competing purchases.
			if first_upgrade and not is_inf(_save_time(economy, MatchEconomy.UPGRADE_COST)):
				return

	if _try_strategic_strike(scene, sites, units, production, under_pressure, now):
		return

	var production_goal: int = maxi(scene.cpu_production_target, owned.size() + 1)
	# Reserve an extra slot under pressure for numerical or matchup disadvantages.
	var best_gap := 0.0
	for option in options:
		best_gap = maxf(best_gap, option.counter_gap)
	if under_pressure and (front.enemies.size() > front.allies or best_gap > scene.cpu_counter_gap):
		production_goal += 1
	var can_expand_production: bool = production.total < mini(production_goal, scene.cpu_production_limit)

	var allow_claim: bool = claims < scene.cpu_expansion_limit and army > 0
	var next_cost: Dictionary = {}
	if not options.is_empty():
		next_cost = catalog[options[0].kind].cost
	var projected := {}
	for resource: StringName in [ENERGY, MATERIALS]:
		var defenses: int = Rules.PROFILES[Rules.NEST].cost[resource] + Rules.PROFILES[Rules.MORTAR].cost[resource]
		var expansion: int = expeditions.claim_price(side).get(resource, 0) if allow_claim else 0
		projected[resource] = next_cost.get(resource, 0) + maxi(defenses, expansion)

	# Invest when income is below the construction budget and savings cannot carry it.
	# Once the budget is covered, existing income (including modifiers) is enough.
	if production.active > 0 or options.is_empty():
		for resource: StringName in [MATERIALS, ENERGY]:
			var rate := economy.income_rate(side, resource)
			if rate * scene.cpu_investment_horizon * difficulty.investment_horizon < projected[resource] \
					and economy.stockpile(side, resource) < projected[resource]:
				if _want_build(scene, _producer_for(catalog, resource), sites, now, difficulty.economy_slot_reserve):
					return

	var can_feed_army := food_rate >= production.food_per_second or food_stock >= reserve
	if not under_pressure and can_feed_army and (allow_claim or army > 0) \
			and _try_expand(scene, frontiers, units, allow_claim, now):
		return

	if not under_pressure and now >= 80.0 and production.active >= 2:
		var recon := [BattleRadar.WATCHTOWER] if now < 130.0 else \
			[BattleRadar.RADAR, BattleRadar.WATCHTOWER, BattleRadar.COUNTERINTELLIGENCE]
		for kind: StringName in recon:
			var exists := false
			for structure in battle._fortifications.values():
				if structure.side == side and structure.kind == kind:
					exists = true
					break
			if not exists and _want_build(scene, kind, sites, now, 1):
				return
	if can_expand_production:
		_build_military(scene, options, food_producer, sites, now)
	if allow_claim and frontiers.is_empty() and not under_pressure:
		_reconnoiter(scene, owned, now)


func _reconnoiter(scene: Node3D, owned: Array[MatchRegion], now: float) -> void:
	if now < _next_claim:
		return
	var battle: MatchBattle = scene._battle
	if battle.visibility == null:
		return
	var intel: FactionIntelligence = scene._intelligence[side]
	for scout: ScoutExpeditions.Scout in scene._expeditions.available(side):
		var unit := battle.get_unit(scout.unit_id)
		if unit == null or not unit.waypoints.is_empty():
			continue
		var best := Vector2.INF
		var distance := INF
		for region in owned:
			for id in region.neighbor_ids:
				if intel.regions.has(id):
					continue
				var candidate := _site(scene.get_region(id))
				var length := unit.position.distance_squared_to(candidate)
				if length < distance:
					best = candidate
					distance = length
		if best.is_finite() and battle.order_move(side, unit.id, best, true):
			_next_claim = now + 3.0
			return


func _try_strategic_strike(scene: Node3D, sites: Array[MatchRegion], units: Array[MatchBattle.Unit],
		production: Production, under_pressure: bool, now: float) -> bool:
	var battle: MatchBattle = scene._battle
	var ready: MatchBattle.MissileSilo
	for structure in battle._fortifications.values():
		var silo := structure as MatchBattle.MissileSilo
		if silo == null or silo.side != side or silo.hp <= 0.0:
			continue
		match silo.missile_state:
			MatchBattle.MissileState.CHARGING:
				return false
			MatchBattle.MissileState.READY:
				if silo.active:
					ready = silo
	if ready == null:
		if now < SILO_MIN_TIME or under_pressure or production.active < 3 \
				or now < _retry_at.get(Rules.SILO, 0.0) or not scene._has_building_capacity(side, Rules.SILO):
			return false
		var reserve: Dictionary = Rules.PROFILES[Rules.SILO].cost.duplicate()
		reserve[FOOD] += production.food_per_cycle * 2
		reserve[ENERGY] += 40
		reserve[MATERIALS] += 25
		if not scene.economy.cost_block_reason(side, reserve).is_empty():
			return false
	var best := _missile_target(battle, units)
	if not best.is_finite():
		return false
	if ready != null:
		return battle.prepare_missile(side, ready.id, best)
	return _want_build(scene, Rules.SILO, sites, now)


func _missile_target(battle: MatchBattle, units: Array[MatchBattle.Unit]) -> Vector2:
	var candidates := PackedVector2Array()
	for outpost in battle._outposts.values():
		if outpost.side != side and battle.can_see(side, outpost.position):
			candidates.append(outpost.position)
	for unit in units:
		if candidates.size() >= SILO_SITE_BUDGET:
			break
		if unit.side != side and unit.side != NEUTRAL and unit.type_id != UnitCatalog.SCOUT \
				and not battle.missile_protected(unit.position):
			candidates.append(unit.position)
	for contact in battle.radar.contacts_for(side):
		if candidates.size() >= SILO_SITE_BUDGET:
			break
		if not battle.missile_protected(contact.point) and not battle.can_see(side, contact.point):
			candidates.append(contact.point)

	var best := Vector2.INF
	var best_score := SILO_MIN_VALUE
	for target in candidates:
		var score := 0.0
		for outpost in battle._outposts.values():
			if (outpost.side == side or battle.can_see(side, outpost.position)) \
					and not battle.missile_protected(outpost.position) \
					and Rules.blast_hits(target, outpost.position, MatchBattle.OUTPOST_FOOTPRINT * 2.0):
				score += -10.0 if outpost.side == side else 10.0
		for fort in battle._fortifications.values():
			if (fort.side == side or battle.can_see(side, fort.position)) and not battle.missile_protected(fort.position) \
					and Rules.blast_hits(target, fort.position, fort.profile.size, fort.angle):
				score += -6.0 if fort.side == side else 3.0
		for unit in battle.nearby_units(units, target, Rules.MISSILE_RADIUS):
			if unit.hp <= 0.0 or unit.side == NEUTRAL or unit.position.distance_squared_to(target) > Rules.MISSILE_RADIUS ** 2 \
					or not battle.can_observe_unit(side, unit) or battle.missile_protected(unit.position):
				continue
			score += -2.0 if unit.side == side else 1.0
		for contact in battle.radar.contacts_for(side):
			if contact.point.distance_squared_to(target) <= Rules.MISSILE_RADIUS ** 2 \
					and not battle.can_see(side, contact.point) and not battle.missile_protected(contact.point):
				score += contact.composition.values().reduce(func(total: int, count: int) -> int: return total + count, 0) * 0.45
		if score > best_score:
			best = target
			best_score = score
	return best


func _build_military(scene: Node3D, options: Array[Dictionary], food_producer: StringName,
		sites: Array[MatchRegion], now: float) -> bool:
	var can_feed_more := false
	for option in options:
		if option.food_ready:
			can_feed_more = true
			if _want_build(scene, option.kind, sites, now):
				return true
	return not can_feed_more and not options.is_empty() and _want_build(scene, food_producer, sites, now)


func _military_options(scene: Node3D, production: Production, allies: Dictionary,
		enemies: Dictionary, front: CpuTactics.Threat, covered: bool, now: float) -> Array[Dictionary]:
	var economy: MatchEconomy = scene.economy
	var army := 0
	for count: int in allies.values():
		army += count
	var opposition := enemies.duplicate()
	# Anticipate unit types from the military buildings visible on the map.
	if difficulty.enemy_production_weight > 0:
		for type: StringName in production.opposition:
			opposition[type] = opposition.get(type, 0) + difficulty.enemy_production_weight * production.opposition[type]
	if front != null and front.score > 0.0:
		# A force threatening a held region counts more than a force across the map.
		for type: StringName in front.composition:
			opposition[type] = opposition.get(type, 0) + difficulty.local_threat_weight * front.composition[type]
	var scores := {}
	var installed_matchup := 0.0
	var fielded_matchup := 0.0
	for kind: StringName in scene.BUILDINGS:
		var profile: Dictionary = scene.BUILDINGS[kind]
		if not profile.has("unit_type"):
			continue
		var type: StringName = profile.unit_type
		var unit: Dictionary = UnitCatalog.DEFINITIONS[type]
		var matchup := _matchup(unit, opposition, covered)
		if unit.has("support"):
			var healers: int = allies.get(type, 0)
			var supported := army - healers
			matchup = 0.3 * minf(1.0, supported / 10.0) - 0.24 * healers
		scores[kind] = matchup
		if production.active > 0:
			installed_matchup += matchup * production.counts.get(kind, 0) / production.active
		if army > 0:
			fielded_matchup += matchup * allies.get(type, 0) / army

	var existing_matchup := (installed_matchup + fielded_matchup) * 0.5 if army > 0 else installed_matchup
	var options: Array[Dictionary] = []
	var food_rate := economy.income_rate(side, FOOD)
	var food_stock := economy.stockpile(side, FOOD)
	var buffer_cycles: float = scene.cpu_food_buffer_cycles * difficulty.food_buffer
	var investment_horizon: float = scene.cpu_investment_horizon * difficulty.investment_horizon
	for kind: StringName in scores:
		if now < _retry_at.get(kind, 0.0):
			continue
		var profile: Dictionary = scene.BUILDINGS[kind]
		var unit: Dictionary = UnitCatalog.DEFINITIONS[profile.unit_type]
		var deployed: int = allies.get(profile.unit_type, 0)
		if unit.has("support") and (army < 8 or production.counts.has(kind) or deployed * 6 >= army):
			continue
		if profile.unit_type == UnitCatalog.RAIDER and (not opposition.has(UnitCatalog.INFANTRY)
				or production.counts.get(kind, 0) >= 2):
			continue
		var interval: float = economy.production_interval(side) if kind == BARRACKS else profile.interval
		var wait := _save_time(economy, profile.cost)
		if is_inf(wait):
			continue
		var food_demand: float = production.food_per_second + unit.food / interval
		# A stockpile can carry early production until a Farm comes online.
		var cycle_food: int = production.food_per_cycle + unit.food
		var cycle_reserve: float = cycle_food * buffer_cycles
		if production.active <= 1:
			cycle_reserve = maxf(cycle_food, (cycle_food - food_rate * interval) * buffer_cycles)
		var spend_stockpile := now < 65.0 or production.active <= 1
		var food_ready: bool = food_rate >= food_demand or (
			spend_stockpile and food_stock - profile.cost.get(FOOD, 0) >= cycle_reserve)
		var present_share: float = float(allies.get(profile.unit_type, 0)) / maxi(1, army)
		var installed_share: float = float(production.counts.get(kind, 0)) / maxi(1, production.active)
		var construction_cost: float = 0.0
		for resource: StringName in profile.cost:
			construction_cost += float(profile.cost[resource]) / MatchEconomy.RESOURCES[resource].starting_stock
		var score := _utility([scores[kind], -(installed_share + present_share * 0.5),
			-wait / investment_horizon, -construction_cost, -maxf(0.0, food_demand - food_rate)],
			[scene.cpu_counter_weight * difficulty.counter, scene.cpu_diversity_weight * difficulty.diversity,
				2.0, 0.35, 0.25])
		options.append({"kind": kind, "score": score, "food_ready": food_ready,
			"counter_gap": scores[kind] - existing_matchup})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.kind < b.kind if a.score == b.score else a.score > b.score)
	return options


func _save_time(economy: MatchEconomy, cost: Dictionary) -> float:
	var wait := 0.0
	for resource: StringName in cost:
		var missing: float = cost[resource] - economy.stockpile(side, resource)
		if missing > 0.0:
			var income := economy.income_rate(side, resource)
			if income <= 0.0:
				return INF
			wait = maxf(wait, missing / income)
	return wait


func _matchup(unit: Dictionary, opposition: Dictionary, covered: bool) -> float:
	var total := 0.0
	var score := 0.0
	if unit.damage <= 0.0:
		return 0.0
	for type: StringName in opposition:
		var enemy: Dictionary = UnitCatalog.DEFINITIONS[type]
		if enemy.damage <= 0.0:
			continue
		var count: float = opposition[type]
		var class_bonus := UnitCatalog.damage_multiplier(unit, enemy)
		var dps: float = unit.damage * class_bonus / unit.cooldown
		var enemy_dps: float = enemy.damage * UnitCatalog.damage_multiplier(enemy, unit) / enemy.cooldown
		# Estimate time to defeat each other, including time spent closing to weapon range.
		var reach: float = unit.range - enemy.range
		var attack_time: float = enemy.hp / dps + maxf(0.0, -reach) / unit.speed
		var survival_time: float = unit.hp / enemy_dps + maxf(0.0, reach) / enemy.speed
		var support := 0.0
		if covered and reach > 0.0:
			# A defended line buys firing time and lets longer-range units
			# attack from behind the front.
			survival_time += reach / enemy.speed
			support = reach / (unit.range + enemy.range)
		score += count * ((survival_time - attack_time) / (survival_time + attack_time)
			+ support + (class_bonus - 1.0) * 0.6)
		total += count
	return score / maxf(1.0, total)


func _producer_for(catalog: Dictionary, resource: StringName) -> StringName:
	for kind: StringName in catalog:
		var income: Dictionary = catalog[kind].get("income", {})
		if income.get(resource, 0.0) > 0.0:
			return kind
	return &""


# True means this CPU built this priority or is waiting to afford it. A failed site
# search backs off and lets other priorities run during this decision and its retries.
func _want_build(scene: Node3D, kind: StringName, regions: Array[MatchRegion], now: float,
		reserve_slots := 0) -> bool:
	if kind.is_empty() or now < _retry_at.get(kind, 0.0):
		return false
	var available: Array[MatchRegion] = regions.filter(func(region: MatchRegion) -> bool:
		if not scene.building_slot_block_reason(kind, [region.region_id]).is_empty():
			return false
		# Optional income buildings should leave space for reinforcements and defenses.
		return reserve_slots == 0 or (scene.region_occupancy(region.region_id).free
			>= scene._building_slot_cost(kind) + reserve_slots))
	if available.is_empty():
		return false
	if not scene._purchase_block_reason(side, kind).is_empty():
		return not is_inf(_save_time(scene.economy, scene._minimum_build_cost(kind)))
	var definition: Dictionary = scene.BUILDINGS[kind]
	var size: Vector2 = Rules.PROFILES.get(kind, definition).size
	var start := 0 if available.size() <= REGION_SITE_BUDGET else _rng.randi_range(0, available.size() - 1)
	for i in range(mini(available.size(), REGION_SITE_BUDGET)):
		var region := available[(start + i) % available.size()]
		var center := _site(region)
		if kind == Rules.SILO:
			if _place_large_structure(scene, kind, region, size):
				return true
			continue
		for attempt in range(difficulty.site_samples):
			var edge := _rng.randi_range(0, region.polygon.size() - 1)
			var rim := region.polygon[edge].lerp(
				region.polygon[(edge + 1) % region.polygon.size()], _rng.randf())
			var point := center.lerp(rim, _rng.randf_range(0.12, 0.94))
			var footprint := Rules.footprint(point, size)
			if not _fits_region(region, footprint):
				continue
			var world_position: Vector3 = scene._world_position(point)
			if not scene._placement_block_reason(side, kind, world_position).is_empty():
				continue
			if scene.try_place_building(side, kind, world_position):
				return true
	_retry_at[kind] = now + scene.cpu_placement_retry
	return false


func _place_large_structure(scene: Node3D, kind: StringName, region: MatchRegion, size: Vector2) -> bool:
	if region.map_bounds.size.x < size.x or region.map_bounds.size.y < size.y:
		return false
	var point := region.interior_point(func(candidate: Vector2) -> bool:
		return scene._placement_block_reason(side, kind, scene._world_position(candidate)).is_empty())
	return point.is_finite() and scene.try_place_building(side, kind, scene._world_position(point))


func _threats(scene: Node3D, owned: Array[MatchRegion], units: Array[MatchBattle.Unit]) -> Array[CpuTactics.Threat]:
	var threats: Array[CpuTactics.Threat] = []
	var battle: MatchBattle = scene._battle
	var radius: float = absf(scene.cpu_threat_radius)
	var radius_squared := radius * radius
	for region in owned:
		var hub := CpuTactics.Threat.new()
		hub.region = region
		var outpost: MatchBattle.Outpost = scene._outposts_by_region.get(region.region_id)
		var hp: float
		if outpost != null and outpost.side == side and outpost.hp > 0.0:
			hub.hub = outpost.position
			hp = outpost.hp / outpost.max_hp
		elif region.region_id == scene._layout.starting_territories[side - MatchRegion.Owner.PLAYER][0]:
			hub.hub = scene._battle._bases[side]
			hp = scene._battle.base_hp(side) / scene._battle.base_health_stat(side).total
		else:
			continue
		var nearest_distance := INF
		for unit in battle.nearby_units(units, hub.hub, radius):
			if unit.type_id == UnitCatalog.SCOUT or unit.hp <= 0.0 or not battle.can_observe_unit(side, unit):
				continue
			var distance := hub.hub.distance_squared_to(unit.position)
			if distance > radius_squared:
				continue
			if unit.side == side:
				hub.allies += 1
				continue
			hub.enemies.append(unit.position)
			hub.composition[unit.type_id] = hub.composition.get(unit.type_id, 0) + 1
			if distance < nearest_distance:
				nearest_distance = distance
				hub.nearest = unit.position
		if not hub.enemies.is_empty():
			hub.score = hub.enemies.size() + 1.0 - nearest_distance / radius_squared \
				+ (1.0 - hp) * 2.0 - hub.allies * 0.5
			threats.append(hub)
	threats.sort_custom(func(a: CpuTactics.Threat, b: CpuTactics.Threat) -> bool:
		return a.region.region_id < b.region.region_id if a.score == b.score else a.score > b.score)
	return threats


func _defend(scene: Node3D, threats: Array[CpuTactics.Threat], unit_buffer: int, now: float) -> bool:
	for threat: CpuTactics.Threat in threats.slice(0, DEFENSE_HUB_BUDGET):
		if difficulty.threat_threshold > 0.0 and threat.score <= difficulty.threat_threshold:
			break
		var counts := {}
		for placed in scene._fortifications.values():
			var fort: MatchBattle.Fortification = placed.defense
			if fort.side == side and fort.active and threat.region.region_id in placed.regions:
				counts[fort.kind] = counts.get(fort.kind, 0) + 1
		var kinds: Array[StringName] = [Rules.NEST]
		if threat.composition.get(UnitCatalog.HEAVY, 0) >= 2:
			kinds.push_front(Rules.ANTI_TANK)
		if threat.enemies.size() >= maxi(MIN_WALL_TARGETS, threat.allies) and counts.has(Rules.NEST):
			kinds.append(Rules.WALL)
		if threat.enemies.size() >= MIN_MORTAR_TARGETS:
			kinds.append(Rules.MORTAR)
		for kind in kinds:
			var key := "%s/%s" % [threat.region.region_id, kind]
			if counts.has(kind) or now < _retry_at.get(key, 0.0):
				continue
			var cost: Dictionary = Rules.wall_cost(WALL_SEGMENTS) if kind == Rules.WALL \
				else Rules.PROFILES[kind].cost
			var reserve := cost.duplicate()
			for resource in RESPONSE_RESERVE:
				reserve[resource] += RESPONSE_RESERVE[resource]
			if kind == Rules.MORTAR:
				reserve[FOOD] += unit_buffer
			if not scene.economy.cost_block_reason(side, reserve).is_empty():
				continue
			if kind == Rules.WALL:
				if _try_wall(scene, threat):
					return true
			elif _try_gun(scene, kind, threat):
				return true
			_retry_at[key] = now + scene.cpu_placement_retry
	return false


func _try_gun(scene: Node3D, kind: StringName, threat: CpuTactics.Threat) -> bool:
	var profile: Dictionary = Rules.PROFILES[kind]
	var battle: MatchBattle = scene._battle
	var forward := _approach(threat, battle._bases[battle.nearest_hostile_base(side, threat.hub)])
	var best := Vector2.INF
	var best_score := -INF
	for offset: float in [0.0, 0.48, -0.48, 0.95, -0.95, 1.57, -1.57, 2.4, -2.4, PI]:
		var direction := forward.rotated(offset)
		for distance: float in [1.35, 2.25, 3.15, 4.05]:
			var point := threat.hub + direction * distance
			if not _fits_region(threat.region, Rules.footprint(point, profile.size)):
				continue
			var score := 0.0
			var targets_checked := 0
			for enemy in threat.enemies:
				if point.distance_squared_to(enemy) > float(profile.range) ** 2:
					continue
				targets_checked += 1
				if targets_checked > GUN_TARGET_BUDGET:
					break
				if profile.splash == 0.0 and not battle.navigation.line_clear(point, enemy):
					continue
				score += 1.0 + (1.0 - point.distance_to(enemy) / profile.range) * 0.15
			if score <= 0.0:
				continue
			# Use a flank when it gives the nest similar coverage and leaves room for a barrier.
			var bias := absf(direction.cross(forward)) * 0.65 if kind == Rules.NEST \
				else -direction.dot(forward) * 0.25
			if score + bias > best_score and scene._placement_block_reason(
					side, kind, scene._world_position(point)).is_empty():
				best_score = score + bias
				best = point
	return best.is_finite() and scene.try_place_building(side, kind, scene._world_position(best))


func _try_wall(scene: Node3D, threat: CpuTactics.Threat) -> bool:
	var battle: MatchBattle = scene._battle
	var forward := _approach(threat, battle._bases[battle.nearest_hostile_base(side, threat.hub)])
	for bearing: float in [0.0, 0.35, -0.35, 0.65, -0.65]:
		var approach := forward.rotated(bearing)
		var across := approach.orthogonal()
		var half_wall := across * WALL_SEGMENTS * Rules.WALL_SEGMENT_LENGTH * 0.5
		for distance: float in [2.5, 3.0, 3.5, 4.0, 4.5, 5.0]:
			var center := threat.hub + approach * distance
			var start := center - half_wall
			var end := center + half_wall
			# Only put a barrier between the defenders and an observed approach.
			var intercepts := false
			for enemy in threat.enemies:
				if Geometry2D.segment_intersects_segment(threat.hub, enemy, start, end) != null:
					intercepts = true
					break
			if not intercepts:
				continue
			# A free perimeter keeps the wall from joining other obstacles or the map edge.
			var clearance := Rules.footprint(center,
				Vector2(half_wall.length() * 2.0, Rules.WALL_WIDTH) + WALL_BYPASS * 2.0,
				across.angle())
			if not _fits_region(threat.region, clearance) \
					or not scene._battle.fortification_site_clear(clearance):
				continue
			if scene.try_place_wall(side, scene._world_position(start), scene._world_position(end)):
				return true
	return false


func on_assignment_interrupted(owner: MatchRegion.Owner, region_id: StringName, elapsed: float) -> void:
	if owner == side:
		_claim_retry_at[region_id] = elapsed + CLAIM_INTERRUPTION_RETRY


func _try_expand(scene: Node3D, frontiers: Dictionary[StringName, MatchRegion],
		units: Array[MatchBattle.Unit], allow_new_claim: bool, now: float) -> bool:
	if frontiers.is_empty():
		return false
	var expeditions: ScoutExpeditions = scene._expeditions
	var dormant := _dormant_buildings(scene, frontiers)
	var targets: Array[MatchRegion] = []
	for region: MatchRegion in frontiers.values():
		var id := region.region_id
		if (allow_new_claim or dormant.has(id)) and not expeditions.assignments.has(id) \
				and expeditions.eligibility(side, id).is_empty():
			targets.append(region)
	if targets.is_empty():
		return false

	var scouts := expeditions.available(side)
	if now + MatchBattle.TIME_EPSILON >= _next_claim and not scouts.is_empty() \
			and _can_fund_expedition(scene, expeditions.claim_price(side)):
		var ready := targets.filter(func(region: MatchRegion) -> bool:
			return now + MatchBattle.TIME_EPSILON >= _claim_retry_at.get(region.region_id, 0.0))
		if not ready.is_empty() and _dispatch_best_claim(scene, ready, scouts, units, dormant, now):
			_next_claim = now + scene.cpu_scout_dispatch_interval * difficulty.scout_delay
			return true

	if now + MatchBattle.TIME_EPSILON >= _next_replacement \
			and _can_fund_expedition(scene, expeditions.replacement_cost):
		for index in ScoutExpeditions.CAPACITY:
			var scout: ScoutExpeditions.Scout = expeditions.slots[side][index]
			if not expeditions.replacement_block_reason(scout).is_empty():
				continue
			_next_replacement = now + scene.cpu_placement_retry
			return expeditions.replace(side, index)
	return false


func _can_fund_expedition(scene: Node3D, cost: Dictionary) -> bool:
	var budget := cost.duplicate()
	budget[ENERGY] = budget.get(ENERGY, 0) + roundi(scene.cpu_scout_energy_reserve * difficulty.scout_reserve)
	return scene.economy.cost_block_reason(side, budget).is_empty()


func _dispatch_best_claim(scene: Node3D, targets: Array[MatchRegion],
		scouts: Array[ScoutExpeditions.Scout], units: Array[MatchBattle.Unit],
		dormant: Dictionary, now: float) -> bool:
	var battle: MatchBattle = scene._battle
	var expeditions: ScoutExpeditions = scene._expeditions
	var observers: Array[MatchBattle.Unit] = []
	for scout in scouts:
		var unit := battle.get_unit(scout.unit_id)
		if unit != null:
			observers.append(unit)
	if observers.is_empty():
		return false
	var hazards := PackedVector2Array()
	for unit in units:
		if unit.side != side and unit.type_id != UnitCatalog.SCOUT:
			hazards.append(unit.position)
	for placed in scene._fortifications.values():
		var defense: MatchBattle.Fortification = placed.defense
		if defense.side != side and defense.active and defense.profile.has("range") \
				and battle.can_see(side, defense.position):
			hazards.append(defense.position)

	var choices: Array[Dictionary] = []
	for region in targets:
		var center := _site(region)
		var travel := INF
		for scout in observers:
			var speed := maxf(0.01, battle.unit_speed_stat(scout).total)
			travel = minf(travel, scout.position.distance_to(center) / speed)
		var id := region.region_id
		var value := _claim_region_value(scene, region)
		var danger := _route_danger(hazards, scene.cpu_threat_radius, center, center)
		choices.append({"id": id, "region": region, "value": value, "recovery": dormant.has(id),
			"score": value + _claim_route_value(scene, travel, danger)})
	choices.sort_custom(_prefer_claim)

	# Rank the whole frontier cheaply, then probe a fixed number of regions
	# with authoritative pathfinding. Backoff lets lower ranks surface.
	var best: Dictionary = {}
	for choice in choices.slice(0, difficulty.claim_options):
		var rank_route := _rank_claim_route.bind(scene, choice.region, hazards)
		var plan := expeditions.preview_claim(side, choice.id, rank_route)
		if plan == null:
			_claim_retry_at[choice.id] = now + scene.cpu_placement_retry
			continue
		var candidate := {"id": choice.id, "recovery": choice.recovery,
			"score": choice.value - plan.rank, "rank_route": rank_route}
		if best.is_empty() or _prefer_claim(candidate, best):
			best = candidate
	if best.is_empty():
		return false
	if scene.dispatch_scout(side, best.id, best.rank_route).is_empty():
		return true
	_claim_retry_at[best.id] = now + scene.cpu_placement_retry
	return false


func _rank_claim_route(unit: MatchBattle.Unit, plan: ScoutExpeditions.ClaimRoute, scene: Node3D,
		region: MatchRegion, hazards: PackedVector2Array) -> float:
	var previous := unit.position
	var danger := _route_danger(hazards, scene.cpu_threat_radius, plan.site, plan.site)
	for waypoint in plan.waypoints:
		danger = maxf(danger, _route_danger(hazards, scene.cpu_threat_radius, previous, waypoint))
		previous = waypoint
	if danger > scene.cpu_scout_max_danger:
		return INF
	var development: bool = difficulty.scout_production > 0.0 \
		and _room_for_production(scene, region, plan.site)
	return -(_claim_route_value(scene, plan.travel_time, danger)
		+ float(development) * scene.cpu_scout_production_weight * difficulty.scout_production)


func _claim_region_value(scene: Node3D, region: MatchRegion) -> float:
	var friendly := 0
	var openings := 0
	for id in region.neighbor_ids:
		var neighbor: MatchRegion = scene.get_region(id)
		if neighbor.region_owner == side:
			friendly += 1
		elif not scene.region_live(side, neighbor) or neighbor.region_owner == NEUTRAL:
			openings += 1
	var borders := maxi(1, region.neighbor_ids.size())
	var connections := float(friendly + openings * 0.5) / borders
	var occupancy: Dictionary = scene.region_occupancy(region.region_id)
	var free: int = occupancy.free - scene._building_slot_cost(scene.OUTPOST_KIND)
	var capacity: float = float(free) / occupancy.capacity
	# One free slot enables production. Extra slots leave room for its economy and defense.
	var development := (capacity + float(free > 0)) * 0.5
	var landmark: LegendaryLandmark = scene._landmarks.get(region.region_id)
	var bonus := 0.18 if region.specialty != RegionSpecialty.Kind.STANDARD else 0.0
	if landmark != null and scene.landmark_known(side, landmark):
		# Shorter production intervals are beneficial. Other bonuses add to their stat.
		var magnitude := -landmark.magnitude if landmark.stat == FactionStats.BARRACKS_INTERVAL \
			else landmark.magnitude
		bonus += 0.5 + 0.5 * magnitude / (1.0 + absf(magnitude))
	return _utility([connections, development, bonus],
		[scene.cpu_scout_connection_weight * difficulty.scout_connection,
			scene.cpu_scout_capacity_weight * difficulty.scout_capacity,
			scene.cpu_scout_landmark_weight * difficulty.scout_landmark])


func _claim_route_value(scene: Node3D, travel: float, danger: float) -> float:
	return _utility([-travel / (travel + scene.cpu_investment_horizon), -danger],
		[scene.cpu_scout_travel_weight * difficulty.scout_travel, scene.cpu_scout_danger_weight * difficulty.scout_danger])


func _room_for_production(scene: Node3D, region: MatchRegion, outpost_site: Vector2) -> bool:
	var occupancy: Dictionary = scene.region_occupancy(region.region_id)
	if occupancy.free <= scene._building_slot_cost(scene.OUTPOST_KIND):
		return false
	var profile: Dictionary = scene.BUILDINGS[BARRACKS]
	var extent := MatchBattle.producer_spawn_extent(profile.size, profile.unit_type)
	var outpost := Rect2(outpost_site - MatchBattle.OUTPOST_CLEARANCE, MatchBattle.OUTPOST_CLEARANCE * 2.0)
	var battle: MatchBattle = scene._battle
	for vertex in region.polygon:
		var point := _site(region).lerp(vertex, 0.65)
		var exits := Rect2(point - extent, extent * 2.0)
		if not outpost.intersects(exits) \
				and _fits_region(region, Rules.footprint(point, profile.size)) \
				and battle.producer_site_clear(point, profile):
			return true
	return false


func _route_danger(hazards: PackedVector2Array, radius: float, start: Vector2, end: Vector2) -> float:
	var nearest := radius
	for point in hazards:
		var closest := start if start == end else Geometry2D.get_closest_point_to_segment(point, start, end)
		nearest = minf(nearest, point.distance_to(closest))
	return 1.0 - nearest / radius


func _prefer_claim(a: Dictionary, b: Dictionary) -> bool:
	if a.recovery != b.recovery:
		return a.recovery
	return a.id < b.id if a.score == b.score else a.score > b.score


func _utility(terms: Array, weights: Array) -> float:
	var score := 0.0
	for index in terms.size():
		score += terms[index] * weights[index]
	return score


func _dormant_buildings(scene: Node3D, frontiers: Dictionary[StringName, MatchRegion]) -> Dictionary:
	var dormant := {}
	for placed in scene._fortifications.values():
		if placed.defense.side != side or placed.defense.active:
			continue
		for region_id in placed.regions:
			if frontiers.has(region_id):
				dormant[region_id] = true
	return dormant


func _approach(threat: CpuTactics.Threat, fallback: Vector2) -> Vector2:
	var direction := threat.hub.direction_to(threat.nearest)
	return threat.hub.direction_to(fallback) if direction.is_zero_approx() else direction


func _fits_region(region: MatchRegion, footprint: PackedVector2Array) -> bool:
	for point in footprint:
		if not Geometry2D.is_point_in_polygon(point, region.polygon):
			return false
	return true


func _site(region: MatchRegion) -> Vector2:
	return Vector2(region.position.x, region.position.z)
