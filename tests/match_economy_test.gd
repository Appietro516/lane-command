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
	if failures == 0:
		print("Match economy rules and controls passed.")
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

	_check(match_scene.try_build(CPU) and match_scene.try_build(CPU),
		"Both CPU barracks use the shared match API.")
	_check(cpu_slots.get_node("Slot1").get_child_count() == 1
		and cpu_slots.get_node("Slot2").get_child_count() == 1,
		"CPU barracks fill both authored CPU slots.")
	match_scene._process(13.0)
	_click(build)
	_check_state(match_scene.economy, PLAYER, [0.0, 2, 2.5], "Build button at capacity")
	match_scene._process(20.0)
	_check(player_slots.get_node("Slot2").get_child_count() == 1
		and barracks_label.text == "Barracks 2/2" and build.disabled and upgrade.disabled,
		"The second player slot is occupied and both controls stay disabled after income.")


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
