extends RefCounted

const Catalog := preload("res://match/unit_catalog.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var x := -3.0
	var selected: MatchBattle.Unit
	for type_id: StringName in Catalog.DEFINITIONS:
		selected = battle.spawn_unit(MatchRegion.Owner.PLAYER, Vector2(x, 0.0), type_id)
		var opponent := battle.spawn_unit(MatchRegion.Owner.CPU, Vector2(x, 2.0), type_id)
		assert(selected != null and opponent != null)
		x += 3.0
	await scene.get_tree().process_frame
	var camera := scene.get_viewport().get_camera_3d()
	var view := scene._unit_views[selected.id] as MeshInstance3D
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = camera.unproject_position(view.global_position)
	scene.get_viewport().push_input(event, true)
	assert(scene.selected_unit() == selected)
