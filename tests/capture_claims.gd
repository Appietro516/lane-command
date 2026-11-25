extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.try_claim(MatchRegion.Owner.PLAYER, &"northwest")
	scene._process(17.0)
	await scene.get_tree().process_frame

	var viewport := scene.get_viewport()
	var camera := viewport.get_camera_3d()
	var target := scene.get_node("Regions/Northeast") as MatchRegion
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(target.global_position)
	viewport.push_input(click, true)
