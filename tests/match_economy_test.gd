extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rules(PLAYER, CPU)
	_test_rules(CPU, PLAYER)
	await _test_match_controls()
	_test_cpu_purchases()
	_test_symmetric_production()
	if failures == 0:
		print("Match economy, controls, CPU purchases and symmetric production passed.")
	quit(1 if failures > 0 else 0)


func _test_rules(side: MatchRegion.Owner, other_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	_check_state(economy, side, [50.0, 0, 3.5], "Initial state")
	economy.advance(-20.0)
	_check_state(economy, side, [50.0, 0, 3.5], "Negative elapsed time")
	economy.advance(0.5)
	_check_state(economy, side, [51.5, 0, 3.5], "Fractional income")
	economy.advance(0.5)
	_check_state(economy, side, [53.0, 0, 3.5], "Income after one second")

	_check(not economy.try_upgrade(side), "Reject an unaffordable upgrade.")
	_check_state(economy, side, [53.0, 0, 3.5], "Unaffordable upgrade")
	_check(economy.try_build(side), "Accept the first barracks.")
	_check_state(economy, side, [13.0, 1, 3.5], "First barracks")
	_check(not economy.try_build(side), "Reject an unaffordable barracks.")
	_check_state(economy, side, [13.0, 1, 3.5], "Unaffordable barracks")
	_check_state(economy, other_side, [53.0, 0, 3.5], "Other side after first barracks")

	economy.advance(9.0)
	_check(economy.try_build(side), "Accept a barracks at the exact price.")
	_check_state(economy, side, [0.0, 2, 3.5], "Second barracks at the exact price")
	economy.advance(20.0)
	_check(not economy.try_build(side), "Reject a third barracks with sufficient energy.")
	_check_state(economy, side, [60.0, 2, 3.5], "Barracks capacity")
	_check(economy.try_upgrade(side), "Accept an upgrade at the exact price.")
	_check_state(economy, side, [0.0, 2, 2.5], "Production upgrade at the exact price")
	economy.advance(20.0)
	_check(not economy.try_upgrade(side), "Reject a repeat upgrade with sufficient energy.")
	_check_state(economy, side, [60.0, 2, 2.5], "Repeat upgrade")
	_check_state(economy, other_side, [200.0, 0, 3.5], "Other side after all purchases")


func _test_match_controls() -> void:
	root.size = Vector2i(1280, 800)
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	# Let the nested containers finish layout before sending viewport clicks.
	await process_frame
	await process_frame

	var build: Button = match_scene.get_node("%Build")
	var upgrade: Button = match_scene.get_node("%Upgrade")
	var energy_label: Label = match_scene.get_node("%Energy")
	var income_label: Label = match_scene.get_node("%Income")
	var barracks_label: Label = match_scene.get_node("%BarracksCount")
	var player_slots := match_scene.get_node("Regions/PlayerStart/BarracksSlots")
	var cpu_slots := match_scene.get_node("Regions/CPUStart/BarracksSlots")

	_check(energy_label.text == "Energy 50" and income_label.text == "Income +3/s"
		and barracks_label.text == "Barracks 0/2", "The HUD renders initial economy values.")
	_check(not build.disabled and upgrade.disabled, "Only Build is affordable at startup.")
	_click(build)
	_check_state(match_scene.economy, PLAYER, [10.0, 1, 3.5], "Build button")
	_check(player_slots.get_node("Slot1").get_child_count() == 1
		and player_slots.get_node("Slot2").get_child_count() == 0,
		"The Build button places a barracks in the first player slot.")
	_check(energy_label.text == "Energy 10" and barracks_label.text == "Barracks 1/2"
		and build.disabled and upgrade.disabled, "Build updates the HUD immediately.")

	match_scene._process(17.0)
	_check(energy_label.text == "Energy 61" and not upgrade.disabled,
		"Income refreshes the HUD and enables Upgrade.")
	_click(upgrade)
	_check_state(match_scene.economy, PLAYER, [1.0, 1, 2.5], "Upgrade button")
	_check(energy_label.text == "Energy 1" and upgrade.disabled and upgrade.text == "Upgraded",
		"Upgrade updates the HUD immediately.")

	_check(cpu_slots.get_node("Slot1").get_child_count() == 1
		and cpu_slots.get_node("Slot2").get_child_count() == 1,
		"Autonomous CPU purchases fill both authored CPU slots.")
	match_scene._process(13.0)
	_click(build)
	_check_state(match_scene.economy, PLAYER, [0.0, 2, 2.5], "Build button at capacity")
	match_scene._process(20.0)
	_check(player_slots.get_node("Slot2").get_child_count() == 1
		and barracks_label.text == "Barracks 2/2" and build.disabled and upgrade.disabled,
		"The second player slot is occupied and both controls stay disabled after income.")
	match_scene.free()


func _test_cpu_purchases() -> void:
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var cpu_slots := match_scene.get_node("Regions/CPUStart/BarracksSlots")

	match_scene._process(1.75)
	_check_state(match_scene.economy, CPU, [55.25, 0, 3.5], "Before the first CPU decision")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [16.0, 1, 3.5], "First CPU purchase at 2 seconds")
	_check(cpu_slots.get_node("Slot1").get_child_count() == 1
		and cpu_slots.get_node("Slot2").get_child_count() == 0,
		"The first CPU barracks appears in the first slot.")

	match_scene._process(7.75)
	_check_state(match_scene.economy, CPU, [39.25, 1, 3.5], "Before the CPU can afford slot two")
	_check(match_scene.get_node("Units").get_child_count() == 2,
		"The first CPU barracks spawns at 5.5 and 9 seconds without player input.")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 3.5], "Second CPU purchase at 10 seconds")
	_check(cpu_slots.get_node("Slot2").get_child_count() == 1,
		"The second CPU barracks appears in the second slot.")

	match_scene._process(19.75)
	_check_state(match_scene.economy, CPU, [59.25, 2, 3.5], "Before the CPU can afford its upgrade")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 2.5], "CPU upgrade at 30 seconds")
	match_scene._process(22.0)
	_check_state(match_scene.economy, CPU, [66.0, 2, 2.5], "After reaching CPU capacity")
	_check_state(match_scene.economy, PLAYER, [206.0, 0, 3.5], "Idle player")
	match_scene.free()


