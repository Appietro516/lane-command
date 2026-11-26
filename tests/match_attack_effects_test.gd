extends SceneTree

const Catalog := preload("res://match/unit_catalog.gd")
const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Effects := preload("res://match/unit_attack_effects.gd")
const PLAYER := MatchBattle.PLAYER
const CPU := MatchBattle.CPU
const STEP := MatchBattle.STEP
const PLAYER_BASE := Vector2(-12.0, 0.0)
const CPU_BASE := Vector2(12.0, 0.0)

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for type_id: StringName in Catalog.OFFENSIVE_TYPES:
		_test_cadence(type_id)
		_test_structure(type_id, &"base")
		_test_structure(type_id, &"outpost")
		_test_structure(type_id, &"farm")
	_test_blocked_and_out_of_range()
	_test_lethal_attacks()
	_test_partitioning()
	await _test_scene()
	if _failures == 0:
		print("Attack events, simulation-synced effects and sustained combat checks passed.")
	quit(1 if _failures else 0)


func _test_cadence(type_id: StringName) -> void:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var events: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(events.append)
	var economy := MatchEconomy.new()
	var attacker := battle.spawn_unit(PLAYER, Vector2.ZERO, type_id)
	# Exercise a non-catalog effective interval without relying on the presentation profile.
	attacker.attack_interval = STEP * 30.0
	var target := battle._spawn_unit(CPU, Vector2(attacker.definition.range, 0.0), Catalog.SCOUT)
	var initial_hp := target.hp
	battle.advance(STEP * 0.5, economy)
	_check(events.is_empty() and target.hp == initial_hp, "Partial steps do not resolve attacks.")
	battle.advance(STEP * 0.5, economy)
	_check(events.size() == 1 and target.hp < initial_hp, "%s emits once on damage." % type_id)
	if events.size() != 1:
		return
	_check_event(events[0], attacker, target.id, target.position, STEP)
	battle.advance(attacker.attack_interval - STEP, economy)
	_check(events.size() == 1, "%s stays quiet during its effective cooldown." % type_id)
	battle.advance(STEP, economy)
	_check(events.size() == 2 and is_equal_approx(target.hp, initial_hp - attacker.definition.damage * 2.0),
		"%s applies and reports the next hit together." % type_id)
	if events.size() == 2:
		_check_event(events[1], attacker, target.id, target.position, STEP + attacker.attack_interval)


func _test_structure(type_id: StringName, kind: StringName) -> void:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var events: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(events.append)
	var target_id := MatchBattle.BASE_TARGET
	var position := CPU_BASE
	var offset := minf(1.92, float(Catalog.DEFINITIONS[type_id].range) + 0.88)
	var building: MatchBattle.BuildingHealth
	match kind:
		&"outpost":
			position = Vector2.ZERO
			offset = 0.95
			var outpost := battle.add_outpost(&"fixture", CPU, position, 1)
			building = outpost
			target_id = outpost.id
		&"farm":
			position = Vector2.ZERO
			offset = 1.08
			var farm := battle.add_structure(kind, {"hp": 1.0, "size": Vector2.ONE}, CPU, position)
			building = farm
			target_id = farm.id
	var attacker := battle.spawn_unit(PLAYER, position - Vector2(offset, 0.0), type_id)
	var economy := MatchEconomy.new()
	battle.advance(STEP, economy)
	_check(events.size() == 1, "%s reports hitting %s." % [type_id, kind])
	if events.size() == 1:
		_check_event(events[0], attacker, target_id, position, STEP)
	if building != null:
		_check(building.hp == 0.0 and battle.get_fortification(target_id) == null
			and battle.get_outpost(target_id) == null, "Destroyed structures retain a contact position in the event.")
	else:
		var damage: float = attacker.definition.damage * attacker.definition.structure_damage_multiplier
		_check(is_equal_approx(battle.base_hp(CPU), MatchBattle.BASE_HP - damage),
			"The base hit applies catalog structure damage.")


