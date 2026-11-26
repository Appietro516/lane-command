class_name BattleNavigation
extends RefCounted
## Owns a private native navigation map for one movement clearance.

const MeshBuild := preload("res://match/battle_navigation_mesh.gd")

const MESH_MARGIN := 0.02
const MESH_CELL := 0.01
const CHUNK_SIZE := 12.0
const MAX_CACHED_REQUESTS := 512
const MAX_CHANGE_HISTORY := 64

class Chunk:
	var bounds: Rect2
	var region: RID
	var dirty := true
	var generation := 0
	var pending_generation := -1
	var pending: MeshBuild
	var task := -1
	var outline: PackedVector2Array

const OBSTACLES_PER_BRANCH := 6

class Change:
	var bounds: Rect2
	var removed: bool

	func _init(footprint: Rect2, demolition: bool) -> void:
		bounds = footprint
		removed = demolition


class Obstacle:
	var rect: Rect2
	var transform: Transform2D
	var inverse: Transform2D
	var bounds: Rect2
	var corners: PackedVector2Array

	func _init(footprint: Rect2, angle: float) -> void:
		var center := footprint.get_center()
		rect = Rect2(-footprint.size * 0.5, footprint.size)
		transform = Transform2D(angle, center)
		inverse = transform.affine_inverse()
		bounds = transform * rect
		corners = BattleNavigation.corners_of(rect)

	func footprint() -> Rect2:
		return Rect2(rect.position + transform.origin, rect.size)


class ObstacleBranch:
	var bounds: Rect2
	var ids := PackedInt64Array()
	var left: ObstacleBranch
	var right: ObstacleBranch


var revision := 0
var _bounds: Rect2
var _boundary: PackedVector2Array
var _boundary_clearance: float
var _obstacles: Dictionary[int, Obstacle] = {}
var _next_obstacle_id := 0
var _obstacle_tree: ObstacleBranch
var _clearance_routes: Dictionary[float, BattleNavigation] = {}
var _map: RID
var _chunks: Array[Chunk] = []
var _dirty := false
var _pending_tasks := 0
var _ready_to_publish := false
var _walkable: PackedVector2Array
var _requests: Dictionary[Vector4, PackedVector2Array] = {}
var _changes: Array[Change] = []


func _init(bounds: Rect2, boundary := PackedVector2Array(), boundary_clearance := 0.0) -> void:
	_bounds = bounds
	_boundary = boundary
	_boundary_clearance = boundary_clearance


func add_obstacle(footprint: Rect2, angle := 0.0) -> int:
	var id := _next_obstacle_id
	_insert_obstacle(id, footprint, angle)
	return id


func _insert_obstacle(id: int, footprint: Rect2, angle: float) -> void:
	_next_obstacle_id = id + 1
	var obstacle := Obstacle.new(footprint, angle)
	_obstacles[id] = obstacle
	_obstacle_tree = null
	revision += 1
	_geometry_changed((obstacle.transform * obstacle.rect.grow(MESH_MARGIN)))
	for clearance in _clearance_routes:
		_clearance_routes[clearance]._insert_obstacle(id, obstacle.footprint().grow(clearance),
			obstacle.transform.get_rotation())


func remove_obstacle(id: int) -> void:
	var obstacle := _obstacles.get(id) as Obstacle
	if _obstacles.erase(id):
		_obstacle_tree = null
		revision += 1
		_geometry_changed(obstacle.transform * obstacle.rect.grow(MESH_MARGIN), true)
		for routes in _clearance_routes.values():
			routes.remove_obstacle(id)


## Maintain one native map per movement clearance, with matching obstacle IDs.
func with_clearance(clearance: float) -> BattleNavigation:
	if clearance == 0.0:
		return self
	var routes := _clearance_routes.get(clearance) as BattleNavigation
	if routes == null:
		routes = BattleNavigation.new(_bounds.grow(-clearance), _boundary, _boundary_clearance + clearance)
		for id in _obstacles:
			var obstacle := _obstacles[id]
			routes._insert_obstacle(id, obstacle.footprint().grow(clearance),
				obstacle.transform.get_rotation())
		routes.revision = revision
		_clearance_routes[clearance] = routes
	return routes


