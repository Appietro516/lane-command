class_name MatchRegion
extends Node3D

enum Owner { NEUTRAL, PLAYER, CPU }

const OWNER_COLORS := {
	Owner.NEUTRAL: Color("#747c85"),
	Owner.PLAYER: Color("#287dce"),
	Owner.CPU: Color("#c4434c"),
}
const BORDER_WIDTH := 0.055

var region_id: StringName
var region_owner: Owner = Owner.NEUTRAL:
	set(value):
		region_owner = value
		if is_node_ready():
			(geometry.material_override as StandardMaterial3D).albedo_color = OWNER_COLORS[value]
var neighbor_ids: Array[StringName]
var polygon: PackedVector2Array
var geometry: MeshInstance3D


func _init(cell: TerritoryLayout.Cell) -> void:
	region_id = cell.id
	neighbor_ids = cell.neighbor_ids
	polygon = cell.polygon
	position = Vector3(cell.site.x, 0.0, cell.site.y)


func _ready() -> void:
	var local_polygon := PackedVector2Array()
	for point in polygon:
		local_polygon.append(point - Vector2(position.x, position.z))

	var border := _make_surface(local_polygon, 0.0)
	border.name = "Border"
	var border_material := StandardMaterial3D.new()
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_material.albedo_color = Color("#28313d")
	border.material_override = border_material
	add_child(border)

	var inset := Geometry2D.offset_polygon(local_polygon, -BORDER_WIDTH, Geometry2D.JOIN_MITER)
	geometry = _make_surface(inset[0], 0.008)
	geometry.name = "Surface"
	var material := StandardMaterial3D.new()
	material.albedo_color = OWNER_COLORS[region_owner]
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.3
	geometry.material_override = material
	add_child(geometry)


func set_selected(selected: bool) -> void:
	(geometry.material_override as StandardMaterial3D).emission_enabled = selected


static func _make_surface(points: PackedVector2Array, height: float) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for point in points:
		vertices.append(Vector3(point.x, height, point.y))
		normals.append(Vector3.UP)

	var indices := Geometry2D.triangulate_polygon(points)
	# CCW triangles in XY face up in XZ with Godot's clockwise front faces.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance
