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
	await _test_claimed_placement()
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
	var player_buildings := match_scene.get_node("Buildings/Player")
	var cpu_buildings := match_scene.get_node("Buildings/CPU")
	var placement_panel := match_scene.get_node("%PlacementPanel") as PanelContainer
	var cancel := match_scene.get_node("%CancelPlacement") as Button
	var status := match_scene.get_node("%PlacementStatus") as Label

	_check(energy_label.text == "Energy 50" and income_label.text == "Income +3/s"
		and barracks_label.text == "Barracks 0/2", "The HUD renders initial economy values.")
	_check(not build.disabled and upgrade.disabled, "Only Build is affordable at startup.")

	await _choose_barracks(build)
	_check(placement_panel.visible and player_buildings.get_child_count() == 0
		and energy_label.text == "Energy 50", "Choosing a menu item enters placement without buying.")
	await _click_world(Vector3(-3.4, 0.0, -3.2))
	_check(status.text.contains("your territory") and placement_panel.visible,
		"A neutral click shows an ownership message and keeps placement active.")
	await _click_world(Vector3(10.0, 0.0, -1.25))
	await _click_at(Vector2(20, 140))
	_check(player_buildings.get_child_count() == 0 and energy_label.text == "Energy 50",
		"Neutral, enemy and off-map clicks spend no energy and create no building.")
	_click(cancel)
	_check(not placement_panel.visible, "Cancel exits placement.")
	await _click_world(Vector3(-9.65, 0.0, -1.37))
	_check(player_buildings.get_child_count() == 0 and energy_label.text == "Energy 50",
		"A world click after cancel only selects the region.")

	await _choose_barracks(build)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_check(not placement_panel.visible, "Escape exits placement.")

	await _choose_barracks(build)
	_send_click(root.get_camera_3d().unproject_position(Vector3(-9.65, 0.0, -1.37)),
		MOUSE_BUTTON_RIGHT)
	_check(not placement_panel.visible, "Right-click exits placement.")

	await _choose_barracks(build)
	var first_position := Vector3(-9.65, 0.0, -1.37)
	await _click_world(first_position)
	_check_state(match_scene.economy, PLAYER, [10.0, 1, 3.5], "First placed barracks")
	_check(player_buildings.get_child_count() == 1
		and _building_at(player_buildings, first_position),
		"The barracks appears at the unsnapped cursor position.")
	_check(energy_label.text == "Energy 10" and barracks_label.text == "Barracks 1/2"
		and build.disabled and upgrade.disabled and not placement_panel.visible,
		"Placement updates the HUD immediately and exits placement mode.")

	match_scene._process(17.0)
	_check(energy_label.text == "Energy 61" and not upgrade.disabled,
		"Income refreshes the HUD and enables Upgrade.")
	_click(upgrade)
	_check_state(match_scene.economy, PLAYER, [1.0, 1, 2.5], "Upgrade button")
	_check(energy_label.text == "Energy 1" and upgrade.disabled and upgrade.text == "Upgraded",
		"Upgrade updates the HUD immediately.")

	_check(cpu_buildings.get_child_count() == 2,
		"The CPU places both barracks autonomously.")
	match_scene._process(13.0)
	await _choose_barracks(build)
	var second_position := Vector3(-12.73, 0.0, 0.41)
	await _click_world(second_position)
	_check_state(match_scene.economy, PLAYER, [0.0, 2, 2.5], "Second placed barracks")
	match_scene._process(20.0)
	_check(_building_at(player_buildings, second_position)
		and barracks_label.text == "Barracks 2/2" and build.disabled and upgrade.disabled,
		"The second arbitrary position works and the capacity remains enforced.")

	match_scene.free()


func _test_claimed_placement() -> void:
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame
	var region: MatchRegion = scene.get_region(&"region_1")
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	# This point is on the claimed side of the bisector, inside the visual gap.
	var claimed_position := start.global_position.lerp(region.global_position, 0.505)
	await _click_world(claimed_position)
	_click(scene.get_node("%Claim"))
	_check(scene.owns_region(PLAYER, region.region_id), "Claim transfers the clicked region.")
	scene.economy.advance(27.0)
	scene._process(0.0)
	var build := scene.get_node("%Build") as Button
	var player_buildings := scene.get_node("Buildings/Player")
	await _choose_barracks(build)
	await _click_world(claimed_position)
	_check_state(scene.economy, PLAYER, [41.0, 1, 3.5], "Building in a newly claimed region")
	_check(_building_at(player_buildings, claimed_position),
		"Claimed territory accepts building placement at the clicked point.")
	await _choose_barracks(build)
	await _click_world(claimed_position)
	_check_state(scene.economy, PLAYER, [1.0, 2, 3.5], "Overlapping placement")
	_check(player_buildings.get_child_count() == 2
		and (player_buildings.get_child(1) as Node3D).position.distance_to(claimed_position) < 0.001,
		"An existing building at the point does not block placement.")
	scene.restart_match()
	scene.set_process(false)
	await _choose_barracks(build)
	_click(scene.get_node("%Restart"))
	scene.set_process(false)
	_check(not scene.get_node("%PlacementPanel").visible and player_buildings.get_child_count() == 0,
		"Restart cancels active placement and clears constructed buildings.")
	scene.free()


