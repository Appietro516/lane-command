extends SceneTree

const MatchScene := preload("res://main.tscn")
const Profiles := preload("res://match/difficulty_profile.gd")
const Prototype := preload("res://tests/prototype_match_fixture.gd")
const ScoutFixture := preload("res://tests/scout_fixture.gd")
const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS
const FOOD := MatchEconomy.FOOD

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_difficulty_and_reset()
	_test_decisions()
	_test_route_budget()
	if _failures == 0:
		print("CPU difficulty profiles, reset, shared rules, strategy and route budgets passed.")
	quit(int(_failures > 0))


func _test_difficulty_and_reset() -> void:
	var scene := MatchScene.instantiate()
	scene.region_count = 7
	scene.legendary_count = 0
	root.add_child(scene)

	var initial_event: StringName
	for level in range(1, 6):
		scene.cpu_difficulty = level
		scene.restart_match()
		scene.set_process(false)
		var profile := Profiles.get_profile(level)
		_check(scene._cpu_strategy.difficulty == profile
			and scene.get_node("%ActiveDifficulty").text == "CPU " + Profiles.display_name(level),
			"The CPU uses and displays the selected difficulty.")
		var expected_period: float = scene.cpu_decision_interval * profile.cadence
		_check(is_equal_approx(scene._time_until_cpu_decision, expected_period), "Restart resets decision cadence.")
		_check_starting_rules(scene)
		scene._process(expected_period - 0.25)
		_check(scene._battle._timers.is_empty(), "The CPU waits for its first scheduled decision.")
		var budget: Dictionary = _stock(scene, CPU)
		scene._process(0.25)
		_check(scene._battle._timers.size() == 1, "The CPU opens with paid military production at each level.")
		for resource in MatchEconomy.RESOURCES:
			var expected: float = budget[resource] + MatchEconomy.RESOURCES[resource].baseline * 0.25 				- MatchEconomy.BARRACKS_COST.get(resource, 0)
			_check(is_equal_approx(scene.economy.stockpile(CPU, resource), expected), "The opening pays shared prices.")

		var region: StringName = scene.get_region(TerritoryLayout.CPU_START).neighbor_ids[0]
		scene.economy.advance(40.0)
		_check(ScoutFixture.claim(scene, CPU, region), "CPU can complete a paid scout claim at every level.")
		var event_id := StringName("claim/%d/%s" % [CPU, region])
		var event: Dictionary = scene.narrative_events.instance(event_id)
		_check(event.has("event_id"), "The completed claim generates a normal discovery.")
		if level == 1:
			initial_event = event.get("event_id", &"")
		else:
			_check(initial_event == event.get("event_id", &""), "The same seeded claim draws the same event.")
		scene._cpu_strategy._claim_retry_at[region] = 99.0
		var old_strategy: RefCounted = scene._cpu_strategy
		var old_economy: MatchEconomy = scene.economy
		var old_battle: MatchBattle = scene._battle
		var old_events: NarrativeEvents = scene.narrative_events
		scene.get_node("%Restart").pressed.emit()
		_check(scene.cpu_difficulty == level and scene._cpu_strategy != old_strategy
			and scene.economy != old_economy and scene._battle != old_battle
			and scene.narrative_events != old_events and scene.narrative_events.instance(event_id).is_empty()
			and scene._cpu_strategy._claim_retry_at.is_empty()
			and scene._expeditions.assignments.is_empty() and scene._outposts_by_region.is_empty()
			and scene.owns_region(NEUTRAL, region), "Restart clears claims, discovery history, and strategy state.")
		_check_starting_rules(scene)
	scene.free()


