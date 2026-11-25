extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const EPSILON := 0.001

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for region_count in range(TerritoryLayout.MIN_REGIONS, TerritoryLayout.MAX_REGIONS + 1):
		_test_layout(region_count)
	_test_scene()
	if failures == 0:
		print("Generated territory and match startup checks passed.")
	quit(1 if failures > 0 else 0)


func _test_layout(region_count: int) -> void:
	var original := TerritoryLayout.new(17, region_count)
	var repeated := TerritoryLayout.new(17, region_count)
	_check(original.cells.size() == region_count, "The generator supports %d regions." % region_count)
	for i in range(original.cells.size()):
		var cell := original.cells[i]
		var same_cell := repeated.cells[i]
		_check(cell.id == same_cell.id and cell.polygon == same_cell.polygon
			and cell.neighbor_ids == same_cell.neighbor_ids, "Same seed reproduces the map and IDs.")

	for map_seed in [0, 1, 17, 71, -1]:
		var layout := TerritoryLayout.new(map_seed, region_count)
		_check(layout.cells[2].id == original.cells[2].id, "Region IDs are stable across seeds.")
		if map_seed != 17:
			_check(layout.cells[2].polygon != original.cells[2].polygon,
				"A different seed changes the generated geometry.")
		_check_partition(layout)


func _check_partition(layout: TerritoryLayout) -> void:
	var bounds := TerritoryLayout.BOUNDS
	var area := 0.0
	var ids: Array[StringName] = []
	for i in range(layout.cells.size()):
		var cell := layout.cells[i]
		_check(not ids.has(cell.id), "Region IDs are unique.")
		ids.append(cell.id)
		area += _polygon_area(cell.polygon)
		_check(layout.region_at(cell.site) == cell.id and Geometry2D.is_point_in_polygon(cell.site, cell.polygon),
			"Every cell contains its generating site.")
		for point in cell.polygon:
			_check(bounds.grow(EPSILON).has_point(point), "Cell vertices stay within the map.")
		for j in range(i + 1, layout.cells.size()):
			var other := layout.cells[j]
			for overlap in Geometry2D.intersect_polygons(cell.polygon, other.polygon):
				_check(_polygon_area(overlap) < EPSILON, "Distinct cells have no area in common.")
			var shared_edge := _have_common_edge(cell.polygon, other.polygon)
			_check(cell.neighbor_ids.has(other.id) == shared_edge
				and other.neighbor_ids.has(cell.id) == shared_edge,
				"Neighbors share a positive-length polygon edge in both directions.")
	_check(absf(area - bounds.get_area()) < EPSILON, "The cell polygons cover the entire map.")

	for y in range(13):
		for x in range(21):
			var point := bounds.position + bounds.size * Vector2(x / 20.0, y / 12.0)
			var id := layout.region_at(point)
			var valid := false
			for cell in layout.cells:
				if cell.id == id:
					valid = Geometry2D.is_point_in_polygon(point, cell.polygon)
					for i in range(cell.polygon.size()):
						var closest := Geometry2D.get_closest_point_to_segment(point, cell.polygon[i],
							cell.polygon[(i + 1) % cell.polygon.size()])
						valid = valid or closest.distance_to(point) < EPSILON
			_check(valid, "An in-bounds point resolves to a region containing it.")
	_check(layout.region_at(bounds.position - Vector2.ONE) == &"", "Off-map points resolve to no region.")


func _have_common_edge(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for i in range(first.size()):
		var start := first[i]
		var end := first[(i + 1) % first.size()]
		if start.distance_to(end) <= EPSILON:
			continue
		for j in range(second.size()):
			if start.distance_to(second[(j + 1) % second.size()]) < EPSILON \
					and end.distance_to(second[j]) < EPSILON:
				return true
	return false


func _polygon_area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for i in range(points.size()):
		sum += points[i].cross(points[(i + 1) % points.size()])
	return absf(sum) * 0.5


func _test_scene() -> void:
	var scene := MATCH_SCENE.instantiate()
	scene.region_count = 7
	scene.map_seed = 71
	root.add_child(scene)
	scene.set_process(false)
	var camera := root.get_camera_3d()
	_check(camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"The match starts with an active orthographic camera.")
	var regions := scene.get_node("Regions")
	_check(regions.get_child_count() == scene.region_count, "The match uses the configured region count.")
	for region: MatchRegion in regions.get_children():
		var owner := MatchRegion.Owner.NEUTRAL
		match region.region_id:
			TerritoryLayout.PLAYER_START:
				owner = MatchRegion.Owner.PLAYER
			TerritoryLayout.CPU_START:
				owner = MatchRegion.Owner.CPU
		_check(region.region_owner == owner, "Generated regions initialize with their correct owners.")
		_check(scene.region_at_world_position(region.global_position) == region.region_id,
			"World lookup resolves each generated region at its site.")
		var material := region.geometry.material_override as StandardMaterial3D
		_check(region.geometry.mesh != null and material.albedo_color == MatchRegion.OWNER_COLORS[owner],
			"Generated geometry uses the correct owner color.")
		for node in region.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for i in range(8):
				var point := mesh.to_global(mesh.get_aabb().get_endpoint(i))
				_check(camera.is_position_in_frustum(point), "The strategy camera frames the map and bases.")
		if owner != MatchRegion.Owner.NEUTRAL:
			var base := region.get_node("PlayerBase" if owner == MatchRegion.Owner.PLAYER else "CPUBase") as Node3D
			_check(scene.region_at_world_position(base.global_position) == region.region_id,
				"Each base is inside its starting region.")
			for slot: Marker3D in region.get_node("BarracksSlots").get_children():
				_check(scene.region_at_world_position(slot.global_position) == region.region_id,
					"Each barracks slot is inside its starting region.")

	scene.position = Vector3(45.0, 4.0, -30.0)
	scene.rotate_y(0.8)
	var player_start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	_check(scene.region_at_world_position(player_start.global_position) == TerritoryLayout.PLAYER_START,
		"World lookup accounts for the map transform.")
	scene.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
