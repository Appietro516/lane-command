extends MeshInstance3D
## One unlit, batched mesh for unit attacks. Only the match's fixed clock ages cues.

const Catalog := preload("res://match/unit_catalog.gd")
const MAX_CUES := 512
const UNIT_HEIGHT := 0.52
const STRUCTURE_HEIGHT := 0.88


var _cues: Array[MatchBattle.AttackResolved] = []
var _replace_index := 0
var _rendered_time := -1.0
var _geometry := ImmediateMesh.new()


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# Keep the contact flash visible over tall structures and overlapping tokens.
	material.no_depth_test = true
	material.render_priority = 1
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _geometry


func record(attack: MatchBattle.AttackResolved) -> void:
	if not Catalog.DEFINITIONS[attack.attacker_type].has("attack_effect"):
		return
	if _cues.size() < MAX_CUES:
		_cues.append(attack)
	else:
		_cues[_replace_index] = attack
		_replace_index = (_replace_index + 1) % MAX_CUES


func clear() -> void:
	_cues.clear()
	_geometry.clear_surfaces()
	_replace_index = 0
	_rendered_time = -1.0


func render_at(simulation_time: float) -> void:
	if _cues.is_empty() or simulation_time == _rendered_time:
		return
	_rendered_time = simulation_time
	_geometry.clear_surfaces()
	var active := 0
	for attack in _cues:
		var profile: Dictionary = Catalog.DEFINITIONS[attack.attacker_type].attack_effect
		var progress := (simulation_time - attack.simulation_time) / float(profile.duration)
		if progress >= 1.0:
			continue
		if active == 0:
			_geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_draw_cue(attack, profile.style, progress)
		_cues[active] = attack
		active += 1
	if active > 0:
		_geometry.surface_end()
	if active < _cues.size():
		_cues.resize(active)
		_replace_index = 0


func _draw_cue(attack: MatchBattle.AttackResolved, style: StringName, progress: float) -> void:
	var start := attack.attack_position
	var impact := attack.impact_position
	var direction := start.direction_to(impact)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var height := UNIT_HEIGHT if attack.target_id > MatchBattle.NO_TARGET else STRUCTURE_HEIGHT
	var tint: Color = MatchRegion.accent_color(attack.attacker_side)
	tint.a = 1.0 - progress * progress
	var core := tint.lerp(Color(1.0, 0.98, 0.88, tint.a), 0.78)

	match style:
		&"swing":
			# Sweep past the contact point, with a bright leading edge.
			var angle := direction.angle() + lerpf(-1.08, 0.65, progress)
			var pivot := start.lerp(impact, 0.35)
			var reach := maxf(0.42, pivot.distance_to(impact) + 0.22)
			_arc(pivot, reach, angle - 0.62, 1.24, 0.18, height, tint, 8)
			_arc(pivot, reach, angle + 0.30, 0.32, 0.10, height, core, 3)
			_spark(impact, direction, lerpf(0.17, 0.36, progress), height, core)
		&"tracer":
			# The head is already at the impact. The tail retracts along the shot.
			var tail := start.lerp(impact, progress * 0.88)
			_stroke(tail, impact, 0.14, height, tint)
			_stroke(tail.lerp(impact, 0.22), impact, 0.045, height, core)
			_spark(impact, direction, lerpf(0.14, 0.29, progress), height, tint)
		&"pulse":
			# The weapon braces into the shot as the contact flash expands.
			var brace := start + direction * lerpf(-0.20, 0.48, minf(progress * 4.0, 1.0))
			_arc(brace, 0.49, direction.angle() - 0.93, 1.86, 0.14, UNIT_HEIGHT, tint, 6)
			var radius := lerpf(0.32, 1.0, 1.0 - (1.0 - progress) ** 2)
			_arc(impact, radius, 0.0, TAU, 0.15, height, tint, 12)
			_arc(impact, radius * 0.66, 0.0, TAU, 0.08, height, core, 12)
			_spark(impact, direction, lerpf(0.28, 0.45, progress), height, core)

		&"heal":
			var mint := Color(0.55, 1.0, 0.69, tint.a)
			_stroke(start, impact, 0.05, height, mint)
			_arc(impact, lerpf(0.22, 0.72, progress), 0.0, TAU, 0.075, height, mint, 12)
			_spark(impact, Vector2.from_angle(PI * 0.25), 0.15, height + 0.01, core)
		&"slash":
			var angle := direction.angle() + lerpf(-0.8, 0.75, progress)
			_arc(impact, 0.39, angle - 0.9, 1.8, 0.10, height, core, 7)
			_arc(impact - direction * 0.13, 0.58, angle - 0.6, 1.35, 0.08, height, tint, 6)
			_spark(impact, direction, 0.25, height, tint)


func _spark(center: Vector2, direction: Vector2, radius: float, height: float, tint: Color) -> void:
	var axis := direction.rotated(PI * 0.25)
	_stroke(center - axis * radius, center + axis * radius, 0.085, height, tint)
	var across := axis.orthogonal() * radius
	_stroke(center - across, center + across, 0.085, height, tint)


func _arc(center: Vector2, radius: float, start: float, sweep: float, width: float,
		height: float, tint: Color, segments: int) -> void:
	var previous := Vector2.from_angle(start)
	for segment in range(1, segments + 1):
		var next := Vector2.from_angle(start + sweep * segment / segments)
		_quad(center + previous * (radius - width), center + previous * radius,
			center + next * (radius - width), center + next * radius, height, tint)
		previous = next


func _stroke(start: Vector2, end: Vector2, width: float, height: float, tint: Color) -> void:
	var edge := start.direction_to(end).orthogonal() * width * 0.5
	_quad(start - edge, start + edge, end - edge, end + edge, height, tint)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, height: float, tint: Color) -> void:
	_geometry.surface_set_color(tint)
	for point: Vector2 in [a, b, c, c, b, d]:
		_geometry.surface_add_vertex(Vector3(point.x, height, point.y))
