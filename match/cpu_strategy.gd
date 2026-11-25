extends RefCounted
## One construction, claim, or upgrade per decision. All mutations go through match APIs.

const Rules := preload("res://match/fortification_rules.gd")
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS
const FOOD := MatchEconomy.FOOD
const BARRACKS := &"barracks"
const RESPONSE_RESERVE := {ENERGY: 10, MATERIALS: 6}
const REGION_SITE_BUDGET := 5
const SAMPLES_PER_REGION := 14
const WALL_SEGMENTS := 2
const WALL_BYPASS := Vector2(0.45, 0.18)
const FOOD_BUFFER_CYCLES := 3.0
const MIN_MORTAR_TARGETS := 2
const MIN_WALL_TARGETS := 2
const CLAIM_COOLDOWN := 12.0


class Threat:
	var region: MatchRegion
	var hub: Vector2
	var enemies := PackedVector2Array()
	var nearest := Vector2.INF
	var score := 0.0
	var allies := 0


var _rng := RandomNumberGenerator.new()
var _retry_at := {}
var _next_defense := 0.0
var _next_claim := 0.0


func _init(map_seed: int) -> void:
	_rng.seed = map_seed ^ 46


func decide(scene: Node3D) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var now := battle.elapsed_time()
	var owned: Array[MatchRegion] = []
	var frontiers: Dictionary[StringName, MatchRegion] = {}
	var base: Vector2 = battle._bases[CPU]
	var enemy_base: Vector2 = battle._bases[MatchRegion.Owner.PLAYER]
	for region: MatchRegion in scene._regions_by_id.values():
		if region.region_owner != CPU:
			continue
		owned.append(region)
		for id in region.neighbor_ids:
			var neighbor: MatchRegion = scene.get_region(id)
			if neighbor.region_owner == NEUTRAL:
				frontiers[id] = neighbor

	var units := battle.active_units()
	var threats := _threats(scene, owned, units)
	var sites := owned.duplicate()
	sites.sort_custom(func(a: MatchRegion, b: MatchRegion) -> bool:
		return _site(a).distance_squared_to(base) < _site(b).distance_squared_to(base))

	var catalog: Dictionary = scene.BUILDINGS
	var unit_food := int(MatchEconomy.UNIT_COST[FOOD])
	var interval := economy.production_interval(CPU)
	var food_rate := economy.income_rate(CPU, FOOD)
	var food_stock := economy.stockpile(CPU, FOOD)
	var upgrade := not economy.has_upgrade(CPU)
	var upgrade_interval := interval + MatchEconomy.UPGRADED_PRODUCTION_INTERVAL \
		- MatchEconomy.PRODUCTION_INTERVAL if upgrade else interval
	upgrade_interval = maxf(upgrade_interval, FactionStats.STAT_DEFINITIONS[FactionStats.BARRACKS_INTERVAL].minimum)
	var active := 0
	var barracks := 0
	var unit_buffer := 0
	var demand := 0.0
	var production_demand := 0.0
	var composition := {}
	for timer in battle._timers:
		if timer.side != CPU or not timer.active:
			continue
		active += 1
		if timer.kind == BARRACKS:
			barracks += 1
		composition[timer.kind] = true
		var food: int = MatchBattle.UnitCatalog.DEFINITIONS[timer.unit_type].food
		unit_buffer += food
		var cycle := timer.interval(economy)
		demand += food / cycle
		production_demand += food / (upgrade_interval if timer.kind == BARRACKS else cycle)
	var next_kind := BARRACKS
	if barracks >= 2:
		for kind: StringName in catalog:
			if catalog[kind].has("unit_type") and not composition.has(kind):
				next_kind = kind
				break
	var next_profile: Dictionary = catalog[next_kind]
	var next_food: int = MatchBattle.UnitCatalog.DEFINITIONS[next_profile.unit_type].food
	var next_interval: float = upgrade_interval if next_kind == BARRACKS else next_profile.interval
	var next_demand := production_demand + next_food / next_interval
	var army := 0
	for unit in units:
		if unit.side == CPU:
			army += 1
	var production_goal := maxi(4, owned.size() + 1)
	if not threats.is_empty() and threats[0].enemies.size() > army:
		production_goal = production_goal + 1

	# With no production, save for the first barracks before discretionary purchases.
	if active == 0 and _want_build(scene, BARRACKS, sites, now):
		return

	var claims: int = owned.size() - scene._layout.cpu_start_ids.size()
	var dormant := _dormant_buildings(scene, frontiers)
	var claim_targets := _claim_targets(scene, frontiers, units, base, enemy_base, dormant)
	# Recover dormant investments even if the ordinary expansion budget has been reached.
	if now >= _next_claim:
		for region in claim_targets:
			if not dormant.has(region.region_id):
				break
			if _want_claim(scene, region.region_id, now):
				return

	# Protect the next few deployments before paying for anything that takes Food.
	var producer := _producer_for(catalog, FOOD)
	var food_short := food_rate < demand and food_stock < unit_buffer * FOOD_BUFFER_CYCLES
	if food_short and _want_build(scene, producer, sites, now):
		return

	if now >= _next_defense and _defend(scene, threats, unit_buffer, now):
		_next_defense = now + scene.cpu_defense_cooldown
		return

	# Use opening reserves for a second barracks when there is time to add recurring income.
	var early_buffer := maxf(0.0, unit_food * 2 - food_rate * interval) * FOOD_BUFFER_CYCLES
	if active == 1 and barracks == 1 and (food_rate >= next_demand or food_stock >= early_buffer) \
			and _want_build(scene, BARRACKS, sites, now):
		return

	if food_rate < production_demand and _want_build(scene, producer, sites, now):
		return
	if upgrade and barracks > 0 and food_rate >= production_demand \
			and food_stock >= MatchEconomy.UPGRADE_COST[FOOD] + unit_buffer:
		if scene.try_upgrade(CPU):
			return
		# Accumulate the upgrade's Energy before competing purchases.
		if not economy.cost_block_reason(CPU, MatchEconomy.UPGRADE_COST).is_empty():
			return

	var allow_claim: bool = claims < scene.cpu_expansion_limit and (army > 0 or active == 0)
	var projected: Dictionary = next_profile.cost.duplicate()
	for resource: StringName in [ENERGY, MATERIALS]:
		var defenses: int = Rules.PROFILES[Rules.NEST].cost[resource] + Rules.PROFILES[Rules.MORTAR].cost[resource]
		var expansion: int = MatchEconomy.CLAIM_COST.get(resource, 0) if allow_claim else 0
		projected[resource] += maxi(defenses, expansion)

	# Invest when income is below the construction budget and savings cannot carry it.
	# Once the budget is covered, existing income (including modifiers) is enough.
	if active > 0:
		for resource: StringName in [MATERIALS, ENERGY]:
			var rate := economy.income_rate(CPU, resource)
			if rate * scene.cpu_investment_horizon < projected[resource] \
					and economy.stockpile(CPU, resource) < projected[resource]:
				if _want_build(scene, _producer_for(catalog, resource), sites, now):
					return

	var under_pressure := not threats.is_empty() and threats[0].score > 0.0
	if allow_claim and now >= _next_claim and (not under_pressure or active == 0):
		for region in claim_targets:
			if _want_claim(scene, region.region_id, now):
				return

	if active < production_goal:
		if food_rate >= next_demand:
			_want_build(scene, next_kind, sites, now)
		elif food_stock < (unit_buffer + next_food) * FOOD_BUFFER_CYCLES \
				or scene._purchase_block_reason(CPU, next_kind).is_empty():
			_want_build(scene, producer, sites, now)


