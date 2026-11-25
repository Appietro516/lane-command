extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const EPSILON := 0.001

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_layout(Vector2(18, 18), 2, 1, 1)
	_test_layout(Vector2(30, 18), 7, 2, 3)
	_test_layout(TerritoryLayout.DEFAULT_SIZE, 24, 1, 1)
	_test_layout(Vector2(51, 100), 43, 9, 4)
	_test_layout(Vector2(192, 18), 29, 8, 21)
	_test_layout(Vector2(192, 192), TerritoryLayout.MAX_REGIONS, 31, 64)
	_test_invalid_config()
	_test_scene()
	await _test_expanded_gameplay()
	if failures == 0:
		print("Generated territory and match startup checks passed.")
	quit(1 if failures > 0 else 0)


func _test_layout(size: Vector2, count: int, player_count: int, cpu_count: int) -> void:
	var original := TerritoryLayout.new(17, count, size, player_count, cpu_count)
	var repeated := TerritoryLayout.new(17, count, size, player_count, cpu_count)
	_check(original.cells.size() == count and original.bounds.size == size,
		"The generator uses the configured dimensions and region count.")
	_check(original.active_seed == 17 and repeated.active_seed == 17,
		"The layout exposes the seed used to generate it.")
	_check(original.player_start_ids == repeated.player_start_ids
		and original.cpu_start_ids == repeated.cpu_start_ids,
		"Same seed and settings reproduce starting ownership.")
	for i in range(original.cells.size()):
		var cell := original.cells[i]
		var same_cell := repeated.cells[i]
		_check(cell.id == same_cell.id and cell.site == same_cell.site
			and cell.polygon == same_cell.polygon and cell.neighbor_ids == same_cell.neighbor_ids,
			"Same seed reproduces sites, polygons, IDs and adjacency.")

	for map_seed in [0, 1, 17, 71, -1]:
		var layout := TerritoryLayout.new(map_seed, count, size, player_count, cpu_count)
		for i in range(layout.cells.size()):
			_check(layout.cells[i].id == original.cells[i].id, "Region IDs are stable across seeds.")
		if map_seed != 17:
			_check(layout.cells[0].polygon != original.cells[0].polygon,
				"A different seed changes the generated geometry.")
		_check_partition(layout)
		_check_starts(layout, player_count, cpu_count)


func _test_invalid_config() -> void:
	var fallback := TerritoryLayout.new(-13, -8, Vector2(0, -20), 8, 3)
	_check(fallback.bounds.size == TerritoryLayout.DEFAULT_SIZE
		and fallback.cells.size() == TerritoryLayout.MIN_REGIONS and fallback.active_seed == -13,
		"Invalid dimensions and too few regions fall back to a playable match.")
	_check_starts(fallback, 1, 1)
	_check_partition(fallback)

	var dense := TerritoryLayout.new(91, 1000000, Vector2(1, 1), 0, -14)
	_check(dense.bounds.size == Vector2.ONE * TerritoryLayout.MIN_DIMENSION and dense.cells.size() == 9,
		"The minimum dimensions and site spacing limit oversized region counts.")
	_check_starts(dense, 1, 1)
	_check_partition(dense)

	var nonfinite := TerritoryLayout.new(71, 11, Vector2(NAN, INF), 2, 4)
	_check(nonfinite.bounds.size == TerritoryLayout.DEFAULT_SIZE and nonfinite.cells.size() == 11,
		"Nonfinite dimensions fall back to the default size.")
	_check_starts(nonfinite, 2, 4)


func _check_starts(layout: TerritoryLayout, player_count: int, cpu_count: int) -> void:
	_check(layout.player_start_ids.size() == player_count and layout.cpu_start_ids.size() == cpu_count,
		"Each faction receives its configured number of starting regions.")
	_check(layout.player_start_ids.has(TerritoryLayout.PLAYER_START)
		and layout.cpu_start_ids.has(TerritoryLayout.CPU_START), "Each faction owns its base region.")
	for region_id in layout.player_start_ids:
		_check(not layout.cpu_start_ids.has(region_id), "Starting territories never overlap.")
	_check_connected(layout, layout.player_start_ids)
	_check_connected(layout, layout.cpu_start_ids)
	var separation := (layout.cells[0].site - layout.cells[-1].site).abs()
	var axis := Vector2.AXIS_Y if layout.bounds.size.y > layout.bounds.size.x else Vector2.AXIS_X
	_check(separation[axis] >= layout.bounds.size[axis] * 0.4, "Bases start at opposite ends of the map.")


