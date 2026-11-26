extends RefCounted

const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._time_until_cpu_decision = INF
	var battle: MatchBattle = scene._battle
	var side := MatchRegion.Owner.PLAYER
	var regions: Array[StringName] = []
	var removed := battle.add_fortification(Rules.WALL, side, Vector2.ZERO, PI * 0.5)
	var covered: Array[StringName] = [scene._layout.region_at(removed.position)]
	scene._add_structure_view(removed, regions, covered)
	for y in [-2, -1, 1, 2]:
		var wall := battle.add_fortification(Rules.WALL, side, Vector2(0, y), PI * 0.5)
		covered = [scene._layout.region_at(wall.position)]
		scene._add_structure_view(wall, regions, covered)
	var unit := battle.spawn_unit(side, Vector2(-1.3, 0), Catalog.RANGED)
	assert(battle.issue_move(unit.id, Vector2(4.0, 0)))
	assert(unit.waypoints.size() > 1)
	scene._select_unit(unit.id)
	removed.hp = 0.0
	for i in 44:
		scene._process(MatchBattle.STEP)
	assert(battle.get_fortification(removed.id) == null and unit.position.x > 0.0)
	assert(unit.waypoints == PackedVector2Array([Vector2(4.0, 0)]))
	var camera := scene.get_viewport().get_camera_3d() as StrategyCamera
	camera._focus = Vector2.ZERO
	camera.size = 10.0
	camera._update_position()
	camera.set_process(false)
