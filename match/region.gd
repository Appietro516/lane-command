class_name MatchRegion
extends Node3D

enum Owner { NEUTRAL, PLAYER, CPU }

const PICK_LAYER := 1 << 1
const OWNER_COLORS := {
	Owner.NEUTRAL: Color("#747c85"),
	Owner.PLAYER: Color("#287dce"),
	Owner.CPU: Color("#c4434c"),
}

@export var region_id: StringName
@export var region_owner: Owner = Owner.NEUTRAL:
	set(value):
		region_owner = value
		if is_node_ready():
			(geometry.material_override as StandardMaterial3D).albedo_color = OWNER_COLORS[value]
@export var neighbor_ids: Array[StringName] = []
@export var geometry: MeshInstance3D


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = OWNER_COLORS[region_owner]
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.55
	geometry.material_override = material

	# Pick the visible mesh so irregular regions use the same selection path.
	var body := StaticBody3D.new()
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.transform = global_transform.affine_inverse() * geometry.global_transform
	var collision := CollisionShape3D.new()
	collision.shape = geometry.mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)


func set_selected(selected: bool) -> void:
	(geometry.material_override as StandardMaterial3D).emission_enabled = selected