func _test_blocked_and_out_of_range() -> void:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var events: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(events.append)
	var attacker := battle.spawn_unit(PLAYER, Vector2(-1.0, 0.0), Catalog.RANGED)
	var target := battle._spawn_unit(CPU, Vector2(1.9, 0.0), Catalog.SCOUT)
	var economy := MatchEconomy.new()
	battle.advance(STEP, economy)
	_check(events.is_empty() and target.hp == 10.0 and attacker.position.x > -1.0,
		"Chasing an out-of-range target applies no damage and emits no attack.")
	target.position.x = 1.0
	var wall := battle.navigation.add_obstacle(Rect2(-0.2, -1.0, 0.4, 2.0))
	battle.advance(STEP, economy)
	_check(events.is_empty() and target.hp == 10.0, "Obstructed line of fire emits no attack.")
	battle.navigation.remove_obstacle(wall)
	battle.stats.set_modifier(&"test", PLAYER, FactionStats.UNIT_DPS, -100.0)
	battle.advance(STEP, economy)
	_check(events.is_empty() and target.hp == 10.0, "An attack that applies zero damage emits no event.")


func _test_lethal_attacks() -> void:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var events: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(events.append)
	var attacker := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.INFANTRY)
	var second := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.INFANTRY)
	var target := battle.spawn_unit(CPU, Vector2(0.5, 0.0), Catalog.INFANTRY)
	attacker.hp = 1.0
	target.hp = 1.0
	battle.advance(STEP, MatchEconomy.new())
	_check(events.size() == 2 and battle.get_unit(target.id) == null
		and battle.get_unit(attacker.id) == null and battle.get_unit(second.id) != null,
		"A lethal hit and its simultaneous counterattack resolve, with no shot at the fallen target.")
	if events.size() == 2:
		_check_event(events[0], attacker, target.id, target.position, STEP)
		_check(events[1].attacker_side == CPU and events[1].target_side == PLAYER
			and events[1].attacker_id == target.id and events[1].target_id == attacker.id,
			"The simultaneous counterattack identifies the opposing side and original target.")


func _test_partitioning() -> void:
	var regular := _sample_battle([STEP * 120.0])
	var partitioned := _sample_battle([0.125, 0.375, 0.4, 0.1, 1.0])
	var without_listener := _sample_battle([2.0], false)
	_check(not regular.events.is_empty() and regular == partitioned,
		"Event payloads and battle state are identical across delta partitions.")
	_check(regular.hp == without_listener.hp,
		"Attaching a presentation observer does not affect combat damage.")


func _sample_battle(deltas: Array, listen := true) -> Dictionary:
	var battle := MatchBattle.new(PLAYER_BASE, CPU_BASE)
	var events := []
	if listen:
		battle.attack_resolved.connect(func(event: MatchBattle.AttackResolved) -> void:
			events.append([event.attacker_id, event.attacker_type, event.attacker_side, event.target_id,
				event.target_side, event.attack_position, event.impact_position, event.simulation_time]))
	battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.RANGED)
	var target := battle._spawn_unit(CPU, Vector2(2.0, 0.0), Catalog.SCOUT)
	var economy := MatchEconomy.new()
	for delta: float in deltas:
		battle.advance(delta, economy)
	return {"events": events, "hp": target.hp}


