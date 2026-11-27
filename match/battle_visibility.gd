class_name BattleVisibility
extends RefCounted
## Radius vision indexed by faction and coverage in map space.

enum State { UNEXPLORED, EXPLORED, VISIBLE }

const CELLS_PER_CHUNK := 12
const UPDATE_INTERVAL := 0.2
const CHUNKS_PER_STEP := 24
const CHUNK_BUDGET_USEC := 1800
const FULL_ROW := (1 << CELLS_PER_CHUNK) - 1
const SCOUT_RADIUS := 9.0
const UNIT_RADIUS := 5.0
const BASE_RADIUS := 8.0
const OUTPOST_RADIUS := 6.0
const STRUCTURE_RADIUS := 4.0

class Source:
	var side: int
	var position: Vector2
	var radius: float
	var radius_squared: float
	var spans: PackedInt32Array
	var sample: Vector2i
	var sample_bounds: Rect2
	var coverage: Rect2i

class Sample:
	var cell: Vector2i
	var center: Vector2
	var inner_radius_squared: float
	var outer_radius_squared: float
	var spans: PackedInt32Array
	var members: Dictionary[int, Source] = {}


class Chunk:
	var samples: Dictionary[Vector3, Sample] = {}
	var visible := PackedInt32Array()
	var explored := PackedInt32Array()

	func _init() -> void:
		visible.resize(CELLS_PER_CHUNK)
		explored.resize(CELLS_PER_CHUNK)

	func texture_pixels() -> PackedByteArray:
		var pixels := PackedByteArray()
		pixels.resize(CELLS_PER_CHUNK * CELLS_PER_CHUNK)
		for y in CELLS_PER_CHUNK:
			for x in CELLS_PER_CHUNK:
				var bit := 1 << x
				pixels[y * CELLS_PER_CHUNK + x] = State.VISIBLE if visible[y] & bit else (State.EXPLORED if explored[y] & bit else State.UNEXPLORED)
		return pixels

var bounds: Rect2
var dimensions: Vector2i
var _spans_by_radius: Dictionary[float, PackedInt32Array] = {}
var cell_size: Vector2
var _cell_half_diagonal: float
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
var _draining := false
var max_update_usec := 0


func _init(map_bounds: Rect2) -> void:
	bounds = map_bounds
	dimensions = BattleNavigation.chunk_dimensions(bounds)
	cell_size = bounds.size / Vector2(dimensions * CELLS_PER_CHUNK)
	_cell_half_diagonal = cell_size.length() * 0.5 + 0.00001


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / cell_size).floor())


func set_source(id: int, side: int, point: Vector2, radius: float, urgent := true) -> void:
	remove_source(id)
	var source := Source.new()
	source.side = side
	source.position = point
	source.radius = radius
	source.radius_squared = radius * radius
	if not _spans_by_radius.has(radius):
		var spans := PackedInt32Array()
		for y in range(floori(radius / cell_size.y) + 1):
			var width := sqrt(maxf(0.0, source.radius_squared - (y * cell_size.y) ** 2))
			spans.append(floori(width / cell_size.x))
		_spans_by_radius[radius] = spans
	source.spans = _spans_by_radius[radius]
	source.sample = cell_at(point)
	source.sample_bounds = _cell_bounds(source.sample)
	source.coverage = _coverage(source.sample, radius)
	sources[id] = source
	_index(id, source, true)
	_urgent = _urgent or urgent


func remove_source(id: int) -> void:
	var source := sources.get(id) as Source
	if source == null:
		return
	_index(id, source, false)
	sources.erase(id)
	_urgent = true


func move_source(id: int, point: Vector2) -> void:
	var source := sources[id]
	source.position = point
	if source.sample_bounds.has_point(point):
		return
	var sample := cell_at(point)
	_index(id, source, false)
	source.sample = sample
	source.sample_bounds = _cell_bounds(sample)
	source.coverage = _coverage(sample, source.radius)
	_index(id, source, true)


func _cell_bounds(cell: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(cell) * cell_size, cell_size)


