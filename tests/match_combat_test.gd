extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const PLAYER_BASE := Vector2(-10.2, 2.0)
const CPU_BASE := Vector2(10.2, 2.0)

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
	_test_orders_and_defense()
	_test_routes()
	await _test_match_scene()
	await _test_match_end_and_restart()
	if failures == 0:
		print("Open-map combat, unit inspection, movement orders, outcomes and replay checks passed.")
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
		and units[0].position.x > -6.5 and units[1].position.x < 6.5
		and is_equal_approx(units[0].position.x, -units[1].position.x)
		and units[0].position.y < 0.0 and units[1].position.y < 0.0,
		"Both units leave their off-axis barracks and advance toward the opposing base.")
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
	attacker.position = Vector2(direction * 8.45, 2.0)
	farther.position = attacker.position + Vector2(0.0, 2.8)
	nearer.position = attacker.position + Vector2(0.0, 1.4)
	nearer.hp = MatchBattle.ATTACK_DAMAGE

	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == nearer.id and attacker.position.y > 2.0 and nearer.hp == 3
		and battle.base_hp(defender_side) == 80,
		"The nearest local opponent draws the unit out of base attack range before contact.")
	battle.target_priority = MatchBattle.TargetPriority.LOWEST_HP
	farther.hp = 1
	battle.advance(MatchBattle.STEP, economy)
	_check(attacker.target == farther.id, "The optional lowest-HP priority overrides distance.")
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


func _test_base_destruction(attacker_side: MatchRegion.Owner, defender_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([attacker_side])
	var destroyed: Array[MatchRegion.Owner] = []
	battle.base_destroyed.connect(func(side: MatchRegion.Owner) -> void: destroyed.append(side))
	battle.advance(6.0, economy)
	_check(battle.base_hp(defender_side) == 80, "A distant base takes no damage.")
	for step in range(480):
		if battle.base_hp(defender_side) < 80:
			break
		battle.advance(MatchBattle.STEP, economy)
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


func _test_orders_and_defense() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER, CPU])
	battle.advance(3.5, economy)
	var player := battle.active_units()[0]
	var opponent := battle.active_units()[1]
	var destination := Vector2(-6.0, 5.0)
	_check(battle.issue_move(player.id, destination)
		and player.movement_destination == destination and not player.waypoints.is_empty(),
		"A move exposes its destination and route immediately.")
	_check(not battle.issue_move(opponent.id, destination), "CPU units reject player commands.")
	battle.advance(0.5, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.position.y > -2.0,
		"The ordered unit advances away from its strategic base target.")

	opponent.position = player.position + Vector2(2.0, 0.0)
	opponent.hp = MatchBattle.ATTACK_DAMAGE
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == opponent.id and player.order == MatchBattle.Order.MOVE
		and player.ordered_destination == destination and player.movement_destination != destination,
		"Detecting a local threat interrupts movement while retaining the order.")
	battle.advance(0.5, economy)
	_check(battle.get_unit(opponent.id) == null and player.target == MatchBattle.NO_TARGET
		and player.movement_destination == destination,
		"After killing its attacker, the unit resumes the original route.")
	battle.advance(2.8, economy)
	_check(player.order == MatchBattle.Order.HOLD and player.position == destination
		and player.waypoints.is_empty(), "Arrival converts a move into a persistent hold.")

	battle.advance(0.5, economy)
	var next_opponent: MatchBattle.Unit
	for unit in battle.active_units():
		if unit.side == CPU:
			next_opponent = unit
	if next_opponent == null:
		_check(false, "A second opponent is available to test defense after arrival.")
		return
	next_opponent.position = player.position + Vector2(2.0, 0.0)
	battle.advance(MatchBattle.STEP, economy)
	_check(player.order == MatchBattle.Order.HOLD and player.target == next_opponent.id,
		"Holding units still defend against local enemies.")
	battle.advance(0.25, economy)
	next_opponent.position = destination + Vector2(battle.aggro_radius + 0.2, 0.0)
	_check(player.position.distance_to(next_opponent.position) < battle.aggro_radius,
		"The former target is still close enough to draw the unit away without a hold area.")
	battle.advance(MatchBattle.STEP, economy)
	_check(player.target == MatchBattle.NO_TARGET and player.movement_destination == destination,
		"A nearby opponent outside the hold area breaks off the pursuit.")
	next_opponent.position = Vector2(4.0, 4.0)
	battle.advance(0.5, economy)
	_check(player.position == destination, "The unit returns to the hold destination.")


