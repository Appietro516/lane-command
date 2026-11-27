extends SceneTree

const Catalog := preload("res://match/unit_catalog.gd")
const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const PLAYER_BASE := Vector2(-10.2, 2.0)
const CPU_BASE := Vector2(10.2, 2.0)

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_infantry_speed()
	_test_movement_and_delta_partition()
	_test_duel_and_cleanup()
	_test_target_priority(PLAYER, CPU)
	_test_target_priority(CPU, PLAYER)
	_test_targeting_across_combat_cells()
	_test_base_destruction(PLAYER, CPU)
	_test_base_destruction(CPU, PLAYER)
	_test_orders_and_defense()
	_test_routes()
	for side: MatchRegion.Owner in [PLAYER, CPU]:
		for type_id: StringName in Catalog.OFFENSIVE_TYPES:
			_test_stances(side, type_id)
	_test_threat_ranking()
	_test_blocked_targets()
	await _test_tactical_hud()
	await _test_match_scene()
	await _test_match_end_and_restart()
	if failures == 0:
		print("Open-map combat, unit inspection, movement orders, outcomes and replay checks passed.")
	quit(1 if failures else 0)


func _test_infantry_speed() -> void:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var economy := MatchEconomy.new()
	var start := Vector2(-4.0, -5.0)
	var unit := battle.spawn_unit(PLAYER, start)
	_check(battle.issue_move(unit.id, Vector2(4.0, -5.0)), "Infantry accepts a clear move order.")
	battle.advance(1.0, economy)
	var baseline_distance := start.distance_to(unit.position)
	_check(is_equal_approx(baseline_distance, 1.584),
		"Infantry covers 1.584 map units in one second.")

	battle.stats.set_modifier(&"drill", PLAYER, FactionStats.UNIT_SPEED, 0.6)
	start = unit.position
	battle.advance(1.0, economy)
	_check(is_equal_approx(start.distance_to(unit.position), 2.184),
		"A live speed buff adds 0.6 units of travel in the next second.")


func _test_movement_and_delta_partition() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU])
	var split_battle := _with_barracks([PLAYER, CPU])
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var deployed := battle.active_units()
	_check(deployed.size() == 2, "Both sides deploy one unit on schedule.")
	if deployed.size() != 2:
		return
	var player_spawn := deployed[0].position
	var cpu_spawn := deployed[1].position
	battle.advance(1.0, economy)
	for delta in [0.031, 1.217, 2.002, 2.0]:
		split_battle.advance(delta, economy)
	var units := battle.active_units()
	_check(units.size() == 2, "Only the first wave has deployed after one second of movement.")
	if units.size() != 2:
		return
	_check(units[0].side == PLAYER and units[1].side == CPU
		and units[0].position.x > player_spawn.x and units[1].position.x < cpu_spawn.x
		and is_equal_approx(units[0].position.x, -units[1].position.x)
		and units[0].position.y < 0.0 and units[1].position.y < 0.0,
		"Both units leave their off-axis barracks and advance toward the opposing base.")
	_check(units[0].hp == 12 and units[1].hp == 12,
		"Fresh units start at 12 HP.")
	_check(battle.base_hp(PLAYER) == MatchBattle.BASE_HP and battle.base_hp(CPU) == MatchBattle.BASE_HP,
		"Both bases start at the current HP cap.")

	battle.advance(4.0, economy)
	for index in range(200):
		split_battle.advance(0.02, economy)
	_check(_unit_state(battle) == _unit_state(split_battle),
		"Partitioning elapsed time leaves positions, targets, HP and cooldowns identical.")


func _test_duel_and_cleanup() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU])
	var removed: Array[int] = []
	battle.unit_removed.connect(func(id: int) -> void: removed.append(id))
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var units := battle.active_units()
	if units.size() != 2:
		_check(false, "Both duelists must spawn.")
		return
	var player := units[0]
	var cpu := units[1]

	for step in range(400):
		if player.hp < 12:
			break
		battle.advance(MatchBattle.STEP, economy)
	_check(player.hp == 9 and cpu.hp == 9 and player.target == cpu.id and cpu.target == player.id,
		"On contact, both units select each other and deal 3 damage at the same time.")
	var player_position := player.position
	var cpu_position := cpu.position
	battle.advance(0.99, economy)
	_check(player.hp == 9 and cpu.hp == 9, "There is no second attack before one second.")
	_check(player.position == player_position and cpu.position == cpu_position,
		"Engaged units stay still while their attacks cool down.")
	battle.advance(0.01, economy)
	_check(player.hp == 6 and cpu.hp == 6, "Both units attack again at one second.")
	battle.advance(2.0, economy)
	_check(player.hp == 0 and cpu.hp == 0 and removed == [player.id, cpu.id],
		"A simultaneous fourth hit removes both duelists.")
	_check(battle.get_unit(player.id) == null and battle.get_unit(cpu.id) == null
		and battle.get_unit(3) != null and battle.get_unit(4) != null,
		"The next wave stays active after the duelists die.")


