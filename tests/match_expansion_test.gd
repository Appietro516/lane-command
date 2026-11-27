extends SceneTree

const MATCH := preload("res://main.tscn")
const Scouts := preload("res://tests/scout_fixture.gd")
const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CPU_2 := MatchRegion.Owner.CPU_2
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const IDLE := MatchBattle.Stance.IDLE
const STEP := MatchBattle.STEP

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_medic()
	_test_counters()
	_test_anti_tank()
	root.size = Vector2i(1280, 800)
	var scene := MATCH.instantiate()
	scene.map_shape = MapSettings.Shape.CIRCLE
	scene.region_count = 24
	scene.map_width = MapSettings.scaled_dimensions(MapSettings.Shape.CIRCLE, 24).x
	scene.cpu_opponent_count = 2
	scene.legendary_count = 0
	scene.neutral_objectives_enabled = false
	scene.narrative_catalog = null
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	_test_producers(scene)
	_test_strike(scene)
	_test_interception(scene)
	_test_cpu_arsenal(scene)
	scene.free()
	if failures == 0:
		print("Expansion combat, production, CPU decisions, circular strikes, ruins and restart passed.")
	quit(int(failures > 0))


func _test_medic() -> void:
	var battle := MatchBattle.new(Vector2(-11, 0), Vector2(11, 0))
	var economy := MatchEconomy.new()
	var medic := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.MEDIC, null, IDLE)
	battle.spawn_unit(PLAYER, Vector2.UP, Catalog.MEDIC, null, IDLE)
	var injured := battle.spawn_unit(PLAYER, Vector2.RIGHT, Catalog.INFANTRY, null, IDLE)
	var enemy := battle.spawn_unit(CPU, Vector2.LEFT, Catalog.INFANTRY, null, IDLE)
	var distant := battle.spawn_unit(PLAYER, Vector2(4, 0), Catalog.HEAVY, null, IDLE)
	var dead := battle.spawn_unit(PLAYER, Vector2.DOWN, Catalog.INFANTRY, null, IDLE)
	var injured_building := battle.add_fortification(Rules.WALL, PLAYER, Vector2(-1, 1.5))
	injured.hp = 7.0
	enemy.hp = 7.0
	distant.hp = 7.0
	dead.hp = 0.0
	injured_building.hp = 7.0
	var cues: Array[MatchBattle.AttackResolved] = []
	battle.healing_resolved.connect(func(heal: MatchBattle.AttackResolved) -> void: cues.append(heal))
	battle.order_move(PLAYER, medic.id, Vector2(2, 0), true)
	battle.advance(STEP, economy)
	_check(injured.hp == 9.5 and cues.size() == 1 and cues[0].target_id == injured.id
		and cues[0].simulation_time == battle.elapsed_time() and medic.position.x > 0.0,
		"One same-tick cue corresponds to real healing while moving, with a per-target recovery interval.")
	_check(enemy.hp == 7.0 and distant.hp == 7.0 and injured_building.hp == 7.0
		and battle.get_unit(dead.id) == null, "Healing spares enemies, destroyed units, buildings and distant allies.")
	injured.hp = 11.9
	battle.advance(1.3, economy)
	var ally_cues := cues.filter(func(cue: MatchBattle.AttackResolved) -> bool: return cue.target_id == injured.id)
	_check(injured.hp == 12.0 and ally_cues.size() == 2, "Later healing stops at the effective HP cap.")


func _test_counters() -> void:
	for opponent in [Catalog.INFANTRY, Catalog.RANGED, Catalog.HEAVY]:
		var battle := MatchBattle.new(Vector2(-11, 0), Vector2(11, 0))
		var raider := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.RAIDER)
		var rival := battle.spawn_unit(CPU, Vector2(0.73, 0), opponent)
		battle.order_hold(PLAYER, raider.id)
		battle.order_hold(CPU, rival.id)
		battle.advance(5.0, MatchEconomy.new())
		var winner: MatchBattle.Unit = raider if opponent == Catalog.INFANTRY else rival
		var loser: MatchBattle.Unit = rival if winner == raider else raider
		_check(battle.get_unit(winner.id) != null and battle.get_unit(loser.id) == null,
			"Raider wins against Infantry and loses to %s." % opponent)