func _test_routes() -> void:
	var economy := MatchEconomy.new()
	var battle := _with_barracks([PLAYER])
	battle.advance(3.5, economy)
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
	for step in range(60):
		battle.advance(4.0 * MatchBattle.STEP, economy)
		crossed_obstacle = crossed_obstacle or obstacle.has_point(unit.position)
	_check(unit.position == destination and not crossed_obstacle,
		"The unit follows its waypoints around the obstacle and reaches the original destination.")

	unit.position = Vector2(-4.0, -5.0)
	_check(battle.issue_move(unit.id, destination), "The detour remains available before the wall.")
	battle.navigation.add_obstacle(Rect2(1.5, -9.0, 1.0, 18.0))
	battle.advance(MatchBattle.STEP, economy)
	_check(unit.order == MatchBattle.Order.MOVE and unit.waypoints.is_empty()
		and not battle.issue_move(unit.id, destination),
		"A passable but disconnected destination clears stale waypoints and rejects a new order.")
	var previous := unit.position
	battle.advance(0.25, economy)
	_check(unit.position == previous, "A unit with no route waits without crossing the blocker.")
	var replacement := Vector2(-5.0, -5.0)
	_check(battle.issue_move(unit.id, replacement), "A reachable order replaces a stalled route.")
	battle.advance(1.0, economy)
	_check(unit.order == MatchBattle.Order.HOLD and unit.position == replacement,
		"The replacement reaches its destination.")


