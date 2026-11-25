class_name TerritoryLayout
extends RefCounted

const DEFAULT_SIZE := Vector2(60.0, 36.0)
const DEFAULT_REGION_COUNT := 24
const MIN_REGIONS := 2
const MAX_REGIONS := 128
const MIN_DIMENSION := 18.0
const MAX_DIMENSION := 192.0
const MIN_SITE_PITCH := 5.0
const PLAYER_START: StringName = &"player_start"
const CPU_START: StringName = &"cpu_start"
const EDGE_EPSILON := 0.0001


class Cell:
	var id: StringName
	var site: Vector2
	var polygon: PackedVector2Array
	var neighbor_ids: Array[StringName] = []

	func _init(region_id: StringName, location: Vector2) -> void:
		id = region_id
		site = location


var cells: Array[Cell] = []
var bounds: Rect2
var active_seed: int
var player_start_ids: Array[StringName] = []
var cpu_start_ids: Array[StringName] = []


func _init(map_seed: int, region_count: int, map_size := DEFAULT_SIZE,
		player_start_count := 1, cpu_start_count := 1) -> void:
	active_seed = map_seed
	var world_size := Vector2(_validate_dimension(map_size.x, DEFAULT_SIZE.x),
		_validate_dimension(map_size.y, DEFAULT_SIZE.y))
	bounds = Rect2(-world_size / 2.0, world_size)
	var capacity := floori(world_size.x / MIN_SITE_PITCH) * floori(world_size.y / MIN_SITE_PITCH)
	var count := clampi(region_count, MIN_REGIONS, mini(capacity, MAX_REGIONS))
	player_start_count = maxi(1, player_start_count)
	cpu_start_count = maxi(1, cpu_start_count)
	if player_start_count > count - cpu_start_count:
		player_start_count = 1
		cpu_start_count = 1

	var sites := _generate_sites(count)
	for i in range(count):
		var id := StringName("region_%d" % i)
		if i == 0:
			id = PLAYER_START
		elif i == count - 1:
			id = CPU_START
		cells.append(Cell.new(id, sites[i]))
		if i < player_start_count:
			player_start_ids.append(id)
		elif i >= count - cpu_start_count:
			cpu_start_ids.append(id)

	for cell in cells:
		cell.polygon = PackedVector2Array([
			bounds.position, Vector2(bounds.end.x, bounds.position.y),
			bounds.end, Vector2(bounds.position.x, bounds.end.y),
		])
		for other in cells:
			if cell != other:
				cell.polygon = _clip_to_bisector(cell.polygon, cell.site, other.site)

	for i in range(cells.size()):
		for j in range(i + 1, cells.size()):
			var cell := cells[i]
			var other := cells[j]
			if _shares_edge(cell, other):
				cell.neighbor_ids.append(other.id)
				other.neighbor_ids.append(cell.id)


func _generate_sites(count: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = active_seed
	var transpose := bounds.size.y > bounds.size.x
	var extent := Vector2(bounds.size.y, bounds.size.x) if transpose else bounds.size
	var max_columns := floori(extent.x / MIN_SITE_PITCH)
	var max_rows := floori(extent.y / MIN_SITE_PITCH)
	var rows := clampi(roundi(sqrt(count * extent.y / extent.x)),
		ceili(float(count) / max_columns), mini(max_rows, count - 1))
	var columns := ceili(float(count) / rows)
	var pitch := extent / Vector2(columns, rows)
	var short_pitch := minf(pitch.x, pitch.y)
	# Keep the midpoint of consecutive grid sites closer to them than to any
	# third site, even on elongated maps. Each step then crosses a Voronoi edge.
	var jitter := 0.12 * short_pitch * short_pitch / maxf(pitch.x, pitch.y)
	var sites := PackedVector2Array()
	for column in range(columns):
		var entries := mini(rows, count - sites.size())
		for row in range(entries):
			var slot := row if column % 2 == 0 else rows - 1 - row
			var point := (Vector2(column, slot) + Vector2(0.5, 0.5)) * pitch - extent / 2.0
			point += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			sites.append(Vector2(point.y, point.x) if transpose else point)
	# The traversal runs from one end of the long axis to the other. Its
	# prefix and suffix give both factions contiguous territory at any split.
	return sites


static func _validate_dimension(value: float, default_value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return default_value
	return clampf(value, MIN_DIMENSION, MAX_DIMENSION)


func region_at(point: Vector2) -> StringName:
	# Include the perimeter. At a shared edge or corner, the first closest site wins.
	if point.x < bounds.position.x or point.x > bounds.end.x \
			or point.y < bounds.position.y or point.y > bounds.end.y:
		return &""
	var closest := INF
	var region_id: StringName = &""
	for cell in cells:
		var distance := point.distance_squared_to(cell.site)
		if distance < closest:
			closest = distance
			region_id = cell.id
	return region_id


static func _clip_to_bisector(polygon: PackedVector2Array, site: Vector2,
		other_site: Vector2) -> PackedVector2Array:
	var normal := (other_site - site).normalized()
	var midpoint := site.lerp(other_site, 0.5)
	var clipped := PackedVector2Array()
	for i in range(polygon.size()):
		var start := polygon[i]
		var end := polygon[(i + 1) % polygon.size()]
		var start_distance := (start - midpoint).dot(normal)
		var end_distance := (end - midpoint).dot(normal)
		if start_distance < 0.0 and end_distance > 0.0 or start_distance > 0.0 and end_distance < 0.0:
			clipped.append(start.lerp(end, start_distance / (start_distance - end_distance)))
		if end_distance <= 0.0:
			clipped.append(end)
	return clipped


static func _shares_edge(cell: Cell, other: Cell) -> bool:
	var normal := (other.site - cell.site).normalized()
	var midpoint := cell.site.lerp(other.site, 0.5)
	for i in range(cell.polygon.size()):
		var start := cell.polygon[i]
		var end := cell.polygon[(i + 1) % cell.polygon.size()]
		if start.distance_to(end) > EDGE_EPSILON \
				and absf((start - midpoint).dot(normal)) <= EDGE_EPSILON \
				and absf((end - midpoint).dot(normal)) <= EDGE_EPSILON:
			return true
	return false
