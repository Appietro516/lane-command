extends SceneTree

const GameScene := preload("res://game.tscn")
const Profiles := preload("res://match/difficulty_profile.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var setup_screen: MatchSetup = game.get_node("MatchSetup")
	var count: OptionButton = setup_screen.get_node("%OpponentCount")
	var shape: OptionButton = setup_screen.get_node("%MapShape")
	var size: OptionButton = setup_screen.get_node("%MapSize")
	var regions: LineEdit = setup_screen.get_node("%MapRegions")
	var seed_field: LineEdit = setup_screen.get_node("%MapSeed")
	var start: Button = setup_screen.get_node("%Start")
	var error: Label
	_check(game.get_child_count() == 1 and not game.has_node("Match") and not start.disabled,
		"Launch has a valid setup and no match to simulate.")
	_check(count.has_focus() and count.item_count == 4 and count.get_selected_id() == 1,
		"Keyboard focus starts at the opponent count, with one CPU selected.")
	_press_tab()
	_check(setup_screen._difficulty_pickers[0].has_focus(),
		"Tab focuses the first difficulty selector.")
	_check(shape.get_selected_id() == MapSettings.Shape.RECTANGLE
		and size.text == "Medium · 60 × 36" and regions.text == "24" and seed_field.text == "17"
		and setup_screen._difficulty_pickers[0].get_selected_id() == 3,
		"Setup displays the requested defaults.")

	await _click(start)
	var match_scene := game.get_node_or_null("Match")
	if not _check(match_scene != null and not game.has_node("MatchSetup"),
			"Start swaps the setup scene for a single playable match."):
		game.free()
		quit(1)
		return
	_check(match_scene._layout.settings.size == Vector2(60, 36)
		and match_scene._layout.settings.shape == MapSettings.Shape.RECTANGLE
		and match_scene._layout.cells.size() == 24 and match_scene.active_map_seed == 17
		and match_scene._cpu_strategies.size() == 1
		and match_scene._cpu_strategy.difficulty == Profiles.get_profile(3), "Default Start plays the intended 1v1.")
	var default_layout: TerritoryLayout = match_scene._layout
	var previous_match: WeakRef = weakref(match_scene)
	await _click(match_scene.get_node("%ReturnToSetup"))
	await process_frame
	_check(previous_match.get_ref() == null and game.get_child_count() == 1,
		"Returning to Setup frees the previous match.")

	setup_screen = game.get_node("MatchSetup")
	count = setup_screen.get_node("%OpponentCount")
	shape = setup_screen.get_node("%MapShape")
	size = setup_screen.get_node("%MapSize")
	regions = setup_screen.get_node("%MapRegions")
	seed_field = setup_screen.get_node("%MapSeed")
	start = setup_screen.get_node("%Start")
	error = setup_screen.get_node("%ValidationError")
	_edit(regions, "2.5")
	_check(start.disabled and "whole number" in error.text, "Regions must be integers.")
	_edit(regions, "129")
	_check(start.disabled and "128" in error.text, "Regions obey the engine limit.")
	_edit(regions, "2")
	_check(start.disabled and "stays neutral" in error.text, "1v1 leaves room for a neutral claim.")
	_edit(regions, "24")
	_select(count, 4)
	_edit(regions, "5")
	_check(start.disabled and "at least 6" in error.text, "Four CPU starts also leave room for a neutral claim.")
	_select(shape, MapSettings.Shape.TRIANGLE)
	_select(size, MatchSettings.MapSize.SMALL)
	_edit(regions, "29")
	_check(start.disabled and "up to 28" in error.text, "The small triangle enforces its specific capacity.")
	start.pressed.emit()
	_check(not game.has_node("Match"), "An invalid configuration cannot start.")

	_edit(regions, "18")
	_select(size, MatchSettings.MapSize.LARGE)
	_select(count, 2)
	_check(setup_screen._cpu_rows[1].visible and not setup_screen._cpu_rows[2].visible,
		"Exactly two labeled rows are available with two CPUs.")
	_select(setup_screen._difficulty_pickers[0], 5)
	_select(setup_screen._difficulty_pickers[1], 2)
	_check(setup_screen._difficulty_descriptions[0].text == Profiles.get_profile(5).description
		and setup_screen._difficulty_descriptions[1].text == Profiles.get_profile(2).description,
		"Each CPU describes its own selected profile.")
	for invalid_seed in ["", "1.75", "1e5", "9223372036854775808", "-9223372036854775809"]:
		_edit(seed_field, invalid_seed)
		_check(start.disabled and "whole-number seed" in error.text, "Invalid seed is rejected: " + invalid_seed)
	for valid_seed in ["0", "9223372036854775807", "-9223372036854775808"]:
		_edit(seed_field, valid_seed)
		_check(not start.disabled, "Valid signed integer seed is accepted: " + valid_seed)

	await _click(start)
	match_scene = game.get_node_or_null("Match")
	if not _check(match_scene != null, "The valid triangle starts."):
		game.free()
		quit(1)
		return
	var triangle: TerritoryLayout = match_scene._layout
	_check(match_scene.active_map_seed == -9223372036854775807 - 1 and triangle.boundary.size() == 3
		and is_equal_approx(triangle.bounds.size.y, 90.0 * sqrt(3.0) / 2.0)
		and triangle.bounds.size.x == 90.0 and triangle.cells.size() == 18
		and match_scene._cpu_strategies.size() == 2, "Start applies the exact seed, triangle and region count.")
	_check_profiles(match_scene, [5, 2])
	var old_battle: MatchBattle = match_scene._battle
	await _click(match_scene.get_node("%Restart"))
	_check(match_scene._layout == triangle and match_scene._battle != old_battle
		and match_scene.active_map_seed == triangle.active_seed, "Plain Restart clears the battle and reuses the selected seed and layout.")
	_check_profiles(match_scene, [5, 2])

	await _click(match_scene.get_node("%ReturnToSetup"))
	setup_screen = game.get_node("MatchSetup")
	_check(setup_screen.get_node("%MapSeed").text == str(triangle.active_seed)
		and setup_screen.get_node("%MapShape").get_selected_id() == MapSettings.Shape.TRIANGLE
		and setup_screen.get_node("%MapSize").get_selected_id() == MatchSettings.MapSize.LARGE
		and setup_screen.get_node("%MapRegions").text == "18"
		and setup_screen.get_node("%OpponentCount").get_selected_id() == 2
		and setup_screen._difficulty_pickers[0].get_selected_id() == 5
		and setup_screen._difficulty_pickers[1].get_selected_id() == 2, "Setup keeps the last match's complete selection.")
	await _click(setup_screen.get_node("%Start"))
	match_scene = game.get_node("Match")
	_check_same_map(triangle, match_scene._layout)

	await _click(match_scene.get_node("%ReturnToSetup"))
	setup_screen = game.get_node("MatchSetup")
	seed_field = setup_screen.get_node("%MapSeed")
	root.size = Vector2i(1000, 640)
	_select(setup_screen.get_node("%OpponentCount"), 4)
	_select(setup_screen.get_node("%MapShape"), MapSettings.Shape.SQUARE)
	_select(setup_screen.get_node("%MapSize"), MatchSettings.MapSize.SMALL)
	_edit(setup_screen.get_node("%MapRegions"), "12")
	var levels: Array[int] = [3, 2, 1, 4]
	for i in levels.size():
		_select(setup_screen._difficulty_pickers[i], levels[i])
	_check(setup_screen._cpu_rows[3].visible, "The fourth CPU has its own row.")
	var before := seed_field.text
	var randomize: Button = setup_screen.get_node("%Randomize")
	await process_frame
	var scroll := randomize.find_parent("FormScroll") as ScrollContainer
	scroll.ensure_control_visible(randomize)
	await process_frame
	await _click(randomize)
	var randomized_seed := seed_field.text
	_check(randomized_seed != before and randomized_seed.is_valid_int(), "Randomize changes the visible seed.")
	await _click(setup_screen.get_node("%Start"))
	match_scene = game.get_node("Match")
	var square: TerritoryLayout = match_scene._layout
	_check(square.bounds.size == Vector2(32, 32) and square.cells.size() == 12
		and square.settings.shape == MapSettings.Shape.SQUARE and square.active_seed == randomized_seed.to_int()
		and match_scene._battle._bases.size() == 5, "The square starts all four CPUs with the displayed randomized seed.")
	_check_profiles(match_scene, levels)

	await _click(match_scene.get_node("%ReturnToSetup"))
	setup_screen = game.get_node("MatchSetup")
	_select(setup_screen.get_node("%OpponentCount"), 1)
	_select(setup_screen.get_node("%MapShape"), MapSettings.Shape.RECTANGLE)
	_select(setup_screen.get_node("%MapSize"), MatchSettings.MapSize.MEDIUM)
	_edit(setup_screen.get_node("%MapRegions"), "24")
	_edit(setup_screen.get_node("%MapSeed"), "17")
	await _click(setup_screen.get_node("%Start"))
	_check_same_map(default_layout, game.get_node("Match")._layout)
	game.free()
	if _failures == 0:
		print("Single-player Game Setup checks passed.")
	quit(int(_failures > 0))


func _check_profiles(match_scene: Node, levels: Array[int]) -> void:
	var strategies := {}
	for i in levels.size():
		var strategy: RefCounted = match_scene._cpu_strategies[MatchRegion.Owner.CPU + i]
		_check(strategy.difficulty == Profiles.get_profile(levels[i]), "CPU %d uses its selected difficulty." % (i + 1))
		strategies[strategy] = true
	_check(strategies.size() == levels.size(), "CPU planners are independent.")


func _check_same_map(expected: TerritoryLayout, actual: TerritoryLayout) -> void:
	_check(expected != actual and expected.bounds == actual.bounds and expected.active_seed == actual.active_seed
		and expected.starting_territories == actual.starting_territories
		and expected.base_positions == actual.base_positions, "A fresh match reproduces the seeded starting territories.")
	for i in expected.cells.size():
		_check(expected.cells[i].polygon == actual.cells[i].polygon
			and expected.cells[i].site == actual.cells[i].site, "Repeated map sites and polygons are identical.")


func _select(picker: OptionButton, id: int) -> void:
	picker.select(picker.get_item_index(id))
	picker.item_selected.emit(picker.selected)


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _press_tab() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		push_error(message)
	return condition
