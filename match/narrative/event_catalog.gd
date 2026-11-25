class_name NarrativeCatalog
extends Resource

@export var events: Array[NarrativeEvent] = []


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Array[StringName] = []
	for event in events:
		if event == null:
			errors.append("Missing event definition")
			continue
		var reason := event.validation_error()
		if not reason.is_empty():
			errors.append("%s: %s" % [event.id, reason])
		if event.id in ids:
			errors.append("Duplicate event ID %s" % event.id)
		ids.append(event.id)
	return errors
