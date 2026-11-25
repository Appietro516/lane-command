extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const ADJACENCY := {
	&"player_start": [&"northwest", &"southwest"],
	&"northwest": [&"player_start", &"northeast", &"southwest"],
	&"southwest": [&"player_start", &"northwest", &"southeast"],
	&"northeast": [&"northwest", &"southeast", &"cpu_start"],
	&"southeast": [&"southwest", &"northeast", &"cpu_start"],
	&"cpu_start": [&"northeast", &"southeast"],
}

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var match_scene := MATCH_SCENE.instantiate()
	root.add_child(match_scene)

	var camera: Camera3D = root.get_camera_3d()
	_check(camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"The match starts with an active orthographic camera.")

	var regions := {}
	for child in match_scene.get_node("Regions").get_children():
		var region := child as MatchRegion
		_check(region != null, "Each region node has authored region data.")
		if region == null:
			continue
		_check(not regions.has(region.region_id), "Region IDs are unique.")
		regions[region.region_id] = region

	_check(regions.size() == ADJACENCY.size(), "The match has six regions.")
	for id in ADJACENCY:
		var region: MatchRegion = regions.get(id)
		_check(region != null, "Authored region exists: %s" % id)
		if region == null:
			continue
		var neighbors := region.neighbor_ids.duplicate()
		neighbors.sort()
		var expected_neighbors: Array = ADJACENCY[id].duplicate()
		expected_neighbors.sort()
		_check(neighbors == expected_neighbors, "Authored neighbors match for %s." % id)
		var expected_owner := MatchRegion.Owner.NEUTRAL
		if id == &"player_start":
			expected_owner = MatchRegion.Owner.PLAYER
		elif id == &"cpu_start":
			expected_owner = MatchRegion.Owner.CPU
		_check(region.region_owner == expected_owner, "Initial ownership matches for %s." % id)
		_check(region.geometry != null and region.geometry.mesh != null,
			"Region %s refers to a tile mesh." % id)
		if region.geometry != null:
			var material := region.geometry.material_override as StandardMaterial3D
			_check(material != null and material.albedo_color == MatchRegion.OWNER_COLORS[expected_owner],
				"Tile color matches initial ownership for %s." % id)

	var player_base: Node3D = match_scene.get_node("Regions/PlayerStart/PlayerBase")
	var cpu_base: Node3D = match_scene.get_node("Regions/CPUStart/CPUBase")
	var corridor: MeshInstance3D = match_scene.get_node("Corridor")
	var corridor_bounds := corridor.get_aabb()
	var left_endpoint := corridor.to_global(Vector3(corridor_bounds.position.x, 0, 0))
	var right_endpoint := corridor.to_global(Vector3(corridor_bounds.end.x, 0, 0))
	_check(_on_map(left_endpoint).is_equal_approx(_on_map(player_base.global_position))
		and _on_map(right_endpoint).is_equal_approx(_on_map(cpu_base.global_position)),
		"The straight corridor runs between the two bases.")

	if camera != null:
		for node in match_scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for corner in range(8):
				var point := mesh_instance.to_global(mesh_instance.get_aabb().get_endpoint(corner))
				_check(camera.is_position_in_frustum(point),
					"The camera includes every corner of %s." % mesh_instance.get_path())

	if failures == 0:
		print("Match startup checks passed.")
	quit(1 if failures > 0 else 0)


func _on_map(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