func _test_anti_tank() -> void:
	var battle := MatchBattle.new(Vector2(-11, 0), Vector2(11, 0))
	var economy := MatchEconomy.new()
	var gun := battle.add_fortification(Rules.ANTI_TANK, PLAYER, Vector2.ZERO)
	var heavy := battle.spawn_unit(CPU, Vector2(4, 0), Catalog.HEAVY, null, IDLE)
	var infantry := battle.spawn_unit(CPU, Vector2(3.5, 0.2), Catalog.INFANTRY, null, IDLE)
	var shots := PackedVector2Array()
	battle.fortification_fired.connect(func(fort: MatchBattle.Fortification, point: Vector2) -> void:
		if fort == gun:
			shots.append(point))
	battle.advance(STEP, economy)
	_check(is_equal_approx(heavy.hp, 26.0 - 17.0) and infantry.hp == 12.0 and shots.size() == 1 and shots[0] == heavy.position,
		"The gun prefers Heavy, deals 17 damage, and emits a synchronized single-target cue.")
	battle.advance(1.5, economy)
	_check(is_equal_approx(heavy.hp, 26.0 - 17.0), "The slow gun respects its cooldown.")
	battle.advance(0.4, economy)
	_check(battle.get_unit(heavy.id) == null and infantry.hp == 12.0, "The second armor hit has no splash.")
	battle.advance(1.85, economy)
	_check(is_equal_approx(infantry.hp, 10.2), "Infantry takes only 1.8 damage per hit.")


func _test_producers(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	economy.advance(120.0)
	var first := _place(scene, PLAYER, &"aid_station") as MatchBattle.ProductionTimer
	var second := _place(scene, PLAYER, &"raider_camp") as MatchBattle.ProductionTimer
	var third := _place(scene, CPU_2, &"raider_camp") as MatchBattle.ProductionTimer
	if not _check(first != null and second != null and third != null, "Each new producer can be built on the circle."):
		return
	var food := economy.stockpile(PLAYER, MatchEconomy.FOOD)
	var rally := _street(battle, Vector2.ZERO)
	first.elapsed = 2.0
	_check(battle.set_producer_rally(PLAYER, first.id, rally)
		and battle.set_producer_stance(PLAYER, first.id, IDLE)
		and not scene.try_upgrade(CPU, first.id) and scene.try_upgrade(PLAYER, first.id)
		and not scene.try_upgrade(PLAYER, first.id), "Rally, stance and the one paid upgrade use ownership checks.")
	_check(first.level == 2 and second.level == 1 and third.level == 1 and first.elapsed == 2.0
		and first.rally_point == rally and first.default_stance == IDLE and food - 15 == economy.stockpile(PLAYER, MatchEconomy.FOOD),
		"Upgrading one producer keeps its progress and settings and leaves other producers at level one.")
	var recruits: Array[MatchBattle.Unit] = []
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void: recruits.append(unit))
	battle.advance(third.interval(economy) + STEP, economy)
	_check(recruits.any(func(unit: MatchBattle.Unit) -> bool:
		return unit.type_id == Catalog.MEDIC and unit.following_rally and unit.stance == IDLE)
		and recruits.any(func(unit: MatchBattle.Unit) -> bool:
			return unit.type_id == Catalog.RAIDER and unit.side == PLAYER)
		and recruits.any(func(unit: MatchBattle.Unit) -> bool:
			return unit.type_id == Catalog.RAIDER and unit.side == CPU_2),
		"The integrated producer timers deploy Medics and Raiders under the same faction rules.")
	third.hp = 0.0
	battle.advance(STEP, economy)
	_check(not battle._timers.has(third) and not scene.try_upgrade(CPU_2, third.id),
		"Destroyed producers leave the timer list and reject upgrades.")


