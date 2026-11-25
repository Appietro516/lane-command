extends SceneTree


func _initialize() -> void:
	var diagnostic := _validate_project()
	if not diagnostic.is_empty():
		printerr(diagnostic)
		quit(1)
	else:
		quit()


func _validate_project() -> String:
	var project := ConfigFile.new()
	var error := project.load("res://project.godot")
	if error != OK:
		return "Could not read project.godot (%s)." % error_string(error)

	var renderer = project.get_value("rendering", "renderer/rendering_method", "")
	var web_renderer = project.get_value("rendering", "renderer/rendering_method.web", renderer)
	if web_renderer != "gl_compatibility":
		return "Web export requires the Compatibility renderer (gl_compatibility)."
	var main_scene = project.get_value("application", "run/main_scene", "")
	if not main_scene is String or main_scene.is_empty():
		return "Set a main scene before exporting."

	# The build script already checks that this editor matches .godot-version.
	var version := Engine.get_version_info()
	var major_minor := "%d.%d" % [version.major, version.minor]
	var features = project.get_value("application", "config/features", PackedStringArray())
	if not (features is PackedStringArray or features is Array) or major_minor not in features:
		return "project.godot features and .godot-version must use the same Godot major/minor."
	if "C#" in features:
		return "The standard single-threaded Web build does not support .NET or GDExtension."
	return ""