func _test_target_priority(attacker_side: MatchRegion.Owner, defender_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([attacker_side, defender_side, defender_side])
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var units := battle.active_units()
	if units.size() != 3:
		_check(false, "Three units must spawn for the target priority check.")
		return
	var attacker := units[0]
	var farther := units[1]
	var nearer := units[2]
	var direction := 1.0 if attacker_side == PLAYER else -1.0
	attacker.position = Vector2(direction * 7.5, 3.5)
	farther.position = attacker.position + Vector2(0.0, 2.8)
	nearer.position = attacker.position + Vector2(0.0, 1.4)
	nearer.hp = MatchBattle.ATTACK_DAMAGE

	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == nearer.id and attacker.position.y > 3.5 and nearer.hp == 3
		and battle.base_hp(defender_side) == MatchBattle.BASE_HP,
		"The nearest local opponent draws the unit out of base attack range before contact.")
	battle.target_priority = MatchBattle.TargetPriority.LOWEST_HP
	farther.hp = 1
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == nearer.id, "Hold shot priority does not override Seek Nearest.")
	battle.target_priority = MatchBattle.TargetPriority.NEAREST
	farther.hp = MatchBattle.UNIT_HP
	for step in range(100):
		if battle.get_unit(nearer.id) == null:
			break
		battle.advance(MatchBattle.STEP, economy)
	_check(battle.get_unit(nearer.id) == null and attacker.target == MatchBattle.NO_TARGET,
		"Removing an opponent clears references to its ID.")
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == farther.id, "The surviving unit acquires the next local opponent.")
	battle.aggro_radius = 0.05
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == MatchBattle.BASE_TARGET,
		"Reducing detection below the enemy distance restores strategic advance.")


func _test_targeting_across_combat_cells() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU, CPU])
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var units := battle.active_units()
	if units.size() != 3:
		_check(false, "Three units must spawn for the combat cell check.")
		return
	var attacker := units[0]
	var earlier := units[1]
	var later := units[2]
	attacker.position = Vector2(-4.0, -1.0)
	earlier.position = Vector2(0.0, -1.0)
	later.position = Vector2(-8.0, -1.0)
	# A larger snapshot uses the grid. The later ID is in the first cell queried.
	for id in range(4, 24):
		battle._units[id] = MatchBattle.Unit.new(id, PLAYER, Vector2(-10.0, 6.0))
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == earlier.id,
		"At equal distance on the detection boundary, the first spawn wins regardless of cell.")
	earlier.position = Vector2(8.0, -1.0)
	attacker.position = Vector2(-4.0, -1.0)
	later.position = Vector2(-8.0, -1.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == later.id, "Each step indexes the units' current positions.")


func _test_base_destruction(attacker_side: MatchRegion.Owner, defender_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([attacker_side])
	var destroyed: Array[MatchRegion.Owner] = []
	battle.base_destroyed.connect(func(side: MatchRegion.Owner) -> void: destroyed.append(side))
	battle.advance(6.0, economy)
	_check(battle.base_hp(defender_side) == MatchBattle.BASE_HP, "A distant base takes no damage.")
	var base: Vector2 = battle._bases[defender_side]
	var tank := battle.spawn_unit(attacker_side, base + Vector2(0.0, 1.92), Catalog.HEAVY,
		null, MatchBattle.Stance.SEEK_NEAREST)
	tank.hp = 100.0
	var damage: float = tank.definition.damage * tank.definition.structure_damage_multiplier
	battle.advance(MatchBattle.STEP, economy)
	_check(is_equal_approx(battle.base_hp(defender_side), MatchBattle.BASE_HP - damage),
		"A Heavy deals its siege damage in range.")
	battle._base_health[defender_side].hp = damage
	battle.advance(tank.attack_interval + MatchBattle.STEP, economy)
	var expected_outcome := MatchBattle.Outcome.VICTORY if attacker_side == PLAYER else (
		MatchBattle.Outcome.DEFEAT
	)
	_check(battle.is_finished() and battle.base_hp(defender_side) == 0
		and battle.base_hp(attacker_side) == MatchBattle.BASE_HP and destroyed == [defender_side]
		and battle.outcome() == expected_outcome,
		"A destroyed base reaches zero HP and records the outcome once.")

	var final_units := _unit_state(battle)
	var final_time := battle.elapsed_time()
	battle.advance(60.0, economy)
	_check(not final_units.is_empty() and _unit_state(battle) == final_units
		and destroyed == [defender_side] and battle.elapsed_time() == final_time
		and battle.outcome() == expected_outcome,
		"Further time leaves the completed battle, clock and outcome unchanged.")


func _test_orders_and_defense() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU])
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var player := battle.active_units()[0]
	var opponent := battle.active_units()[1]
	for timer_id in battle._timers:
		battle.set_barracks_active(timer_id, false)
	var destination := Vector2(-6.0, 5.0)
	_check(battle.issue_move(player.id, destination)
		and player.movement_destination == destination and not player.waypoints.is_empty(),
		"A move exposes its destination and route immediately.")
	_check(not battle.issue_move(opponent.id, destination), "CPU units reject player commands.")
	battle.advance(0.5, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.position.y > -2.0,
		"The ordered unit advances away from its strategic base target.")

	opponent.position = player.position + Vector2(0.4, 0.0)
	_check(battle.set_unit_stance(CPU, opponent.id, MatchBattle.Stance.IDLE), "CPU can enter reserve.")
	var opponent_hp := opponent.hp
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.order == MatchBattle.Order.MOVE
		and player.movement_destination == destination and opponent.hp == opponent_hp,
		"An in-range enemy does not divert or interrupt transit.")
	battle.advance(5.0, economy)
	_check(player.order == MatchBattle.Order.HOLD and player.position == destination
		and player.waypoints.is_empty(), "Arrival converts a move into a persistent hold.")

	opponent.position = destination + Vector2(2.0, 0.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.position == destination,
		"Hold ignores detected enemies outside weapon range.")
	opponent.position = destination + Vector2(0.5, 0.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == opponent.id and opponent.hp < opponent_hp and player.position == destination,
		"Hold fires on a target that enters weapon range and keeps its post.")
	opponent.position = destination + Vector2(4.2, 0.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.position == destination,
		"Leaving the hold radius clears the defender's target.")