func _test_scene() -> void:
	var scene := Fixture.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene._time_until_cpu_decision = 120.0
	var battle: MatchBattle = scene._battle
	var effects: MeshInstance3D = scene._unit_attack_effects
	var batch := effects.mesh as ImmediateMesh
	var attacker := battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.HEAVY)
	var target := battle._spawn_unit(CPU, Vector2(0.7, 0.0), Catalog.SCOUT)
	target.hp = 1.0
	scene._process(STEP)
	_check(batch.get_surface_count() == 1 and battle.get_unit(target.id) == null,
		"The live scene renders a pulse even when the target was removed this step.")
	var bounds := batch.get_aabb()
	paused = true
	scene.set_process(true)
	await process_frame
	await process_frame
	scene.set_process(false)
	_check(is_equal_approx(battle.elapsed_time(), STEP) and batch.get_aabb() == bounds,
		"Pausing freezes both the fixed clock and the drawn cue.")
	paused = false
	scene._process(STEP * 6.0)
	_check(batch.get_surface_count() == 1 and batch.get_aabb() != bounds,
		"The pulse advances when simulation resumes.")
	scene._process(0.5)
	_check(batch.get_surface_count() == 0 and effects._cues.is_empty(),
		"Expired cues release their snapshots and geometry.")
	attacker.hp = 0.0
	scene._process(STEP)

	# Sustained mixed-unit combat, preceded by a burst beyond the retention limit.
	battle.stats.set_modifier(&"stress", CPU, FactionStats.UNIT_MAX_HP, 1000000.0)
	target = battle._spawn_unit(CPU, Vector2(0.55, 0.0), Catalog.SCOUT)
	for index in MatchBattle.MILITARY_UNIT_CAP:
		var type_id: StringName = Catalog.OFFENSIVE_TYPES[index % Catalog.OFFENSIVE_TYPES.size()]
		var unit := battle.spawn_unit(PLAYER, Vector2(0.0, (index % 7 - 3) * 0.08), type_id)
		unit.attack_interval = STEP
	for index in 12:
		scene._process(STEP)
	_check(effects._cues.size() == Effects.MAX_CUES and batch.get_surface_count() == 1
		and effects.get_child_count() == 0, "A burst saturates the fixed capacity in one batched mesh.")
	for unit in battle.active_units():
		unit.attack_interval = unit.definition.cooldown
	for index in 300:
		scene._process(STEP)
		_check(effects._cues.size() <= Effects.MAX_CUES and batch.get_surface_count() <= 1,
			"Sustained combat stays within the transient effect budget.")
	_check(target.hp < 1000000.0 and effects.get_child_count() == 0,
		"The stress fixture applies continuous damage without accumulating effect nodes.")

	scene.restart_match()
	scene.set_process(false)
	_check(effects._cues.is_empty() and batch.get_surface_count() == 0,
		"Restart clears the active batch before the fresh battle begins.")
	battle = scene._battle
	for unit in battle.active_units():
		unit.hp = 0.0
	scene._time_until_cpu_decision = 120.0
	battle.stats.set_modifier(&"deciding_hit", PLAYER, FactionStats.UNIT_DPS, 100.0)
	var base := scene.get_node("Regions/CPUStart/CPUBase") as Node3D
	var base_position: Vector2 = scene._map_position(base.global_position)
	battle.spawn_unit(PLAYER, base_position - Vector2(1.92, 0.0), Catalog.HEAVY)
	scene._process(STEP)
	_check(battle.is_finished() and batch.get_surface_count() == 1 and effects._cues.size() == 1,
		"The match-ending hit is rendered on the final simulation step.")
	scene._process(1.0)
	_check(is_equal_approx(battle.elapsed_time(), STEP) and effects._cues.size() == 1,
		"The ended match produces no new attacks.")
	scene.free()
	_check(not is_instance_valid(effects), "Scene exit frees the shared effect mesh node.")


func _check_event(event: MatchBattle.AttackResolved, attacker: MatchBattle.Unit, target_id: int,
		impact: Vector2, time: float) -> void:
	_check(event.attacker_id == attacker.id and event.attacker_type == attacker.type_id
		and event.attacker_side == attacker.side and event.target_id == target_id
		and event.target_side == CPU and event.attack_position == attacker.position
		and event.impact_position == impact and is_equal_approx(event.simulation_time, time),
		"Attack event carries the correct participants, positions and fixed-step timestamp.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
