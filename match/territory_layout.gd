class_name TerritoryLayout
extends RefCounted

const DEFAULT_SIZE := MapSettings.DEFAULT_SIZE
const DEFAULT_REGION_COUNT := MapSettings.DEFAULT_REGION_COUNT
const MIN_REGIONS := MapSettings.MIN_REGIONS
const MAX_REGIONS := MapSettings.MAX_REGIONS
const MAX_CPU_OPPONENTS := 4
const BASE_SEPARATION := 5.0
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
var settings: MapSettings
var bounds: Rect2
var boundary: PackedVector2Array
var base_positions: Dictionary[StringName, Vector2] = {}
var starting_counts: Vector3i
var active_seed: int
var player_start_ids: Array[StringName] = []
var cpu_start_ids: Array[StringName] = []
# The first region in each territory contains its starting base.
var starting_territories: Array[Array] = []
var configuration_error := ""


func _init(map_seed: int, region_count: int, map_size := DEFAULT_SIZE,
		player_start_count := 1, cpu_start_count := 1, cpu_opponents := 1,
		shape := MapSettings.Shape.RECTANGLE) -> void:
	settings = MapSettings.new(shape, map_size, region_count, map_seed)
	active_seed = settings.seed
	bounds = settings.bounds
	boundary = settings.boundary
	starting_counts = Vector3i(player_start_count, cpu_start_count, cpu_opponents)
	configuration_error = settings.configuration_error
	if not configuration_error.is_empty():
		return
	var count := settings.region_count
	if cpu_opponents < 1 or cpu_opponents > MAX_CPU_OPPONENTS:
		configuration_error = "Choose between 1 and %d CPU opponents." % MAX_CPU_OPPONENTS
		return
	var reserved_count := player_start_count + cpu_start_count * cpu_opponents
	if player_start_count < 1 or cpu_start_count < 1 or reserved_count > count \
			or (cpu_opponents > 1 and reserved_count == count):
		configuration_error = "Increase the region count or reduce starting territories or CPU opponents."
		if cpu_opponents > 1:
			configuration_error += " Leave at least one neutral region for claims."
		return

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
		cell.polygon = boundary
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

	_assign_starting_territories(cpu_opponents, player_start_count, cpu_start_count)
	if not configuration_error.is_empty():
		starting_territories.clear()
		return
	var owned: Dictionary[StringName, bool] = {}
	for territory in starting_territories:
		for id: StringName in territory:
			owned[id] = true
	for cell in cells:
		if not owned.has(cell.id) and not _fits_in_cell(cell, cell.site, MatchBattle.OUTPOST_CLEARANCE):
			configuration_error = "A neutral region is too small for an outpost. Increase the map size or reduce regions."
			starting_territories.clear()
			return


func _assign_starting_territories(cpu_opponents: int, player_count: int, cpu_count: int) -> void:
	var starts: Array[Cell] = [cells.front(), cells.back()]
	var candidates: Dictionary[Cell, Vector2] = {}
	for cell in cells:
		var point := _base_position(cell, cpu_opponents)
		if point.is_finite():
			candidates[cell] = point
	if not candidates.has(starts[0]) or not candidates.has(starts[1]):
		configuration_error = "A starting region is too small for a base. Increase the map size or reduce regions."
		return
	while starts.size() <= cpu_opponents:
		var best: Cell
		var separation := BASE_SEPARATION * BASE_SEPARATION
		for candidate in candidates:
			if candidate in starts:
				continue
			var nearest := INF
			for start in starts:
				nearest = minf(nearest, candidates[candidate].distance_squared_to(candidates[start]))
			if nearest >= separation and (best == null or nearest > separation):
				best = candidate
				separation = nearest
		if best == null:
			configuration_error = "Increase the map size or reduce CPU opponents to make room for separated bases."
			return
		starts.append(best)
	for start in starts:
		base_positions[start.id] = candidates[start]

	if cpu_opponents == 1 and settings.shape != MapSettings.Shape.TRIANGLE:
		starting_territories = [player_start_ids, cpu_start_ids.duplicate()]
		starting_territories[1].reverse()
		return

	var reserved: Dictionary[StringName, bool] = {}
	for start in starts:
		starting_territories.append([start.id])
		reserved[start.id] = true

	# Expand in rounds so each side gets a chance to reserve adjacent cells.
	var by_id: Dictionary[StringName, Cell] = {}
	for cell in cells:
		by_id[cell.id] = cell
	for round_index in range(1, maxi(player_count, cpu_count)):
		for index in starts.size():
			if round_index >= (player_count if index == 0 else cpu_count):
				continue
			var best: StringName
			var distance := INF
			for id: StringName in starting_territories[index]:
				for neighbor in by_id[id].neighbor_ids:
					if reserved.has(neighbor):
						continue
					var candidate_distance := starts[index].site.distance_squared_to(by_id[neighbor].site)
					if candidate_distance < distance:
						best = neighbor
						distance = candidate_distance
			if best.is_empty():
				configuration_error = "Increase the region count or assign fewer starting regions so every faction can stay connected."
				return
			starting_territories[index].append(best)
			reserved[best] = true
	player_start_ids.assign(starting_territories[0])
	cpu_start_ids.assign(starting_territories[1])


