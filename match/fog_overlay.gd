extends MeshInstance3D

var _field: BattleVisibility
var _side: int
var _image: Image
var _texture: ImageTexture
var _presented := -1
var upload_usec := 0


func configure(field: BattleVisibility, side: int, boundary: PackedVector2Array) -> void:
	_field = field
	_side = side
	visible = field != null
	if field == null:
		return
	_presented = -1
	upload_usec = 0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := field.bounds.get_center()
	for index in boundary.size():
		for point: Vector2 in [center, boundary[index], boundary[(index + 1) % boundary.size()]]:
			surface.add_vertex(Vector3(point.x, 0.025, point.y))
	mesh = surface.commit()
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
	var updates: Dictionary = _field.changed.get(_side, {})
	for id in updates:
		if updates[id] <= _presented:
			continue
		var chunk := _field.chunk_data(id)
		var patch := Image.create_from_data(width, width, false, Image.FORMAT_R8, chunk.texture_pixels())
		_image.blit_rect(patch, Rect2i(0, 0, width, width), chunk.origin)
		modified = true
	if modified:
		_texture.update(_image)
	_presented = _field.revision
	upload_usec += Time.get_ticks_usec() - start
