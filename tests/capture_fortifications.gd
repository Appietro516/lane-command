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
	var battle: MatchBattle = scene._battle
	var nest_target := _infantry(battle, 101, Vector2(-11.5, -1.7))
	var mortar_target := _infantry(battle, 102, Vector2(-4.85, 0.7))
	var splash_target := _infantry(battle, 103, Vector2(-4.55, 1.25))
	scene._process(MatchBattle.STEP)
	assert(nest_target.hp == 10.75 and mortar_target.hp == 7.0 and splash_target.hp == 7.0)
	assert(scene._shot_effects.get_child_count() == 2)
	# Hold the brief shot effects through the screenshot readback.
	scene._shot_effects.process_mode = Node.PROCESS_MODE_DISABLED
	scene._toggle_build_menu()
	await scene.get_tree().process_frame
	var camera := scene.get_viewport().get_camera_3d()
	scene._pick_map(camera.unproject_position(mortar + Vector3.UP * 0.65))
	assert(scene._range_ring.visible and scene._splash_ring.visible)


func _infantry(battle: MatchBattle, id: int, point: Vector2) -> MatchBattle.Unit:
	var unit := MatchBattle.Unit.new(id, MatchRegion.Owner.CPU, point)
	unit.order = MatchBattle.Order.HOLD
	unit.ordered_destination = point
	battle._units[id] = unit
	battle.unit_produced.emit(unit)
	return unit
