class_name LegendaryLandmark
extends Node3D

const HALF_SIZE := Vector2(0.65, 0.65)

var region_id: StringName
var source_id: StringName
var display_name: String
var stat: StringName
var magnitude: float
var footprint: Rect2


func configure(id: StringName, point: Vector2, buff: LegendaryBuff) -> void:
	region_id = id
	source_id = StringName("legendary/" + id)
	display_name = buff.landmark_name
	stat = buff.stat
	magnitude = buff.magnitude
	footprint = Rect2(point - HALF_SIZE, HALF_SIZE * 2.0)
