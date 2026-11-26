extends SceneTree

const GAME := preload("res://game.tscn")
const MATCH := preload("res://main.tscn")
const PROFILES := preload("res://match/difficulty_profile.gd")
const SCOUT_FIXTURE := preload("res://tests/scout_fixture.gd")
const CATALOG := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CPU_2 := MatchRegion.Owner.CPU_2
const CPU_3 := MatchRegion.Owner.CPU_3
const CPU_4 := MatchRegion.Owner.CPU_4
const NEUTRAL := MatchRegion.Owner.NEUTRAL

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_setup_and_starts()
	_test_claims_and_elimination()
	_test_hostile_targeting()
	_measure_battle(1)
	_measure_battle(4)
	await process_frame
	if _failures == 0:
		print("Multi-CPU match checks passed.")
	quit(int(_failures > 0))


func _test_setup_and_starts() -> void:
	var scene := GAME.instantiate()
	scene.map_seed = 71
	scene.region_count = 7
	root.add_child(scene)
	_check(scene._battle._bases.size() == 2, "The normal entry starts with one CPU.")
	var picker: OptionButton = scene._opponent_picker
	for count in [2, 4, 1]:
		picker.select(picker.get_item_index(count))
		picker.item_selected.emit(picker.selected)
		for i in count:
			scene._difficulty_pickers[i].select(i + 1)
		scene._confirm_setup.pressed.emit()
		scene.set_process(false)
		_check(not scene._match_setup.visible and scene._battle._bases.size() == count + 1
			and scene._cpu_strategies.size() == count and scene._cpu_hp_labels.size() == count
			and scene._buildings.size() == count + 1, "Setup switches to the selected faction count.")
		_check(scene.active_map_seed == 71 and scene._layout.cells.size() == 7,
			"Changing opponent count preserves the configured map and seed.")
		var bases := {}
		var accents := {}
		var territory_count := 0
		for side: MatchRegion.Owner in scene._bases:
			var territory: Array = scene._layout.starting_territories[side - PLAYER]
			var region: MatchRegion = scene.get_region(territory[0])
			var position: Vector2 = scene._battle._bases[side]
			bases[position] = true
			accents[MatchRegion.accent_color(side)] = true
			territory_count += territory.size()
			_check(region.region_owner == side and scene._layout.region_at(position) == region.region_id,
				"Each base is in its own starting region.")
			var footprint := MatchBattle.BASE_FOOTPRINT
			for corner in BattleNavigation.corners_of(Rect2(position - footprint, footprint * 2.0)):
				_check(scene._layout.region_at(corner) == region.region_id,
					"The entire base fits in its region.")
			_check(scene._expeditions.available(side).size() == scene._expeditions.CAPACITY,
				"Every side starts with the same scouts.")
			for resource in MatchEconomy.RESOURCES:
				_check(scene.economy.stockpile(side, resource) == MatchEconomy.RESOURCES[resource].starting_stock,
					"Each side receives the same resources.")
			if side != PLAYER:
				_check(scene._cpu_strategies[side].difficulty == PROFILES.get_profile(side - CPU + 2),
					"The setup assigns the chosen difficulty to the correct opponent.")
		_check(bases.size() == count + 1 and accents.size() == count + 1
			and territory_count == count + 1 and territory_count < scene._layout.cells.size(),
			"Starts and colors are distinct with neutral expansion space.")
		scene._open_match_setup(false)

	var packed := TerritoryLayout.new(17, 5, TerritoryLayout.DEFAULT_SIZE, 1, 1, 4)
	var over_limit := TerritoryLayout.new(17, 24, TerritoryLayout.DEFAULT_SIZE, 1, 1, 5)
	_check(not packed.configuration_error.is_empty() and packed.starting_territories.is_empty()
		and not over_limit.configuration_error.is_empty(), "Invalid counts are rejected before assigning starts.")
	scene._region_count_field.text = "5"
	picker.select(picker.get_item_index(4))
	picker.item_selected.emit(picker.selected)
	var previous: MatchBattle = scene._battle
	scene._confirm_setup.pressed.emit()
	_check(scene._match_setup.visible and scene._battle == previous and scene.cpu_opponent_count == 1,
		"An invalid setup leaves the active match intact.")
	scene.free()