func _producer_for(catalog: Dictionary, resource: StringName) -> StringName:
	for kind: StringName in catalog:
		var income: Dictionary = catalog[kind].get("income", {})
		if income.get(resource, 0.0) > 0.0:
			return kind
	return &""


# True means the CPU built this priority or is waiting to afford it. A failed site
# search backs off and lets other priorities run during this decision and its retries.
func _want_build(scene: Node3D, kind: StringName, regions: Array[MatchRegion], now: float) -> bool:
	if kind.is_empty() or now < _retry_at.get(kind, 0.0):
		return false
	if not scene._purchase_block_reason(CPU, kind).is_empty():
		return true
	var definition: Dictionary = scene.BUILDINGS[kind]
	var size: Vector2 = Rules.PROFILES.get(kind, definition).size
	var start := 0 if regions.size() <= REGION_SITE_BUDGET else _rng.randi_range(0, regions.size() - 1)
	for i in range(mini(regions.size(), REGION_SITE_BUDGET)):
		var region := regions[(start + i) % regions.size()]
		var center := _site(region)
		for attempt in range(SAMPLES_PER_REGION):
			var edge := _rng.randi_range(0, region.polygon.size() - 1)
			var rim := region.polygon[edge].lerp(
				region.polygon[(edge + 1) % region.polygon.size()], _rng.randf())
			var point := center.lerp(rim, _rng.randf_range(0.12, 0.94))
			var footprint := Rules.footprint(point, size)
			if not _fits_region(region, footprint) or not scene._battle.fortification_site_clear(footprint):
				continue
			if scene.try_place_building(CPU, kind, scene._world_position(point)):
				return true
	_retry_at[kind] = now + scene.cpu_placement_retry
	return false


