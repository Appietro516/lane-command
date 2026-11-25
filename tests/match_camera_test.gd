extends SceneTree

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const STEP := 1.0 / 60.0
const PLAYER := MatchRegion.Owner.PLAYER

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	var camera := root.get_camera_3d() as StrategyCamera
	camera.set_process(false)
	await process_frame
	await process_frame

	var center := root.get_visible_rect().get_center()
	var overview := camera.position
	var overview_size := camera.size
	var angle := camera.rotation
	_click(center, MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(camera.size, overview_size), "Scroll starts a smooth transition.")
	_advance(camera, 1)
	_check(camera.size < overview_size and camera.size > overview_size / StrategyCamera.ZOOM_STEP,
		"One frame interpolates toward the new zoom.")
	for i in range(24):
		_click(center, MOUSE_BUTTON_WHEEL_UP)
	_advance(camera)
	_check(is_equal_approx(camera.size, StrategyCamera.MIN_SIZE), "Zoom stops at the close limit.")

	var hud := scene.get_node("%Overview") as Button
	var hud_point := hud.get_global_rect().get_center()
	_click(hud_point, MOUSE_BUTTON_WHEEL_DOWN)
	_mouse(hud_point, MOUSE_BUTTON_MIDDLE)
	_check(not camera.is_dragging(), "Middle drag cannot start on the HUD.")
	_mouse(hud_point, MOUSE_BUTTON_MIDDLE, false)
	_advance(camera)
	_check(is_equal_approx(camera.size, StrategyCamera.MIN_SIZE), "Wheel input over the HUD does not zoom.")

	var center_ground: Vector3 = scene._ground_point(center)
	_key(KEY_D, true)
	_advance(camera, 12)
	_key(KEY_D, false)
	var shifted: Vector2 = camera.unproject_position(center_ground)
	_check(shifted.x < center.x - 40.0 and is_equal_approx(shifted.y, center.y),
		"WASD pans horizontally along the screen axes.")
	_key(KEY_UP, true)
	_advance(camera, 80)
	_key(KEY_UP, false)
	_advance(camera)
	var top_focus: Vector3 = scene._ground_point(center)
	_check(is_equal_approx(top_focus.z, scene._layout.bounds.position.y),
		"Arrow-key panning clamps the focus to the map edge.")
	_check(camera.rotation == angle, "Panning and zoom preserve the strategy angle.")

	for i in range(24):
		_click(center, MOUSE_BUTTON_WHEEL_DOWN)
	_advance(camera)
	_check(is_equal_approx(camera.size, overview_size), "Zoom stops at the overview scale.")
	_key(KEY_HOME, true)
	_key(KEY_HOME, false)
	_advance(camera)
	_check(camera.position.distance_to(overview) < 0.001, "Home centers the overview.")

	for i in range(24):
		_click(center, MOUSE_BUTTON_WHEEL_UP)
	_advance(camera)
	_mouse(center - Vector2(410, 0), MOUSE_BUTTON_MIDDLE)
	_drag(center + Vector2(410, 0), Vector2(820, 0))
	_mouse(hud_point, MOUSE_BUTTON_MIDDLE, false)
	_advance(camera)
	_check(not camera.is_dragging() and camera.unproject_position(center_ground).x > center.x + 600,
		"Middle drag follows the pointer and ends over the HUD (dragging %s, screen x %.1f)." % [
			camera.is_dragging(), camera.unproject_position(center_ground).x,
		])

	var start := scene.get_region(TerritoryLayout.PLAYER_START) as MatchRegion
	var open_ground := Vector3(-11.0, 0.0, -1.2)
	var ground_pointer := camera.unproject_position(open_ground)
	_click(ground_pointer)
	_check(scene._selected_region_id == start.region_id, "Ground clicks use the moved camera.")
	var core := start.get_node("PlayerBase/Core") as Node3D
	_click(camera.unproject_position(core.global_position))
	_check(scene._selected_region_id == start.region_id, "A visible base selects its territory.")

	scene._begin_placement(&"barracks")
	_mouse(ground_pointer, MOUSE_BUTTON_MIDDLE)
	_drag(ground_pointer + Vector2(20, 10), Vector2(20, 10))
	_click(ground_pointer)
	_click(ground_pointer, MOUSE_BUTTON_RIGHT)
	_mouse(ground_pointer, MOUSE_BUTTON_MIDDLE, false)
	scene._physics_process(0.0)
	_check(scene._preview != null and scene.economy.barracks_count(PLAYER) == 0,
		"Dragging during placement neither places a building nor cancels placement.")
	_advance(camera)

	_click(camera.unproject_position(open_ground))
	_key(KEY_HOME, true)
	_key(KEY_HOME, false)
	_advance(camera)
	scene._physics_process(0.0)
	var buildings := scene.get_node("Buildings/Player")
	var barracks := buildings.get_child(0) as Node3D if buildings.get_child_count() > 0 else null
	_check(barracks != null and barracks.global_position.distance_to(open_ground) < 0.001,
		"Placement retains the exact clicked map point while the camera moves.")
	if barracks != null:
		_test_unit_orders(scene, camera, center, barracks)

	_click(hud_point)
	_advance(camera)
	_check(camera.position.distance_to(overview) < 0.001 and is_equal_approx(camera.size, overview_size),
		"The Overview button restores the opening camera framing.")
	scene.free()
	if _failures == 0:
		print("Strategy camera zoom, pan, overview, input isolation, and map picking checks passed.")
	quit(1 if _failures > 0 else 0)


