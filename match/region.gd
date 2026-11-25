class_name MatchRegion
extends Node3D

enum Owner { NEUTRAL, PLAYER, CPU }

const OWNER_COLORS := {
	Owner.NEUTRAL: Color("#394b53"),
	Owner.PLAYER: Color("#235c76"),
	Owner.CPU: Color("#784538"),
}
const BORDER_COLOR := Color("#728487")
const SELECTED_BORDER_COLOR := Color("#ffe5a5")
const EDGE_GAP := 0.10
const BORDER_WIDTH := 0.075

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