func _check_starting_rules(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	_check(battle.elapsed_time() == 0.0 and battle.active_units().size() == 4
		and battle.base_hp(PLAYER) == MatchBattle.BASE_HP and battle.base_hp(CPU) == MatchBattle.BASE_HP,
		"The two bases and four scouts start with shared stats.")
	for side in [PLAYER, CPU]:
		var scouts: Array = scene._expeditions.available(side)
		_check(scouts.size() == 2, "Each side starts with exactly two available scouts.")
		for scout in scouts:
			var unit := battle.get_unit(scout.unit_id)
			_check(unit != null and unit.type_id == Catalog.SCOUT and unit.hp == unit.definition.hp
				and battle.unit_speed_stat(unit).total == unit.definition.speed,
				"Scout health and speed use the shared catalog.")
		for resource in MatchEconomy.RESOURCES:
			var definition: Dictionary = MatchEconomy.RESOURCES[resource]
			_check(scene.economy.stockpile(side, resource) == definition.starting_stock
				and scene.economy.income_rate(side, resource) == definition.baseline,
				"All levels use standard starting stockpiles and income.")


func _test_decisions() -> void:
	var scene := Prototype.instantiate()
	root.add_child(scene)
	var openings := []
	var predicted_openings := []
	var weak_raid_responses := []
	var generator_investments := []
	var claim_targets := []
	scene.cpu_scout_connection_weight = 0.0
	scene.cpu_scout_landmark_weight = 0.0
	scene.cpu_scout_production_weight = 0.0
	scene.cpu_scout_capacity_weight = 0.0
	scene.cpu_scout_travel_weight = 5.0
	scene.cpu_difficulty = 1
	_prepare_expansion(scene)
	scene._try_cpu_purchase()
	var initial_targets: Array = scene._expeditions.assignments.keys()
	_check(not initial_targets.is_empty(), "The scout preference fixture has a reachable frontier.")
	if initial_targets.is_empty():
		scene.free()
		return
	var closest: StringName = initial_targets[0]
	scene.cpu_scout_capacity_weight = 0.35
	for level in range(1, 6):
		scene.cpu_difficulty = level
		scene.restart_match()
		scene.set_process(false)
		scene.economy.advance(50.0)
		_spawn_ranged(scene, 4)
		scene._try_cpu_purchase()
		openings.append(scene._battle._timers[0].kind if not scene._battle._timers.is_empty() else &"")

		scene.restart_match()
		scene.set_process(false)
		scene.economy.advance(50.0)
		var player_base: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
		var site := player_base.interior_point(func(point: Vector2) -> bool:
			return scene._placement_block_reason(PLAYER, &"training_range", scene._world_position(point)).is_empty())
		_check(site.is_finite() and scene.try_place_building(PLAYER, &"training_range", scene._world_position(site)),
			"The player has a visible Training Range before any units deploy.")
		scene._try_cpu_purchase()
		var timers: Array = scene._battle._timers
		predicted_openings.append(timers[1].kind if timers.size() > 1 else &"")

		_prepare_expansion(scene)
		var battle: MatchBattle = scene._battle
		battle.spawn_unit(PLAYER, battle._bases[CPU] + Vector2(-4.0, 1.0), Catalog.INFANTRY)
		scene._try_cpu_purchase()
		weak_raid_responses.append(_has_building(scene, Rules.NEST))

		_prepare_expansion(scene)
		scene.cpu_investment_horizon = 35.0
		scene.economy.try_spend(CPU, {ENERGY: int(scene.economy.energy(CPU)) - 75})
		scene._try_cpu_purchase()
		generator_investments.append(_has_building(scene, &"generator"))
		scene.cpu_investment_horizon = 26.0

		_prepare_expansion(scene)
		# Leave just enough space for a claim in one of the two frontier regions.
		var occupied: Array[StringName] = [closest]
		for i in scene.region_building_capacity - 1:
			scene._register_region_structure(StringName("fixture/%d" % i), scene.LEGENDARY_KIND, occupied)
		var before: float = scene.economy.energy(CPU)
		scene._try_cpu_purchase()
		var targets: Array = scene._expeditions.assignments.keys()
		if targets.size() == 1:
			claim_targets.append(targets[0])
			_check(scene.economy.energy(CPU) == before - scene.claim_energy and scene.owns_region(NEUTRAL, targets[0]),
				"Scoring still uses the normal price and reserves a neutral target until arrival.")
		else:
			_check(false, "Level %d can dispatch in the region preference fixture." % level)
	_check(openings.front() == &"barracks" and openings.back() == &"heavy_factory",
		"Expert counters a ranged push with Heavy while Relaxed favors Infantry. Got %s." % [openings])
	_check(predicted_openings.front() == &"barracks" and predicted_openings.back() == &"heavy_factory",
		"Expert addresses a visible production threat before the first unit deploys. Got %s." % [predicted_openings])
	_check(not weak_raid_responses.front() and weak_raid_responses.back(),
		"Expert defends against a small raid Relaxed tolerates. Got %s." % [weak_raid_responses])
	_check(not generator_investments.front() and generator_investments.back(),
		"Expert invests to fund upcoming spending while Relaxed keeps the stockpile. Got %s." % [generator_investments])
	_check(claim_targets.size() == 5 and claim_targets.front() != claim_targets.back(),
		"Higher development priority affects real scout targets. Got %s." % [claim_targets])
	_prepare_expansion(scene)
	scene.cpu_production_limit = 2
	scene.economy.try_spend(CPU, {ENERGY: int(scene.economy.energy(CPU)) - 75})
	scene._try_cpu_purchase()
	_check(scene._battle._timers.size() == 2 and not _has_building(scene, &"generator"),
		"Expert funds a second military producer before optional income buildings.")

	_prepare_expansion(scene)
	var base_regions: Array[StringName] = [TerritoryLayout.CPU_START]
	for slot in 2:
		scene._register_region_structure(StringName("fixture/base/%d" % slot), scene.LEGENDARY_KIND, base_regions)
	scene.economy.try_spend(CPU, {ENERGY: int(scene.economy.energy(CPU)) - 75})
	scene._try_cpu_purchase()
	_check(not _has_building(scene, &"generator") and scene.region_occupancy(base_regions[0]).free == 1,
		"Expert preserves the last slot for a reinforcement or defense.")
	scene.free()


func _test_route_budget() -> void:
	var scene := MatchScene.instantiate()
	scene.region_count = TerritoryLayout.MAX_REGIONS
	scene.map_width = 80.0
	scene.map_height = 55.0
	scene.cpu_start_count = 42
	scene.legendary_count = 0
	root.add_child(scene)
	var previous := 0
	for level in range(1, 6):
		scene.cpu_difficulty = level
		_prepare_expansion(scene)
		var profile := Profiles.get_profile(level)
		_check(profile.claim_options > previous and profile.site_samples <= 22, "Planning has explicit fixed budgets.")
		previous = profile.claim_options
		# Every frontier route fails, so the retry list records exactly which regions received a probe.
		scene._battle.add_landmark_footprint(scene._layout.bounds)
		scene._try_cpu_purchase()
		var probes: int = scene._cpu_strategy._claim_retry_at.size()
		_check(probes == profile.claim_options and scene._expeditions.assignments.is_empty(),
			"Level %d caps failed routes on a 128-region map. Probed %d." % [level, probes])
	scene.free()


func _prepare_expansion(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene.cpu_production_limit = 1
	scene.economy.advance(60.0)
	scene.economy.set_income_source(CPU, FOOD, &"fixture", "Fixture supply", 5.0)
	var region: MatchRegion = scene.get_region(TerritoryLayout.CPU_START)
	var point := region.interior_point(func(site: Vector2) -> bool:
		return scene._placement_block_reason(CPU, &"barracks", scene._world_position(site)).is_empty())
	_check(point.is_finite() and scene.try_place_building(CPU, &"barracks", scene._world_position(point))
		and scene.try_upgrade(CPU, ScoutFixture.barracks(scene._battle, CPU).id), "The scout fixture buys production and the upgrade at the shared prices.")
	var battle: MatchBattle = scene._battle
	battle.spawn_unit(CPU, battle._bases[CPU] + Vector2(2.0, 1.0), Catalog.INFANTRY)


func _spawn_ranged(scene: Node, count: int) -> void:
	var battle: MatchBattle = scene._battle
	for i in count:
		var unit := battle.spawn_unit(PLAYER, battle._bases[CPU] + Vector2(-7.5, 3.0 + i * 0.35), Catalog.RANGED)
		_check(unit != null, "The fighting fixture can position the scripted attackers.")


func _has_building(scene: Node, kind: StringName) -> bool:
	return scene._fortifications.values().any(func(placed) -> bool:
		return placed.defense.side == CPU and placed.defense.kind == kind)


func _stock(scene: Node, side: MatchRegion.Owner) -> Dictionary:
	var stock := {}
	for resource in MatchEconomy.RESOURCES:
		stock[resource] = scene.economy.stockpile(side, resource)
	return stock


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
