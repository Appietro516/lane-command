extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const Rules := preload("res://match/fortification_rules.gd")
const KINDS := {&"barracks": Catalog.INFANTRY, &"training_range": Catalog.RANGED,
	&"heavy_factory": Catalog.HEAVY}
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const FOOD := MatchEconomy.FOOD
const STEP := MatchBattle.STEP

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Fixture.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	_test_concurrent_production(scene)
	scene.restart_match()
	scene.set_process(false)
	_test_lifecycle(scene)
	scene.free()
	if _failures == 0:
		print("Military construction, automatic deployments, starvation, upgrades, territory, destruction and restart passed.")
	quit(int(_failures > 0))


func _test_concurrent_production(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var heavy_site := Vector2(10.2, -5.0)
	var before := _stock(economy, CPU)
	_check(not scene.try_place_building(CPU, &"heavy_factory", scene._world_position(heavy_site))
		and _stock(economy, CPU) == before, "An unaffordable CPU factory spends nothing.")

	economy.advance(120.0)
	var deployments := _record_deployments(battle)
	for side: MatchRegion.Owner in [PLAYER, CPU]:
		var direction := -1.0 if side == PLAYER else 1.0
		_place(scene, side, &"barracks", Vector2(direction * 13.0, -1.3))
		_place(scene, side, &"training_range", Vector2(direction * 8.5, -0.8))
		var factory := _place(scene, side, &"heavy_factory", Vector2(direction * heavy_site.x, heavy_site.y))
		if factory == null:
			return
		var enemy: MatchRegion.Owner = CPU if side == PLAYER else PLAYER
		var stock := _stock(economy, enemy)
		_check(not scene.try_place_building(enemy, factory.kind, scene._world_position(factory.position))
			and _stock(economy, enemy) == stock, "Enemy territory rejects a military purchase.")
		stock = _stock(economy, side)
		var exit := factory.position + Vector2.DOWN * (factory.spawn_extent().y + 0.1)
		_check(not scene.try_place_building(side, &"farm", scene._world_position(exit))
			and not scene.try_place_building(side, factory.kind, scene._world_position(factory.position))
			and not scene.try_place_wall(side, scene._world_position(exit - Vector2.RIGHT),
				scene._world_position(exit + Vector2.RIGHT))
			and _stock(economy, side) == stock, "The producer footprint and Heavy exit clearances are reserved.")

	battle.advance(1.0, economy)
	var duplicate := _place(scene, PLAYER, &"training_range", Vector2(-12.8, 5.55))
	if duplicate == null:
		return
	_check(scene.try_upgrade(PLAYER) and scene.try_upgrade(CPU), "Both factions can fund the Barracks upgrade.")
	var barracks_option: Button = scene._build_options[&"barracks"]
	var heavy_option: Button = scene._build_options[&"heavy_factory"]
	_check(barracks_option.text.contains("Infantry every 2.5s · 4 Food")
		and heavy_option.text.contains("55 Energy + 35 Materials\nHeavy every 6s · 8 Food"),
		"The menu displays the effective cadence, build price, unit and Food cost.")
	var food_before := {PLAYER: economy.stockpile(PLAYER, FOOD), CPU: economy.stockpile(CPU, FOOD)}
	battle.advance(1.5 - STEP, economy)
	_check(deployments.is_empty(), "Production waits for the first completed cycle.")
	battle.advance(1.0 + STEP, economy)
	_check(_types(deployments, PLAYER) == [Catalog.INFANTRY]
		and _types(deployments, CPU) == [Catalog.INFANTRY], "The upgraded Barracks deploy on the same tick.")
	battle.advance(1.0, economy)
	_check(_types(deployments, PLAYER).back() == Catalog.RANGED
		and _types(deployments, CPU).back() == Catalog.RANGED, "Ranges deploy at their unchanged 4.5s cadence.")
	battle.advance(1.0, economy)
	_check(_types(deployments, PLAYER) == [Catalog.INFANTRY, Catalog.RANGED, Catalog.INFANTRY, Catalog.RANGED]
		and _types(deployments, CPU) == [Catalog.INFANTRY, Catalog.RANGED, Catalog.INFANTRY],
		"A later Range in the same region has an independent cycle.")
	battle.advance(0.5, economy)
	_check(_types(deployments, PLAYER).back() == Catalog.HEAVY
		and _types(deployments, CPU).back() == Catalog.HEAVY, "Factories deploy at their unchanged 6s cadence.")
	battle.advance(6.0, economy)
	for side: MatchRegion.Owner in [PLAYER, CPU]:
		var spent := 0
		var types := _types(deployments, side)
		for type: StringName in types:
			spent += Catalog.DEFINITIONS[type].food
		_check(types.count(Catalog.INFANTRY) == 4 and types.count(Catalog.RANGED) >= 2
			and types.count(Catalog.HEAVY) == 2 and economy.stockpile(side, FOOD) == food_before[side] - spent,
			"All types repeat with a single Food charge per deployment.")
	_check(_types(deployments, PLAYER).count(Catalog.RANGED) == 4
		and _types(deployments, CPU).count(Catalog.RANGED) == 2, "Each Range completes its own repeated cycles.")

	var view: Node3D = scene._fortifications[duplicate.id].view
	var marking := view.get_node("Marking") as Node3D
	scene._pick_map(root.get_camera_3d().unproject_position(marking.global_position))
	_check(scene.get_node("%UnitName").text == "Player Training Range"
		and scene.get_node("%UnitIntent").text.contains("Ranged · 5 Food per unit\nCapacity  0.222222 units/s"),
		"Picking a Range opens the existing inspector with its unit and rate.")


func _test_lifecycle(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var frontier := &"region_1"
	economy.advance(100.0)
	_check(ScoutFixture.claim(scene, PLAYER, frontier), "Claim the factory region through the shared API.")
	var region: MatchRegion = scene.get_region(frontier)
	var point := region.interior_point(func(candidate: Vector2) -> bool:
		return scene._placement_block_reason(PLAYER, &"heavy_factory", scene._world_position(candidate)).is_empty())
	var factory := _place(scene, PLAYER, &"heavy_factory", point)
	if factory == null:
		return
	var deployments := _record_deployments(battle)
	var outpost: MatchBattle.Outpost = scene._outposts_by_region[frontier]
	battle.advance(2.0, economy)
	outpost.hp = 0.0
	battle.advance(8.0, economy)
	_check(not factory.active and is_equal_approx(factory.elapsed, 2.0) and deployments.is_empty(),
		"Losing the outpost preserves partial progress without producing.")
	scene._select_fortification(factory.id)
	_check(scene.get_node("%UnitIntent").text.contains("Inactive")
		and scene.get_node("%UnitIntent").text.contains("Capacity  0 units/s"), "Paused production shows zero capacity.")
	_check(ScoutFixture.claim(scene, PLAYER, frontier) and factory.active, "Reclaiming reactivates the original factory.")
	_check(economy.try_spend(PLAYER, {FOOD: int(economy.stockpile(PLAYER, FOOD))}), "Drain Food.")
	battle.advance(16.0, economy)
	_check(is_equal_approx(factory.elapsed, factory.interval(economy)) and deployments.is_empty(),
		"A starved factory holds one completed cycle without producing or banking more.")
	economy.advance(7.0)
	battle.advance(0.0, economy)
	_check(deployments.is_empty() and economy.stockpile(PLAYER, FOOD) == 7.0, "Partial Food never gets charged.")
	economy.advance(1.0)
	battle.advance(0.0, economy)
	battle.advance(0.0, economy)
	_check(_types(deployments, PLAYER) == [Catalog.HEAVY] and economy.stockpile(PLAYER, FOOD) == 0.0
		and is_zero_approx(factory.elapsed), "Exact Food releases the held cycle once.")

	var obstacle := factory.obstacle
	factory.hp = 0.0
	economy.advance(20.0)
	battle.advance(8.0, economy)
	_check(not factory.active and not battle._timers.has(factory) and not scene._fortifications.has(factory.id)
		and not battle.navigation._obstacles.has(obstacle) and deployments.size() == 1
		and economy.stockpile(PLAYER, FOOD) == 20.0, "Destruction removes the timer, view and exit reservation.")
	scene.restart_match()
	scene.set_process(false)
	_check(scene._battle._timers.is_empty() and scene._fortifications.is_empty()
		and ScoutFixture.combat_units(scene._battle).is_empty() and not scene.economy.has_upgrade(PLAYER)
		and scene.economy.stockpile(PLAYER, FOOD) == 20.0, "Restart restores starting production state.")


	var barracks := _place(scene, PLAYER, &"barracks", Vector2(-13.0, -1.3))
	if barracks == null:
		return
	_check(is_zero_approx(barracks.elapsed) and scene.economy.barracks_count(PLAYER) == 1,
		"The first Barracks after restart starts a fresh cycle.")
	barracks.hp = 1.0
	var attacker: MatchBattle.Unit = scene._battle.spawn_unit(CPU,
		barracks.position + Vector2.UP * 1.25, Catalog.RANGED)
	_check(attacker != null, "A ranged attacker starts outside the Barracks footprint.")
	scene._battle.advance(STEP, scene.economy)
	_check(scene.economy.barracks_count(PLAYER) == 0 and not scene._battle._timers.has(barracks),
		"Combat destruction removes a Barracks and updates its HUD count.")


func _place(scene: Node, side: MatchRegion.Owner, kind: StringName, point: Vector2) -> MatchBattle.ProductionTimer:
	var before := _stock(scene.economy, side)
	var world: Vector3 = scene._world_position(point)
	var reason: String = scene._placement_block_reason(side, kind, world)
	if not _check(scene.try_place_building(side, kind, world), "%s places %s at %s (%s)." % [side, kind, point, reason]):
		return null
	var timer: MatchBattle.ProductionTimer = scene._battle._timers.back()
	var cost: Dictionary = scene.BUILDINGS[kind].cost
	for resource in before:
		_check(scene.economy.stockpile(side, resource) == before[resource] - cost.get(resource, 0),
			"Construction charges the configured resource amounts.")
	_check(timer.unit_type == KINDS[kind] and timer.position.is_equal_approx(point),
		"The producer keeps its dedicated type and actual placement point.")
	return timer


func _record_deployments(battle: MatchBattle) -> Array[Dictionary]:
	var deployments: Array[Dictionary] = []
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		var producer: MatchBattle.ProductionTimer
		for timer in battle._timers:
			if timer.side == unit.side and timer.unit_type == unit.type_id and timer.active 					and Rect2(timer.position - timer.spawn_extent(), timer.spawn_extent() * 2.0).has_point(unit.position):
				producer = timer
				break
		var routes := battle.navigation.with_clearance(unit.definition.clearance)
		_check(producer != null and routes.is_passable(unit.position)
			and not routes.path(unit.position, Vector2.ZERO).is_empty(),
			"Each unit starts at a matching building exit with a route onto the map.")
		_check(deployments.is_empty() or unit.id > deployments.back().id, "Every deployment receives a unique unit ID.")
		deployments.append({"side": unit.side, "type": unit.type_id, "id": unit.id})
		unit.order = MatchBattle.Order.HOLD
		unit.ordered_destination = unit.position)
	return deployments


func _types(deployments: Array[Dictionary], side: MatchRegion.Owner) -> Array:
	return deployments.filter(func(entry: Dictionary) -> bool: return entry.side == side) 		.map(func(entry: Dictionary) -> StringName: return entry.type)


func _stock(economy: MatchEconomy, side: MatchRegion.Owner) -> Dictionary:
	var result := {}
	for resource in MatchEconomy.RESOURCES:
		result[resource] = economy.stockpile(side, resource)
	return result


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		push_error(message)
	return condition
