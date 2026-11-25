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
	await _test_match_end_and_restart()
	if failures == 0:
		print("Corridor combat, outcomes, HUD and full replay checks passed.")
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
	var expected_outcome := MatchBattle.Outcome.VICTORY if attacker_side == PLAYER else (
		MatchBattle.Outcome.DEFEAT
	)
	_check(battle.is_finished() and battle.base_hp(defender_side) == 0
		and battle.base_hp(attacker_side) == 80 and destroyed == [defender_side]
		and battle.outcome() == expected_outcome,
		"A destroyed base reaches zero HP and records the outcome once.")

	var final_units := _unit_state(battle)
	var final_time := battle.elapsed_time()
	battle.advance(60.0, economy)
	_check(not final_units.is_empty() and _unit_state(battle) == final_units
		and destroyed == [defender_side] and battle.elapsed_time() == final_time
		and battle.outcome() == expected_outcome,
		"Further time leaves the completed battle, clock and outcome unchanged.")


func _test_match_scene() -> void:
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var units := scene.get_node("Units") as Node3D
	var regions := scene.get_node("Regions")
	# Deliberately vary ownership across the same corridor to exercise both and neutral.
	scene.get_region(&"region_1").region_owner = CPU
	scene.get_region(&"region_2").region_owner = PLAYER
	var initial_owners := _region_owners(regions)

	scene._process(2.0)
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)), "Build a player barracks alongside the autonomous CPU purchase.")
	scene._process(3.5)
	if units.get_child_count() != 2:
		_check(false, "Both barracks must deploy a unit.")
		scene.free()
		return
	var cpu_view := units.get_child(0) as MeshInstance3D
	var player_view := units.get_child(1) as MeshInstance3D
	var cpu_start := cpu_view.position
	var player_start := player_view.position
	scene._process(3.5)
	var player_base := scene.get_node("Regions/PlayerStart/PlayerBase") as Node3D
	var cpu_base := scene.get_node("Regions/CPUStart/CPUBase") as Node3D
	var route := cpu_base.global_position - player_base.global_position
	var direction := route.normalized()
	var gap := (cpu_view.position - player_view.position).dot(direction)
	_check((cpu_view.position - cpu_start).dot(direction) < 0.0
		and (player_view.position - player_start).dot(direction) > 0.0
		and (cpu_view.global_position - player_base.global_position).cross(direction).is_zero_approx()
		and (player_view.global_position - player_base.global_position).cross(direction).is_zero_approx()
		and gap > 0.0 and gap <= MatchBattle.UNIT_ATTACK_RANGE,
		"The scene renders both waves meeting on the route between the bases.")
	var battle: MatchBattle = scene._battle
	_check(battle.active_units().size() == 4 and battle.active_units()[0].hp == 9
		and battle.active_units()[1].hp == 9, "The initial units exchange damage in the match scene.")
	scene._process(3.0)
	_check(not cpu_view.is_inside_tree() and not player_view.is_inside_tree()
		and units.get_child_count() == battle.active_units().size(),
		"The scene removes dead units and still renders the active units.")
	_check(_region_owners(regions) == initial_owners, "Moving and fighting leave region ownership unchanged.")
	scene.free()