func _test_routes() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER])
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var unit := battle.active_units()[0]
	unit.position = Vector2(-4.0, -5.0)
	var destination := Vector2(4.0, -5.0)
	_check(battle.issue_move(unit.id, destination) and unit.waypoints.size() == 1,
		"An unobstructed order uses a direct route.")
	var obstacle := Rect2(-1.0, -6.0, 2.0, 2.0)
	battle.navigation.add_obstacle(obstacle)
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.waypoints.size() > 1 and unit.waypoints[-1] == destination,
		"A new obstacle replans the route through intermediate waypoints.")
	_check(not battle.issue_move(unit.id, obstacle.get_center())
		and unit.ordered_destination == destination, "Blocked ground preserves the valid order.")
	_check(not battle.issue_move(unit.id, Vector2.INF), "Off-map destinations are rejected.")
	var crossed_obstacle := false
	for step in range(360):
		battle.advance(MatchBattle.STEP, economy)
		crossed_obstacle = crossed_obstacle or obstacle.has_point(unit.position)
	_check(unit.position == destination and not crossed_obstacle,
		"The unit follows its waypoints around the obstacle and reaches the original destination.")

	unit.position = Vector2(-4.0, -5.0)
	_check(battle.issue_move(unit.id, destination), "The detour remains available before the wall.")
	var detour := unit.waypoints.duplicate()
	var blocker := battle.navigation.add_obstacle(Rect2(1.5, -9.0, 1.0, 18.0))
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.order == MatchBattle.Order.MOVE and unit.waypoints.is_empty()
		and not battle.issue_move(unit.id, destination),
		"A passable but disconnected destination clears stale waypoints and rejects a new order.")
	var previous := unit.position
	battle.advance(0.25, economy)
	_check(unit.position == previous, "A unit with no route waits without crossing the blocker.")
	battle.navigation.remove_obstacle(blocker)
	_check(battle.navigation.path(previous, destination) == detour,
		"Removing the blocker restores the same detour between previously queried endpoints.")
	var replacement := Vector2(-5.0, -5.0)
	_check(battle.issue_move(unit.id, replacement), "A reachable order replaces a stalled route.")
	battle.advance(1.0, economy)
	_check(unit.order == MatchBattle.Order.HOLD and unit.position == replacement,
		"The replacement reaches its destination.")


func _test_stances(side: MatchRegion.Owner, type_id: StringName) -> void:
	var enemy := CPU if side == PLAYER else PLAYER
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var economy := MatchEconomy.new()
	var start := Vector2.ZERO
	var unit := battle.spawn_unit(side, start, type_id)
	var near := battle.spawn_unit(enemy, Vector2(0, 0.5), Catalog.RANGED)
	var strong := battle.spawn_unit(enemy, Vector2(0, 3), Catalog.HEAVY)
	battle.set_unit_stance(enemy, near.id, MatchBattle.Stance.IDLE)
	battle.set_unit_stance(enemy, strong.id, MatchBattle.Stance.IDLE)
	unit.hp = 100.0
	near.hp = 20.0
	var context := "%s %s" % [MatchRegion.Owner.keys()[side], type_id]
	_check(not battle.set_unit_stance(enemy, unit.id, MatchBattle.Stance.IDLE)
		and not battle.order_move(enemy, unit.id, Vector2.LEFT)
		and not battle.order_hold(enemy, unit.id), context + " rejects orders from the other faction.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.IDLE)
	var near_start_hp := near.hp
	battle.navigation.add_obstacle(Rect2(6, 6, 1, 1))
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.position == start and unit.target == near.id
		and near.hp < near_start_hp and unit.waypoints.is_empty(),
		context + " stays in place and defends itself after a map change.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.SEEK_NEAREST)
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.target == near.id and near.hp < near_start_hp,
		context + " fires at the nearest hostile.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.SEEK_STRONGEST)
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.target == strong.id and unit.position.y > 0,
		context + " advances on the stronger, farther hostile.")

	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.IDLE)
	var post := Vector2(-1, 0)
	_check(battle.order_hold(side, unit.id, post) and unit.order == MatchBattle.Order.HOLD,
		context + " accepts a chosen hold point while assigned to Idle.")
	battle.advance(1.0, economy)
	_check(unit.position == post and unit.order == MatchBattle.Order.HOLD,
		context + " reaches and holds the chosen post.")
	near.position = post + Vector2(0, 0.5)
	var near_hp := near.hp
	battle.advance(unit.attack_interval, economy)
	_check(near.hp < near_hp and unit.position == post,
		context + " defends the post while assigned to Idle.")
	unit.hp = 100.0
	var waypoint := Vector2(-3, 0)
	_check(battle.order_move(side, unit.id, waypoint, true), context + " accepts a move with resume.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.SEEK_STRONGEST)
	_check(unit.order == MatchBattle.Order.MOVE, context + " retains Move when only its default changes.")
	near.position = Vector2(0, 7)
	strong.position = Vector2(0, -7)
	var outpost := battle.add_outpost(&"objective", enemy, Vector2(-5, 1), 24)
	for step in 180:
		battle.advance(MatchBattle.STEP, economy)
		if unit.order == MatchBattle.Order.AUTONOMOUS:
			break
	_check(unit.position == waypoint and unit.order == MatchBattle.Order.AUTONOMOUS
		and unit.target == MatchBattle.NO_TARGET, context + " resumes its stance after arrival.")
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.target == outpost.id, context + " Seek Strongest falls back to a reachable outpost.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.SEEK_NEAREST)
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.target == outpost.id, context + " Seek Nearest uses the same strategic fallback.")
	battle.set_unit_stance(side, unit.id, MatchBattle.Stance.IDLE)
	var reserve := unit.position
	battle.advance(1.0, economy)
	_check(unit.position == reserve and unit.target == MatchBattle.NO_TARGET and unit.waypoints.is_empty(),
		context + " clears the strategic route when returning to reserve.")