func _check_connected(layout: TerritoryLayout, owned_ids: Array[StringName]) -> void:
	var visited: Array[StringName] = [owned_ids[0]]
	var frontier := 0
	while frontier < visited.size():
		for cell in layout.cells:
			if cell.id == visited[frontier]:
				for neighbor in cell.neighbor_ids:
					if owned_ids.has(neighbor) and not visited.has(neighbor):
						visited.append(neighbor)
				break
		frontier += 1
	_check(visited.size() == owned_ids.size(), "Each faction starts with connected territory.")


func _check_partition(layout: TerritoryLayout) -> void:
	var bounds := layout.bounds
	var area := 0.0
	var ids: Array[StringName] = []
	for i in range(layout.cells.size()):
		var cell := layout.cells[i]
		_check(not ids.has(cell.id), "Region IDs are unique.")
		ids.append(cell.id)
		var cell_area := _polygon_area(cell.polygon)
		_check(cell_area > 1.0 and not Geometry2D.triangulate_polygon(cell.polygon).is_empty(),
			"Every cell has a nondegenerate, triangulable polygon.")
		area += cell_area
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
	_check(absf(area - bounds.get_area()) < bounds.get_area() * 0.00001, "The cell polygons cover the entire map.")

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
		if start.distance_to(end) <= TerritoryLayout.EDGE_EPSILON:
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
	scene.map_width = 156.0
	scene.map_height = 192.0
	scene.region_count = 43
	scene.player_start_count = 6
	scene.cpu_start_count = 3
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
		if region.region_id in scene._layout.player_start_ids:
			owner = MatchRegion.Owner.PLAYER
		elif region.region_id in scene._layout.cpu_start_ids:
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
		if region.region_id in [TerritoryLayout.PLAYER_START, TerritoryLayout.CPU_START]:
			var base := region.get_node("PlayerBase" if owner == MatchRegion.Owner.PLAYER else "CPUBase") as Node3D
			var center := Vector2(base.global_position.x, base.global_position.z)
			var footprint := Rect2(center - MatchBattle.BASE_FOOTPRINT, MatchBattle.BASE_FOOTPRINT * 2.0)
			for corner in BattleNavigation.corners_of(footprint):
				_check(scene._layout.region_at(corner) == region.region_id,
					"Each base footprint is inside its starting region.")
		else:
			_check(region.get_child_count() == 2, "Only base regions contain a starting structure.")

	var claim_id: StringName = &""
	for owned_id in scene._layout.player_start_ids:
		var owned_region: MatchRegion = scene.get_region(owned_id)
		for neighbor_id in owned_region.neighbor_ids:
			if scene.owns_region(MatchRegion.Owner.NEUTRAL, neighbor_id):
				claim_id = neighbor_id
				break
		if claim_id != &"":
			break
	_check(scene.try_claim(MatchRegion.Owner.PLAYER, claim_id)
		and scene.owns_region(MatchRegion.Owner.PLAYER, claim_id),
		"Claims use the custom region count and the configured starting frontier.")

	var player_extra_id: StringName = scene._layout.player_start_ids[1]
	var cpu_extra_id: StringName = scene._layout.cpu_start_ids[0]
	scene._set_region_owner(player_extra_id, MatchRegion.Owner.CPU)
	scene._set_region_owner(cpu_extra_id, MatchRegion.Owner.NEUTRAL)
	scene.restart_match()
	_check(scene.owns_region(MatchRegion.Owner.PLAYER, player_extra_id)
		and scene.owns_region(MatchRegion.Owner.CPU, cpu_extra_id)
		and scene.owns_region(MatchRegion.Owner.NEUTRAL, claim_id),
		"Restart restores the configured multi-region starting territories.")

	scene.position = Vector3(45.0, 4.0, -30.0)
	scene.rotate_y(0.8)
	var player_start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	_check(scene.region_at_world_position(player_start.global_position) == TerritoryLayout.PLAYER_START,
		"World lookup accounts for the map transform.")
	scene.free()


