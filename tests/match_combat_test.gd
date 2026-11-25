extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CORRIDOR_LENGTH := 20.4

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_movement_and_delta_partition()
	_test_duel_and_cleanup()
	_test_target_priority(PLAYER, CPU)
	_test_target_priority(CPU, PLAYER)
	_test_base_destruction(PLAYER, CPU)
	_test_base_destruction(CPU, PLAYER)
	_test_match_scene()
	_test_match_end()
	if failures == 0:
		print("Corridor movement, combat rules and match scene checks passed.")
	quit(1 if failures else 0)


func _test_movement_and_delta_partition() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU])
	var split_battle := _with_barracks([PLAYER, CPU])
	battle.advance(4.5, economy)
	for delta in [0.031, 1.217, 2.002, 1.25]:
		split_battle.advance(delta, economy)
	var units := battle.active_units()
	_check(units.size() == 2, "Both sides deploy one unit.")
	if units.size() != 2:
		return
	_check(units[0].side == PLAYER and units[1].side == CPU
		and is_equal_approx(units[0].position, 1.75 + MatchBattle.MOVEMENT_SPEED)
		and is_equal_approx(units[1].position, CORRIDOR_LENGTH - units[0].position),
		"Both units march toward the enemy base for the time since deployment.")
	_check(units[0].hp == 12 and units[1].hp == 12,
		"Fresh units start at 12 HP.")
	_check(battle.base_hp(PLAYER) == 80 and battle.base_hp(CPU) == 80,
		"Both bases start at 80 HP.")

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
	battle.advance(3.5, economy)
	var units := battle.active_units()
	if units.size() != 2:
		_check(false, "Both duelists must spawn.")
		return
	var player := units[0]
	var cpu := units[1]

	for step in range(300):
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
	var survivors := battle.active_units()
	_check(not survivors.has(player) and not survivors.has(cpu) and survivors.size() == 2,
		"The next wave stays active after the duelists die.")


func _test_target_priority(attacker_side: MatchRegion.Owner, defender_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([attacker_side, defender_side, defender_side])
	battle.advance(3.5, economy)
	var units := battle.active_units()
	if units.size() != 3:
		_check(false, "Three units must spawn for the target priority check.")
		return
	var attacker := units[0]
	var farther := units[1]
	var nearer := units[2]
	var direction := 1.0 if attacker_side == PLAYER else -1.0
	attacker.position = CORRIDOR_LENGTH - 1.8 if attacker_side == PLAYER else 1.8
	farther.position = attacker.position + direction * 0.75
	nearer.position = attacker.position + direction * 0.5

	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == nearer.id and nearer.hp == 9 and farther.hp == 12
		and battle.base_hp(defender_side) == 80,
		"The nearest opposing unit takes priority over a farther unit and a base in range.")
	var far_end := 0.0 if attacker_side == PLAYER else CORRIDOR_LENGTH
	nearer.position = far_end
	farther.position = far_end
	battle.advance(1.0, economy)
	_check(attacker.target == MatchBattle.BASE_TARGET and battle.base_hp(defender_side) == 77,
		"The unit attacks the opposing base once there are no opposing units in range.")


func _test_base_destruction(attacker_side: MatchRegion.Owner, defender_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([attacker_side])
	var destroyed: Array[MatchRegion.Owner] = []
	battle.base_destroyed.connect(func(side: MatchRegion.Owner) -> void: destroyed.append(side))
	battle.advance(10.5, economy)
	_check(battle.base_hp(defender_side) == 80, "A distant base takes no damage.")
	battle.advance(0.25, economy)
	_check(battle.base_hp(defender_side) == 77, "An undefended base in close range takes 3 damage.")
	battle.advance(60.0, economy)
	_check(battle.is_finished() and battle.base_hp(defender_side) == 0
		and battle.base_hp(attacker_side) == 80 and destroyed == [defender_side],
		"A destroyed base reaches zero HP and finishes combat once.")

	var final_units := _unit_state(battle)
	battle.advance(60.0, economy)
	_check(not final_units.is_empty() and _unit_state(battle) == final_units
		and destroyed == [defender_side],
		"After destruction, further time causes no spawning, movement, attacks or cooldown changes.")


func _test_match_scene() -> void:
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var units := scene.get_node("Units") as Node3D
	var regions := scene.get_node("Regions")
	# Deliberately vary ownership across the same corridor to exercise both and neutral.
	regions.get_node("Northwest").region_owner = CPU
	regions.get_node("Southeast").region_owner = PLAYER
	var initial_owners := _region_owners(regions)

	scene._process(2.0)
	_check(scene.try_build(PLAYER), "Build a player barracks alongside the autonomous CPU purchase.")
	scene._process(3.5)
	if units.get_child_count() != 2:
		_check(false, "Both barracks must deploy a cube.")
		scene.free()
		return
	var cpu_view := units.get_child(0) as MeshInstance3D
	var player_view := units.get_child(1) as MeshInstance3D
	var cpu_start := cpu_view.position
	var player_start := player_view.position
	scene._process(3.5)
	var x_gap := cpu_view.position.x - player_view.position.x
	var corridor_z: float = scene.get_node("Corridor").position.z
	_check(cpu_view.position.x < cpu_start.x and player_view.position.x > player_start.x
		and is_equal_approx(cpu_view.position.z, corridor_z)
		and is_equal_approx(player_view.position.z, corridor_z)
		and x_gap > 0.0 and x_gap <= MatchBattle.UNIT_ATTACK_RANGE,
		"The scene renders both waves meeting along the straight corridor.")
	var battle: MatchBattle = scene._battle
	_check(battle.active_units().size() == 4 and battle.active_units()[0].hp == 9
		and battle.active_units()[1].hp == 9, "The initial cubes exchange damage in the match scene.")
	scene._process(3.0)
	_check(not cpu_view.is_inside_tree() and not player_view.is_inside_tree()
		and units.get_child_count() == battle.active_units().size(),
		"The scene removes dead cubes and still renders the active units.")
	_check(_region_owners(regions) == initial_owners, "Moving and fighting leave region ownership unchanged.")
	scene.free()


func _test_match_end() -> void:
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene._process(60.0)
	var battle: MatchBattle = scene._battle
	var player_base := scene.get_node("Regions/PlayerStart/PlayerBase") as Node3D
	var cpu_base := scene.get_node("Regions/CPUStart/CPUBase") as Node3D
	var build := scene.get_node("%Build") as Button
	var upgrade := scene.get_node("%Upgrade") as Button
	_check(battle.is_finished() and not player_base.visible and cpu_base.visible,
		"The CPU destroys the idle player's base and the scene hides it.")
	_check(not scene.is_processing() and build.disabled and upgrade.disabled
		and not scene.try_build(PLAYER) and not scene.try_upgrade(PLAYER),
		"Ending the match stops automatic processing and disables purchases.")
	scene.free()


func _with_barracks(sides: Array) -> MatchBattle:
	var battle := MatchBattle.new(CORRIDOR_LENGTH)
	for index in range(sides.size()):
		battle.add_barracks(sides[index], index)
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
