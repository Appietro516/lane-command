extends "res://tests/capture_combat.gd"


func setup(scene: Node) -> void:
	# Capture at the requested window dimensions instead of the fixed logical viewport.
	var window := scene.get_window()
	window.content_scale_size = window.size
	await super(scene)
	var viewport := scene.get_viewport()
	var camera := viewport.get_camera_3d() as StrategyCamera
	var center := viewport.get_visible_rect().get_center()
	var overview := camera.position
	for i in range(12):
		_click(viewport, center, MOUSE_BUTTON_WHEEL_UP)
	camera._process(1.0)

	_click(viewport, center, MOUSE_BUTTON_MIDDLE)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(410, 145)
	motion.position = center + motion.relative
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	viewport.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.position = motion.position
	release.button_index = MOUSE_BUTTON_MIDDLE
	viewport.push_input(release, true)
	camera._process(1.0)
	assert(is_equal_approx(camera.size, StrategyCamera.MIN_SIZE))
	assert(camera.position.distance_to(overview) > 3.0)
