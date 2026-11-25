extends SceneTree

const Catalog := preload("res://match/unit_catalog.gd")
const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Fortifications := preload("res://match/fortification_rules.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const PLAYER_BASE := Vector2(-12.0, 0.0)
const CPU_BASE := Vector2(12.0, 0.0)
const STEP := MatchBattle.STEP

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deployment_and_buffs()
	for type_id: StringName in Catalog.DEFINITIONS:
		_test_attack_range_and_cooldown(type_id)
		_test_structures(type_id)
		_test_orders_and_wall(type_id)
	_test_ranged_targeting()
	_test_delta_partition()
	await _test_selection_and_restart()
	if failures == 0:
		print("Typed deployment, combat, navigation, inspection and restart checks passed.")
	quit(1 if failures else 0)


func _test_deployment_and_buffs() -> void:
	var infantry: Dictionary = Catalog.DEFINITIONS[Catalog.INFANTRY]
	var ranged: Dictionary = Catalog.DEFINITIONS[Catalog.RANGED]
	var heavy: Dictionary = Catalog.DEFINITIONS[Catalog.HEAVY]
	_check(ranged.hp < infantry.hp and ranged.range > infantry.range
		and ranged.cooldown < infantry.cooldown and heavy.hp > infantry.hp
		and heavy.speed < infantry.speed and heavy.food > infantry.food
		and heavy.structure_damage_multiplier > 1.0, "Roster defaults create distinct roles.")
	var stats := FactionStats.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE, MatchBattle.DEFAULT_AGGRO_RADIUS,
		MatchBattle.DEFAULT_BOUNDS, stats)
	var economy := MatchEconomy.new(stats)
	var deployed: Array[MatchBattle.Unit] = []
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void: deployed.append(unit))

	for side: MatchRegion.Owner in [PLAYER, CPU]:
		stats.set_modifier(&"training", side, FactionStats.UNIT_DPS, 1.0)
		stats.set_modifier(&"training", side, FactionStats.UNIT_SPEED, 0.5)
		stats.set_modifier(&"training", side, FactionStats.UNIT_MAX_HP, 4.0)
		var stock := economy.stockpile(side, MatchEconomy.FOOD)
		var base := PLAYER_BASE if side == PLAYER else CPU_BASE
		_check(battle.spawn_unit(side, base, Catalog.INFANTRY, economy) == null
			and battle.spawn_unit(side, Vector2.ZERO, &"unknown", economy) == null
			and economy.stockpile(side, MatchEconomy.FOOD) == stock,
			"Invalid site and type leave Food untouched for side %d." % side)
		for type_id: StringName in Catalog.DEFINITIONS:
			var profile: Dictionary = Catalog.DEFINITIONS[type_id]
			var unit := battle.spawn_unit(side, Vector2.ZERO, type_id, economy)
			stock -= profile.food
			_check(unit != null and unit.type_id == type_id and unit.id == deployed.size()
				and unit.side == side and economy.stockpile(side, MatchEconomy.FOOD) == stock,
				"Both sides deploy %s at the catalog Food cost with sequential IDs." % type_id)
			if unit == null:
				continue
			var attack := battle.unit_attack_stat(unit)
			_check(unit.hp == profile.hp + 4.0 and battle.unit_health_stat(unit).total == unit.hp
				and is_equal_approx(attack.total, profile.damage + profile.cooldown)
				and is_equal_approx(attack.breakdown[1].magnitude, profile.cooldown)
				and battle.unit_speed_stat(unit).total == profile.speed + 0.5,
				"%s uses its own baselines and exposes faction modifiers." % type_id)
		_check(battle.spawn_unit(side, Vector2.ZERO, Catalog.HEAVY, economy) == null
			and economy.stockpile(side, MatchEconomy.FOOD) == stock,
			"An unaffordable deployment leaves Food untouched.")
		stats.set_source_active(&"training", false)
		for unit in deployed:
			if unit.side == side:
				_check(unit.hp == unit.definition.hp, "Removing a HP buff clamps %s." % unit.type_id)

	_check(deployed.size() == 6 and battle.active_units() == deployed,
		"Only successful spawns register and emit deployment.")