## Check whether breaching one specific footprint reconnects a blocked order.
func reachable_without_obstacle(start: Vector2, end: Vector2, clearance: float,
		ignored_id: int) -> bool:
	var routes := BattleNavigation.new(_bounds.grow(-clearance), _boundary, _boundary_clearance + clearance)
	for id in _obstacles:
		if id != ignored_id:
			var obstacle := _obstacles[id]
			routes.add_obstacle(obstacle.footprint().grow(clearance), obstacle.transform.get_rotation())
	return not routes.path(start, end).is_empty()


func contains(point: Vector2) -> bool:
	if _boundary.is_empty():
		return point.is_finite() and _bounds.has_point(point)
	return MapSettings.contains_in(_boundary, point, _boundary_clearance)


func contains_footprint(polygon: PackedVector2Array) -> bool:
	for corner in polygon:
		if not contains(corner):
			return false
	return not polygon.is_empty()


func is_passable(point: Vector2) -> bool:
	if not contains(point):
		return false
	for id in _obstacles:
		var obstacle := _obstacles[id]
		if obstacle.bounds.has_point(point) and obstacle.rect.has_point(obstacle.inverse * point):
			return false
	return true


func line_clear(start: Vector2, end: Vector2, ignored_obstacle := -1,
		allow_exit := false) -> bool:
	# A segment between two points inside a convex boundary stays inside it.
	return contains(start) and contains(end) and _first_blocker(start, end, ignored_obstacle, allow_exit) == -1


func _first_blocker(start: Vector2, end: Vector2, ignored_obstacle := -1,
		allow_exit := false) -> int:
	var low := start.min(end)
	var high := start.max(end)
	if _obstacles.size() > OBSTACLES_PER_BRANCH:
		if _obstacle_tree == null:
			var ids: Array[int] = []
			ids.assign(_obstacles.keys())
			_obstacle_tree = _build_obstacle_tree(ids)
		return _branch_blocker(_obstacle_tree, start, end, low, high,
			(end - start).orthogonal(), ignored_obstacle, allow_exit)
	for id in _obstacles:
		if id != ignored_obstacle and _blocks_segment(_obstacles[id], start, end, low, high, allow_exit):
			return id
	return -1


func _build_obstacle_tree(ids: Array[int]) -> ObstacleBranch:
	var branch := ObstacleBranch.new()
	branch.bounds = _obstacles[ids[0]].bounds
	for i in range(1, ids.size()):
		branch.bounds = branch.bounds.merge(_obstacles[ids[i]].bounds)
	if ids.size() <= OBSTACLES_PER_BRANCH:
		branch.ids = PackedInt64Array(ids)
		return branch

	var axis := Vector2.AXIS_X if branch.bounds.size.x >= branch.bounds.size.y else Vector2.AXIS_Y
	ids.sort_custom(func(a: int, b: int) -> bool:
		return _obstacles[a].transform.origin[axis] < _obstacles[b].transform.origin[axis])
	var middle := ids.size() / 2
	branch.left = _build_obstacle_tree(ids.slice(0, middle))
	branch.right = _build_obstacle_tree(ids.slice(middle))
	return branch


func _branch_blocker(branch: ObstacleBranch, start: Vector2, end: Vector2,
		low: Vector2, high: Vector2, normal: Vector2, ignored: int, allow_exit: bool) -> int:
	var bounds := branch.bounds
	if not _overlaps_bounds(bounds, low, high):
		return -1
	# Reject branches on one side of the segment's line. Leave a margin for
	# floating point rounding. Leaves still use the exact rotated footprints.
	var half_extents := bounds.size * 0.5 + Vector2(0.001, 0.001)
	if absf(normal.dot(bounds.get_center() - start)) > normal.abs().dot(half_extents):
		return -1
	if branch.left != null:
		var hit := _branch_blocker(branch.left, start, end, low, high, normal, ignored, allow_exit)
		if hit != -1:
			return hit
		return _branch_blocker(branch.right, start, end, low, high, normal, ignored, allow_exit)
	for id in branch.ids:
		if id != ignored and _blocks_segment(_obstacles[id], start, end, low, high, allow_exit):
			return id
	return -1


static func _overlaps_bounds(bounds: Rect2, low: Vector2, high: Vector2) -> bool:
	return high.x >= bounds.position.x and low.x <= bounds.end.x \
		and high.y >= bounds.position.y and low.y <= bounds.end.y


static func _blocks_segment(obstacle: Obstacle, start: Vector2, end: Vector2,
		low: Vector2, high: Vector2, allow_exit: bool) -> bool:
	if not _overlaps_bounds(obstacle.bounds, low, high):
		return false
	var local_start := obstacle.inverse * start
	var local_end := obstacle.inverse * end
	if obstacle.rect.has_point(local_start):
		# A new building can cover a unit. Let it walk out of that footprint.
		return not allow_exit or obstacle.rect.has_point(local_end)
	if obstacle.rect.has_point(local_end):
		return true
	for edge in range(4):
		if Geometry2D.segment_intersects_segment(local_start, local_end, obstacle.corners[edge],
				obstacle.corners[(edge + 1) % 4]) != null:
			return true
	return false


func path(start: Vector2, end: Vector2) -> PackedVector2Array:
	if not contains(start) or not is_passable(end):
		return PackedVector2Array()
	if _first_blocker(start, end, -1, true) == -1:
		return PackedVector2Array([end])

	var key := Vector4(start.x, start.y, end.x, end.y)
	if _requests.has(key):
		return _requests[key].duplicate()
	var route := _native_path(start, end)
	if _requests.size() >= MAX_CACHED_REQUESTS:
		_requests.clear()
	_requests[key] = route.duplicate()
	return route


func _native_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	_ensure_map()
	if _dirty:
		_update_chunks(true)
	var raw := NavigationServer2D.map_get_path(_map, start, end, true)
	var route := _safe_route(raw, start, end)
	if route.is_empty() and not raw.is_empty() and raw[-1].is_equal_approx(end):
		# The funnel can cut across a narrow post at a fuzzy seam. The
		# midpoint variant takes the same corridor through each portal.
		route = _safe_route(NavigationServer2D.map_get_path(_map, start, end, false), start, end)
	return route


func _safe_route(raw: PackedVector2Array, start: Vector2, end: Vector2) -> PackedVector2Array:
	var route := PackedVector2Array()
	if raw.is_empty():
		return route
	# Native queries project endpoints and can return partial paths. Connect
	# endpoints to the live geometry and accept only a complete safe route.
	var previous := start
	for i in raw.size():
		var point := raw[i]
		if i == raw.size() - 1:
			if point.is_equal_approx(end):
				point = end
			elif not line_clear(point, end):
				return PackedVector2Array()
		if previous.is_equal_approx(point):
			continue
		if not line_clear(previous, point, -1, route.is_empty()):
			return PackedVector2Array()
		route.append(point)
		previous = point
	if previous != end:
		if not line_clear(previous, end, -1, route.is_empty()):
			return PackedVector2Array()
		route.append(end)
	return route


func route_affected(start: Vector2, destination: Vector2, waypoints: PackedVector2Array,
		since: int) -> bool:
	if since == revision:
		return false
	var first := _changes.size() - (revision - since)
	if since < 0 or first < 0 or waypoints.is_empty():
		return true
	for index in range(first, _changes.size()):
		var change := _changes[index]
		if change.removed:
			# Demolition only warrants a detour change when it opens a shortcut.
			if waypoints.size() > 1 and _overlaps_bounds(change.bounds,
					start.min(destination), start.max(destination)) \
					and line_clear(start, destination, -1, true):
				return true
			continue
		var previous := start
		for point in waypoints:
			if _overlaps_bounds(change.bounds, previous.min(point), previous.max(point)) \
					and not line_clear(previous, point, -1, previous == start):
				return true
			previous = point
	return false


func _geometry_changed(bounds: Rect2, removed := false) -> void:
	_requests.clear()
	_changes.append(Change.new(bounds, removed))
	if _changes.size() > MAX_CHANGE_HISTORY:
		_changes.pop_front()
	for chunk in _chunks:
		if chunk.bounds.grow(MESH_MARGIN).intersects(bounds, true):
			chunk.generation += 1
			chunk.dirty = true
			_dirty = true
			_ready_to_publish = false


## Launch dirty bakes together after the simulation's obstacle mutations.
func update() -> void:
	if _map.is_valid() and (_pending_tasks > 0 or (_dirty and not _ready_to_publish)):
		_update_chunks(false)
	for routes in _clearance_routes.values():
		routes.update()


