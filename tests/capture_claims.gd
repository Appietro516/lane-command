extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	var player_start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	var first_claim: StringName = player_start.neighbor_ids[0]
	scene.try_claim(MatchRegion.Owner.PLAYER, first_claim)
	scene._process(17.0)
	await scene.get_tree().process_frame

	var viewport := scene.get_viewport()
	var camera := viewport.get_camera_3d()
	var target: MatchRegion
	var claimed: MatchRegion = scene.get_region(first_claim)
	for neighbor_id in claimed.neighbor_ids:
		if scene.owns_region(MatchRegion.Owner.NEUTRAL, neighbor_id):
			target = scene.get_region(neighbor_id)
			if not player_start.neighbor_ids.has(neighbor_id):
				break
	if target == null:
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(target.global_position)
	viewport.push_input(click, true)
