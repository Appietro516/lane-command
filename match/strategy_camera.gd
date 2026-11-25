class_name StrategyCamera
extends Camera3D

const MIN_SIZE := 9.0
const ZOOM_STEP := 1.18
const PAN_SPEED := 0.75
const RESPONSE := 14.0
const CAMERA_DISTANCE := 32.0

var _map_bounds := Rect2(-TerritoryLayout.DEFAULT_SIZE / 2.0, TerritoryLayout.DEFAULT_SIZE)
var _focus := Vector2.ZERO
var _target_focus := Vector2.ZERO
var _target_size: float
var _overview_size: float
var _dragging := false


func _ready() -> void:
	get_viewport().size_changed.connect(_update_overview_size)
	get_window().focus_exited.connect(end_drag)
	get_window().mouse_exited.connect(end_drag)
	_update_overview_size()
	reset_view(true)


func set_map_bounds(bounds: Rect2) -> void:
	_map_bounds = bounds
	_update_overview_size()
	reset_view(true)


func reset_view(immediate := false) -> void:
	_target_focus = _map_bounds.get_center()
	_target_size = _overview_size
	if immediate:
		_focus = _target_focus
		size = _target_size
		_update_position()


func is_dragging() -> bool:
	return _dragging


func _update_overview_size() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var map_size := _map_bounds.size
	var width := absf(basis.x.x) * map_size.x + absf(basis.x.z) * map_size.y
	var height := absf(basis.y.x) * map_size.x + absf(basis.y.z) * map_size.y
	var was_at_overview := is_equal_approx(_target_size, _overview_size)
	# Leave room for the HUD above and below the map.
	_overview_size = maxf(MIN_SIZE, maxf(width / (0.92 * viewport_size.aspect()), height / 0.74))
	_target_size = _overview_size if was_at_overview else minf(_target_size, _overview_size)


func _process(delta: float) -> void:
	if not _dragging:
		var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		_pan(direction * size * PAN_SPEED * delta)
	var weight := 1.0 - exp(-RESPONSE * delta)
	_focus = _focus.lerp(_target_focus, weight)
	size = lerpf(size, _target_size, weight)
	_update_position()


func _update_position() -> void:
	# At the pan limits even the closest corner must stay in front of the camera.
	var depth := Vector2(absf(basis.z.x), absf(basis.z.z)).dot(_map_bounds.size)
	position = Vector3(_focus.x, 0.0, _focus.y) + basis.z * maxf(CAMERA_DISTANCE, depth + 4.0)


func _pan(offset: Vector2) -> void:
	# Project camera right and screen down onto the map plane.
	var right := Vector2(basis.x.x, basis.x.z)
	var down := Vector2(-basis.y.x, -basis.y.z) / (basis.z.y * basis.z.y)
	var bounds := _map_bounds
	_target_focus = (_target_focus + right * offset.x + down * offset.y).clamp(
		bounds.position, bounds.end)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.is_action_pressed("camera_overview"):
			reset_view()
			get_viewport().set_input_as_handled()
		elif event.is_action("camera_left") or event.is_action("camera_right") \
				or event.is_action("camera_up") or event.is_action("camera_down"):
			get_viewport().set_input_as_handled()
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var viewport_height := get_viewport().get_visible_rect().size.y
		if viewport_height > 0.0:
			_pan(-event.relative * size / viewport_height)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.pressed:
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_MIDDLE:
			_dragging = true
		MOUSE_BUTTON_WHEEL_UP:
			_target_size = maxf(MIN_SIZE, _target_size / ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			_target_size = minf(_overview_size, _target_size * ZOOM_STEP)
		_:
			return
	get_viewport().set_input_as_handled()


func end_drag() -> void:
	_dragging = false