func _test_claims_and_elimination() -> void:
	var scene := MATCH.instantiate()
	scene.cpu_opponent_count = 4
	scene.additional_cpu_difficulties.assign([1, 4, 5])
	scene.legendary_count = 0
	scene.claim_duration = 0.1
	# Let the fixture reach the expansion phase quickly and keep its defensive
	# radius clear while units hold at their own production sites.
	scene.cpu_production_limit = 1
	scene.cpu_production_target = 1
	scene.cpu_threat_radius = 5.0
	scene.cpu_expansion_limit = 1
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var starts := battle._bases.duplicate()
	var seeds := {}
	var retry_region: StringName = scene._layout.starting_territories[2][0]
	scene._expeditions.assignment_interrupted.emit(CPU_2, retry_region, 1.0)
	for side in [CPU, CPU_2, CPU_3, CPU_4]:
		var strategy: RefCounted = scene._cpu_strategies[side]
		seeds[strategy._rng.seed] = true
		_check(strategy._claim_retry_at.has(retry_region) == (side == CPU_2),
			"An interrupted expedition changes only its own planner's retry state.")
	_check(seeds.size() == 4, "Every opponent receives a distinct RNG stream.")
	var produced := {}
	var record_production := func(unit: MatchBattle.Unit) -> void:
		if unit.type_id != CATALOG.SCOUT:
			produced[unit.side] = true
			battle.set_unit_stance(unit.side, unit.id, MatchBattle.Stance.IDLE)
	battle.unit_produced.connect(record_production)
	var opening := Time.get_ticks_usec()
	var claiming_sides := {}
	scene.claim_completed.connect(func(side: MatchRegion.Owner, _region: StringName, _scout: int) -> void:
		claiming_sides[side] = true)
	for i in 110:
		scene._process(0.5)
		if claiming_sides.size() == 4 and produced.size() == 4:
			break
	battle.unit_produced.disconnect(record_production)
	print("Seeded five-faction opening reached %.1f simulated seconds in %d ms." % [
		battle.elapsed_time(), (Time.get_ticks_usec() - opening) / 1000])
	var claims := {}
	for outpost: MatchBattle.Outpost in battle._outposts.values():
		claims[outpost.side] = outpost.region_id
		_check(scene.owns_region(outpost.side, outpost.region_id), "Outpost ownership follows its claimant.")
		var id := StringName("claim/%d/%s" % [outpost.side, outpost.region_id])
		var event: Dictionary = scene.narrative_events.instance(id)
		_check(event.get("side") == outpost.side and event.get("status") == NarrativeEvents.Status.RESOLVED,
			"Each CPU claim resolves its own discovery.")
	_check(scene.narrative_events.pending_player_id().is_empty(), "CPU events never open a player dialogue.")
	for side in [CPU, CPU_2, CPU_3, CPU_4]:
		var has_producer := battle._timers.any(func(timer: MatchBattle.ProductionTimer) -> bool:
			return timer.side == side and timer.active)
		_check(produced.has(side) and has_producer,
			"Side %d buys a military producer and deploys its own troops." % side)
		_check(claims.has(side), "Side %d scouts and claims its own region." % side)
	_check(not produced.has(PLAYER) and economy.barracks_count(PLAYER) == 0,
		"CPU production leaves the human economy and building state independent.")

	var eliminated := CPU_2
	var pending := _dispatch_from_frontier(scene, eliminated)
	_check(not pending.is_empty(), "The test starts a claim before eliminating its owner.")
	var remaining_id: StringName = scene._layout.starting_territories[3][0]
	var other_stock := economy.energy(CPU_3)
	var eliminated_stock := economy.energy(eliminated)
	battle._base_health[eliminated].hp = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(battle.outcome() == MatchBattle.Outcome.IN_PROGRESS and scene._cpu_strategies.size() == 3,
		"The first lost CPU base eliminates one opponent and leaves the match in progress.")
	_check(not scene._bases[eliminated].visible and scene._buildings[eliminated].get_child_count() == 0
		and battle.active_barracks_count(eliminated) == 0 and economy.barracks_count(eliminated) == 0
		and not scene._expeditions.assignments.has(pending)
		and scene._expeditions.available(eliminated).is_empty(), "Elimination removes that side's army, production and claims.")
	for region_id in scene._initial_owners:
		_check(not scene.owns_region(eliminated, region_id), "An eliminated faction releases all its territory.")
	_check(scene.owns_region(CPU_3, remaining_id) and not economy.try_spend(eliminated, {})
		and not scene.narrative_events.submit(&"eliminated", &"claim_completed", eliminated, remaining_id),
		"Survivor ownership stays intact and eliminated factions cannot spend or trigger events.")
	battle.advance(1.0, economy, true)
	_check(economy.energy(CPU_3) > other_stock and economy.energy(eliminated) == eliminated_stock,
		"Survivor income continues and the eliminated stockpile stops accruing.")
	var later := &"survivor/claim"
	_check(scene.narrative_events.submit(later, &"claim_completed", CPU_3, remaining_id)
		and scene.narrative_events.resolve_cpu(later), "A surviving CPU can still resolve discoveries.")

	for side in [CPU_4, CPU, CPU_3]:
		battle._base_health[side].hp = 0.0
		battle.advance(MatchBattle.STEP, economy)
		_check(battle.is_finished() == (side == CPU_3), "Victory waits for the last hostile base.")
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY, "Destroying all CPU bases wins the match.")
	scene.restart_match()
	scene.set_process(false)
	battle = scene._battle
	_check(battle._bases == starts and scene.active_map_seed == 17
		and scene._cpu_strategies.size() == 4 and scene._expeditions.assignments.is_empty()
		and scene.narrative_events.instance(later).is_empty() and scene._outposts_by_region.is_empty()
		and scene._cpu_strategies[CPU_2].difficulty == PROFILES.get_profile(1)
		and scene._cpu_strategies[CPU_2]._claim_retry_at.is_empty()
		and scene._cpu_strategies[CPU_2]._rng.seed in seeds, "Restart restores seeded starts, profiles and fresh state.")
	battle._base_health[PLAYER].hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(battle.outcome() == MatchBattle.Outcome.DEFEAT and battle.base_hp(CPU_4) > 0.0,
		"The human loses immediately when their base falls.")
	scene.free()