func _test_symmetric_production() -> void:
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var units := match_scene.get_node("Units")

	match_scene._process(2.0)
	_check(match_scene.try_build(PLAYER), "The player can buy at the same time as the CPU.")
	match_scene._process(3.25)
	_check(units.get_child_count() == 0, "Neither barracks spawns early.")
	match_scene._process(0.25)
	_check(units.get_child_count() == 2, "Both sides spawn at 3.5 seconds after construction.")
	if units.get_child_count() == 2:
		var cpu_unit := units.get_child(0) as MeshInstance3D
		var player_unit := units.get_child(1) as MeshInstance3D
		_check(cpu_unit.mesh == player_unit.mesh and cpu_unit.mesh is BoxMesh,
			"Both sides spawn the same cube mesh.")
		_check(cpu_unit.position.x > 0 and player_unit.position.x < 0
			and cpu_unit.material_override != player_unit.material_override,
			"Cubes spawn on their own side and use distinct colors.")

	match_scene._process(4.5)
	_check(match_scene.try_build(PLAYER), "Both sides add a second barracks at 10 seconds.")
	match_scene._process(2.5)
	_check(units.get_child_count() == 6, "The first barracks on each side keeps its own timer.")
	match_scene._process(1.0)
	_check(units.get_child_count() == 8, "The second barracks on each side starts a full cycle.")

	match_scene._process(16.5)
	_check(match_scene.try_upgrade(PLAYER), "Both sides upgrade at 30 seconds.")
	match_scene._process(0.0)
	_check(units.get_child_count() == 28, "Both upgrades preserve elapsed production time.")
	match_scene._process(2.25)
	_check(units.get_child_count() == 28, "Upgraded barracks wait for the 2.5-second interval.")
	match_scene._process(0.25)
	_check(units.get_child_count() == 32, "All four barracks spawn at the upgraded interval.")
	var player_units := 0
	for unit: MeshInstance3D in units.get_children():
		if unit.position.x < 0.0:
			player_units += 1
	_check(player_units == 16, "Both sides produce the same number of units across both rates.")
	match_scene.free()


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _check_state(economy: MatchEconomy, side: MatchRegion.Owner, expected: Array,
		context: String) -> void:
	var actual := [economy.energy(side), economy.barracks_count(side),
		economy.production_interval(side)]
	_check(actual == expected, "%s for %s. Expected %s, got %s." % [
		context, MatchRegion.Owner.keys()[side], expected, actual,
	])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