func _test_match_end_and_restart() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_SCENE.instantiate()
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
	var upgrade := scene.get_node("%Upgrade") as Button
	var restart := scene.get_node("%Restart") as Button
	var units := scene.get_node("Units")
	_check_full_reset(scene, initial_owners)

	# Give the first player barracks a two-second lead, then keep pace with CPU purchases.
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)),
		"The first barracks starts the player advance.")
	scene._process(10.0)
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -3.65)), "The player adds the second barracks at 10 seconds.")
	scene._process(20.0)
	_check(scene.try_upgrade(PLAYER) and scene.economy.has_upgrade(CPU),
		"Both sides have upgraded before the deciding attack.")
	scene.get_region(&"region_1").region_owner = PLAYER
	regions.get_node("CPUStart").region_owner = PLAYER
	scene._process(30.0)
	var battle: MatchBattle = scene._battle
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY and outcome.visible
		and outcome.text == "Victory" and player_base.visible and not cpu_base.visible
		and player_hp.text == "Player base · 80 HP" and cpu_hp.text == "CPU base · 0 HP",
		"Destroying the CPU base shows Victory and updates both base readouts.")
	_check(units.get_child_count() > 0 and battle.elapsed_time() > 30.0,
		"The finished match still has units and elapsed time to clear.")
	_check(not scene.is_processing() and build.disabled and upgrade.disabled
		and not scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -2.4)) and not scene.try_upgrade(PLAYER)
		and restart.visible and not restart.disabled,
		"Ending a match stops simulation and purchases while leaving Restart available.")

	_click(restart)
	_check(scene.is_processing(), "Restart re-enables automatic processing after Victory.")
	scene.set_process(false)
	_check_full_reset(scene, initial_owners)

	scene._process(1.75)
	_check(scene.economy.barracks_count(CPU) == 0, "CPU waits through its initial decision interval.")
	scene._process(0.25)
	_check(scene.economy.barracks_count(CPU) == 1 and scene.economy.energy(CPU) == 16.0,
		"CPU resumes autonomous purchases using the starting energy and cadence.")
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2))
		and scene.economy.barracks_count(PLAYER) == 1 and scene.economy.energy(PLAYER) == 16.0,
		"The player can place a barracks in the replay.")
	scene._process(3.25)
	_check(units.get_child_count() == 0, "Replay production does not inherit old timers.")
	scene._process(0.25)
	var replay_battle: MatchBattle = scene._battle
	var replay_units := replay_battle.active_units()
	_check(units.get_child_count() == 2 and replay_units.size() == 2
		and replay_units[0].id == 1 and is_equal_approx(replay_battle.elapsed_time(), 5.5),
		"Both first barracks deploy on schedule with fresh unit IDs and match time.")

	_click(restart)
	scene.set_process(false)
	_check_full_reset(scene, initial_owners)
	scene._process(13.0)
	_check(player_hp.text == "Player base · 77 HP" and cpu_hp.text == "CPU base · 80 HP"
		and not outcome.visible, "The HUD reflects nonlethal base damage during play.")
	scene._process(47.0)
	_check(scene._battle.outcome() == MatchBattle.Outcome.DEFEAT
		and outcome.visible and outcome.text == "Defeat"
		and not player_base.visible and cpu_base.visible
		and player_hp.text == "Player base · 0 HP" and cpu_hp.text == "CPU base · 80 HP",
		"The idle replay ends in Defeat when the CPU destroys the player base.")
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
		_check(material.albedo_color == MatchRegion.OWNER_COLORS[region.region_owner],
			"Region color reflects its restored ownership.")
	for side in [PLAYER, CPU]:
		var start_region := "PlayerStart" if side == PLAYER else "CPUStart"
		var base := scene.get_node("Regions/%s/%sBase" % [
			start_region, "Player" if side == PLAYER else "CPU",
		]) as Node3D
		_check(base.visible and battle.base_hp(side) == MatchBattle.BASE_HP,
			"Restart restores both bases and their HP.")
		_check(economy.energy(side) == MatchEconomy.STARTING_ENERGY
			and economy.barracks_count(side) == 0 and not economy.has_upgrade(side),
			"Restart restores starting energy and clears barracks and upgrades for each side.")
	_check(scene.get_node("Buildings/Player").get_child_count() == 0
		and scene.get_node("Buildings/CPU").get_child_count() == 0,
		"Restart removes all placed buildings.")
	_check(battle.active_units().is_empty() and scene.get_node("Units").get_child_count() == 0
		and battle.elapsed_time() == 0.0 and battle.outcome() == MatchBattle.Outcome.IN_PROGRESS,
		"Restart clears units, match time and the recorded outcome.")
	_check(scene.get_node("%PlayerHP").text == "Player base · 80 HP"
		and scene.get_node("%CPUHP").text == "CPU base · 80 HP"
		and scene.get_node("%Energy").text == "Energy 50"
		and scene.get_node("%BarracksCount").text == "Barracks 0/2"
		and not scene.get_node("%Outcome").visible and not scene.get_node("%Build").disabled
		and scene.get_node("%Upgrade").disabled and scene.get_node("%Upgrade").text == "Upgrade · 60",
		"The HUD refreshes to its starting readouts and purchase controls.")


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _with_barracks(sides: Array) -> MatchBattle:
	var battle := MatchBattle.new(CORRIDOR_LENGTH)
	for side in sides:
		battle.add_barracks(side)
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