func _test_expanded_gameplay() -> void:
	const PLAYER := MatchRegion.Owner.PLAYER
	const CPU := MatchRegion.Owner.CPU
	const NEUTRAL := MatchRegion.Owner.NEUTRAL
	root.size = Vector2i(1280, 800)
	var scene := MATCH_SCENE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var layout: TerritoryLayout = scene._layout
	_check(layout.cells.size() == 24 and layout.bounds.size == Vector2(60, 36),
		"The normal match entry point starts a larger 24-region map.")
	_check(scene.active_map_seed == scene.map_seed and str(scene.map_seed) in scene.get_node("%Overview").tooltip_text,
		"The active seed is available in the match and the overview tooltip.")
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	var target: MatchRegion
	for id in start.neighbor_ids:
		if scene.owns_region(NEUTRAL, id):
			var candidate: MatchRegion = scene.get_region(id)
			if absf(candidate.position.x) > 15.0 or absf(candidate.position.z) > 9.0:
				target = candidate
				break
	_check(target != null, "The larger world has a claim beyond the prototype bounds.")
	if target == null:
		scene.free()
		return

	await process_frame
	var camera := root.get_camera_3d() as StrategyCamera
	# Pan to the lower perimeter at close zoom, then return to overview for the click.
	var overview_size := camera.size
	camera._target_size = StrategyCamera.MIN_SIZE
	camera._pan(Vector2(0, 1000))
	camera._process(2.0)
	_check(camera.size < overview_size and absf(camera._focus.y - layout.bounds.end.y) < EPSILON,
		"The camera pans and zooms beyond the old bounds.")
	camera.reset_view(true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(target.global_position)
	root.push_input(click, true)
	await physics_frame
	await physics_frame
	_check(scene._selected_region_id == target.region_id, "A screen click selects the generated region.")
	_check(scene.try_claim(PLAYER, target.region_id) and scene.owns_region(PLAYER, target.region_id),
		"The generated adjacency permits a claim beyond the old bounds.")
	scene.economy.advance(14.0)
	var site := target.interior_point(func(point: Vector2) -> bool:
		return scene._placement_block_reason(PLAYER, &"barracks", scene._world_position(point)).is_empty())
	_check(site.is_finite() and scene.try_place_building(PLAYER, &"barracks", scene._world_position(site)),
		"A barracks can be placed in the new territory.")
	scene._process(15.0)
	var units: Array[MatchBattle.Unit] = scene._battle.active_units()
	_check(units.any(func(unit: MatchBattle.Unit) -> bool: return unit.side == PLAYER)
		and units.any(func(unit: MatchBattle.Unit) -> bool: return unit.side == CPU),
		"Both sides buy or operate barracks and produce units on the expanded map.")
	var battle: MatchBattle = scene._battle
	for timer in battle._timers:
		battle.set_barracks_active(timer, false)
	scene._advance_simulation(24.0)
	_check(units.any(func(unit: MatchBattle.Unit) -> bool: return unit.hp < MatchBattle.UNIT_HP),
		"Units from opposite ends engage in combat on the expanded map.")

	scene.restart_match()
	_check(scene._layout == layout and scene.active_map_seed == layout.active_seed
		and scene.get_region(target.region_id) == target and scene.owns_region(NEUTRAL, target.region_id)
		and scene.owns_region(PLAYER, TerritoryLayout.PLAYER_START)
		and scene.owns_region(CPU, TerritoryLayout.CPU_START)
		and scene._battle.active_units().is_empty() and scene.economy.barracks_count(PLAYER) == 0,
		"Restart preserves the active layout and seed and resets ownership, buildings and combat.")
	scene.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
