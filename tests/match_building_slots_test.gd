extends SceneTree

const MATCH := preload("res://main.tscn")
const ScoutFixture := preload("res://tests/scout_fixture.gd")
const Rules := preload("res://match/fortification_rules.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const PLAYER_START := TerritoryLayout.PLAYER_START
const CPU_START := TerritoryLayout.CPU_START
const FARM := &"farm"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_walls()
	_test_spanning_structures()
	_test_claim_and_inactive_structures()
	_test_seeded_capacity()
	if failures == 0:
		print("Regional building slots, shared purchases, walls, claims and restart passed.")
	quit(int(failures > 0))


func _match(landmarks := 0, capacity := 5, player_starts := 1) -> Node:
	var scene := MATCH.instantiate()
	scene.region_count = 6
	scene.neutral_objectives_enabled = false
	scene.legendary_count = landmarks
	scene.region_building_capacity = capacity
	scene.player_start_count = player_starts
	scene.claim_duration = 0.1
	scene.narrative_catalog = null
	root.add_child(scene)
	scene.set_process(false)
	scene.economy.advance(300.0)
	return scene


func _test_catalog_and_walls() -> void:
	var scene := _match()
	var player_types: Array[StringName] = [&"barracks", &"training_range", &"heavy_factory", &"generator"]
	var cpu_types: Array[StringName] = [&"mine", FARM, Rules.NEST, Rules.MORTAR]
	for kind in player_types:
		_build(scene, PLAYER, PLAYER_START, kind)
	for kind in cpu_types:
		_build(scene, CPU, CPU_START, kind)
	for region_id: StringName in [PLAYER_START, CPU_START]:
		var occupancy: Dictionary = scene.region_occupancy(region_id)
		_check(occupancy.used == 5 and occupancy.free == 0 and occupancy.by_kind.get(&"base") == 1,
			"Both sides fill exactly five slots including their base.")
		for kind: StringName in player_types if region_id == PLAYER_START else cpu_types:
			_check(occupancy.by_kind.get(kind) == 1, "%s consumes exactly one slot." % kind)

	scene._select_region(PLAYER_START)
	scene._refresh_hud()
	var slots := scene.get_node("%RegionSlots") as Label
	var farm: Button = scene._build_options[FARM]
	var wall: Button = scene._build_options[Rules.WALL]
	_check(slots.text.contains("5/5") and slots.text.contains("Full")
		and slots.tooltip_text.contains("Heavy Factory") and slots.tooltip_text.contains("Region full")
		and farm.disabled and farm.tooltip_text.contains("full") and not wall.disabled,
		"HUD shows regional counts and explains the disabled catalog, while the wall stays available.")
	var clear_point := _site(scene, PLAYER_START, FARM)
	var before := _stock(scene, PLAYER)
	_check(clear_point.is_finite() and not scene.try_place_building(PLAYER, FARM, scene._world_position(clear_point))
		and _stock(scene, PLAYER) == before, "A clear sixth purchase fails without spending.")
	var cpu_point := _site(scene, CPU_START, FARM)
	before = _stock(scene, CPU)
	var cpu_region: Array[MatchRegion] = [scene.get_region(CPU_START)]
	_check(cpu_point.is_finite() and not scene.try_place_building(CPU, FARM, scene._world_position(cpu_point))
		and not scene._cpu_strategy._want_build(scene, FARM, cpu_region, 0.0)
		and _stock(scene, CPU) == before, "The shared transaction and CPU site search both honor capacity.")

	var drag := _long_wall(scene, PLAYER, PLAYER_START)
	if drag.size() == 2:
		var start: Vector3 = scene._world_position(drag[0])
		var end: Vector3 = scene._world_position(drag[1])
		var plan: Dictionary = scene._wall_plan(PLAYER, drag[0], drag[1])
		var materials := int(_stock(scene, PLAYER).y)
		scene.economy.try_spend(PLAYER, {MatchEconomy.MATERIALS: materials})
		before = _stock(scene, PLAYER)
		_check(not scene.try_place_wall(PLAYER, start, end) and _stock(scene, PLAYER) == before
			and scene._fortifications.size() == 8, "An unaffordable multi-segment drag is atomic.")
		scene.economy.grant_resource(PLAYER, MatchEconomy.MATERIALS, materials)
		before = _stock(scene, PLAYER)
		_check(scene.try_place_wall(PLAYER, start, end), "A long wall can be built in a full region.")
		var cost := Vector3(plan.cost[MatchEconomy.ENERGY], plan.cost[MatchEconomy.MATERIALS], 0)
		var occupied: Dictionary = scene.region_occupancy(PLAYER_START)
		_check(occupied.used == 5 and occupied.by_kind.get(Rules.WALL) == 8
			and _stock(scene, PLAYER) == before - cost and slots.tooltip_text.contains("Wall segments (0 slots) × 8"),
			"Eight wall segments charge the full price and use zero slots.")
		# The first two segments fit. The remaining segments run into the existing wall.
		var extension := drag[0] - drag[0].direction_to(drag[1]) * 2.0
		var collision: Dictionary = scene._wall_plan(PLAYER, extension, drag[1])
		before = _stock(scene, PLAYER)
		_check(collision.segments.size() == 2 and not collision.reason.is_empty()
			and not scene.try_place_wall(PLAYER, scene._world_position(extension), end)
			and _stock(scene, PLAYER) == before and scene._fortifications.size() == 16,
			"A collision after a valid prefix leaves zero partial wall segments.")
	else:
		_check(false, "The seeded fixture has a clear long wall lane.")

	var first: MatchBattle.Fortification = scene._fortifications.values()[0].defense
	first.hp = 0
	scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.region_occupancy(PLAYER_START).free == 1, "Destroying a Barracks immediately frees its slot.")
	_build(scene, PLAYER, PLAYER_START, FARM)
	_check(scene.region_occupancy(PLAYER_START).used == 5, "The freed slot can be purchased again.")
	scene.restart_match()
	_check(scene.region_occupancy(PLAYER_START).used == 1 and scene.region_occupancy(CPU_START).used == 1
		and not scene.region_occupancy(PLAYER_START).by_kind.has(Rules.WALL),
		"Restart clears purchases and walls and restores the two base reservations.")
	scene._battle._base_health[CPU].hp = 0
	scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.region_occupancy(CPU_START).used == 0 and scene.region_occupancy(PLAYER_START).used == 1,
		"Destroying a base releases only that base's slot.")
	scene.free()