func _test_strike(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	economy.advance(300.0)
	var site := _claim_silo_site(scene, PLAYER)
	var silo := _place(scene, PLAYER, Rules.SILO, site) as MatchBattle.MissileSilo
	if not _check(silo != null, "A claimed circle region has room for a silo."):
		return
	var owner_region: StringName = scene._layout.region_at(silo.position)
	_check(scene.region_occupancy(owner_region).used == 5, "The silo uses four slots alongside an outpost.")
	var victim_region := _strike_region(scene, silo.position)
	if not _check(victim_region != null, "The circle has a suitably separated strike fixture."):
		return
	var center := Vector2(victim_region.position.x, victim_region.position.z) + Vector2(0.31, 0.36)
	scene._complete_claim(CPU, victim_region.region_id, -1,
		Vector2(victim_region.position.x, victim_region.position.z))
	var farm := _place(scene, CPU, &"farm", victim_region.region_id)
	_check(farm != null and economy.income_rate(CPU, MatchEconomy.FOOD) == 4.0,
		"The target region has a working outpost and income source.")
	var direction := center.direction_to(Vector2.ZERO)
	var near := battle.spawn_unit(PLAYER, center + direction * 5.8, Catalog.INFANTRY, null, IDLE)
	var far := battle.spawn_unit(CPU_2, center + direction * 7.7, Catalog.RANGED, null, IDLE)
	if not _check(near != null and far != null, "The blast-edge targets spawn on passable circle terrain."):
		return
	scene._select_fortification(silo.id)
	var designated: Button = scene.get_node("%TargetMissile")
	_check(designated.visible and not battle.prepare_missile(CPU, silo.id, center)
		and not battle.prepare_missile(PLAYER, silo.id, scene._layout.bounds.end),
		"Only the owning faction may target playable ground.")
	designated.pressed.emit()
	var cursor := root.get_camera_3d().unproject_position(scene._world_position(center))
	scene._preview_missile_at(cursor)
	_check(scene._missile_ring.visible and is_equal_approx(scene._missile_ring.scale.x, Rules.MISSILE_RADIUS),
		"The inspector shows the fixed blast radius before committing.")
	scene._commit_ground_target(cursor)
	_check(silo.missile_state == MatchBattle.MissileState.CHARGING and scene.get_node("%MissileWarning").visible
		and silo.missile_target.is_equal_approx(center) and not battle.prepare_missile(PLAYER, silo.id, center + Vector2.ONE),
		"An off-center target starts a warned countdown and cannot be moved.")
	battle._elapsed_time = silo.launches_at - STEP
	battle._advance_missiles()
	_check(battle._missile_flights.is_empty() and near.hp > 0.0, "Charging does not yet hit the target.")
	battle.advance(STEP, economy)
	_check(silo.missile_state == MatchBattle.MissileState.EXHAUSTED and battle._missile_flights.size() == 1
		and scene._missile_models.size() == 1 and near.hp > 0.0, "Launch exhausts ammunition and starts visible flight.")
	battle.advance(Rules.MISSILE_FLIGHT, economy)
	_check(battle.get_unit(near.id) == null and battle.get_unit(far.id) == far
		and victim_region.ruined and victim_region.region_owner == NEUTRAL and scene._ruins.get_child_count() >= 2,
		"The geometric blast kills inside its radius, spares the outside, and leaves structure remnants.")
	_check(economy.income_rate(CPU, MatchEconomy.FOOD) == 1.0 and battle.get_fortification(farm.id) == null
		and scene._expeditions.eligibility(PLAYER, victim_region.region_id) == "Permanently ruined",
		"Ruins immediately remove economic output and cannot be claimed.")
	scene._set_region_owner(victim_region.region_id, PLAYER)
	_check(victim_region.region_owner == NEUTRAL and not scene.try_place_building(PLAYER, &"farm", scene._world_position(center))
		and not battle.prepare_missile(PLAYER, silo.id, center) and battle.is_side_active(CPU),
		"Ruins cannot be restored, and a surviving silo can never launch twice.")
	var crossing := battle.spawn_unit(PLAYER, center - direction * 1.5, Catalog.HEAVY, null, IDLE)
	var beyond := center + direction * 2.0
	_check(crossing != null and battle.order_move(PLAYER, crossing.id, beyond, true),
		"Heavy clearance still permits a route through the ruined outpost footprint.")
	battle.advance(4.0, economy)
	_check(crossing.position == beyond and battle.navigation.contains(center),
		"A Heavy traverses the ruined territory in the original navigation map.")
	for hostile in [CPU, CPU_2]:
		battle._base_health[hostile].hp = 0.0
	battle.advance(STEP, economy)
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY, "Victory still requires every hostile base.")
	scene.restart_match()
	scene.set_process(false)
	_check(not victim_region.ruined and scene._ruins.get_child_count() == 0
		and scene._battle._missile_flights.is_empty() and scene._battle.outcome() == MatchBattle.Outcome.IN_PROGRESS,
		"Restart restores the seeded map and removes strikes and rubble.")