func _test_attack_range_and_cooldown(type_id: StringName) -> void:
	var profile: Dictionary = Catalog.DEFINITIONS[type_id]
	var economy := MatchEconomy.new()
	var outside := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var unit := outside.spawn_unit(PLAYER, Vector2.ZERO, type_id)
	var enemy := outside.spawn_unit(CPU, Vector2(profile.range + 0.02, 0.0), type_id)
	outside.advance(STEP, economy)
	_check(unit.hp == profile.hp and enemy.hp == profile.hp and unit.position.x > 0.0,
		"%s approaches without firing just outside range." % type_id)

	var duel := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	duel.stats.set_modifier(&"player_training", PLAYER, FactionStats.UNIT_DPS, 1.0)
	duel.stats.set_modifier(&"cpu_training", CPU, FactionStats.UNIT_DPS, 1.0)
	var effective_damage: float = profile.damage + profile.cooldown
	unit = duel.spawn_unit(PLAYER, Vector2.ZERO, type_id)
	enemy = duel.spawn_unit(CPU, Vector2(profile.range, 0.0), type_id)
	var removed: Array[int] = []
	duel.unit_removed.connect(func(id: int) -> void: removed.append(id))
	duel.advance(STEP, economy)
	var hp_after_hit: float = profile.hp - effective_damage
	_check(is_equal_approx(unit.hp, hp_after_hit) and unit.hp == enemy.hp
		and unit.cooldown == profile.cooldown and unit.position == Vector2.ZERO
		and unit.target == enemy.id and enemy.target == unit.id,
		"%s attacks at the boundary with symmetric damage and stops moving." % type_id)
	duel.advance(profile.cooldown - STEP, economy)
	_check(is_equal_approx(unit.hp, hp_after_hit) and unit.hp == enemy.hp,
		"%s waits for its configured cooldown." % type_id)
	duel.advance(STEP, economy)
	_check(is_equal_approx(unit.hp, hp_after_hit - effective_damage) and unit.hp == enemy.hp,
		"%s fires again at the configured cooldown." % type_id)
	duel.advance(10.0, economy)
	_check(duel.active_units().is_empty() and removed == [unit.id, enemy.id],
		"%s resolves simultaneous casualties for both sides." % type_id)


func _test_structures(type_id: StringName) -> void:
	var profile: Dictionary = Catalog.DEFINITIONS[type_id]
	var damage: float = profile.damage * profile.structure_damage_multiplier
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var outpost := battle.add_outpost(&"middle", CPU, Vector2.ZERO, 24)
	var attacker := battle.spawn_unit(PLAYER, Vector2(-4.0, 0.0), type_id)
	for step in range(180):
		if outpost.hp < outpost.max_hp:
			break
		battle.advance(STEP, economy)
	_check(is_equal_approx(outpost.hp, outpost.max_hp - damage) and attacker.target == outpost.id,
		"%s approaches the opposing outpost and applies its catalog damage." % type_id)

	battle = MatchBattle.new(PLAYER_BASE, CPU_BASE)
	for side: MatchRegion.Owner in [PLAYER, CPU]:
		var direction := 1.0 if side == PLAYER else -1.0
		battle.spawn_unit(side, Vector2(7.0 * direction, 0.0), type_id)
	battle.advance(3.0, economy)
	_check(battle.base_hp(PLAYER) == battle.base_hp(CPU)
		and battle.base_hp(CPU) <= MatchBattle.BASE_HP - damage,
		"%s attacks bases from either faction under the same rules." % type_id)


func _test_orders_and_wall(type_id: StringName) -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE, MatchBattle.DEFAULT_AGGRO_RADIUS,
		Rect2(-15.0, -0.5, 30.0, 1.0))
	var wall := battle.add_fortification(Fortifications.WALL, CPU, Vector2.ZERO, PI * 0.5)
	var start := Vector2(-3.0, 0.0)
	var destination := Vector2(3.0, 0.0)
	var unit := battle.spawn_unit(PLAYER, start, type_id)
	_check(battle.issue_move(unit.id, destination), "%s accepts a move through a hostile wall." % type_id)
	battle.stats.set_modifier(&"training", PLAYER, FactionStats.UNIT_SPEED, 0.5)
	battle.advance(STEP, economy)
	_check(is_equal_approx(unit.position.distance_to(start), (unit.definition.speed + 0.5) * STEP),
		"%s moves using its configured speed and faction modifier." % type_id)
	battle.advance(24.0, economy)
	_check(battle.get_fortification(wall.id) == null and unit.order == MatchBattle.Order.HOLD
		and unit.position == destination, "%s breaches the wall and resumes its order." % type_id)

	battle = MatchBattle.new(PLAYER_BASE, CPU_BASE)
	battle.navigation.add_obstacle(Rect2(-1.0, -1.0, 2.0, 2.0))
	unit = battle.spawn_unit(PLAYER, start, type_id)
	var clearance: float = unit.definition.clearance
	var obstacle_edge := Vector2(-1.0 - maxf(0.01, clearance * 0.5), 0.0)
	_check(battle.navigation.with_clearance(clearance).is_passable(obstacle_edge) == (clearance == 0.0),
		"%s uses its catalog clearance near a static footprint." % type_id)
	_check(battle.issue_move(unit.id, destination) and unit.waypoints.size() > 1
		and absf(unit.waypoints[0].y) > 1.0 + clearance,
		"%s detours around the expanded footprint." % type_id)
	battle.advance(6.0, economy)
	_check(unit.position == destination, "%s reaches a move order past a footprint." % type_id)