func _test_spanning_structures() -> void:
	var scene := _match(0, 5, 2)
	var neighbor := &"region_1"
	var a := _center(scene, PLAYER_START)
	var b := _center(scene, neighbor)
	var middle := a.lerp(b, 0.5)
	var axis := a.direction_to(b)
	var cross := middle - axis * 0.2 + axis.orthogonal() * 3.0
	for i in range(5):
		_build(scene, PLAYER, neighbor, FARM, cross)
	var start_before: Dictionary = scene.region_occupancy(PLAYER_START)
	var before := _stock(scene, PLAYER)
	var cross_world: Vector3 = scene._world_position(cross)
	var reason: String = scene._placement_block_reason(PLAYER, FARM, cross_world)
	_check(reason.contains("Region 1") and reason.contains("5/5")
		and not scene.try_place_building(PLAYER, FARM, cross_world) and _stock(scene, PLAYER) == before,
		"A footprint touching a second full region rejects at preview and purchase.")
	var last: MatchBattle.Fortification = scene._fortifications.values().back().defense
	last.hp = 0
	scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.try_place_building(PLAYER, FARM, cross_world)
		and scene.region_occupancy(PLAYER_START).used == start_before.used + 1
		and scene.region_occupancy(neighbor).used == 5,
		"A single farm spanning an owned edge uses one slot in each covered region.")
	var farm: MatchBattle.Fortification = scene._fortifications.values().back().defense
	var drag_center := cross + axis.orthogonal() * 1.8
	var drag_start := drag_center - axis * 3.1
	var drag_end := drag_center + axis * 3.1
	var before_wall: Dictionary = scene.region_occupancy(PLAYER_START)
	_check(scene.try_place_wall(PLAYER, scene._world_position(drag_start), scene._world_position(drag_end))
		and scene.region_occupancy(PLAYER_START).used == before_wall.used
		and scene.region_occupancy(neighbor).used == 5
		and scene.region_occupancy(PLAYER_START).by_kind.get(Rules.WALL, 0) > 0
		and scene.region_occupancy(neighbor).by_kind.get(Rules.WALL, 0) > 0,
		"A wall crossing an owned edge uses zero slots in both regions.")
	farm.hp = 0
	scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.region_occupancy(PLAYER_START).used == start_before.used
		and scene.region_occupancy(neighbor).used == 4, "Destruction releases both slots of a spanning building.")
	scene.free()


