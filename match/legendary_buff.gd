class_name LegendaryBuff
extends Resource
## One weighted entry in a match's legendary landmark catalog.

@export var landmark_name := ""
@export var stat: StringName
@export var magnitude := 1.0
@export_range(0, 10000, 1) var weight := 1


func _init(display_name := "", stat_id := &"", amount := 1.0) -> void:
	landmark_name = display_name
	stat = stat_id
	magnitude = amount
