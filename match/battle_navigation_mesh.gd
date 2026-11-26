extends RefCounted
## Builds a NavigationPolygon from a convex chunk and rotated rectangular cuts.
## Each job owns its input snapshot and output resource.

var outline: PackedVector2Array
var obstructions: Array[PackedVector2Array] = []
var polygon: NavigationPolygon


func build(cell_size: float) -> void:
	var faces: Array[PackedVector2Array] = []
	if not outline.is_empty():
		faces.append(outline)
	for obstruction in obstructions:
		var next: Array[PackedVector2Array] = []
		var bounds := _bounds(obstruction)
		for face in faces:
			if bounds.intersects(_bounds(face)):
				_subtract(face, obstruction, next)
			else:
				next.append(face)
		faces = next

	# Godot joins edges within one region by matching both endpoints.
	# Make the decomposition conform at T-junctions before publishing it.
	var vertices := PackedVector2Array()
	var vertex_ids: Dictionary[Vector2, int] = {}
	var face_ids: Array[PackedInt32Array] = []
	for face in faces:
		var ids := PackedInt32Array()
		for point in face:
			var snapped := point.snapped(Vector2(0.001, 0.001))
			if not vertex_ids.has(snapped):
				vertex_ids[snapped] = vertices.size()
				vertices.append(snapped)
			var id := vertex_ids[snapped]
			if ids.is_empty() or ids[-1] != id:
				ids.append(id)
		if ids.size() > 1 and ids[0] == ids[-1]:
			ids.resize(ids.size() - 1)
		if ids.size() >= 3:
			face_ids.append(ids)
	var mesh := NavigationPolygon.new()
	mesh.cell_size = cell_size
	mesh.vertices = vertices
	for ids in face_ids:
		mesh.add_polygon(_conform_edges(ids, vertices))
	polygon = mesh


static func _conform_edges(ids: PackedInt32Array, vertices: PackedVector2Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in ids.size():
		var a := vertices[ids[i]]
		var b := vertices[ids[(i + 1) % ids.size()]]
		result.append(ids[i])
		var direction := b - a
		var length_squared := direction.length_squared()
		var length := sqrt(length_squared)
		var tolerance := 0.0016 * length
		var splits: Dictionary[float, int] = {}
		var low := a.min(b) - Vector2(0.002, 0.002)
		var high := a.max(b) + Vector2(0.002, 0.002)
		for j in vertices.size():
			var point := vertices[j]
			if ids.has(j) or point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
				continue
			var relative := point - a
			var along := direction.dot(relative)
			if along > tolerance and along < length_squared - tolerance \
					and absf(direction.cross(relative)) < tolerance:
				splits[along] = j
		var distances := splits.keys()
		distances.sort()
		for distance in distances:
			result.append(splits[distance])
	return result


static func _subtract(face: PackedVector2Array, obstruction: PackedVector2Array,
		result: Array[PackedVector2Array]) -> void:
	# Split off the portion outside each directed edge. The portion remaining
	# after all four cuts is the intersection, which is excluded from the mesh.
	var inside := face
	var pieces: Array[PackedVector2Array] = []
	for i in obstruction.size():
		var origin := obstruction[i]
		var direction := obstruction[(i + 1) % obstruction.size()] - origin
		var positive := PackedVector2Array()
		var negative := PackedVector2Array()
		var previous := inside[-1]
		var before := direction.cross(previous - origin)
		for point in inside:
			var after := direction.cross(point - origin)
			if (before < 0.0 and after > 0.0) or (before > 0.0 and after < 0.0):
				var crossing := previous.lerp(point, before / (before - after))
				positive.append(crossing)
				negative.append(crossing)
			if after >= 0.0:
				positive.append(point)
			if after <= 0.0:
				negative.append(point)
			previous = point
			before = after
		if not _has_area(positive):
			result.append(face)
			return
		if _has_area(negative):
			pieces.append(negative)
		inside = positive
	result.append_array(pieces)


static func _has_area(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var area := 0.0
	for i in range(1, points.size() - 1):
		area += (points[i] - points[0]).cross(points[i + 1] - points[0])
	return area > 0.000001


static func _bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		bounds = bounds.expand(points[i])
	return bounds
