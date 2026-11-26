extends SceneTree

const GAME := preload("res://game.tscn")
const MATCH := preload("res://main.tscn")
const Fortifications := preload("res://match/fortification_rules.gd")
const SCOUT_FIXTURE := preload("res://tests/scout_fixture.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const AREA_EPSILON := 0.001

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_shapes()
	else:
		for shape in MapSettings.SHAPE_NAMES:
			for map_seed in [-71, 0, 104729]:
				_test_partition(shape, Vector2(18, 18), 2, map_seed, 1)
				_test_partition(shape, Vector2(72, 31), 24, map_seed, 4)
				_test_partition(shape, Vector2(168, 192), 128, map_seed, 4)
		_test_setup()
		await _test_triangle_play()
	if _failures == 0:
		print("Map shape checks passed.")
	quit(int(_failures > 0))


func _test_partition(shape: MapSettings.Shape, dimensions: Vector2, count: int, map_seed: int,
		opponents: int) -> void:
	var layout := TerritoryLayout.new(map_seed, count, dimensions, 1, 1, opponents, shape)
	var reproducible := TerritoryLayout.new(map_seed, count, dimensions, 1, 1, opponents, shape)
	_check(layout.configuration_error.is_empty() and layout.cells.size() == count
		and layout.starting_territories.size() == opponents + 1,
		"%s can host %d requested regions and %d opponents at %s (%s)." % [
			MapSettings.SHAPE_NAMES[shape], count, opponents, dimensions, layout.configuration_error])
	if not layout.configuration_error.is_empty():
		return
	match shape:
		MapSettings.Shape.RECTANGLE:
			_check(layout.bounds.size == dimensions and layout.boundary.size() == 4,
				"Rectangle preserves both dimensions.")
		MapSettings.Shape.SQUARE:
			_check(layout.bounds.size == Vector2.ONE * dimensions.x and layout.boundary.size() == 4,
				"Square has four sides and equal dimensions.")
		MapSettings.Shape.TRIANGLE:
			_check(layout.boundary.size() == 3 and layout.boundary[0].y == layout.bounds.position.y,
				"Triangle has a north-facing apex.")
			for i in 3:
				_check(is_equal_approx(layout.boundary[i].distance_to(layout.boundary[(i + 1) % 3]),
					dimensions.x), "Triangle is equilateral in the map plane.")
	_check(layout.base_positions == reproducible.base_positions
		and layout.starting_territories == reproducible.starting_territories,
		"Same seed reproduces faction starts and ownership.")
	var area := 0.0
	var cells: Dictionary[StringName, TerritoryLayout.Cell] = {}
	var cell_bounds: Array[Rect2] = []
	for cell in layout.cells:
		var bounds := Rect2(cell.polygon[0], Vector2.ZERO)
		for point in cell.polygon:
			bounds = bounds.expand(point)
		cell_bounds.append(bounds)
	for i in layout.cells.size():
		var cell := layout.cells[i]
		var same := reproducible.cells[i]
		_check(cell.id == same.id and cell.polygon == same.polygon and cell.site == same.site
			and cell.neighbor_ids == same.neighbor_ids, "Same seed reproduces geometry and graph.")
		_check(not cells.has(cell.id) and layout.region_at(cell.site) == cell.id,
			"Distinct IDs resolve at their own sites.")
		cells[cell.id] = cell
		var cell_area := _area(cell.polygon)
		_check(cell_area > 1.0 and not Geometry2D.triangulate_polygon(cell.polygon).is_empty(),
			"Each territory has a usable polygon.")
		area += cell_area
		for point in cell.polygon:
			_check(layout.contains(point), "Cell vertices lie inside the playable boundary.")
		for j in range(i + 1, layout.cells.size()):
			if not cell_bounds[i].intersects(cell_bounds[j]):
				continue
			for overlap in Geometry2D.intersect_polygons(cell.polygon, layout.cells[j].polygon):
				_check(_area(overlap) < AREA_EPSILON, "Cells have no interior overlap.")
	var map_area := _area(layout.boundary)
	_check(absf(area - map_area) < map_area * 0.000001, "Cells cover the entire boundary.")

	var connected: Array[StringName] = [layout.cells[0].id]
	var index := 0
	while index < connected.size():
		var cell := cells[connected[index]]
		for neighbor in cell.neighbor_ids:
			_check(cells[neighbor].neighbor_ids.has(cell.id), "Neighbor edges are symmetric.")
			if neighbor not in connected:
				connected.append(neighbor)
		index += 1
	_check(connected.size() == count, "The region graph is connected.")
	var starts := PackedVector2Array()
	for id in layout.base_positions:
		var position := layout.base_positions[id]
		for point in BattleNavigation.corners_of(Rect2(position - MatchBattle.BASE_FOOTPRINT,
				MatchBattle.BASE_FOOTPRINT * 2.0)):
			_check(layout.region_at(point) == id, "Each entire base fits in its own region.")
		for other in starts:
			_check(other.distance_to(position) >= TerritoryLayout.BASE_SEPARATION,
				"Bases have separate approaches.")
		starts.append(position)


func _test_setup() -> void:
	var scene := GAME.instantiate()
	root.add_child(scene)
	var original: TerritoryLayout = scene._layout
	_select_shape(scene, MapSettings.Shape.TRIANGLE)
	scene._map_width_field.text = "18"
	scene._region_count_field.text = "4"
	scene._confirm_setup.pressed.emit()
	_check(scene._layout == original and scene._match_setup.visible and "2–3" in scene._difficulty_description.text,
		"Setup explains the shape-specific maximum and preserves the active match.")
	scene._region_count_field.text = "3"
	scene._seed_field.text = "9223372036854775808"
	scene._confirm_setup.pressed.emit()
	_check(scene._layout == original and "seed" in scene._difficulty_description.text,
		"Setup rejects seeds beyond signed 64-bit range.")
	scene._seed_field.text = "-9223372036854775808"
	scene._confirm_setup.pressed.emit()
	var triangle: TerritoryLayout = scene._layout
	_check(triangle != original and triangle.cells.size() == 3
		and scene.active_map_seed == -9223372036854775807 - 1,
		"Setup applies valid dimensions, shape, count and an exact signed seed.")
	scene._open_match_setup(false)
	scene._confirm_setup.pressed.emit()
	_check(scene._layout == triangle, "Restart with the same settings preserves the exact layout.")
	scene._open_match_setup(false)
	_select_shape(scene, MapSettings.Shape.SQUARE)
	scene._map_width_field.text = "80"
	scene._region_count_field.text = "18"
	scene._opponent_picker.select(3)
	scene._opponent_picker.item_selected.emit(3)
	scene._confirm_setup.pressed.emit()
	_check(scene._layout.bounds.size == Vector2(80, 80) and scene._battle._bases.size() == 5,
		"Changing shape and opponents rebuilds the map and all five independent factions.")
	for side in scene._battle._bases:
		_check(scene._expeditions.available(side).size() == 2, "Each faction receives two Scouts.")
	scene.free()

	var invalid := MATCH.instantiate()
	invalid.map_width = 10
	root.add_child(invalid)
	_check(invalid._layout == null and invalid._match_setup.visible,
		"An invalid launch config opens editable setup.")
	invalid._map_width_field.text = "60"
	invalid._confirm_setup.pressed.emit()
	_check(invalid._layout != null and not invalid._match_setup.visible,
		"Correcting launch settings starts the match.")
	invalid.free()


func _test_triangle_play() -> void:
	var scene := MATCH.instantiate()
	scene.map_shape = MapSettings.Shape.TRIANGLE
	scene.map_width = 66
	scene.region_count = 24
	scene.cpu_opponent_count = 4
	scene.legendary_count = 0
	scene.narrative_catalog = null
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var layout: TerritoryLayout = scene._layout
	var battle: MatchBattle = scene._battle
	var routes := battle.navigation
	var camera: StrategyCamera = scene._camera
	for corner in layout.boundary:
		_check(camera.is_position_in_frustum(scene._world_position(corner)), "Overview frames the entire triangle.")
	camera._pan(Vector2(-1000, -1000))
	_check(layout.contains(camera._target_focus), "Triangle camera pans within the playable border.")
	camera.reset_view(true)

	var exterior := layout.bounds.position + Vector2(2, 2)
	_check(layout.bounds.has_point(exterior) and layout.region_at(exterior).is_empty()
		and scene.region_at_world_position(scene._world_position(exterior)).is_empty(),
		"Empty corner space inside the bounding box has no owner.")
	scene._select_region(TerritoryLayout.PLAYER_START)
	scene._pick_map(camera.unproject_position(scene._world_position(exterior)))
	_check(scene._selected_region_id.is_empty(), "Clicking the triangle exterior selects no region.")
	_check(not routes.is_passable(exterior) and routes.path(exterior, Vector2.ZERO).is_empty()
		and routes.path(Vector2.ZERO, exterior).is_empty() and not routes.line_clear(Vector2.ZERO, exterior),
		"Navigation rejects either route endpoint outside the triangle.")
	_check(not routes.reachable_without_obstacle(Vector2.ZERO, exterior, 0.0, -1)
		and battle.spawn_unit(PLAYER, exterior) == null, "Breach routes and spawns reject exterior points.")

	var isolated := BattleNavigation.new(layout.bounds, layout.boundary).with_clearance(0.2)
	var choke := isolated.add_obstacle(Rect2(-30, -11, 60, 1))
	var north := Vector2(0, -20)
	_check(isolated.is_passable(north) and isolated.is_passable(Vector2.ZERO)
		and isolated.path(north, Vector2.ZERO).is_empty(),
		"Detour waypoints cannot route around a barrier through exterior corner space.")
	isolated.remove_obstacle(choke)
	_check(not isolated.path(north, Vector2.ZERO).is_empty(), "Removing the barrier restores the route.")

	var boundary_midpoint := layout.boundary[0].lerp(layout.boundary[2], 0.5)
	var edge_point := boundary_midpoint.move_toward(Vector2.ZERO, 0.08)
	_check(routes.contains(edge_point) and not routes.with_clearance(0.2).contains(edge_point),
		"Unit clearance applies to diagonal borders.")
	var player_base: Vector2 = battle._bases[PLAYER]
	var edge := Vector2(player_base.x, layout.bounds.end.y - 0.1)
	_check(layout.region_at(edge) == TerritoryLayout.PLAYER_START
		and not scene.try_place_building(PLAYER, &"farm", scene._world_position(edge))
		and not scene.try_place_building(PLAYER, &"barracks", scene._world_position(exterior)),
		"Building centers inside and outside the border cannot produce exterior footprints.")
	_check(not scene.try_place_wall(PLAYER, scene._world_position(edge),
		scene._world_position(edge + Vector2(1.5, 0))) and not scene.try_place_wall(PLAYER,
		scene._world_position(player_base), scene._world_position(exterior)),
		"Walls require both endpoints and all segment corners inside the map.")
	_check(not battle.outpost_site_clear(edge_point) and not battle.outpost_site_clear(exterior),
		"Claim outposts cannot reserve footprints that cross the boundary.")

	for side in battle._bases:
		_check(scene._expeditions.available(side).size() == 2, "Triangle starts have room for both Scouts.")
	var scouts: Array = scene._expeditions.available(PLAYER)
	if not scouts.is_empty():
		var scout: MatchBattle.Unit = battle.get_unit(scouts[0].unit_id)
		_check(not battle.order_move(PLAYER, scout.id, exterior),
			"A Scout cannot target the triangular bounding-box corner.")
	var unit := battle.spawn_unit(PLAYER, Vector2.ZERO)
	_check(unit != null and not battle.order_move(PLAYER, unit.id, exterior)
		and not battle.order_hold(PLAYER, unit.id, exterior), "Combat orders reject exterior ground.")

	var claimed := false
	for id: StringName in scene.get_region(TerritoryLayout.PLAYER_START).neighbor_ids:
		if scene.owns_region(NEUTRAL, id) and SCOUT_FIXTURE.claim(scene, PLAYER, id):
			var outpost: MatchBattle.Outpost = scene._outposts_by_region[id]
			claimed = routes.contains_footprint(Fortifications.footprint(outpost.position,
				MatchBattle.OUTPOST_FOOTPRINT * 2.0))
			break
	_check(claimed, "A Scout can reach and claim a valid neutral territory on the triangle.")
	scene.free()


func _select_shape(scene: Node, shape: MapSettings.Shape) -> void:
	scene._shape_picker.select(scene._shape_picker.get_item_index(shape))
	scene._shape_picker.item_selected.emit(scene._shape_picker.selected)


func _capture_shapes() -> void:
	const OUTPUT := "res://.godot/map-smoke"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for shape in MapSettings.SHAPE_NAMES:
		await _capture_match(shape, Vector2(18, 18), 2, 17, 1, OUTPUT)
		await _capture_match(shape, Vector2(100, 60), 128, 71, 4, OUTPUT)


func _capture_match(shape: MapSettings.Shape, dimensions: Vector2, regions: int, map_seed: int,
		opponents: int, output: String) -> void:
	var scene := MATCH.instantiate()
	scene.map_shape = shape
	scene.map_width = dimensions.x
	scene.map_height = dimensions.y
	scene.map_seed = map_seed
	scene.region_count = regions
	scene.cpu_opponent_count = opponents
	root.add_child(scene)
	scene.set_process(false)
	var name: String = MapSettings.SHAPE_NAMES[shape].to_lower()
	if scene._layout == null:
		_check(false, "Load the %s smoke scene with %d regions." % [name, regions])
	else:
		_check(scene._battle._bases.size() == opponents + 1, "Render every configured faction.")
		for side in scene._battle._bases:
			_check(scene._expeditions.available(side).size() == 2, "Every rendered start has two Scouts.")
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image != null and image.save_png("%s/%s-%d.png" % [output, name, regions]) == OK,
			"Capture the rendered %s match with %d regions." % [name, regions])
	scene.free()


func _area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in polygon.size():
		twice_area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice_area) * 0.5


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