func _test_threat_ranking() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var attacker := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.RANGED)
	var heavy := battle.spawn_unit(CPU, Vector2(0, -2.5), Catalog.HEAVY)
	var infantry := battle.spawn_unit(CPU, Vector2(0, 2), Catalog.INFANTRY)
	battle.set_unit_stance(PLAYER, attacker.id, MatchBattle.Stance.SEEK_STRONGEST)
	battle.set_unit_stance(CPU, heavy.id, MatchBattle.Stance.IDLE)
	battle.set_unit_stance(CPU, infantry.id, MatchBattle.Stance.IDLE)
	attacker.cooldown = 5.0
	heavy.hp = 10.0
	battle.target_priority = MatchBattle.TargetPriority.LOWEST_HP
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == heavy.id, "Strongest uses current DPS and HP independently of shot priority.")
	battle.stats.set_modifier(&"suppression", CPU, FactionStats.UNIT_DPS, -4.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == infantry.id, "An effective DPS reduction can change the threat ranking.")
	heavy.hp = infantry.hp
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == infantry.id, "Equal threat favors the closer unit.")
	heavy.position = -infantry.position
	var reordered: Dictionary[int, MatchBattle.Unit] = {
		attacker.id: attacker, infantry.id: infantry, heavy.id: heavy,
	}
	battle._units = reordered
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == heavy.id, "Equal threat and distance favor the lower ID independent of insertion order.")
	battle.stats.remove_source(&"suppression")
	heavy.hp = 1.0
	battle.threat_weights = Vector2(1.0, 0.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == heavy.id, "Changing the weights changes which effective stats drive the score.")


func _test_blocked_targets() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var attacker := battle.spawn_unit(PLAYER, Vector2(-1, 0))
	var trapped := battle.spawn_unit(CPU, Vector2(1, 0), Catalog.HEAVY)
	var reachable := battle.spawn_unit(CPU, Vector2(-1, -3))
	battle.set_unit_stance(CPU, trapped.id, MatchBattle.Stance.IDLE)
	battle.set_unit_stance(CPU, reachable.id, MatchBattle.Stance.IDLE)
	for stance in [MatchBattle.Stance.SEEK_NEAREST, MatchBattle.Stance.SEEK_STRONGEST]:
		battle.set_unit_stance(PLAYER, attacker.id, stance)
		battle.advance(MatchBattle.STEP, economy)
		_check(attacker.target == trapped.id, "The closer and stronger target is selected before the barrier.")
		var obstacle := battle.navigation.add_obstacle(Rect2(-0.25, -9, 0.5, 18))
		for step in 8:
			battle.advance(MatchBattle.STEP, economy)
			_check(attacker.target == reachable.id and attacker.position.x < -0.25,
				"The disconnected target is skipped without oscillating or crossing the barrier.")
		battle.navigation.remove_obstacle(obstacle)
		attacker.position = Vector2(-1, 0)
	trapped.hp = 0
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == reachable.id, "An unavailable target cannot retain a stale pursuit.")