func _choose_barracks(build: Button) -> void:
	_click(build)
	var scene := build.owner
	var list := scene.get_node("%BuildList") as VBoxContainer
	var option := list.get_child(0) as Button
	await process_frame
	await process_frame
	_check(list.is_visible_in_tree() and list.get_child_count() == 1
		and option.text == "Barracks · %d energy" % MatchEconomy.BARRACKS_COST,
		"Build opens the catalog menu with the configured price.")
	_click(option)
	await process_frame


func _building_at(buildings: Node, point: Vector3) -> bool:
	for child: Node3D in buildings.get_children():
		if child.global_position.distance_to(point) < 0.001:
			return true
	return false


func _click_world(point: Vector3) -> void:
	await _click_at(root.get_camera_3d().unproject_position(point))


func _click_at(position: Vector2) -> void:
	_send_click(position)
	await physics_frame
	await physics_frame


func _test_cpu_purchases() -> void:
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var cpu_buildings := match_scene.get_node("Buildings/CPU")

	match_scene._process(1.75)
	_check_state(match_scene.economy, CPU, [55.25, 0, 3.5], "Before the first CPU decision")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [16.0, 1, 3.5], "First CPU purchase at 2 seconds")
	_check(cpu_buildings.get_child_count() == 1
		and match_scene.owns_region(CPU, match_scene.region_at_world_position(
			cpu_buildings.get_child(0).global_position)),
		"The first CPU barracks appears inside CPU territory.")

	match_scene._process(7.75)
	_check_state(match_scene.economy, CPU, [39.25, 1, 3.5], "Before the CPU can afford its second barracks")
	_check(match_scene.get_node("Units").get_child_count() == 2,
		"The first CPU barracks spawns at 5.5 and 9 seconds without player input.")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 3.5], "Second CPU purchase at 10 seconds")
	_check(cpu_buildings.get_child_count() == 2
		and match_scene.owns_region(CPU, match_scene.region_at_world_position(
			cpu_buildings.get_child(1).global_position)),
		"The second CPU barracks also appears inside CPU territory.")
	_check_state(match_scene.economy, PLAYER, [80.0, 0, 3.5], "Idle player")
	match_scene.free()

	# Keep both bases defended while checking the CPU's later economy decisions.
	match_scene = MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	match_scene._process(2.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)), "Build the player's first defending barracks.")
	match_scene._process(8.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -3.65)), "Build the player's second defending barracks.")
	match_scene._process(19.75)
	_check_state(match_scene.economy, CPU, [59.25, 2, 3.5], "Before the CPU can afford its upgrade")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 2.5], "CPU upgrade at 30 seconds")
	_check(match_scene.try_upgrade(PLAYER), "Keep both sides on the upgraded production rate.")
	match_scene._process(22.0)
	_check_state(match_scene.economy, CPU, [66.0, 2, 2.5], "After reaching CPU capacity")
	match_scene.free()


func _test_symmetric_production() -> void:
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var units := match_scene.get_node("Units")
	var produced: Array[MatchBattle.Unit] = []
	match_scene._battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		produced.append(unit))

	match_scene._process(2.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)), "The player can buy at the same time as the CPU.")
	match_scene._process(3.25)
	_check(units.get_child_count() == 0, "Neither barracks spawns early.")
	match_scene._process(0.25)
	_check(units.get_child_count() == 2, "Both sides spawn at 3.5 seconds after construction.")
	if units.get_child_count() == 2:
		var cpu_unit := units.get_child(0) as MeshInstance3D
		var player_unit := units.get_child(1) as MeshInstance3D
		var token := player_unit.mesh as PrismMesh
		_check(cpu_unit.mesh == token and token != null,
			"Both sides spawn the same triangular token mesh.")
		_check(cpu_unit.position.x > 0 and player_unit.position.x < 0
			and cpu_unit.basis.y.is_equal_approx(Vector3.LEFT)
			and player_unit.basis.y.is_equal_approx(Vector3.RIGHT)
			and cpu_unit.material_override != player_unit.material_override,
			"Units start on their own side, face the opposing base and use distinct colors.")

	match_scene._process(4.5)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -3.65)), "Both sides add a second barracks at 10 seconds.")
	match_scene._process(2.5)
	_check(produced.size() == 6, "The first barracks on each side keeps its own timer.")
	match_scene._process(1.0)
	_check(produced.size() == 8, "The second barracks on each side starts a full cycle.")

	match_scene._process(16.5)
	_check(match_scene.try_upgrade(PLAYER), "Both sides upgrade at 30 seconds.")
	match_scene._process(0.0)
	_check(produced.size() == 28, "Both upgrades preserve elapsed production time.")
	match_scene._process(2.25)
	_check(produced.size() == 28, "Upgraded barracks wait for the 2.5-second interval.")
	match_scene._process(0.25)
	_check(produced.size() == 32, "All four barracks spawn at the upgraded interval.")
	var player_units := 0
	for unit in produced:
		if unit.side == PLAYER:
			player_units += 1
	_check(player_units == 16, "Both sides produce the same number of units across both rates.")
	match_scene.free()


func _click(button: BaseButton) -> void:
	_send_click(button.get_global_rect().get_center())


func _send_click(position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
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