func _threats(scene: Node3D, owned: Array[MatchRegion], units: Array[MatchBattle.Unit]) -> Array[Threat]:
	var threats: Array[Threat] = []
	var radius_squared: float = scene.cpu_threat_radius ** 2
	for region in owned:
		var hub := Threat.new()
		hub.region = region
		var outpost: MatchBattle.Outpost = scene._outposts_by_region.get(region.region_id)
		var hp: float
		if outpost != null:
			hub.hub = outpost.position
			hp = outpost.hp / outpost.max_hp
		elif region.region_id == TerritoryLayout.CPU_START:
			hub.hub = scene._battle._bases[CPU]
			hp = scene._battle.base_hp(CPU) / scene._battle.base_health_stat(CPU).total
		else:
			continue
		var nearest_distance := INF
		for unit in units:
			var distance := hub.hub.distance_squared_to(unit.position)
			if distance > radius_squared:
				continue
			if unit.side == CPU:
				hub.allies += 1
				continue
			hub.enemies.append(unit.position)
			if distance < nearest_distance:
				nearest_distance = distance
				hub.nearest = unit.position
		if not hub.enemies.is_empty():
			hub.score = hub.enemies.size() + 1.0 - nearest_distance / radius_squared \
				+ (1.0 - hp) * 2.0 - hub.allies * 0.5
			threats.append(hub)
	threats.sort_custom(func(a: Threat, b: Threat) -> bool: return a.score > b.score)
	return threats


func _defend(scene: Node3D, threats: Array[Threat], unit_buffer: int, now: float) -> bool:
	for threat: Threat in threats:
		var counts := {}
		for placed in scene._fortifications.values():
			var fort: MatchBattle.Fortification = placed.defense
			if fort.side == CPU and fort.active and threat.region.region_id in placed.regions:
				counts[fort.kind] = counts.get(fort.kind, 0) + 1
		var kinds: Array[StringName] = [Rules.NEST]
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
			if not scene.economy.cost_block_reason(CPU, reserve).is_empty():
				continue
			if kind == Rules.WALL:
				if _try_wall(scene, threat):
					return true
			elif _try_gun(scene, kind, threat):
				return true
			_retry_at[key] = now + scene.cpu_placement_retry
	return false


