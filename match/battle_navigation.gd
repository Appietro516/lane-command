class_name BattleNavigation
extends RefCounted
## Routes ground positions around static footprints using their corners as waypoints.

const CORNER_CLEARANCE := 0.025
const MAX_CACHED_ENDPOINTS := 256
const OBSTACLES_PER_BRANCH := 6

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
var _obstacles: Dictionary[int, Obstacle] = {}
var _next_obstacle_id := 0
var _obstacle_tree: ObstacleBranch
var _clearance_routes: Dictionary[float, BattleNavigation] = {}
var _graph := AStar2D.new()
var _graph_revision := -1
var _removed_obstacles := PackedInt64Array()
# For each rejected link, remember one obstacle that must disappear before the
# link can become visible. A packed pair keeps this index compact.
var _blocked_links: Dictionary[int, PackedInt64Array] = {}
var _start_links: Dictionary[Vector2, PackedInt64Array] = {}
var _end_links: Dictionary[Vector2, PackedInt64Array] = {}


func _init(bounds: Rect2) -> void:
	_bounds = bounds


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
	# An addition can invalidate any existing link. Rebuild on the next detour.
	_graph_revision = -1
	_removed_obstacles.clear()
	for clearance in _clearance_routes:
		_clearance_routes[clearance]._insert_obstacle(id, obstacle.footprint().grow(clearance),
			obstacle.transform.get_rotation())


func remove_obstacle(id: int) -> void:
	if _obstacles.erase(id):
		_obstacle_tree = null
		revision += 1
		if _graph_revision >= 0:
			_removed_obstacles.append(id)
		for routes in _clearance_routes.values():
			routes.remove_obstacle(id)


## Maintain one route graph per movement clearance, with matching obstacle IDs.
func with_clearance(clearance: float) -> BattleNavigation:
	if clearance == 0.0:
		return self
	var routes := _clearance_routes.get(clearance) as BattleNavigation
	if routes == null:
		routes = BattleNavigation.new(_bounds.grow(-clearance))
		for id in _obstacles:
			var obstacle := _obstacles[id]
			routes._insert_obstacle(id, obstacle.footprint().grow(clearance),
				obstacle.transform.get_rotation())
		_clearance_routes[clearance] = routes
	return routes


## Check whether breaching one specific footprint reconnects a blocked order.
func reachable_without_obstacle(start: Vector2, end: Vector2, clearance: float,
		ignored_id: int) -> bool:
	var routes := BattleNavigation.new(_bounds.grow(-clearance))
	for id in _obstacles:
		if id != ignored_id:
			var obstacle := _obstacles[id]
			routes.add_obstacle(obstacle.footprint().grow(clearance), obstacle.transform.get_rotation())
	return not routes.path(start, end).is_empty()


func is_passable(point: Vector2) -> bool:
	if not point.is_finite() or not _bounds.has_point(point):
		return false
	for id in _obstacles:
		var obstacle := _obstacles[id]
		if obstacle.bounds.has_point(point) and obstacle.rect.has_point(obstacle.inverse * point):
			return false
	return true


func line_clear(start: Vector2, end: Vector2, ignored_obstacle := -1,
		allow_exit := false) -> bool:
	return _first_blocker(start, end, ignored_obstacle, allow_exit) == -1


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
	if not is_passable(end):
		return PackedVector2Array()
	if line_clear(start, end, -1, true):
		return PackedVector2Array([end])

	if _graph_revision < 0:
		_rebuild_graph()
	elif _graph_revision != revision:
		_refresh_graph_after_removals()
	var start_links := _visible_corners(start, true, _start_links)
	var end_links := _visible_corners(end, false, _end_links)
	if start_links.is_empty() or end_links.is_empty():
		return PackedVector2Array()
	var start_id := _next_obstacle_id * 4
	var end_id := start_id + 1
	_graph.add_point(start_id, start)
	_graph.add_point(end_id, end)
	for id in start_links:
		_graph.connect_points(start_id, id)
	for id in end_links:
		_graph.connect_points(id, end_id)
	var route := _graph.get_point_path(start_id, end_id)
	_graph.remove_point(start_id)
	_graph.remove_point(end_id)
	return route.slice(1)


func _visible_corners(point: Vector2, is_start: bool,
		cache: Dictionary[Vector2, PackedInt64Array]) -> PackedInt64Array:
	if cache.has(point):
		return cache[point]
	var links := PackedInt64Array()
	for id in _graph.get_point_ids():
		var corner := _graph.get_point_position(id)
		var visible := line_clear(point, corner, -1, true) if is_start else line_clear(corner, point)
		if visible:
			links.append(id)
	# Moving endpoints can be unique on every step, even on an unchanged map.
	if cache.size() >= MAX_CACHED_ENDPOINTS:
		cache.clear()
	cache[point] = links
	return links


func _rebuild_graph() -> void:
	_graph.clear()
	_blocked_links.clear()
	_add_visible_corners()
	_finish_graph_update()


func _refresh_graph_after_removals() -> void:
	for obstacle_id in _removed_obstacles:
		for offset in range(4):
			var point_id := obstacle_id * 4 + offset
			if _graph.has_point(point_id):
				_graph.remove_point(point_id)
	for obstacle_id in _removed_obstacles:
		var links := _blocked_links.get(obstacle_id, PackedInt64Array()) as PackedInt64Array
		_blocked_links.erase(obstacle_id)
		for index in range(0, links.size(), 2):
			var a := links[index]
			var b := links[index + 1]
			if _graph.has_point(a) and _graph.has_point(b):
				_connect_corners(a, b, _graph.get_point_position(a))
	# Overlapping footprints can hide corners of surviving obstacles.
	_add_visible_corners()
	_finish_graph_update()


func _finish_graph_update() -> void:
	_start_links.clear()
	_end_links.clear()
	_removed_obstacles.clear()
	_graph_revision = revision


func _add_visible_corners() -> void:
	for obstacle_id in _obstacles:
		var obstacle := _obstacles[obstacle_id]
		var corners := corners_of(obstacle.rect.grow(CORNER_CLEARANCE))
		for offset in corners.size():
			var id := obstacle_id * 4 + offset
			if _graph.has_point(id):
				continue
			var corner := obstacle.transform * corners[offset]
			if not is_passable(corner):
				continue
			var previous := _graph.get_point_ids()
			_graph.add_point(id, corner)
			for other in previous:
				_connect_corners(id, other, corner)


func _connect_corners(a: int, b: int, corner: Vector2) -> void:
	var other := _graph.get_point_position(b)
	# Match the visibility direction of a full build for newly exposed corners.
	var blocker := _first_blocker(corner, other) if a > b else _first_blocker(other, corner)
	if blocker == -1:
		_graph.connect_points(a, b)
	else:
		var links: PackedInt64Array = _blocked_links.get_or_add(blocker, PackedInt64Array())
		links.append(a)
		links.append(b)


static func corners_of(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])
