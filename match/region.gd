class_name MatchRegion
extends Node3D

enum Owner { NEUTRAL, PLAYER, CPU, CPU_2, CPU_3, CPU_4 }

const EXTRA_CPU_ACCENTS := {
	Owner.CPU_2: Color("#b4ed72"),
	Owner.CPU_3: Color("#d8a5ff"),
	Owner.CPU_4: Color("#ffdb68"),
}
const PLAYER_ACCENT := preload("res://match/player_accent.tres")
const CPU_ACCENT := preload("res://match/cpu_accent.tres")

const OWNER_COLORS := {
	Owner.NEUTRAL: Color("#394b53"),
	Owner.PLAYER: Color("#235c76"),
	Owner.CPU: Color("#784538"),
	Owner.CPU_2: Color("#466632"),
	Owner.CPU_3: Color("#63477d"),
	Owner.CPU_4: Color("#756226"),
}
const BORDER_COLOR := Color("#728487")
const SELECTED_BORDER_COLOR := Color("#ffe5a5")
const EDGE_GAP := 0.10
const BORDER_WIDTH := 0.075
const INTERIOR_SAMPLE_SPACING := 0.5

var region_id: StringName
var region_owner: Owner = Owner.NEUTRAL:
	set(value):
		region_owner = value
		if is_node_ready():
			_fill_material.albedo_color = OWNER_COLORS[value]
var neighbor_ids: Array[StringName]
var polygon: PackedVector2Array

var geometry: MeshInstance3D
var _fill_material := StandardMaterial3D.new()
var _border_material := StandardMaterial3D.new()


static func side_label(side: Owner, show_cpu_number: bool) -> String:
	match side:
		Owner.NEUTRAL:
			return "Neutral"
		Owner.PLAYER:
			return "Player"
		Owner.CPU:
			return "CPU 1" if show_cpu_number else "CPU"
		_:
			return "CPU %d" % (side - Owner.PLAYER)


static func accent_color(side: Owner) -> Color:
	match side:
		Owner.PLAYER:
			return PLAYER_ACCENT.albedo_color
		Owner.CPU:
			return CPU_ACCENT.albedo_color
		_:
			return EXTRA_CPU_ACCENTS[side]


func _init(cell: TerritoryLayout.Cell) -> void:
	region_id = cell.id
	neighbor_ids = cell.neighbor_ids
	polygon = cell.polygon
	position = Vector3(cell.site.x, 0.0, cell.site.y)


func _ready() -> void:
	var outline := PackedVector2Array()
	for point in polygon:
		outline.append(point - Vector2(position.x, position.z))
	var outer_edge := Geometry2D.offset_polygon(outline, -EDGE_GAP, Geometry2D.JOIN_MITER)[0]
	var inner_edge := Geometry2D.offset_polygon(outer_edge, -BORDER_WIDTH, Geometry2D.JOIN_MITER)[0]
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.albedo_color = BORDER_COLOR
	_add_surface("Border", outer_edge, _border_material, -0.02)

	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.albedo_color = OWNER_COLORS[region_owner]
	geometry = _add_surface("Tile", inner_edge, _fill_material, 0.0)



func set_selected(selected: bool) -> void:
	_border_material.albedo_color = SELECTED_BORDER_COLOR if selected else BORDER_COLOR


func interior_point(is_clear: Callable = Callable()) -> Vector2:
	var preferred := _preferred_interior_point()
	if not preferred.is_finite() or not is_clear.is_valid() or is_clear.call(preferred):
		return preferred

	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var columns := ceili(bounds.size.x / INTERIOR_SAMPLE_SPACING)
	var rows := ceili(bounds.size.y / INTERIOR_SAMPLE_SPACING)
	var best := Vector2.INF
	var best_distance := INF
	for y in range(rows):
		for x in range(columns):
			var fraction := Vector2((x + 0.5) / columns, (y + 0.5) / rows)
			var candidate := bounds.position + fraction * bounds.size
			var distance := preferred.distance_squared_to(candidate)
			if distance < best_distance and is_clear.call(candidate) and _contains_interior(candidate):
				best = candidate
				best_distance = distance
	return best


func _contains_interior(point: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for i in range(polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(
			point, polygon[i], polygon[(i + 1) % polygon.size()])
		if point.is_equal_approx(nearest):
			return false
	return true


func _preferred_interior_point() -> Vector2:
	var site := Vector2(position.x, position.z)
	if _contains_interior(site):
		return site

	# A triangle centroid stays inside even when the authored polygon is concave.
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var best := Vector2.INF
	var largest_area := 0.0
	for i in range(0, triangles.size(), 3):
		var a := polygon[triangles[i]]
		var b := polygon[triangles[i + 1]]
		var c := polygon[triangles[i + 2]]
		var area := absf((b - a).cross(c - a))
		if area > largest_area:
			largest_area = area
			best = (a + b + c) / 3.0
	return best


func _add_surface(surface_name: String, polygon: PackedVector2Array,
		material: StandardMaterial3D, height: float) -> MeshInstance3D:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var point := polygon[index]
		surface.add_vertex(Vector3(point.x, 0.0, point.y))
	var view := MeshInstance3D.new()
	view.name = surface_name
	view.mesh = surface.commit()
	view.material_override = material
	view.position.y = height
	add_child(view)
	return view
