class_name MatchRegion
extends Node3D

enum Owner { NEUTRAL, PLAYER, CPU }

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
	geometry.material_override = material