func _dispatch_from_frontier(scene: Node, side: MatchRegion.Owner) -> StringName:
	for region: MatchRegion in scene._regions_by_id.values():
		if scene.dispatch_scout(side, region.region_id).is_empty():
			return region.region_id
	return &""


func _test_hostile_targeting() -> void:
	var positions: Dictionary[MatchRegion.Owner, Vector2] = {
		PLAYER: Vector2(-23, 0), CPU: Vector2(23, 0), CPU_2: Vector2(0, 12), CPU_3: Vector2(0, -12),
	}
	var economy := MatchEconomy.new(null, positions.keys())
	var battle := MatchBattle.new(positions[PLAYER], positions[CPU], 4.0,
		Rect2(-30, -18, 60, 36), null, positions)
	var shooter := battle.spawn_unit(CPU_2, Vector2(0, -9), CATALOG.RANGED)
	var rival := battle.spawn_unit(CPU_3, Vector2(0, -8))
	var ally := battle.spawn_unit(CPU_2, Vector2(0, -8.8))
	battle.order_hold(CPU_2, shooter.id)
	battle.set_unit_stance(CPU_3, rival.id, MatchBattle.Stance.IDLE)
	battle.set_unit_stance(CPU_2, ally.id, MatchBattle.Stance.IDLE)
	var attacks: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(func(hit: MatchBattle.AttackResolved) -> void: attacks.append(hit))
	rival.hp = 1.0
	battle.advance(MatchBattle.STEP, economy)
	_check(attacks.size() == 1 and attacks[0].target_side == CPU_3 and attacks[0].target_id == rival.id
		and battle.get_unit(rival.id) == null and ally.hp == CATALOG.DEFINITIONS[CATALOG.INFANTRY].hp,
		"CPU units can kill a different CPU's unit and ignore closer allies.")
	battle._base_health[CPU_3].hp = 1.0
	shooter.cooldown = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(attacks.size() == 2 and attacks[1].target_side == CPU_3
		and attacks[1].target_id == MatchBattle.BASE_TARGET and battle.base_hp(CPU_3) == 0.0
		and battle.base_hp(PLAYER) == MatchBattle.BASE_HP and battle.base_hp(CPU) == MatchBattle.BASE_HP,
		"CPU-versus-CPU base damage resolves against the selected base.")
	battle.set_unit_stance(CPU_2, shooter.id, MatchBattle.Stance.SEEK_NEAREST, true)
	battle.advance(MatchBattle.STEP, economy)
	_check(shooter.target == MatchBattle.BASE_TARGET and shooter.target_base in [PLAYER, CPU],
		"Autonomous targeting finds another living opponent after a base falls.")


func _measure_battle(opponents: int) -> void:
	var layout := TerritoryLayout.new(17, 24, TerritoryLayout.DEFAULT_SIZE, 1, 1, opponents)
	var positions: Dictionary[MatchRegion.Owner, Vector2] = {}
	var army_sites: Dictionary[MatchRegion.Owner, Vector2] = {}
	for cell in layout.cells:
		for i in layout.starting_territories.size():
			if cell.id == layout.starting_territories[i][0]:
				var side := (PLAYER + i) as MatchRegion.Owner
				positions[side] = cell.site
				army_sites[side] = cell.site.lerp(Vector2.ZERO, 0.55)
	var battle := MatchBattle.new(positions[PLAYER], positions[CPU], 4.0, layout.bounds, null, positions)
	var economy := MatchEconomy.new(null, positions.keys())
	for side in positions:
		for index in 16:
			var point := army_sites[side] + Vector2.from_angle(TAU * index / 16.0) * 2.2
			if not battle.navigation.with_clearance(0.1).is_passable(point):
				point = army_sites[side]
			var type := CATALOG.RANGED if index % 3 == 0 else CATALOG.INFANTRY
			_check(battle.spawn_unit(side, point, type) != null, "The performance scenario deploys the full army.")
	var timings: Array[int] = []
	for i in 360:
		var start := Time.get_ticks_usec()
		battle.advance(MatchBattle.STEP, economy)
		timings.append(Time.get_ticks_usec() - start)
	timings.sort()
	var p95 := timings[floori(timings.size() * 0.95)]
	print("1v%d combat with %d initial units, 360 fixed steps, p95 %.2f ms." % [
		opponents, positions.size() * 16, p95 / 1000.0])
	_check(p95 < MatchBattle.STEP * 1000000.0, "Representative combat fits the fixed-step budget at p95.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
