extends MultiMeshInstance3D
## One instanced field of radar points. Exact intelligence stays in BattleRadar.

var _marker_material := StandardMaterial3D.new()
var _next_refresh := 0.0
var _snapshot_time := -1.0
var _visible_contacts: Array[BattleRadar.Contact] = []


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.no_depth_test = true
	var diamond := PlaneMesh.new()
	diamond.size = Vector2.ONE * 0.48
	diamond.material = _marker_material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = diamond


func clear() -> void:
	_next_refresh = 0.0
	_snapshot_time = -1.0
	_visible_contacts.clear()
	multimesh.visible_instance_count = 0


func refresh(battle: MatchBattle, side: MatchRegion.Owner) -> void:
	var now := battle.elapsed_time()
	var contacts := battle.radar.contacts_for(side)
	if contacts.is_empty():
		if not _visible_contacts.is_empty():
			clear()
		return
	var timestamp: float = contacts[0].recorded_at
	if timestamp != _snapshot_time or now >= _next_refresh:
		_snapshot_time = timestamp
		_next_refresh = now + BattleVisibility.UPDATE_INTERVAL
		_visible_contacts.clear()
		if multimesh.instance_count < contacts.size():
			multimesh.instance_count = ceili(contacts.size() / 32.0) * 32
		var marker_basis := Basis(Vector3.UP, PI / 4.0)
		for contact: BattleRadar.Contact in contacts:
			if battle.can_see(side, contact.point):
				continue
			var height := 0.11
			var transform_3d := Transform3D(marker_basis, Vector3(contact.point.x, height, contact.point.y))
			multimesh.set_instance_transform(_visible_contacts.size(), transform_3d)
			_visible_contacts.append(contact)
		multimesh.visible_instance_count = _visible_contacts.size()
	var alpha := clampf(1.0 - (now - timestamp) / BattleRadar.CONTACT_LIFETIME * 0.75, 0.25, 1.0)
	_marker_material.albedo_color = Color(0.52, 0.89, 1.0, alpha)


func contact_at(camera: Camera3D, pointer: Vector2, battle: MatchBattle, side: MatchRegion.Owner) -> BattleRadar.Contact:
	var nearest := 12.0 ** 2
	var result: BattleRadar.Contact
	for contact in _visible_contacts:
		var screen := camera.unproject_position(Vector3(contact.point.x, 0.11, contact.point.y))
		var distance := pointer.distance_squared_to(screen)
		if distance < nearest and not battle.can_see(side, contact.point):
			result = contact
			nearest = distance
	return result
