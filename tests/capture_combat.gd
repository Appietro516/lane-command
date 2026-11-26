extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._process(2.0)
	scene.try_place_building(MatchRegion.Owner.PLAYER, &"barracks", Vector3(-10.2, 0, -1.2))
	scene._process(7.75)
	await scene.get_tree().process_frame

	var viewport := scene.get_viewport()
	var camera := viewport.get_camera_3d()
	var combat_units := ScoutFixture.combat_units(scene._battle)
	var player_unit := scene._unit_views[combat_units.back().id] as Node3D
	_click(viewport, camera.unproject_position(player_unit.global_position), MOUSE_BUTTON_LEFT)
	_click(viewport, camera.unproject_position(Vector3(-5.0, 0, -5.0)), MOUSE_BUTTON_RIGHT)
	assert(scene.selected_unit() != null)
	assert(scene.selected_unit().order == MatchBattle.Order.MOVE)
	assert(scene._battle.set_unit_stance(MatchRegion.Owner.PLAYER, scene.selected_unit().id,
		MatchBattle.Stance.IDLE))
	scene._process(0.9)


func _click(viewport: Viewport, pointer: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = pointer
	viewport.push_input(event, true)