func _ensure_map() -> void:
	if _map.is_valid():
		return
	_map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(_map, MESH_CELL)
	NavigationServer2D.map_set_use_async_iterations(_map, false)
	NavigationServer2D.map_set_edge_connection_margin(_map, MESH_MARGIN * 0.5)
	NavigationServer2D.map_set_active(_map, true)
	_walkable = corners_of(_bounds)
	if not _boundary.is_empty():
		_walkable = PackedVector2Array()
		for i in _boundary.size():
			var point := _boundary[i]
			var before := (point - _boundary[posmod(i - 1, _boundary.size())]).normalized()
			var after := (_boundary[(i + 1) % _boundary.size()] - point).normalized()
			var tangent := before + after
			var inward := Vector2(-tangent.y, tangent.x).normalized()
			_walkable.append(point + inward * ((_boundary_clearance + MESH_MARGIN)
				/ inward.dot(Vector2(-after.y, after.x))))
	var columns := ceili(_bounds.size.x / CHUNK_SIZE)
	var rows := ceili(_bounds.size.y / CHUNK_SIZE)
	var size := _bounds.size / Vector2(columns, rows)
	for y in rows:
		for x in columns:
			var chunk := Chunk.new()
			chunk.bounds = Rect2(_bounds.position + size * Vector2(x, y), size)
			var outlines := Geometry2D.intersect_polygons(_walkable, corners_of(chunk.bounds))
			if not outlines.is_empty():
				chunk.outline = outlines[0]
				_chunks.append(chunk)
	_dirty = true


func _chunk_source(chunk: Chunk) -> MeshBuild:
	var source := MeshBuild.new()
	source.outline = chunk.outline
	for obstacle in _obstacles.values():
		if chunk.bounds.grow(MESH_MARGIN * 2).intersects(obstacle.bounds, true):
			source.obstructions.append(obstacle.transform *
				corners_of(obstacle.rect.grow(MESH_MARGIN)))
	return source


func _update_chunks(immediate: bool) -> void:
	var all_ready := true
	for chunk in _chunks:
		if chunk.task != -1 and WorkerThreadPool.is_task_completed(chunk.task):
			WorkerThreadPool.wait_for_task_completion(chunk.task)
			chunk.task = -1
			_pending_tasks -= 1
		if not chunk.dirty:
			if chunk.task == -1:
				chunk.pending = null
			continue
		if chunk.task == -1 and chunk.pending != null and chunk.pending_generation == chunk.generation:
			continue
		if not immediate:
			all_ready = false
			if chunk.task == -1:
				chunk.pending = _chunk_source(chunk)
				chunk.pending_generation = chunk.generation
				chunk.task = WorkerThreadPool.add_task(chunk.pending.build.bind(MESH_CELL),
					false, "Battle navigation chunk")
				_pending_tasks += 1
	if not immediate:
		# Godot synchronizes connectivity for the whole map. Defer that work
		# until a detour actually needs the new regions.
		_ready_to_publish = all_ready
		return
	if not _dirty:
		return

	for chunk in _chunks:
		if not chunk.dirty:
			continue
		if chunk.task == -1 and chunk.pending != null and chunk.pending_generation == chunk.generation:
			_publish(chunk, chunk.pending.polygon)
			chunk.pending = null
		else:
			# Commands and blocked movement need an answer in this fixed step.
			# Supersede any in-flight snapshot without waiting for its worker.
			var source := _chunk_source(chunk)
			source.build(MESH_CELL)
			_publish(chunk, source.polygon)
	_dirty = false
	_ready_to_publish = false
	NavigationServer2D.map_force_update(_map)


func _publish(chunk: Chunk, polygon: NavigationPolygon) -> void:
	if not chunk.region.is_valid():
		chunk.region = NavigationServer2D.region_create()
		NavigationServer2D.region_set_use_async_iterations(chunk.region, false)
		NavigationServer2D.region_set_map(chunk.region, _map)
	NavigationServer2D.region_set_navigation_polygon(chunk.region, polygon)
	chunk.dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _map.is_valid():
		for chunk in _chunks:
			if chunk.task != -1:
				WorkerThreadPool.wait_for_task_completion(chunk.task)
			if chunk.region.is_valid():
				NavigationServer2D.free_rid(chunk.region)
		NavigationServer2D.free_rid(_map)


static func corners_of(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])