func _test_unit_orders(scene: Node, camera: StrategyCamera, center: Vector2, barracks: Node3D) -> void:
	for i in range(4):
		_click(center, MOUSE_BUTTON_WHEEL_UP)
	_advance(camera)
	_mouse(center, MOUSE_BUTTON_MIDDLE)
	_drag(center + Vector2(400, 0), Vector2(400, 0))
	_mouse(center, MOUSE_BUTTON_MIDDLE, false)
	_advance(camera)

	var roof := barracks.get_node("RoofMarking") as Node3D
	_click(camera.unproject_position(roof.global_position))
	_check(scene._selected_region_id == TerritoryLayout.PLAYER_START,
		"Clicking a barracks after camera movement selects its region.")
	scene._process(3.75)
	var units := scene.get_node("Units")
	_check(units.get_child_count() == 1, "A player unit is available for picking.")
	if units.get_child_count() != 1:
		return
	var view := units.get_child(0) as Node3D
	var pointer := camera.unproject_position(view.global_position)
	_mouse(pointer, MOUSE_BUTTON_MIDDLE)
	_click(pointer)
	_mouse(pointer, MOUSE_BUTTON_MIDDLE, false)
	_check(scene.selected_unit() == null, "A camera drag cannot select the unit below it.")
	_click(pointer)
	var unit: MatchBattle.Unit = scene.selected_unit()
	_check(unit != null and unit.side == PLAYER, "Unit clicks use the moved and zoomed camera.")
	var destination := Vector3(-6.0, 0.0, 0.0)
	_click(camera.unproject_position(destination), MOUSE_BUTTON_RIGHT)
	_check(unit != null and unit.order == MatchBattle.Order.MOVE
		and unit.ordered_destination.distance_to(Vector2(destination.x, destination.z)) < 0.001,
		"Right-click orders use the intended map point after panning and zooming.")


func _advance(camera: StrategyCamera, frames := 80) -> void:
	for i in range(frames):
		camera._process(STEP)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(pointer: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_mouse(pointer, button)
	_mouse(pointer, button, false)


func _mouse(pointer: Vector2, button: MouseButton, pressed := true) -> void:
	var event := InputEventMouseButton.new()
	event.position = pointer
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)


func _drag(pointer: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pointer
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