func _try_gun(scene: Node3D, kind: StringName, threat: Threat) -> bool:
	var profile: Dictionary = Rules.PROFILES[kind]
	var forward := _approach(threat, scene._battle._bases[MatchRegion.Owner.PLAYER])
	var best := Vector2.INF
	var best_score := -INF
	for offset: float in [0.0, 0.48, -0.48, 0.95, -0.95, 1.57, -1.57, 2.4, -2.4, PI]:
		var direction := forward.rotated(offset)
		for distance: float in [1.35, 2.25, 3.15, 4.05]:
			var point := threat.hub + direction * distance
			if not _fits_region(threat.region, Rules.footprint(point, profile.size)):
				continue
			var score := 0.0
			for enemy in threat.enemies:
				if point.distance_squared_to(enemy) > float(profile.range) ** 2:
					continue
				if kind == Rules.NEST and not scene._battle.navigation.line_clear(point, enemy):
					continue
				score += 1.0 + (1.0 - point.distance_to(enemy) / profile.range) * 0.15
			if score <= 0.0:
				continue
			# Use a flank when it gives the nest similar coverage and leaves room for a barrier.
			var bias := absf(direction.cross(forward)) * 0.65 if kind == Rules.NEST \
				else -direction.dot(forward) * 0.25
			if score + bias > best_score and scene._placement_block_reason(
					CPU, kind, scene._world_position(point)).is_empty():
				best_score = score + bias
				best = point
	return best.is_finite() and scene.try_place_building(CPU, kind, scene._world_position(best))


func _try_wall(scene: Node3D, threat: Threat) -> bool:
	var forward := _approach(threat, scene._battle._bases[MatchRegion.Owner.PLAYER])
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
			if scene.try_place_wall(CPU, scene._world_position(start), scene._world_position(end)):
				return true
	return false


func _claim_targets(scene: Node3D, frontiers: Dictionary[StringName, MatchRegion],
		units: Array[MatchBattle.Unit], base: Vector2, enemy_base: Vector2,
		dormant: Dictionary) -> Array[MatchRegion]:
	var targets: Array[MatchRegion] = []
	var scores := {}
	for region in frontiers.values():
		var site := _site(region)
		var distance := base.distance_to(site)
		for unit in units:
			if unit.side == CPU:
				distance = minf(distance, unit.position.distance_to(site))
		scores[region.region_id] = (5.0 if scene._landmarks.has(region.region_id) else 0.0) \
			- distance - enemy_base.distance_to(site) * 0.15
		targets.append(region)
	targets.sort_custom(func(a: MatchRegion, b: MatchRegion) -> bool:
		if dormant.has(a.region_id) != dormant.has(b.region_id):
			return dormant.has(a.region_id)
		return scores[a.region_id] > scores[b.region_id])
	return targets


func _dormant_buildings(scene: Node3D, frontiers: Dictionary[StringName, MatchRegion]) -> Dictionary:
	var dormant := {}
	for placed in scene._fortifications.values():
		if placed.defense.side != CPU or placed.defense.active:
			continue
		for region_id in placed.regions:
			if frontiers.has(region_id):
				dormant[region_id] = true
	return dormant

func _want_claim(scene: Node3D, region_id: StringName, now: float) -> bool:
	var key := "claim/%s" % region_id
	if now < _retry_at.get(key, 0.0):
		return false
	if not scene.economy.cost_block_reason(CPU, MatchEconomy.CLAIM_COST).is_empty():
		return true
	if scene.try_claim(CPU, region_id):
		_next_claim = now + CLAIM_COOLDOWN
		return true
	_retry_at[key] = now + scene.cpu_placement_retry
	return false


func _approach(threat: Threat, fallback: Vector2) -> Vector2:
	var direction := threat.hub.direction_to(threat.nearest)
	return threat.hub.direction_to(fallback) if direction.is_zero_approx() else direction


func _fits_region(region: MatchRegion, footprint: PackedVector2Array) -> bool:
	for point in footprint:
		if not Geometry2D.is_point_in_polygon(point, region.polygon):
			return false
	return true


func _site(region: MatchRegion) -> Vector2:
	return Vector2(region.position.x, region.position.z)
