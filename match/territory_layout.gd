class_name TerritoryLayout
extends RefCounted

const BOUNDS := Rect2(-15.0, -9.0, 30.0, 18.0)
const MIN_REGIONS := 5
const MAX_REGIONS := 7
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


func _init(map_seed: int, region_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	cells.append(Cell.new(PLAYER_START, Vector2(-10.2, 0.0)))
	cells.append(Cell.new(CPU_START, Vector2(10.2, 0.0)))

	# One site per part of the map keeps cells spread out and reserves room for bases.
	var neutral_anchors := [
		Vector2(-3.0, -4.5), Vector2(3.0, 4.5), Vector2(-3.0, 4.5),
		Vector2(3.0, -4.5), Vector2.ZERO,
	]
	for i in range(clampi(region_count, MIN_REGIONS, MAX_REGIONS) - 2):
		var jitter := Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.6, 1.6))
		cells.append(Cell.new(StringName("region_%d" % (i + 1)), neutral_anchors[i] + jitter))

	for cell in cells:
		cell.polygon = PackedVector2Array([
			BOUNDS.position, Vector2(BOUNDS.end.x, BOUNDS.position.y),
			BOUNDS.end, Vector2(BOUNDS.position.x, BOUNDS.end.y),
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


func region_at(point: Vector2) -> StringName:
	# Include the perimeter. At a shared edge or corner, the first closest site wins.
	if point.x < BOUNDS.position.x or point.x > BOUNDS.end.x \
			or point.y < BOUNDS.position.y or point.y > BOUNDS.end.y:
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
