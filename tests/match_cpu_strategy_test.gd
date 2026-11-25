extends SceneTree

const MatchScene := preload("res://main.tscn")
const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Pressure := preload("res://tests/capture_cpu_defense.gd")
const Rules := preload("res://match/fortification_rules.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const PRODUCERS := [&"farm", &"mine", &"generator"]

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := MatchScene.instantiate()
	scene.map_seed = 17
	root.add_child(scene)
	var first := _economy_match(scene)
	scene.restart_match()
	_check(scene._fortifications.is_empty() and scene._outposts_by_region.is_empty()
		and scene._battle.active_units().is_empty() and scene.economy.barracks_count(CPU) == 0,
		"Restart clears the CPU's deployments, construction and claims.")
	_check(first == _economy_match(scene), "Restart reproduces the seeded purchase and placement sequence.")
	_test_losses(scene)
	scene.free()

	scene = Fixture.instantiate()
	root.add_child(scene)
	_test_defense(scene)
	var defense := _snapshot(scene)
	scene.restart_match()
	_test_defense(scene)
	_check(defense == _snapshot(scene), "The same pressure produces the same walls after restart.")
	_test_defense_replacement(scene)
	_test_blocked_placement(scene)
	scene.free()
	if _failures == 0:
		print("Seeded CPU economy, construction, claims, defenses, recovery and restart passed.")
	quit(int(_failures > 0))


func _economy_match(scene: Node) -> Array:
	scene.set_process(false)
	var deployments: Array[int] = []
	var garrison: Array[MatchBattle.Unit] = []
	var deployed_types := {}
	# Hold the match open and cap the test garrison while counting every deployment.
	var battle: MatchBattle = scene._battle
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		if unit.side == CPU:
			deployments.append(unit.id)
			deployed_types[unit.type_id] = true
			unit.order = MatchBattle.Order.HOLD
			unit.ordered_destination = unit.position
			garrison.append(unit)
			if garrison.size() > 6:
				var retired: MatchBattle.Unit = garrison.pop_front()
				retired.hp = 0.0)
	scene._process(2.0)
	_check(battle.active_barracks_count(CPU) == 1 and scene.economy.energy(CPU) == 16.0,
		"The opening barracks is paid for at the shared cost.")
	var blocked_stock := _stock(scene)
	var enemy_base: Vector2 = battle._bases[PLAYER]
	_check(not scene.try_place_building(CPU, &"mine", scene._world_position(enemy_base))
		and not scene.try_place_building(CPU, Rules.MORTAR, scene._world_position(battle._bases[CPU]))
		and not scene.try_place_wall(CPU, scene._world_position(enemy_base),
			scene._world_position(enemy_base + Vector2(0, 2)))
		and _stock(scene) == blocked_stock, "Unaffordable and illegal construction leaves all stockpiles intact.")
	scene._process(70.0)
	for kind in PRODUCERS:
		var count := _structures(scene, kind).size()
		_check(count >= 1 and count <= (2 if kind == &"farm" else 1),
			"Resource demand results in enough %s without runaway duplication." % kind)
	_check(battle.active_barracks_count(CPU) >= 2 and scene.economy.has_upgrade(CPU)
		and deployments.size() >= 24, "The CPU upgrades and sustains multiple barracks under normal income.")
	_check(not scene._outposts_by_region.is_empty(), "The CPU buys an outpost on the expanded map.")
	_check(_structures(scene, Rules.NEST).is_empty() and _structures(scene, Rules.MORTAR).is_empty()
		and _structures(scene, Rules.WALL).is_empty(), "The CPU saves combat spending in an uncontested match.")
	_check(scene._outposts_by_region.size() <= scene.cpu_expansion_limit, "The expansion limit bounds claims.")
	# Larger producers need the next round of economic investment and a clear site.
	scene._process(40.0)
	_check(deployed_types.size() == MatchBattle.UnitCatalog.DEFINITIONS.size(),
		"The seeded CPU deploys every roster type through construction. Deployed %s." % [deployed_types.keys()])
	_check_ownership(scene)
	return _snapshot(scene)


