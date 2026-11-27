extends MeshInstance3D

var _field: BattleVisibility
var _side: int
var _image: Image
var _texture: ImageTexture
var _presented := -1
var upload_usec := 0


func configure(field: BattleVisibility, side: int) -> void:
	_field = field
	_side = side
	visible = field != null
	if field == null:
		return
	_presented = -1
	upload_usec = 0
	var plane := PlaneMesh.new()
	plane.size = field.bounds.size
	mesh = plane
	position = Vector3(field.bounds.get_center().x, 0.025, field.bounds.get_center().y)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var size := field.dimensions * BattleVisibility.CELLS_PER_CHUNK
	_image = Image.create_empty(size.x, size.y, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	var material := ShaderMaterial.new()
	material.shader = preload("res://match/fog_of_war.gdshader")
	material.set_shader_parameter("visibility_mask", _texture)
	material.set_shader_parameter("map_origin", field.bounds.position)
	material.set_shader_parameter("map_size", field.bounds.size)
	material_override = material


func refresh() -> void:
	if _field == null or _presented == _field.revision:
		return
	var start := Time.get_ticks_usec()
	var modified := false
	var width := BattleVisibility.CELLS_PER_CHUNK
	for key in _field.changed:
		if key.z != _side or _field.changed[key] <= _presented:
			continue
		var patch := Image.create_from_data(width, width, false, Image.FORMAT_R8, _field.chunks[key].mask)
		_image.blit_rect(patch, Rect2i(0, 0, width, width), Vector2i(key.x, key.y) * width)
		modified = true
	if modified:
		_texture.update(_image)
	_presented = _field.revision
	upload_usec += Time.get_ticks_usec() - start
