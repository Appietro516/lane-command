class_name FactionIntelligence
extends RefCounted
## Historical observations contain data snapshots only. They cannot be targeted.

var starts: Dictionary = {}
var structures: Dictionary[StringName, Dictionary] = {}
var regions: Dictionary[StringName, Dictionary] = {}
var landmarks: Dictionary[StringName, bool] = {}


func remember_structure(id: StringName, side: int, point: Vector2, label: String, time: float) -> void:
	structures[id] = {"side": side, "point": point, "label": label, "observed_at": time}