func _test_tactical_hud() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var unit := battle.spawn_unit(PLAYER, Vector2(-4, 0), Catalog.HEAVY)
	var rival := battle.spawn_unit(CPU, Vector2(3, 1), Catalog.RANGED)
	battle.set_unit_stance(CPU, rival.id, MatchBattle.Stance.IDLE)
	await process_frame
	_click_at_world(scene._unit_views[unit.id].global_position)
	await process_frame
	var picker := scene.get_node("%StancePicker") as OptionButton
	var hold := scene.get_node("%HoldHere") as Button
	var hold_at := scene.get_node("%HoldOrder") as Button
	var move := scene.get_node("%MoveOrder") as Button
	var resume := scene.get_node("%ResumeStance") as CheckBox
	_check(scene.selected_unit() == unit and picker.visible and hold.visible and hold_at.visible
		and move.visible and resume.visible and resume.button_pressed,
		"Selecting a combat unit exposes the tactical HUD and defaults to resuming stance.")
	_click(picker)
	await process_frame
	var popup := picker.get_popup()
	_check(popup.visible, "The stance dropdown opens through the viewport.")
	scene._process(MatchBattle.STEP)
	_check(popup.visible, "Live updates keep the stance dropdown open.")
	_choose_stance(picker, MatchBattle.Stance.IDLE)
	await process_frame
	_check(unit.stance == MatchBattle.Stance.IDLE and picker.text == "Idle",
		"Choosing Idle updates the inspector and applies reserve stance immediately.")
	_click(hold)
	_check(unit.order == MatchBattle.Order.HOLD and unit.ordered_destination == unit.position,
		"Hold here defends the inspected unit's current position.")
	_click(hold_at)
	await process_frame
	_click_at_world(Vector3(-2, 0, -2))
	_check(unit.order == MatchBattle.Order.HOLD
		and unit.ordered_destination.is_equal_approx(Vector2(-2, -2)) and not unit.waypoints.is_empty(),
		"Hold at accepts a map click and exposes its route.")
	_click(move)
	await process_frame
	_click_at_world(Vector3(-2, 0, 2))
	_check(unit.order == MatchBattle.Order.MOVE and unit.resume_stance_on_arrival,
		"The Move button takes a destination with the resume option.")
	scene._process(2.5)
	_check(unit.order == MatchBattle.Order.AUTONOMOUS and unit.stance == MatchBattle.Stance.IDLE
		and unit.position.is_equal_approx(Vector2(-2, 2)), "The unit goes idle at the Move destination.")
	_click(picker)
	await process_frame
	_choose_stance(picker, MatchBattle.Stance.SEEK_STRONGEST)
	await process_frame
	_check(unit.stance == MatchBattle.Stance.SEEK_STRONGEST, "The HUD can reassign an offensive stance.")
	battle.visibility.set_source(-800012, PLAYER, rival.position, 1.0)
	scene._update_unit_view(rival, scene._unit_views[rival.id])
	_click_at_world(scene._unit_views[rival.id].global_position)
	_check(scene.selected_unit() == rival and not picker.is_visible_in_tree()
		and not move.is_visible_in_tree()
		and scene.get_node("%StanceLabel").text.contains(scene._stance_name(rival.stance)),
		"CPU inspection shows the stance chosen by the planner without player commands.")
	scene._select_unit(unit.id)
	scene._begin_unit_order(MatchBattle.Order.HOLD)
	scene.restart_match()
	scene.set_process(false)
	var fresh: MatchBattle.Unit = scene._battle.spawn_unit(PLAYER, Vector2(-4, 0), Catalog.HEAVY)
	scene._select_unit(fresh.id)
	_check(fresh.stance == MatchBattle.Stance.IDLE and fresh.order == MatchBattle.Order.AUTONOMOUS
		and picker.text == "Idle" and resume.button_pressed
		and scene._pending_unit_order == MatchBattle.Order.AUTONOMOUS,
		"Restart clears the tactical order, stance and pending click mode.")
	scene.free()


func _choose_stance(picker: OptionButton, stance: MatchBattle.Stance) -> void:
	var popup := picker.get_popup()
	# The embedded popup's item activation is delivered by index.
	popup.index_pressed.emit(picker.get_item_index(stance))
	popup.hide()


