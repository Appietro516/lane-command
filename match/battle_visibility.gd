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
	var sample_cell: Vector2i
	var sample_bounds: Rect2

class Sample:
	var cell: Vector2i
	var bounds: Rect2
	var center: Vector2
	var chunk_ids := PackedInt32Array()
	var inner_radius_squared: float
	var outer_radius_squared: float
	var spans: PackedInt32Array
	var members: Dictionary[int, Source] = {}


class Chunk:
	var samples: Array[Sample] = []
	var origin: Vector2i
	var queued := false
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
var _chunk_size: Vector2
var _chunks_per_side: int
var _samples: Dictionary[float, Dictionary] = {}
var interval := UPDATE_INTERVAL
var _chunks: Array[Chunk] = []
var sources: Dictionary[int, Source] = {}
var _dirty := PackedInt32Array()
var _dirty_head := 0
var changed: Dictionary[int, Dictionary] = {}
var _rows := PackedInt32Array()
var revision := 0
var ticks := 0
var processed_chunks := 0
var evaluated_sources := 0
var update_usec := 0
var query_count := 0
var profiling_enabled := false
var invalidations := 0
var unique_invalidations := 0
var _next_update := 0.0
var _urgent := false
var _draining := false
var max_update_usec := 0


func _init(map_bounds: Rect2) -> void:
	bounds = map_bounds
	dimensions = BattleNavigation.chunk_dimensions(bounds)
	cell_size = bounds.size / Vector2(dimensions * CELLS_PER_CHUNK)
	_chunk_size = bounds.size / Vector2(dimensions)
	_chunks_per_side = dimensions.x * dimensions.y
	_chunks.resize(_chunks_per_side * MatchRegion.Owner.size())
	_rows.resize(CELLS_PER_CHUNK)
	_cell_half_diagonal = cell_size.length() * 0.5 + 0.00001


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / cell_size).floor())


func set_source(id: int, side: int, point: Vector2, radius: float, urgent := true) -> Source:
	var source := sources.get(id) as Source
	if source == null:
		source = Source.new()
		sources[id] = source
	else:
		_detach(id, source)
		_urgent = true
	source.side = side
	source.position = point
	source.radius = radius
	source.radius_squared = radius * radius
	_attach(id, source, cell_at(point))
	_urgent = _urgent or urgent
	return source


func remove_source(id: int) -> void:
	var source := sources.get(id) as Source
	if source == null:
		return
	_detach(id, source)
	sources.erase(id)
	_urgent = true


func move_source(id: int, point: Vector2) -> void:
	move_registered_source(id, sources[id], point)


func move_registered_source(id: int, source: Source, point: Vector2) -> void:
	source.position = point
	if source.sample_bounds.has_point(point):
		return
	var cell := cell_at(point)
	if cell == source.sample_cell:
		return
	_detach(id, source)
	_attach(id, source, cell)


func _attach(id: int, source: Source, cell: Vector2i) -> void:
	var by_radius: Dictionary = _samples.get_or_add(source.radius, {})
	var key := Vector3i(cell.x, cell.y, source.side)
	var sample := by_radius.get(key) as Sample
	if sample == null:
		sample = Sample.new()
		sample.cell = cell
		sample.bounds = _cell_bounds(cell)
		sample.center = sample.bounds.get_center()
		sample.inner_radius_squared = maxf(0.0, source.radius - _cell_half_diagonal) ** 2
		sample.outer_radius_squared = (source.radius + _cell_half_diagonal) ** 2
		if not _spans_by_radius.has(source.radius):
			var spans := PackedInt32Array()
			for y in range(floori(source.radius / cell_size.y) + 1):
				var width := sqrt(maxf(0.0, source.radius_squared - (y * cell_size.y) ** 2))
				spans.append(floori(width / cell_size.x))
			_spans_by_radius[source.radius] = spans
		sample.spans = _spans_by_radius[source.radius]
		by_radius[key] = sample
		var coverage := _coverage(cell, source.radius)
		var offset := source.side * _chunks_per_side
		for y in range(coverage.position.y, coverage.end.y):
			for x in range(coverage.position.x, coverage.end.x):
				var chunk_id := offset + y * dimensions.x + x
				var chunk := _chunks[chunk_id]
				if chunk == null:
					chunk = Chunk.new()
					chunk.origin = Vector2i(x, y) * CELLS_PER_CHUNK
					_chunks[chunk_id] = chunk
				chunk.samples.append(sample)
				sample.chunk_ids.append(chunk_id)
				_mark_dirty(chunk_id, chunk)
	sample.members[id] = source
	source.sample_cell = cell
	source.sample_bounds = sample.bounds