func _test_losses(scene: Node) -> void:
	var mines := _structures(scene, &"mine")
	var battle: MatchBattle = scene._battle
	if mines.is_empty() or scene._outposts_by_region.is_empty():
		_check(false, "The recovery fixture requires a working mine and owned outpost.")
		return
	var mine: MatchBattle.Fortification = mines[0]
	var outpost: MatchBattle.Outpost = scene._outposts_by_region.values()[0]
	var region: MatchRegion = scene.get_region(outpost.region_id)
	var point := region.interior_point(func(site: Vector2) -> bool:
		return scene._placement_block_reason(CPU, &"generator", scene._world_position(site)).is_empty())
	scene.economy.advance(60.0)
	if not scene.try_place_building(CPU, &"generator", scene._world_position(point)):
		_check(false, "The recovery fixture needs a producer at the outpost.")
		return
	var installed: MatchBattle.Fortification = _structures(scene, &"generator").back()
	scene.cpu_expansion_limit = 0
	mine.hp = 0.0
	outpost.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(battle.get_fortification(mine.id) == null and not installed.active
		and scene.owns_region(NEUTRAL, outpost.region_id), "Loss removes income and disables the exposed producer.")
	scene._process(24.0)
	_check(installed.active and scene.owns_region(CPU, outpost.region_id),
		"The CPU prioritizes reclaiming the outpost with a dormant investment.")
	# Depleted materials should prompt mine replacement, even after an established economy.
	scene.economy.try_spend(CPU, {MatchEconomy.MATERIALS: int(scene.economy.stockpile(CPU, MatchEconomy.MATERIALS))})
	scene._process(30.0)
	_check(_structures(scene, &"mine").size() == 1 and battle.active_barracks_count(CPU) >= 2,
		"The CPU recovers from producer loss and keeps its barracks active.")


func _test_defense(scene: Node) -> void:
	var shots := Pressure.exercise(scene)
	for kind in [Rules.NEST, Rules.MORTAR]:
		_check(_structures(scene, kind).size() == 1 and shots.has(kind)
			and (shots.get(kind, []) as Array).has(true),
			"The CPU builds one %s at the threatened base and it damages enemies in profile range." % kind)
	var walls := _structures(scene, Rules.WALL)
	_check(walls.size() == 2, "The CPU responds with one two-segment barrier.")
	if walls.size() == 2:
		var battle: MatchBattle = scene._battle
		var wall: MatchBattle.Fortification = walls[0]
		var center := (wall.position + walls[1].position) * 0.5
		var normal := Vector2.from_angle(wall.angle).orthogonal()
		var start := center + normal * 0.75
		var end := center - normal * 0.75
		var nav := battle.navigation
		_check(not nav.line_clear(start, end) and not nav.path(start, end).is_empty(),
			"The CPU wall stops direct movement and leaves a navigable detour.")
		var friendly := MatchBattle.Unit.new(2000, CPU, start)
		battle._units[friendly.id] = friendly
		battle.unit_produced.emit(friendly)
		friendly.order = MatchBattle.Order.MOVE
		friendly.ordered_destination = end
		for unit in battle.active_units():
			if unit.side == PLAYER:
				unit.hp = 0.0
		scene._advance_simulation(3.0)
		_check(friendly.position.distance_to(end) < 0.1, "Friendly infantry takes the detour around the barrier.")
	_check_ownership(scene)


func _test_defense_replacement(scene: Node) -> void:
	var nests := _structures(scene, Rules.NEST)
	if nests.is_empty():
		return
	var nest: MatchBattle.Fortification = nests[0]
	nest.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(_structures(scene, Rules.NEST).is_empty(), "The destroyed nest releases its site.")
	Pressure.exercise(scene, 4)
	nests = _structures(scene, Rules.NEST)
	_check(nests.size() == 1 and nests[0].id != nest.id,
		"Continued pressure prompts one replacement after a defensive loss.")


func _test_blocked_placement(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene._battle.add_landmark_footprint(scene._layout.bounds)
	scene._process(2.0)
	var retry_at: Dictionary = scene._cpu_strategy._retry_at
	var deadline: float = retry_at.get(&"barracks", 0.0)
	_check(deadline > scene._battle.elapsed_time() and scene.economy.barracks_count(CPU) == 0
		and scene.economy.energy(CPU) == 56.0, "A blocked site search backs off without charging the CPU.")
	scene._process(2.0)
	_check(retry_at.get(&"barracks", 0.0) == deadline and scene.economy.energy(CPU) == 62.0,
		"The next decision does not repeat a failed site search.")


func _check_ownership(scene: Node) -> void:
	for placed in scene._fortifications.values():
		if placed.defense.side == CPU:
			for region_id in placed.regions:
				_check(scene.owns_region(CPU, region_id), "The CPU builds structures in owned regions only.")


func _snapshot(scene: Node) -> Array:
	var buildings := []
	for placed in scene._fortifications.values():
		var fort: MatchBattle.Fortification = placed.defense
		if fort.side == CPU:
			buildings.append([fort.kind, fort.position, fort.angle, fort.active])
	return [buildings, scene._outposts_by_region.keys(), _stock(scene)]


func _stock(scene: Node) -> Dictionary:
	var stocks := {}
	for resource in MatchEconomy.RESOURCES:
		stocks[resource] = scene.economy.stockpile(CPU, resource)
	return stocks


func _structures(scene: Node, kind: StringName) -> Array[MatchBattle.Fortification]:
	var result: Array[MatchBattle.Fortification] = []
	for placed in scene._fortifications.values():
		if placed.defense.kind == kind and placed.defense.side == CPU and placed.defense.active:
			result.append(placed.defense)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