func _test_claim_and_inactive_structures() -> void:
	var scene := _match(6)
	var start: MatchRegion = scene.get_region(PLAYER_START)
	var target: StringName = &""
	for region_id in start.neighbor_ids:
		if scene._landmarks.has(region_id):
			target = region_id
			break
	if target.is_empty():
		_check(false, "The seeded fixture has a nearby Legendary.")
		scene.free()
		return
	var occupancy: Dictionary = scene.region_occupancy(target)
	_check(occupancy.used == 1 and occupancy.inactive.get(&"legendary") == 1,
		"A neutral Legendary is inactive and occupies a slot.")
	_check(ScoutFixture.claim(scene, PLAYER, target), "Claiming a Legendary region succeeds.")
	occupancy = scene.region_occupancy(target)
	_check(occupancy.used == 2 and occupancy.by_kind.get(&"outpost") == 1 and occupancy.inactive.is_empty(),
		"The outpost and activated Legendary each use one slot.")
	for i in range(3):
		_build(scene, PLAYER, target, FARM)
	var outpost: MatchBattle.Outpost = scene._outposts_by_region.get(target)
	if outpost != null:
		outpost.hp = 0
		scene._battle.advance(MatchBattle.STEP, scene.economy)
	occupancy = scene.region_occupancy(target)
	scene._select_region(target)
	var point: Vector2 = scene._map_position(scene.get_region(target).global_position)
	scene._battle.visibility.set_source(-800003, PLAYER, point, BattleVisibility.UNIT_RADIUS)
	scene._refresh_intelligence()
	scene._refresh_hud()
	var slots := scene.get_node("%RegionSlots") as Label
	_check(scene.owns_region(NEUTRAL, target) and occupancy.used == 4 and occupancy.free == 1
		and occupancy.inactive.get(FARM) == 3 and slots.tooltip_text.contains("Farm × 3 (3 inactive)"),
		"Losing an outpost frees its slot immediately and retains all inactive farms.")
	_check(scene.building_slot_block_reason(FARM, [target]).contains("outpost"),
		"The last neutral slot is reserved against other construction across the border.")
	_check(ScoutFixture.claim(scene, PLAYER, target) and scene.region_occupancy(target).used == 5
		and scene.region_occupancy(target).inactive.is_empty(),
		"Reclaim uses the reserved slot and reactivates the same structures.")
	scene.restart_match()
	_check(scene.region_occupancy(target).used == 1
		and scene.region_occupancy(target).by_kind.get(&"legendary") == 1,
		"Restart preserves the seeded Legendary without carrying over an outpost or captured structures.")
	scene.free()


func _test_seeded_capacity() -> void:
	var scene := _match(6, 1)
	_check(scene._landmarks.is_empty() and scene.region_occupancy(PLAYER_START).used == 1,
		"Default-neutral landmarks yield to an obligatory outpost at a configured capacity of one.")
	var start: MatchRegion = scene.get_region(PLAYER_START)
	var target: StringName = start.neighbor_ids[0]
	_check(ScoutFixture.claim(scene, PLAYER, target) and scene.region_occupancy(target).used == 1,
		"The reserved neutral slot supports a claim at minimum capacity.")
	scene.free()

	scene = _match(0, 6)
	for i in range(5):
		_build(scene, PLAYER, PLAYER_START, FARM)
	scene.region_building_capacity = 5
	var occupancy: Dictionary = scene.region_occupancy(PLAYER_START)
	_check(occupancy.used == 6 and occupancy.free == 0 and occupancy.by_kind.get(FARM) == 5
		and not scene.building_slot_block_reason(FARM, [PLAYER_START]).is_empty(),
		"Over-capacity configurations retain every structure and block new construction.")
	scene.free()


func _build(scene: Node, side: MatchRegion.Owner, region_id: StringName, kind: StringName,
		avoid := Vector2.INF) -> void:
	var point := _site(scene, region_id, kind, avoid)
	_check(point.is_finite() and scene.try_place_building(side, kind, scene._world_position(point)),
		"The fixture places %s in %s." % [kind, region_id])


func _site(scene: Node, region_id: StringName, kind: StringName, avoid := Vector2.INF) -> Vector2:
	var region: MatchRegion = scene.get_region(region_id)
	var profile: Dictionary = Rules.PROFILES.get(kind, scene.BUILDINGS[kind])
	return region.interior_point(func(p: Vector2) -> bool:
		if p.distance_to(avoid) < 2.8:
			return false
		var footprint := Rules.footprint(p, profile.size)
		for corner in footprint:
			if not Geometry2D.is_point_in_polygon(corner, region.polygon):
				return false
		if profile.has("unit_type"):
			return scene._battle.producer_site_clear(p, profile)
		return scene._battle.fortification_site_clear(footprint))


func _long_wall(scene: Node, side: MatchRegion.Owner, region_id: StringName) -> PackedVector2Array:
	var start := _center(scene, region_id)
	for y in range(-18, 19):
		for x in range(-18, 19):
			var point := start + Vector2(x, y) * 0.5
			for direction in [Vector2.RIGHT, Vector2.DOWN]:
				var end: Vector2 = point + direction * 8.0
				var plan: Dictionary = scene._wall_plan(side, point - direction * 2.0, end)
				if plan.reason.is_empty() and plan.segments[0].regions == [region_id]:
					return PackedVector2Array([point, end])
	return PackedVector2Array()


func _center(scene: Node, region_id: StringName) -> Vector2:
	var region: MatchRegion = scene.get_region(region_id)
	return region.interior_point()


func _stock(scene: Node, side: MatchRegion.Owner) -> Vector3:
	var economy: MatchEconomy = scene.economy
	return Vector3(economy.energy(side), economy.stockpile(side, MatchEconomy.MATERIALS),
		economy.stockpile(side, MatchEconomy.FOOD))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
