class_name MapSettings
extends RefCounted

enum Shape { RECTANGLE, SQUARE, TRIANGLE }

const SHAPE_NAMES := {
	Shape.RECTANGLE: "Rectangle", Shape.SQUARE: "Square", Shape.TRIANGLE: "Triangle",
}
const DEFAULT_SIZE := Vector2(60.0, 36.0)
const DEFAULT_REGION_COUNT := 24
const MIN_REGIONS := 2
const MAX_REGIONS := 128
const MIN_DIMENSION := 18.0
const MAX_DIMENSION := 192.0
const MIN_SITE_PITCH := 5.0
const TRIANGLE_SITE_INSET := 2.5
const PERIMETER_EPSILON := 0.00001

var shape: Shape
var size: Vector2
var region_count: int
var seed: int
var bounds: Rect2
var boundary: PackedVector2Array
var supported_maximum: int
var configuration_error := ""


func _init(map_shape: Shape, dimensions: Vector2, count: int, map_seed: int) -> void:
	shape = map_shape
	size = dimensions
	region_count = count
	seed = map_seed
	if not SHAPE_NAMES.has(shape):
		configuration_error = "Choose Rectangle, Square or Triangle."
		return
	if not _valid_dimension(size.x) or (shape == Shape.RECTANGLE and not _valid_dimension(size.y)):
		configuration_error = "Enter map dimensions between %d and %d world units." % [
			MIN_DIMENSION, MAX_DIMENSION]
		return
	if shape == Shape.SQUARE:
		size.y = size.x
	elif shape == Shape.TRIANGLE:
		# Equilateral in the map plane, with the apex facing north (negative Z).
		size.y = size.x * sqrt(3.0) / 2.0
	bounds = Rect2(-size / 2.0, size)
	if shape == Shape.TRIANGLE:
		boundary = PackedVector2Array([Vector2(0.0, bounds.position.y), bounds.end,
			Vector2(bounds.position.x, bounds.end.y)])
		var divisions := floori(triangle_site_span() / MIN_SITE_PITCH)
		supported_maximum = mini(MAX_REGIONS, (divisions + 1) * (divisions + 2) / 2)
	else:
		boundary = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
			bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		supported_maximum = mini(MAX_REGIONS, floori(size.x / MIN_SITE_PITCH) * floori(size.y / MIN_SITE_PITCH))
	if count < MIN_REGIONS or count > supported_maximum:
		configuration_error = "Choose %d–%d regions for this %s, or increase its size for more regions." % [
			MIN_REGIONS, supported_maximum, SHAPE_NAMES[shape].to_lower()]


func triangle_site_span() -> float:
	return size.x - 2.0 * sqrt(3.0) * TRIANGLE_SITE_INSET


func contains(point: Vector2, clearance := 0.0) -> bool:
	return contains_in(boundary, point, clearance)


## All playable boundaries and generated cells are convex with positive signed area.
static func contains_in(polygon: PackedVector2Array, point: Vector2, clearance := 0.0) -> bool:
	if not point.is_finite() or polygon.size() < 3:
		return false
	for i in polygon.size():
		var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
		if edge.cross(point - polygon[i]) < (clearance - PERIMETER_EPSILON) * edge.length():
			return false
	return true


static func _valid_dimension(value: float) -> bool:
	return is_finite(value) and value >= MIN_DIMENSION and value <= MAX_DIMENSION
