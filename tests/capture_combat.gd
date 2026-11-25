extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._process(2.0)
	scene.try_place_building(MatchRegion.Owner.PLAYER, &"barracks", Vector3(-10.2, 0, -1.2))
	scene._process(7.75)
	await scene.get_tree().process_frame

	var viewport := scene.get_viewport()
	var camera := viewport.get_camera_3d()
	var units := scene.get_node("Units")
	var player_unit := units.get_child(3) as Node3D
	_click(viewport, camera.unproject_position(player_unit.global_position), MOUSE_BUTTON_LEFT)
	_click(viewport, camera.unproject_position(Vector3(-5.0, 0, -5.0)), MOUSE_BUTTON_RIGHT)
	assert(scene.selected_unit() != null)
	assert(scene.selected_unit().order == MatchBattle.Order.MOVE)
	scene._process(0.9)


func _click(viewport: Viewport, pointer: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = pointer
	viewport.push_input(event, true)