func _detach(id: int, source: Source) -> void:
	var by_radius := _samples[source.radius]
	var key := Vector3i(source.sample_cell.x, source.sample_cell.y, source.side)
	var sample := by_radius[key] as Sample
	sample.members.erase(id)
	if not sample.members.is_empty():
		return
	by_radius.erase(key)
	for chunk_id in sample.chunk_ids:
		var chunk := _chunks[chunk_id]
		chunk.samples.erase(sample)
		_mark_dirty(chunk_id, chunk)


func _mark_dirty(id: int, chunk: Chunk) -> void:
	if profiling_enabled:
		invalidations += 1
	if chunk.queued:
		return
	if profiling_enabled:
		unique_invalidations += 1
	chunk.queued = true
	_dirty.append(id)


func _cell_bounds(cell: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(cell) * cell_size, cell_size)


func _coverage(sample: Vector2i, radius: float) -> Rect2i:
	# Padding covers any subcell movement until the source enters a new cell.
	var reach := Vector2i((Vector2.ONE * radius / cell_size).ceil()) + Vector2i.ONE
	var first := ((sample - reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	var last := ((sample + reach) / CELLS_PER_CHUNK).clamp(Vector2i.ZERO, dimensions - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)


func can_see(side: int, point: Vector2) -> bool:
	if profiling_enabled:
		query_count += 1
	if not bounds.has_point(point):
		return false
	var grid := Vector2i((point - bounds.position) / _chunk_size).min(dimensions - Vector2i.ONE)
	var chunk := _chunks[side * _chunks_per_side + grid.y * dimensions.x + grid.x]
	if chunk == null:
		return false
	for sample in chunk.samples:
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
	var chunk := _chunks[side * _chunks_per_side + grid.y * dimensions.x + grid.x]
	if chunk != null and (chunk.explored[cell.y % CELLS_PER_CHUNK] & (1 << (cell.x % CELLS_PER_CHUNK))):
		return State.EXPLORED
	return State.UNEXPLORED


func advance(now: float) -> void:
	if not _urgent and not _draining and now + 0.00001 < _next_update:
		return
	if now + 0.00001 >= _next_update:
		_next_update = now + interval
	_urgent = false
	if _dirty_head == _dirty.size():
		return
	var start := Time.get_ticks_usec()
	ticks += 1
	revision += 1
	# Keep queued chunks in insertion order while a burst drains across steps.
	var stop := mini(_dirty.size(), _dirty_head + CHUNKS_PER_STEP)
	while _dirty_head < stop:
		var id := _dirty[_dirty_head]
		var chunk := _chunks[id]
		_rows.fill(0)
		for sample in chunk.samples:
			evaluated_sources += 1
			if _rasterize(_rows, sample, chunk.origin):
				break
		processed_chunks += 1
		if _rows != chunk.visible:
			chunk.visible = _rows.duplicate()
			for y in CELLS_PER_CHUNK:
				chunk.explored[y] |= _rows[y]
			var side := id / _chunks_per_side
			var patches: Dictionary = changed.get_or_add(side, {})
			patches[id] = revision
		chunk.queued = false
		_dirty_head += 1
		if Time.get_ticks_usec() - start >= CHUNK_BUDGET_USEC:
			break
	_draining = _dirty_head < _dirty.size()
	if not _draining:
		_dirty.clear()
		_dirty_head = 0
	elif _dirty_head >= _chunks.size():
		_dirty = _dirty.slice(_dirty_head)
		_dirty_head = 0
	var elapsed := Time.get_ticks_usec() - start
	update_usec += elapsed
	max_update_usec = maxi(max_update_usec, elapsed)


func chunk_data(id: int) -> Chunk:
	return _chunks[id]


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
