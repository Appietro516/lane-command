extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.economy.advance(30.0)
	var player := MatchRegion.Owner.PLAYER
	var nest := Vector3(-10, 0, -1.7)
	var mortar := Vector3(-7.7, 0, 0.7)
	assert(scene.try_place_building(player, &"machine_gun_nest", nest))
	assert(scene.try_place_building(player, &"mortar", mortar))
	assert(scene.try_place_wall(player, Vector3(-12.5, 0, -4.1), Vector3(-8.4, 0, -3.5)))
	scene._toggle_build_menu()
	await scene.get_tree().process_frame
	var camera := scene.get_viewport().get_camera_3d()
	scene._pick_map(camera.unproject_position(mortar + Vector3.UP * 0.65))
	assert(scene._range_ring.visible and scene._splash_ring.visible)
