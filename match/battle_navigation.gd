class_name BattleNavigation
extends RefCounted
## Routes ground positions around static footprints using their corners as waypoints.

const CORNER_CLEARANCE := 0.025

class Obstacle:
	var rect: Rect2
	var transform: Transform2D
	var inverse: Transform2D
	var bounds: Rect2

	func _init(footprint: Rect2, angle: float) -> void:
		var center := footprint.get_center()
		rect = Rect2(-footprint.size * 0.5, footprint.size)
		transform = Transform2D(angle, center)
		inverse = transform.affine_inverse()
		bounds = transform * rect


var revision := 0
var _bounds: Rect2
var _obstacles: Dictionary[int, Obstacle] = {}
var _next_obstacle_id := 0
var _graph := AStar2D.new()
var _graph_revision := -1


func _init(bounds: Rect2) -> void:
	_bounds = bounds


func add_obstacle(footprint: Rect2, angle := 0.0) -> int:
	var id := _next_obstacle_id
	_next_obstacle_id += 1
	_obstacles[id] = Obstacle.new(footprint, angle)
	revision += 1
	return id


func remove_obstacle(id: int) -> void:
	if _obstacles.erase(id):
		revision += 1


func is_passable(point: Vector2) -> bool:
	if not point.is_finite() or not _bounds.has_point(point):
		return false
	for obstacle: Obstacle in _obstacles.values():
		if obstacle.bounds.has_point(point) and obstacle.rect.has_point(obstacle.inverse * point):
			return false
	return true


func line_clear(start: Vector2, end: Vector2, ignored_obstacle := -1,
		allow_exit := false) -> bool:
	var low := start.min(end)
	var high := start.max(end)
	for id in _obstacles:
		if id == ignored_obstacle:
			continue
		var obstacle := _obstacles[id]
		var bounds := obstacle.bounds
		if high.x < bounds.position.x or low.x > bounds.end.x \
				or high.y < bounds.position.y or low.y > bounds.end.y:
			continue
		var local_start := obstacle.inverse * start
		var local_end := obstacle.inverse * end
		if obstacle.rect.has_point(local_start):
			# A new building can cover a unit. Let it walk out of that footprint.
			if allow_exit and not obstacle.rect.has_point(local_end):
				continue
			return false
		if obstacle.rect.has_point(local_end):
			return false
		var corners := corners_of(obstacle.rect)
		for edge in range(4):
			if Geometry2D.segment_intersects_segment(local_start, local_end, corners[edge],
					corners[(edge + 1) % 4]) != null:
				return false
	return true


func path(start: Vector2, end: Vector2) -> PackedVector2Array:
	if not is_passable(end):
		return PackedVector2Array()
	if line_clear(start, end, -1, true):
		return PackedVector2Array([end])

	if _graph_revision != revision:
		_rebuild_graph()
	var points := _graph.get_point_ids()
	var start_id := points.size()
	var end_id := start_id + 1
	_graph.add_point(start_id, start)
	_graph.add_point(end_id, end)
	for id in points:
		var corner := _graph.get_point_position(id)
		if line_clear(start, corner, -1, true):
			_graph.connect_points(start_id, id)
		if line_clear(corner, end):
			_graph.connect_points(id, end_id)
	var route := _graph.get_point_path(start_id, end_id)
	_graph.remove_point(start_id)
	_graph.remove_point(end_id)
	return route.slice(1)


func _rebuild_graph() -> void:
	_graph.clear()
	for obstacle: Obstacle in _obstacles.values():
		for local_corner in corners_of(obstacle.rect.grow(CORNER_CLEARANCE)):
			var corner := obstacle.transform * local_corner
			if not is_passable(corner):
				continue
			var id := _graph.get_point_count()
			_graph.add_point(id, corner)
			for other in range(id):
				if line_clear(corner, _graph.get_point_position(other)):
					_graph.connect_points(id, other)
	_graph_revision = revision


static func corners_of(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])