func _test_ranged_targeting() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	battle.target_priority = MatchBattle.TargetPriority.LOWEST_HP
	var ranged := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.RANGED)
	var weak := battle.spawn_unit(CPU, Vector2(3.5, 0.0), Catalog.INFANTRY)
	var exposed := battle.spawn_unit(CPU, Vector2(2.0, 0.0), Catalog.HEAVY)
	weak.hp = 1.0
	battle.advance(STEP, economy)
	_check(ranged.target == exposed.id and exposed.hp < exposed.definition.hp and weak.hp == 1.0,
		"Ranged shoots a reachable target ahead of pursuing a lower-HP enemy.")
	battle.navigation.add_obstacle(Rect2(0.9, -0.5, 0.2, 1.0))
	ranged.cooldown = 0.0
	var hp := exposed.hp
	battle.advance(STEP, economy)
	_check(exposed.hp == hp and not ranged.can_attack_target,
		"A wall blocks a ranged shot even when the target is inside weapon range.")


func _test_delta_partition() -> void:
	var whole := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var split := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	for battle in [whole, split]:
		var lane := -5.0
		for type_id: StringName in Catalog.DEFINITIONS:
			battle.spawn_unit(PLAYER, Vector2(-4.0, lane), type_id)
			battle.spawn_unit(CPU, Vector2(4.0, lane), type_id)
			lane += 5.0
	var economy := MatchEconomy.new()
	whole.advance(3.51, economy)
	for delta in [0.13, 1.83, 0.21, 1.34]:
		split.advance(delta, economy)
	_check(_snapshot(whole) == _snapshot(split),
		"Delta partitioning leaves mixed-roster movement, targets and damage identical.")


func _snapshot(battle: MatchBattle) -> Array:
	var state := []
	for unit in battle.active_units():
		state.append([unit.id, unit.type_id, unit.position, unit.hp, unit.target, unit.cooldown])
	return state


func _test_selection_and_restart() -> void:
	root.size = Vector2i(1280, 800)
	var scene := Fixture.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var camera := root.get_camera_3d()
	var battle: MatchBattle = scene._battle
	var x := -4.0
	for type_id: StringName in Catalog.DEFINITIONS:
		var profile: Dictionary = Catalog.DEFINITIONS[type_id]
		var unit := battle.spawn_unit(PLAYER, Vector2(x, -1.0), type_id)
		var view := scene.get_node("Units").get_child(-1) as MeshInstance3D
		_click(camera.unproject_position(view.global_position), MOUSE_BUTTON_LEFT)
		var stats: Label = scene.get_node("%UnitStats")
		_check(scene.selected_unit() == unit and scene.get_node("%UnitInspection").visible
			and scene.get_node("%UnitName").text == "Player %s #%d" % [profile.label, unit.id]
			and stats.text.contains("Range  %s" % profile.range)
			and stats.text.contains("Cooldown  %ss" % String.num(profile.cooldown, 2).trim_suffix(".0")),
			"Clicking %s identifies its type and weapon stats." % type_id)
		_click(camera.unproject_position(Vector3(x, 0.0, 1.0)), MOUSE_BUTTON_RIGHT)
		_check(unit.order == MatchBattle.Order.MOVE and
			scene.get_node("%UnitIntent").text.contains("Order  Move"),
			"The selected %s accepts a move order through the scene." % type_id)
		x += 3.0
	scene.restart_match()
	scene.set_process(false)
	_check(scene.selected_unit() == null and scene.get_node("Units").get_child_count() == 0
		and not scene.get_node("%UnitInspection").visible and scene._battle.active_units().is_empty(),
		"Restart clears typed units, views and inspection.")
	var first: MatchBattle.Unit = scene._battle.spawn_unit(CPU, Vector2.ZERO, Catalog.HEAVY)
	_check(first != null and first.id == 1 and first.hp == first.definition.hp,
		"Restart resets deployment IDs and HP.")
	scene.free()


func _click(pointer: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = pointer
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