func _test_match_scene() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame

	var player_building := Vector3(-10.2, 0.0, -1.2)
	scene._process(2.0)
	_check(scene.try_place_building(PLAYER, &"barracks", player_building),
		"Build a player barracks alongside the autonomous CPU purchase.")
	scene._process(MatchEconomy.PRODUCTION_INTERVAL)
	var deployed := ScoutFixture.combat_units(scene._battle)
	if deployed.size() != 2:
		_check(false, "Both barracks must deploy a unit.")
		scene.free()
		return
	scene._battle.visibility.set_source(-800011, PLAYER, deployed[0].position, 3.0)
	scene._update_unit_view(deployed[0], scene._unit_views[deployed[0].id])
	var cpu_view := scene._unit_views[deployed[0].id] as MeshInstance3D
	var player_view := scene._unit_views[deployed[1].id] as MeshInstance3D
	var cpu_building := scene.get_node("Buildings/CPU").get_child(0) as Node3D
	_check(cpu_view.position.distance_to(cpu_building.position) < 2.0
		and player_view.position.distance_to(player_building) < 2.0
		and absf(player_view.position.z - 2.0) > 1.0,
		"Both factions deploy beside their producing structures, off the former route.")
	var cpu_start := cpu_view.position
	scene._process(0.25)
	_check(cpu_view.position == cpu_start, "The CPU deploys idle before an assault order.")
	var marker := scene.get_node("UnitSelection") as MeshInstance3D
	var panel := scene.get_node("%UnitInspection") as PanelContainer
	var unit_name := scene.get_node("%UnitName") as Label
	var stats := scene.get_node("%UnitStats") as Label
	var intent := scene.get_node("%UnitIntent") as Label
	var order_hint := scene.get_node("%UnitOrderHint") as Label
	var route := (scene.get_node("UnitRoute") as MeshInstance3D).mesh
	_click_at_world(cpu_view.global_position)
	var cpu: MatchBattle.Unit = scene.selected_unit()
	if cpu == null or cpu.side != CPU:
		_check(false, "Clicking the enemy token selects it.")
		scene.free()
		return
	_check(panel.visible and unit_name.text == "CPU Infantry #%d" % cpu.id
		and stats.text == "HP  12 / 12\nAttack  3 · Speed  1.584 units/s\nRange  0.9 · Cooldown  1s"
		and intent.text == "Target  —\nOrder  Autonomous\nState  Idle"
		and marker.global_position == cpu_view.global_position
		and not order_hint.visible and route.get_surface_count() == 0,
		"Enemy inspection shows the live stats, idle stance and selection ring. Stats: %s. Intent: %s." % [stats.text, intent.text])
	var destination := Vector3(-5.0, 0.0, -4.0)
	_click_at_world(destination, MOUSE_BUTTON_RIGHT)
	_check(cpu.order == MatchBattle.Order.AUTONOMOUS and scene.selected_unit() == cpu,
		"Right-clicking ground leaves an inspected CPU unit autonomous.")
	_click_at_world(player_view.global_position)
	var player: MatchBattle.Unit = scene.selected_unit()
	if player == null:
		_check(false, "Clicking the rendered friendly token selects it.")
		scene.free()
		return
	_check(marker.visible and marker.global_position == player_view.global_position,
		"The scene identifies the selected friendly unit with a ring.")
	_check(unit_name.text == "Player Infantry #%d" % player.id
		and intent.text == "Target  None\nOrder  Autonomous\nState  Idle" and order_hint.visible,
		"Switching to a friendly unit refreshes the name, target and move hint.")
	_click_at_world(destination, MOUSE_BUTTON_RIGHT)
	_check(player.ordered_destination.is_equal_approx(Vector2(destination.x, destination.z)),
		"A right-click issues a real move order through viewport input.")
	_check(intent.text == "Target  None\nOrder  Move\nState  Moving to order"
		and route.get_surface_count() == 1 and route.get_aabb().end.x > destination.x,
		"The route and panel refresh immediately to show the order destination.")
	_click_at_world(player_building, MOUSE_BUTTON_RIGHT)
	_click_at_world(cpu_view.global_position, MOUSE_BUTTON_RIGHT)
	_check(player.attack_order_id == cpu.id and player.order == MatchBattle.Order.ATTACK,
		"Right-clicking a visible enemy issues a focus order.")
	_click_at_world(destination, MOUSE_BUTTON_RIGHT)
	scene._process(0.5)
	var first_position := player_view.position
	scene.get_node("%ResumeStance").button_pressed = false
	var replacement := Vector3(-7.0, 0.0, -5.0)
	_click_at_world(replacement, MOUSE_BUTTON_RIGHT)
	scene._process(3.0)
	_check(player_view.position != first_position
		and player.position.is_equal_approx(Vector2(replacement.x, replacement.z))
		and player.order == MatchBattle.Order.HOLD and marker.global_position == player_view.global_position,
		"A second right-click supersedes the first and the visible unit and marker reach it.")
	_check(route.get_surface_count() == 0 and intent.text == "Target  None\nOrder  Hold\nState  Holding",
		"The route clears when the selected unit reaches its hold point.")

	cpu.position = player.position + Vector2(0.0, -2.0)
	scene._process(MatchBattle.STEP)
	_check(player.target == MatchBattle.NO_TARGET and intent.text.ends_with("State  Holding")
		and route.get_surface_count() == 0,
		"The inspected defender stays at its post when an enemy is outside weapon range.")
	cpu.position = player.position + Vector2(0.0, -0.55)
	scene._process(MatchBattle.STEP)
	_check(player.hp == 9 and stats.text.begins_with("HP  9 / 12")
		and intent.text.ends_with("State  Engaging") and route.get_surface_count() == 0,
		"Combat damage updates live and reaching attack range clears the route.")
	cpu.hp = 0
	scene._process(MatchBattle.STEP)
	_check(scene.selected_unit() == player and intent.text.begins_with("Target  None"),
		"Losing the target refreshes the panel while preserving the surviving selection.")

	_click_at_world(player_building)
	_check(scene.selected_unit() == null and panel.visible and unit_name.text == "Player Barracks"
		and not marker.visible and route.get_surface_count() == 0,
		"Clicking the barracks replaces unit inspection with its production details.")
	_click_at_world(Vector3(-10.0, 0.0, -5.9))
	_check(scene.selected_unit() == null and not panel.visible and not marker.visible
		and route.get_surface_count() == 0 and scene._selected_region_id == TerritoryLayout.PLAYER_START,
		"Clicking the map clears inspection and selects the underlying region.")
	_click_at_world(player_view.global_position)
	_check(scene._selected_region_id == &"", "Selecting a unit clears the region selection.")
	_press_escape()
	_check(scene.selected_unit() == null and not panel.visible, "Escape clears inspection.")

	_click_at_world(player_view.global_position)
	scene.economy.advance(10.0)
	scene._refresh_hud()
	_click(scene.get_node("%Build"))
	await process_frame
	var barracks_option: Button = scene._build_options[&"barracks"]
	(scene.get_node("%BuildScroll") as ScrollContainer).ensure_control_visible(barracks_option)
	await process_frame
	_click(barracks_option)
	_check(scene._preview != null and scene.selected_unit() == player and not panel.visible,
		"Entering placement hides inspection and retains the previous selection.")
	_click_at_world(player_view.global_position)
	_check(scene._pending_pick != Vector2.INF and scene.selected_unit() == player,
		"Clicks over a unit go to building placement while it is active.")
	_press_escape()
	_check(scene._preview == null and scene.selected_unit() == player and panel.visible,
		"Escape cancels placement and restores inspection.")

	_click_at_world(player_view.global_position)
	player.hp = 0
	scene._process(MatchBattle.STEP)
	_check(scene.selected_unit() == null and not marker.visible and not panel.visible
		and route.get_surface_count() == 0 and not player_view.is_inside_tree(),
		"Removing the selected unit clears inspection and the rendered view.")
	scene.free()


