extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bounds := Rect2(-30, -18, 60, 36)
	var field := BattleVisibility.new(bounds)
	field.set_source(1, MatchBattle.PLAYER, Vector2.ZERO, 5.0)
	field.set_source(2, MatchBattle.CPU, Vector2(12, 0), 5.0)
	field.advance(0.0)
	_check(field.state_at(MatchBattle.PLAYER, Vector2.ZERO) == BattleVisibility.State.VISIBLE, "player vision")
	_check(field.state_at(MatchBattle.CPU, Vector2.ZERO) == BattleVisibility.State.UNEXPLORED, "separate factions")
	var initial_work := field.processed_chunks
	field.move_source(1, Vector2(-10, 0))
	_check(not field.can_see(MatchBattle.PLAYER, Vector2.ZERO), "leaving vision is immediate")
	field.advance(0.1)
	_check(field.processed_chunks == initial_work, "movement waits for cadence")
	field.advance(0.2)
	_check(field.state_at(MatchBattle.PLAYER, Vector2.ZERO) == BattleVisibility.State.EXPLORED, "exploration persists")
	_check(field.processed_chunks - initial_work < field.dimensions.x * field.dimensions.y, "dirty work stays local")
	field.remove_source(2)
	field.advance(0.21)
	_check(not field.can_see(MatchBattle.CPU, Vector2(12, 0)), "destruction clears current vision")

	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var hidden := battle.spawn_unit(MatchBattle.CPU, Vector2(12, 0))
	_check(hidden != null and not battle.visible_units(MatchBattle.PLAYER).has(hidden), "hidden units absent from observations")
	if hidden != null:
		scene._select_unit(hidden.id)
		_check(scene.selected_unit() == null, "hidden enemy cannot be inspected")
	var scout: MatchBattle.Unit = battle.get_unit(scene._expeditions.slots[MatchBattle.PLAYER][0].unit_id)
	scout.position = Vector2(4, 0)
	_check(battle.visible_units(MatchBattle.PLAYER).has(hidden), "scout reveals enemy at eight units")
	_check(not battle.visible_units(MatchBattle.CPU).has(scout) or battle.can_see(MatchBattle.CPU, scout.position),
		"CPU receives only its own sightings")
	scene.restart_match()
	_check(scene._battle.visibility != field and scene._intelligence[MatchBattle.PLAYER].starts.size() == 2,
		"restart recreates faction intelligence and public starts")
	scene.queue_free()
	print("Visibility test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