func _test_match_scene() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame

	var units := scene.get_node("Units") as Node3D
	var player_building := Vector3(-10.2, 0.0, -1.2)
	scene._process(2.0)
	_check(scene.try_place_building(PLAYER, &"barracks", player_building),
		"Build a player barracks alongside the autonomous CPU purchase.")
	scene._process(3.5)
	if units.get_child_count() != 2:
		_check(false, "Both barracks must deploy a unit.")
		scene.free()
		return
	var cpu_view := units.get_child(0) as MeshInstance3D
	var player_view := units.get_child(1) as MeshInstance3D
	var cpu_building := scene.get_node("Buildings/CPU").get_child(0) as Node3D
	_check(cpu_view.position.distance_to(cpu_building.position) < 2.0
		and player_view.position.distance_to(player_building) < 2.0
		and absf(player_view.position.z - 2.0) > 1.0,
		"Both factions deploy beside their producing structures, off the former route.")
	var cpu_start := cpu_view.position
	scene._process(0.25)
	_check(cpu_view.position != cpu_start, "The CPU starts moving toward its strategic target.")
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
	_check(panel.visible and unit_name.text == "CPU combat unit #%d" % cpu.id
		and stats.text == "HP  12 / 12\nAttack  3 · Speed  2.4 units/s"
		and intent.text == "Target  Player base\nState  Advancing"
		and marker.global_position == cpu_view.global_position
		and not order_hint.visible and route.get_surface_count() == 1,
		"Enemy inspection shows the live stats, strategic target, ring and route.")
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
	_check(unit_name.text == "Player combat unit #%d" % player.id
		and intent.text == "Target  CPU base\nState  Advancing" and order_hint.visible,
		"Switching to a friendly unit refreshes the name, target and move hint.")
	_click_at_world(destination, MOUSE_BUTTON_RIGHT)
	_check(player.ordered_destination.is_equal_approx(Vector2(destination.x, destination.z)),
		"A right-click issues a real move order through viewport input.")
	_check(intent.text == "Target  None\nState  Moving to order"
		and route.get_surface_count() == 1 and route.get_aabb().end.x > destination.x,
		"The route and panel refresh immediately to show the order destination.")
	_click_at_world(player_building, MOUSE_BUTTON_RIGHT)
	_click_at_world(cpu_view.global_position, MOUSE_BUTTON_RIGHT)
	_check(player.ordered_destination.is_equal_approx(Vector2(destination.x, destination.z)),
		"Clicking a building footprint or enemy unit preserves the prior order.")
	scene._process(0.5)
	var first_position := player_view.position
	var replacement := Vector3(-7.0, 0.0, -5.0)
	_click_at_world(replacement, MOUSE_BUTTON_RIGHT)
	scene._process(2.0)
	_check(player_view.position != first_position
		and player.position.is_equal_approx(Vector2(replacement.x, replacement.z))
		and player.order == MatchBattle.Order.HOLD and marker.global_position == player_view.global_position,
		"A second right-click supersedes the first and the visible unit and marker reach it.")
	_check(route.get_surface_count() == 0 and intent.text == "Target  None\nState  Holding",
		"The route clears when the selected unit reaches its hold point.")

	cpu.position = player.position + Vector2(0.0, -2.0)
	scene._process(MatchBattle.STEP)
	_check(player.target == cpu.id and intent.text == "Target  CPU unit #%d\nState  Pursuing" % cpu.id
		and route.get_surface_count() == 1 and route.get_aabb().position.z < cpu.position.y,
		"A new target and its pursuit route replace the previous movement intent live.")
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
	_click(scene.get_node("%BuildList").get_child(0))
	_check(scene._preview != null and scene.selected_unit() == null and not panel.visible,
		"Entering placement clears inspection.")
	_click_at_world(player_view.global_position)
	_check(scene._pending_pick != Vector2.INF and scene.selected_unit() == null,
		"Clicks over a unit go to building placement while it is active.")
	_press_escape()
	_check(scene._preview == null, "Escape still cancels placement.")

	_click_at_world(player_view.global_position)
	player.hp = 0
	scene._process(MatchBattle.STEP)
	_check(scene.selected_unit() == null and not marker.visible and not panel.visible
		and route.get_surface_count() == 0 and not player_view.is_inside_tree(),
		"Removing the selected unit clears inspection and the rendered view.")
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

	# A staggered approach from opposite sides of the player base wins this layout.
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-12.0, 0, 5.0)),
		"The first barracks starts the player advance.")
	scene._process(10.0)
	_check(scene.try_place_building(PLAYER, &"barracks", Vector3(-7.7, 0, -1.0)),
		"The player adds the second barracks at 10 seconds.")
	scene._process(20.0)
	_check(scene.try_upgrade(PLAYER) and scene.economy.has_upgrade(CPU),
		"Both sides have upgraded before the deciding attack.")
	scene.get_region(&"region_1").region_owner = PLAYER
	regions.get_node("CPUStart").region_owner = PLAYER
	scene._process(45.0)
	var battle: MatchBattle = scene._battle
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY and outcome.visible
		and outcome.text == "Victory" and player_base.visible and not cpu_base.visible
		and player_hp.text == "Player base · 80 HP" and cpu_hp.text == "CPU base · 0 HP",
		"Destroying the CPU base shows Victory and updates both base readouts. Got %s, %s, %s." % [
			outcome.text, player_hp.text, cpu_hp.text,
		])
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
	scene._process(8.0)
	for step in range(600):
		if scene._battle.base_hp(PLAYER) < MatchBattle.BASE_HP:
			break
		scene._process(MatchBattle.STEP)
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
		battle.add_barracks(side, Vector2(PLAYER_BASE.x if side == PLAYER else CPU_BASE.x, -3.0))
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
