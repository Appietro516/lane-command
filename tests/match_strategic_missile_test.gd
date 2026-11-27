extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
const Rules := preload("res://match/fortification_rules.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var neutral: MatchRegion
	for region: MatchRegion in scene._regions_by_id.values():
		if region.region_owner == MatchRegion.Owner.NEUTRAL:
			neutral = region
			break
	var start: Vector2 = battle._bases[C]
	var launch := start + Vector2(2.0, -3.0)
	var data: Array[StringName] = [scene._layout.region_at(launch)]
	scene._add_fortification(C, Rules.SILO, launch, 0.0, data)
	var silo := battle._fortifications.values()[-1] as MatchBattle.MissileSilo
	var point := Vector2(neutral.position.x, neutral.position.z)
	var initial_hp := battle.base_hp(C)
	_check(not battle.can_see(P, launch), "silo initially hidden")
	_check(battle.prepare_missile(C, silo.id, point), "launch accepts ground target")
	var warning := battle.public_missile_launches()[silo.id]
	_check(warning.keys().size() == 3 and warning.point == launch and warning.launches_at == 60.0,
		"public warning includes source, owner and countdown")
	scene._refresh_intelligence()
	_check(scene._intel_markers.has(StringName("launch/%d" % silo.id)) and not battle.can_see(P, launch),
		"launch marker overrides fog independently")
	_check(not battle.prepare_missile(C, silo.id, battle._bases[P]), "charging silo cannot retarget")
	_check(battle.retaliation_target(P, Vector2.ZERO) == C, "announcement creates temporary threat")
	silo.hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(battle.public_missile_launches().is_empty(), "destruction cancels launch")

	var shot := MatchBattle.MissileFlight.new()
	shot.side = C
	shot.target = start
	var protected_point: Vector2 = start + Vector2.UP * 2.5
	var protected_region := scene.get_region(scene._layout.region_at(protected_point)) as MatchRegion
	var protected_unit := battle.spawn_unit(C, protected_point)
	_check(protected_unit != null and battle.missile_protected(protected_point), "actor inside original territory")
	battle._resolve_missile(shot)
	_check(battle.base_hp(C) == initial_hp and protected_unit.hp > 0.0 and not protected_region.ruined,
		"original starting territory is immune")
	shot.target = point
	battle._resolve_missile(shot)
	_check(neutral.ruined and neutral.region_owner == MatchRegion.Owner.NEUTRAL, "unprotected region is permanently ruined")
	_check(battle.navigation.is_passable(point) and battle._base_obstacles.has(C), "ruins remain fully traversable")
	_check(scene._missile_models.is_empty(), "enemy projectile cannot expose trajectory")
	scene.queue_free()
	print("Strategic missile test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
