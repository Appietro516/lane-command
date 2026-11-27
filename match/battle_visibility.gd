class_name BattleVisibility
extends RefCounted
## Radius vision indexed by faction and coverage in map space.

enum State { UNEXPLORED, EXPLORED, VISIBLE }

const CELLS_PER_CHUNK := 16
const UPDATE_INTERVAL := 0.2
const SCOUT_RADIUS := 9.0
const UNIT_RADIUS := 5.0
const BASE_RADIUS := 8.0
const OUTPOST_RADIUS := 6.0
const STRUCTURE_RADIUS := 4.0

class Source:
	var side: int
	var position: Vector2
	var radius: float
	var sample: Vector2i
	var coverage: Rect2i

class Chunk:
	var sources: Dictionary[int, Source] = {}
	# 0 unknown, 1 explored, 2 visible. One byte per cell.
	var mask := PackedByteArray()

var bounds: Rect2
var dimensions: Vector2i
var cell_size: Vector2
var interval := UPDATE_INTERVAL
var chunks: Dictionary[Vector3i, Chunk] = {}
var sources: Dictionary[int, Source] = {}
var dirty: Dictionary[Vector3i, bool] = {}
var changed: Dictionary[Vector3i, int] = {}
var revision := 0
var ticks := 0
var processed_chunks := 0
var evaluated_sources := 0
var update_usec := 0
var query_count := 0
var _next_update := 0.0
var _urgent := false


func _init(map_bounds: Rect2) -> void:
	bounds = map_bounds
	dimensions = BattleNavigation.chunk_dimensions(bounds)
	cell_size = bounds.size / Vector2(dimensions * CELLS_PER_CHUNK)


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / cell_size).floor())


func set_source(id: int, side: int, point: Vector2, radius: float) -> void:
	remove_source(id)
	var source := Source.new()
	source.side = side
	source.position = point
	source.radius = radius
	source.sample = cell_at(point)
	source.coverage = _coverage(source.sample, radius)
	sources[id] = source
	_index(id, source, true)
	_urgent = true


func remove_source(id: int) -> void:
	var source := sources.get(id) as Source
	if source == null:
		return
	_index(id, source, false)
	sources.erase(id)
	_urgent = true


func move_source(id: int, point: Vector2) -> void:
	var source := sources[id]
	var sample := cell_at(point)
	source.position = point
	if sample == source.sample:
		return
	var coverage := _coverage(sample, source.radius)
	source.sample = sample
	if coverage != source.coverage:
		_index(id, source, false)
		source.coverage = coverage
		_index(id, source, true)
	else:
		for y in range(coverage.position.y, coverage.end.y):
			for x in range(coverage.position.x, coverage.end.x):
				dirty[Vector3i(x, y, source.side)] = true


func _coverage(sample: Vector2i, radius: float) -> Rect2i:
	# Padding covers any subcell movement until the source enters a new cell.
	var reach := Vector2i((Vector2.ONE * radius / cell_size).ceil()) + Vector2i.ONE
	var first := ((sample - reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	var last := ((sample + reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)


func _index(id: int, source: Source, insert: bool) -> void:
	for y in range(source.coverage.position.y, source.coverage.end.y):
		for x in range(source.coverage.position.x, source.coverage.end.x):
			var key := Vector3i(x, y, source.side)
			var chunk := chunks.get(key) as Chunk
			if chunk == null:
				chunk = Chunk.new()
				chunk.mask.resize(CELLS_PER_CHUNK * CELLS_PER_CHUNK)
				chunks[key] = chunk
			if insert:
				chunk.sources[id] = source
			else:
				chunk.sources.erase(id)
			dirty[key] = true


func can_see(side: int, point: Vector2) -> bool:
	query_count += 1
	if not bounds.has_point(point):
		return false
	var cell := cell_at(point) / CELLS_PER_CHUNK
	var chunk := chunks.get(Vector3i(cell.x, cell.y, side)) as Chunk
	if chunk == null:
		return false
	for source in chunk.sources.values():
		if source.position.distance_squared_to(point) <= source.radius * source.radius:
			return true
	return false


func state_at(side: int, point: Vector2) -> State:
	if can_see(side, point):
		return State.VISIBLE
	if not bounds.has_point(point):
		return State.UNEXPLORED
	var cell := cell_at(point)
	var grid := cell / CELLS_PER_CHUNK
	var chunk := chunks.get(Vector3i(grid.x, grid.y, side)) as Chunk
	if chunk != null and chunk.mask[(cell.y % CELLS_PER_CHUNK) * CELLS_PER_CHUNK + cell.x % CELLS_PER_CHUNK] > 0:
		return State.EXPLORED
	return State.UNEXPLORED


func advance(now: float) -> void:
	if not _urgent and now + 0.00001 < _next_update:
		return
	if now + 0.00001 >= _next_update:
		_next_update = now + interval
	_urgent = false
	if dirty.is_empty():
		return
	var start := Time.get_ticks_usec()
	ticks += 1
	revision += 1
	for key in dirty:
		var chunk := chunks[key]
		var next := chunk.mask.duplicate()
		for i in next.size():
			if next[i] == State.VISIBLE:
				next[i] = State.EXPLORED
		var origin := bounds.position + Vector2(key.x, key.y) * cell_size * CELLS_PER_CHUNK
		for source in chunk.sources.values():
			_rasterize(next, source, origin)
		evaluated_sources += chunk.sources.size()
		processed_chunks += 1
		if next != chunk.mask:
			chunk.mask = next
			changed[key] = revision
	dirty.clear()
	update_usec += Time.get_ticks_usec() - start


func _rasterize(mask: PackedByteArray, source: Source, origin: Vector2) -> void:
	# A sampled center stabilizes masks between cell crossings. Exact targeting uses the live center.
	var center := bounds.position + (Vector2(source.sample) + Vector2.ONE * 0.5) * cell_size - origin
	var radius := source.radius
	var first_row := maxi(0, ceili((center.y - radius) / cell_size.y - 0.5))
	var last_row := mini(CELLS_PER_CHUNK - 1, floori((center.y + radius) / cell_size.y - 0.5))
	for y in range(first_row, last_row + 1):
		var offset := (y + 0.5) * cell_size.y - center.y
		var width := sqrt(maxf(0.0, radius * radius - offset * offset))
		var first := maxi(0, ceili((center.x - width) / cell_size.x - 0.5))
		var last := mini(CELLS_PER_CHUNK - 1, floori((center.x + width) / cell_size.x - 0.5))
		for x in range(first, last + 1):
			mask[y * CELLS_PER_CHUNK + x] = State.VISIBLE