func _coverage(sample: Vector2i, radius: float) -> Rect2i:
	# Padding covers any subcell movement until the source enters a new cell.
	var reach := Vector2i((Vector2.ONE * radius / cell_size).ceil()) + Vector2i.ONE
	var first := ((sample - reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	var last := ((sample + reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)


func _index(id: int, source: Source, insert: bool) -> void:
	var sample_key := Vector3(source.sample.x, source.sample.y, source.radius)
	for y in range(source.coverage.position.y, source.coverage.end.y):
		for x in range(source.coverage.position.x, source.coverage.end.x):
			var key := Vector3i(x, y, source.side)
			var chunk := chunks.get(key) as Chunk
			if chunk == null:
				chunk = Chunk.new()
				chunks[key] = chunk
			var sample := chunk.samples.get(sample_key) as Sample
			if insert:
				if sample == null:
					sample = Sample.new()
					sample.cell = source.sample
					sample.center = source.sample_bounds.get_center()
					sample.inner_radius_squared = maxf(0.0, source.radius - _cell_half_diagonal) ** 2
					sample.outer_radius_squared = (source.radius + _cell_half_diagonal) ** 2
					sample.spans = source.spans
					chunk.samples[sample_key] = sample
				sample.members[id] = source
			else:
				sample.members.erase(id)
				if sample.members.is_empty():
					chunk.samples.erase(sample_key)
			dirty[key] = true


func can_see(side: int, point: Vector2) -> bool:
	query_count += 1
	if not bounds.has_point(point):
		return false
	var cell := cell_at(point) / CELLS_PER_CHUNK
	var chunk := chunks.get(Vector3i(cell.x, cell.y, side)) as Chunk
	if chunk == null:
		return false
	for key in chunk.samples:
		var sample := chunk.samples[key]
		var distance := point.distance_squared_to(sample.center)
		if distance > sample.outer_radius_squared:
			continue
		if distance < sample.inner_radius_squared:
			return true
		for id in sample.members:
			var source := sample.members[id]
			if source.position.distance_squared_to(point) <= source.radius_squared:
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
	if chunk != null and (chunk.explored[cell.y % CELLS_PER_CHUNK] & (1 << (cell.x % CELLS_PER_CHUNK))):
		return State.EXPLORED
	return State.UNEXPLORED


func advance(now: float) -> void:
	if not _urgent and not _draining and now + 0.00001 < _next_update:
		return
	if now + 0.00001 >= _next_update:
		_next_update = now + interval
	_urgent = false
	if dirty.is_empty():
		return
	var start := Time.get_ticks_usec()
	ticks += 1
	revision += 1
	var remaining := CHUNKS_PER_STEP
	for key: Vector3i in dirty.keys():
		var chunk := chunks[key]
		var rows := PackedInt32Array()
		rows.resize(CELLS_PER_CHUNK)
		var origin := Vector2i(key.x, key.y) * CELLS_PER_CHUNK
		for sample_key in chunk.samples:
			evaluated_sources += 1
			if _rasterize(rows, chunk.samples[sample_key], origin):
				break
		processed_chunks += 1
		if rows != chunk.visible:
			chunk.visible = rows
			for y in CELLS_PER_CHUNK:
				chunk.explored[y] |= rows[y]
			changed[key] = revision
		dirty.erase(key)
		remaining -= 1
		if remaining == 0 or Time.get_ticks_usec() - start >= CHUNK_BUDGET_USEC:
			break
	_draining = not dirty.is_empty()
	var elapsed := Time.get_ticks_usec() - start
	update_usec += elapsed
	max_update_usec = maxi(max_update_usec, elapsed)


func _rasterize(rows: PackedInt32Array, source: Sample, origin: Vector2i) -> bool:
	# Each row is a bitset. Circle spans are shared by sources with the same radius.
	var sample := source.cell - origin
	var spans := source.spans
	var reach := spans.size() - 1
	var far_y := maxi(absi(sample.y), absi(CELLS_PER_CHUNK - 1 - sample.y))
	var far_x := maxi(absi(sample.x), absi(CELLS_PER_CHUNK - 1 - sample.x))
	if far_y <= reach and spans[far_y] >= far_x:
		rows.fill(FULL_ROW)
		return true
	var first_row := maxi(0, sample.y - reach)
	var last_row := mini(CELLS_PER_CHUNK - 1, sample.y + reach)
	for y in range(first_row, last_row + 1):
		if rows[y] == FULL_ROW:
			continue
		var width := spans[absi(y - sample.y)]
		var left := maxi(0, sample.x - width)
		var right := mini(CELLS_PER_CHUNK - 1, sample.x + width)
		if left <= right:
			rows[y] |= ((1 << (right - left + 1)) - 1) << left
	return false