func _generate_sites(count: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = active_seed
	if settings.shape == MapSettings.Shape.TRIANGLE:
		return _generate_triangle_sites(count, rng)
	var transpose := bounds.size.y > bounds.size.x
	var extent := Vector2(bounds.size.y, bounds.size.x) if transpose else bounds.size
	var max_columns := floori(extent.x / MapSettings.MIN_SITE_PITCH)
	var max_rows := floori(extent.y / MapSettings.MIN_SITE_PITCH)
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


func _generate_triangle_sites(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	# Use the coarsest inset triangular grid that can hold the requested sites.
	# Take the two lower corners first, then fill the largest remaining gaps.
	var divisions := 1
	while (divisions + 1) * (divisions + 2) / 2 < count:
		divisions += 1
	var center := (boundary[0] + boundary[1] + boundary[2]) / 3.0
	var scale := settings.triangle_site_span() / bounds.size.x
	var apex := center.lerp(boundary[0], scale)
	var left := center.lerp(boundary[2], scale)
	var right := center.lerp(boundary[1], scale)
	var grid := PackedVector2Array()
	for row in range(divisions + 1):
		for column in range(row + 1):
			grid.append(apex + ((left - apex) * (row - column) + (right - apex) * column) / divisions)
	var first := grid[grid.size() - divisions - 1]
	var last := grid[-1]
	var sites := PackedVector2Array([first])
	var nearest := PackedFloat32Array()
	for point in grid:
		nearest.append(minf(point.distance_squared_to(first), point.distance_squared_to(last)))
	while sites.size() < count - 1:
		var best := 0
		for i in range(1, grid.size()):
			if nearest[i] > nearest[best]:
				best = i
		var point := grid[best]
		sites.append(point)
		for i in grid.size():
			nearest[i] = minf(nearest[i], grid[i].distance_squared_to(point))
	sites.append(last)
	for i in sites.size():
		sites[i] += Vector2(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.16, 0.16))
	return sites


func contains(point: Vector2) -> bool:
	return settings.contains(point)


func _base_position(cell: Cell, cpu_opponents: int) -> Vector2:
	# Preserve the original 1v1 rectangular base offsets when they fit.
	if cpu_opponents == 1 and settings.shape == MapSettings.Shape.RECTANGLE:
		var offset := cell.site + Vector2(0.0, 2.0)
		if _base_fits(cell, offset):
			return offset
	if _base_fits(cell, cell.site):
		return cell.site
	# At the tightest pitches, jitter can put an edge site's base too close
	# to the perimeter even though there is room slightly farther in.
	for ring in range(1, 7):
		for direction in 8:
			var point := cell.site + Vector2.from_angle(direction * TAU / 8.0) * ring * 0.25
			if _base_fits(cell, point):
				return point
	return Vector2.INF


func _base_fits(cell: Cell, point: Vector2) -> bool:
	return settings.contains(point, 2.2) and _fits_in_cell(cell, point, MatchBattle.BASE_FOOTPRINT)


static func _fits_in_cell(cell: Cell, point: Vector2, half_size: Vector2) -> bool:
	for corner in BattleNavigation.corners_of(Rect2(point - half_size, half_size * 2.0)):
		if not MapSettings.contains_in(cell.polygon, corner):
			return false
	return true


func region_at(point: Vector2) -> StringName:
	# At a shared edge or corner, the first closest site wins.
	if not contains(point):
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