func _test_match_end_and_restart() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame

	var regions := scene.get_node("Regions")
	var initial_owners := _region_owners(regions)
	var player_base := scene.get_node("Regions/PlayerStart/PlayerBase") as Node3D
	var cpu_base := scene.get_node("Regions/CPUStart/CPUBase") as Node3D
	var player_hp := scene.get_node("%PlayerHP") as Label
	var cpu_hp := scene.get_node("%CPUHP") as Label
	var outcome := scene.get_node("%Outcome") as Label
	var build := scene.get_node("%Build") as Button
	var upgrade := scene.get_node("%ProductionUpgrade") as Button
	var restart := scene.get_node("%Restart") as Button
	var units := scene.get_node("Units")
	_check_full_reset(scene, initial_owners)

	# A staggered approach from opposite sides of the player base wins this layout.
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-12.0, 0, 5.0)),
		"The first barracks starts the player advance.")
	scene._process(14.0)
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-7.7, 0, -1.0)),
		"The player adds the second barracks at 14 seconds.")
	scene._process(8.0)
	_check(scene.try_place_building(PLAYER, &"farm", Vector3(-12.8, 0, -5.2)),
		"A Farm funds the player's upgraded barracks.")
	scene._process(20.0)
	_check(scene.try_upgrade(PLAYER, ScoutFixture.barracks(scene._battle, PLAYER).id), "The player upgrades before the deciding attack.")
	var battle: MatchBattle = scene._battle
	scene.economy.advance(30.0)
	_check(ScoutFixture.barracks(scene._battle, CPU).level == 2 or scene.try_upgrade(CPU, ScoutFixture.barracks(scene._battle, CPU).id),
		"The CPU has a paid upgrade to clear on restart.")
	# Give the player a clear victory fixture independent of CPU build priorities.
	scene._time_until_cpu_decision = 120.0
	scene._set_region_owner(&"region_1", PLAYER)
	scene._set_region_owner(TerritoryLayout.CPU_START, MatchRegion.Owner.NEUTRAL)
	for unit in battle.active_units():
		if unit.side == CPU:
			unit.hp = 0.0
	var attacker := battle.spawn_unit(PLAYER, battle._bases[CPU] + Vector2.DOWN * 1.92, Catalog.HEAVY,
		null, MatchBattle.Stance.SEEK_NEAREST)
	_check(attacker != null, "The victory fixture deploys a Heavy at the enemy base.")
	battle._base_health[CPU].hp = 1.0
	scene._process(MatchBattle.STEP)
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY and outcome.visible
		and outcome.text == "Victory" and player_base.visible and not cpu_base.visible
		and player_hp.text == "Player base · 420 HP" and cpu_hp.text == "CPU base · 0 HP",
		"Destroying the CPU base shows Victory and updates both base readouts. Got %s, %s, %s." % [
			outcome.text, player_hp.text, cpu_hp.text,
		])
	_check(units.get_child_count() > 0 and battle.elapsed_time() > 30.0,
		"The finished match still has units and elapsed time to clear.")
	_check(not scene.is_processing() and build.disabled and upgrade.disabled
		and not scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -2.4)) and not scene.try_upgrade(PLAYER, -999)
		and restart.visible and not restart.disabled,
		"Ending a match stops simulation and purchases while leaving Restart available.")

	_click(restart)
	_check(scene.is_processing(), "Restart re-enables automatic processing after Victory.")
	scene.set_process(false)
	_check_full_reset(scene, initial_owners)

	scene._process(1.75)
	_check(scene.economy.barracks_count(CPU) == 0, "CPU waits through its initial decision interval.")
	scene._process(0.25)
	_check(scene.economy.barracks_count(CPU) == 1 and is_equal_approx(scene.economy.energy(CPU), 14.5),
		"CPU resumes autonomous purchases using the starting energy and cadence.")
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2))
		and scene.economy.barracks_count(PLAYER) == 1 and is_equal_approx(scene.economy.energy(PLAYER), 14.5),
		"The player can place a barracks in the replay.")
	scene._process(4.0)
	_check(units.get_child_count() == 4, "Replay production does not inherit old timers.")
	scene._process(0.25)
	var replay_battle: MatchBattle = scene._battle
	var replay_units := ScoutFixture.combat_units(replay_battle)
	_check(units.get_child_count() == 6 and replay_units.size() == 2
		and replay_units[0].id == 5 and is_equal_approx(replay_battle.elapsed_time(), 6.25),
		"Both first barracks deploy on schedule with fresh unit IDs and match time.")

	_click(restart)
	scene.set_process(false)
	_check_full_reset(scene, initial_owners)
	var defeat_battle: MatchBattle = scene._battle
	for scout in defeat_battle.active_units():
		if scout.side == PLAYER:
			scout.position = Vector2(-12.0, -4.0)
	var siege := defeat_battle.spawn_unit(CPU, defeat_battle._bases[PLAYER] + Vector2.DOWN * 1.92,
		Catalog.HEAVY, null, MatchBattle.Stance.SEEK_NEAREST)
	_check(siege != null, "The defeat fixture deploys a Heavy at the player base.")
	scene._process(MatchBattle.STEP)
	_check(player_hp.text.begins_with("Player base") and defeat_battle.base_hp(PLAYER) < MatchBattle.BASE_HP
		and cpu_hp.text == "CPU base · Known start" and not outcome.visible,
		"The HUD reflects nonlethal base damage during play and masks enemy HP. Got %s, %s." % [player_hp.text, cpu_hp.text])
	defeat_battle._base_health[PLAYER].hp = 1.0
	scene._process(1.5)
	_check(scene._battle.outcome() == MatchBattle.Outcome.DEFEAT
		and outcome.visible and outcome.text == "Defeat"
		and not player_base.visible and not cpu_base.visible
		and player_hp.text == "Player base · 0 HP" and cpu_hp.text == "CPU base · Known start",
		"The replay ends in Defeat when the CPU destroys the player base. Got %s, %s, %s." % [outcome.text, player_hp.text, cpu_hp.text])
	_click(restart)
	_check(scene.is_processing(), "Restart re-enables automatic processing after Defeat.")
	_check_full_reset(scene, initial_owners)
	scene.free()