func _test_interception(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	scene.economy.advance(300.0)
	var site := _claim_silo_site(scene, PLAYER)
	var silo := _place(scene, PLAYER, Rules.SILO, site) as MatchBattle.MissileSilo
	if silo == null:
		return
	var two: Array[MatchBattle.Unit] = []
	for index in 2:
		var point := _street(battle, silo.position.move_toward(Vector2.ZERO, 6.8 + index * 0.2))
		var unit := battle.spawn_unit(CPU, point, Catalog.RANGED, null, IDLE)
		if unit != null:
			two.append(unit)
	var target: Vector2 = battle._bases[CPU]
	_check(battle.prepare_missile(PLAYER, silo.id, target), "The silo can target an opponent's base.")
	var strategy: RefCounted = scene._cpu_strategies[CPU]
	var available := two.duplicate()
	strategy._tactics._orders_left = 16
	strategy._tactics._intercept_launches(battle, CPU, available)
	_check(available.size() < two.size(), "The CPU assigns nearby troops to attack the announced silo.")
	silo.hp = 0.0
	battle.advance(STEP, scene.economy)
	_check(battle._charging_silos.is_empty() and battle._missile_flights.is_empty()
		and battle.base_hp(CPU) > 0.0 and not scene.get_region(TerritoryLayout.CPU_START).ruined,
		"Destroying a charging silo cancels the strike, and even its former target survives.")


func _test_cpu_arsenal(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	economy.advance(330.0)
	var strategy: RefCounted = scene._cpu_strategies[CPU_2]
	var sites: Array[MatchRegion] = []
	var site := _claim_silo_site(scene, CPU_2)
	if not _check(not site.is_empty(), "The CPU can claim space for a silo."):
		return
	sites.append(scene.get_region(site))
	var production := preload("res://match/cpu_strategy.gd").Production.new(battle, economy, CPU_2)
	production.active = 3
	var region := _strike_region(scene, Vector2(scene.get_region(site).position.x, scene.get_region(site).position.z))
	if not _check(region != null, "The CPU has an unprotected hostile target."):
		return
	var point := Vector2(region.position.x, region.position.z)
	scene._complete_claim(PLAYER, region.region_id, -1, point)
	var farm := _place(scene, PLAYER, &"farm", region.region_id)
	if not _check(farm != null, "A hostile farm adds value to the strike target."):
		return
	battle.visibility.set_source(-900001, CPU_2, point, BattleVisibility.SCOUT_RADIUS)
	_check(strategy._try_strategic_strike(scene, sites, battle.active_units(), production, false, 180.0),
		"A well-funded CPU purchases a silo using the normal construction rules.")
	var silos := battle._fortifications.values().filter(func(fort: MatchBattle.Fortification) -> bool:
		return fort is MatchBattle.MissileSilo and fort.side == CPU_2)
	if not _check(silos.size() == 1 and strategy._try_strategic_strike(
			scene, sites, battle.active_units(), production, false, 182.0),
			"The second CPU finds a worthy target and commits its purchased silo."):
		return
	var silo := silos[0] as MatchBattle.MissileSilo
	_check(silo.missile_state == MatchBattle.MissileState.CHARGING
		and not Rules.blast_hits(silo.missile_target, battle._bases[CPU_2], MatchBattle.BASE_FOOTPRINT * 2.0),
		"The CPU launches exactly one prepared strike and excludes targets that hit its own base.")
	scene._refresh_hud()
	_check("CPU 2 missile preparing" in scene.get_node("%MissileWarning").text,
		"A CPU strike warns the player before launch.")
	var active_before := battle._base_obstacles.size()
	battle._elapsed_time = silo.launches_at
	battle._advance_missiles()
	if not _check(battle._missile_flights.size() == 1, "The CPU launches its prepared strike."):
		return
	battle._elapsed_time = battle._missile_flights[0].impact_at
	battle.advance(STEP, economy)
	_check(region.ruined and battle.get_fortification(farm.id) == null
		and battle._base_obstacles.size() == active_before and battle.is_side_active(CPU_2),
		"The CPU strike ruins the hostile hub while preserving protected starting bases.")


func _claim_silo_site(scene: Node, side: MatchRegion.Owner) -> StringName:
	var home: StringName = scene._layout.starting_territories[side - PLAYER][0]
	for id: StringName in scene.get_region(home).neighbor_ids:
		if not scene.owns_region(NEUTRAL, id):
			continue
		if Scouts.claim(scene, side, id):
			var region := scene.get_region(id) as MatchRegion
			var point := region.interior_point(func(candidate: Vector2) -> bool:
				return scene._placement_block_reason(side, Rules.SILO, scene._world_position(candidate)).is_empty())
			if point.is_finite():
				return id
	return &""


func _strike_region(scene: Node, source: Vector2) -> MatchRegion:
	for region: MatchRegion in scene._regions_by_id.values():
		var point := Vector2(region.position.x, region.position.z)
		if region.region_owner == NEUTRAL and point.length() < 13.0 and point.distance_to(source) > 12.0:
			var separated := true
			for base: Vector2 in scene._battle._bases.values():
				separated = separated and base.distance_to(point) > 10.0
			if separated:
				return region
	return null


func _place(scene: Node, side: MatchRegion.Owner, kind: StringName, region_id := &"") -> MatchBattle.Fortification:
	for region: MatchRegion in scene._regions_by_id.values():
		if region.region_owner != side or (not region_id.is_empty() and region.region_id != region_id):
			continue
		var point := region.interior_point(func(site: Vector2) -> bool:
			return scene._placement_block_reason(side, kind, scene._world_position(site)).is_empty())
		if point.is_finite() and scene.try_place_building(side, kind, scene._world_position(point)):
			return scene._battle._fortifications.values().back()
	return null


func _street(battle: MatchBattle, point: Vector2) -> Vector2:
	for index in 8:
		var candidate := point + Vector2.from_angle(TAU * index / 8.0) * 0.65
		if battle.navigation.with_clearance(0.34).is_passable(candidate):
			return candidate
	return point


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
