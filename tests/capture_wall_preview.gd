extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.set_physics_process(false)
	scene._begin_placement(&"wall")
	scene._wall_start = Vector2(-12.5, -4.2)
	await scene.get_tree().process_frame
	var camera := scene.get_viewport().get_camera_3d()
	scene._update_placement_preview(camera.unproject_position(Vector3(-8.6, 0, -3.2)))
	assert(scene._preview.visible and scene._preview_material.albedo_color == scene.VALID_PREVIEW)