func _check_full_reset(scene: Node, initial_owners: Array) -> void:
	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var regions := scene.get_node("Regions")
	_check(_region_owners(regions) == initial_owners, "Restart restores initial ownership.")
	for region: MatchRegion in regions.get_children():
		var material := region.geometry.material_override as StandardMaterial3D
		var memory: Dictionary = scene._intelligence[PLAYER].regions.get(region.region_id, {})
		var color: Color = MatchRegion.OWNER_COLORS[memory.get("side", MatchRegion.Owner.NEUTRAL)]
		if region.specialty_marker != null and not memory.is_empty():
			color = color.lerp(RegionSpecialty.TRAITS[region.specialty].color, 0.15)
		_check(material.albedo_color == color,
			"Region color reflects its restored ownership.")
	for side in [PLAYER, CPU]:
		var start_region := "PlayerStart" if side == PLAYER else "CPUStart"
		var base := scene.get_node("Regions/%s/%sBase" % [
			start_region, "Player" if side == PLAYER else "CPU",
		]) as Node3D
		_check(base.visible == (side == PLAYER) and battle.base_hp(side) == MatchBattle.BASE_HP,
			"Restart restores both bases and their HP.")
		_check(economy.energy(side) == MatchEconomy.STARTING_ENERGY
			and economy.stockpile(side, MatchEconomy.MATERIALS) == 30.0
			and economy.stockpile(side, MatchEconomy.FOOD) == 20.0
			and economy.barracks_count(side) == 0 and scene._battle._timers.is_empty(),
			"Restart restores all starting stockpiles and clears barracks and upgrades for each side.")
	_check(scene.get_node("Buildings/Player").get_child_count() == 0
		and scene.get_node("Buildings/CPU").get_child_count() == 0,
		"Restart removes all placed buildings.")
	_check(ScoutFixture.combat_units(battle).is_empty() and scene.get_node("Units").get_child_count() == 4
		and battle.elapsed_time() == 0.0 and battle.outcome() == MatchBattle.Outcome.IN_PROGRESS,
		"Restart clears units, match time and the recorded outcome.")
	_check(scene.get_node("%PlayerHP").text == "Player base · 420 HP"
		and scene.get_node("%CPUHP").text == "CPU base · Known start"
		and scene.get_node("%Resources/energy/Stockpile").text == "Energy 50"
		and not scene.has_node("%BarracksCount")
		and not scene.get_node("%Outcome").visible and not scene.get_node("%Build").disabled
		and scene.get_node("%ProductionUpgrade").disabled and not scene.get_node("%ProductionUpgrade").visible,
		"The HUD refreshes to its starting readouts and purchase controls.")


func _click(button: Button) -> void:
	_click_at(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)


func _click_at_world(point: Vector3, button := MOUSE_BUTTON_LEFT) -> void:
	_click_at(root.get_camera_3d().unproject_position(point), button)


func _click_at(point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _with_barracks(sides: Array) -> MatchBattle:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	for side in sides:
		var timer := battle.add_barracks(side, Vector2(PLAYER_BASE.x if side == PLAYER else CPU_BASE.x, -3.0))
		battle.set_producer_stance(side, timer.id, MatchBattle.Stance.SEEK_NEAREST)
	return battle


func _unit_state(battle: MatchBattle) -> Array:
	var state := []
	for unit in battle.active_units():
		state.append([unit.id, unit.side, unit.position, unit.hp, unit.target, unit.cooldown])
	return state


func _region_owners(regions: Node) -> Array:
	var owners := []
	for region: MatchRegion in regions.get_children():
		owners.append(region.region_owner)
	return owners


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
