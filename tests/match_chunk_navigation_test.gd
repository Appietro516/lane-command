extends SceneTree

const Battle := preload("res://match/battle.gd")
const Navigation := preload("res://match/battle_navigation.gd")

const BOUNDS := Rect2(-30, -18, 60, 36)
const START := Vector2(-23, 0)
const END := Vector2(23, 0)
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shapes_and_clearance()
	await _test_stale_build_and_cleanup()
	_test_route_retention()
	_test_placement_during_attack()
	if _failures == 0:
		print("Native navigation seams, clearances, stale builds, retention and cleanup passed.")
	quit(int(_failures > 0))


func _test_shapes_and_clearance() -> void:
	for shape in MapSettings.SHAPE_NAMES:
		var settings := MapSettings.new(shape as MapSettings.Shape, BOUNDS.size, 6, 17)
		var navigation := Navigation.new(settings.bounds, settings.boundary)
		navigation.add_obstacle(Rect2(-0.4, -5.0, 0.8, 10.0), 0.12)
		for clearance: float in [0.0, 0.10, 0.22, 0.34]:
			var routes := navigation.with_clearance(clearance)
			_check_route(routes, Vector2(-14, 1), Vector2(14, 1))
			_check(routes.path(Vector2(-14, 1), (settings.bounds.position - Vector2.ONE)).is_empty(),
				"A destination outside the clearance boundary is rejected.")
	var corridor := Navigation.new(Rect2(-12, -2, 24, 4))
	corridor.add_obstacle(Rect2(-0.5, -2.0, 1.0, 3.55))
	_check_route(corridor.with_clearance(0.10), Vector2(-9, 1.7), Vector2(9, 0))
	_check(corridor.with_clearance(0.34).path(Vector2(-9, 1.6), Vector2(9, 0)).is_empty(),
		"The wider unit cannot use the same gap.")


func _test_stale_build_and_cleanup() -> void:
	var navigation := Navigation.new(BOUNDS)
	navigation.add_obstacle(Rect2(-0.4, -3, 0.8, 6), 0.2)
	_check_route(navigation, START, END)
	_check(navigation.get("_chunks").size() == 15, "The default map partitions into 5 by 3 chunks.")
	var map := navigation._map
	var iteration := NavigationServer2D.map_get_iteration_id(map)
	var bounds := Rect2(-7, -14, 2, 3)
	var obstacle := navigation.add_obstacle(bounds)
	navigation.update()
	var tasks: Array[int] = []
	for chunk in navigation.get("_chunks"):
		if chunk.task != -1:
			tasks.append(chunk.task)
	_check(tasks.size() == 2, "A footprint spanning a seam submits exactly two chunk builds.")
	navigation.remove_obstacle(obstacle)
	var replacement := navigation.add_obstacle(Rect2(-6.4, -18, 0.8, 36))
	var finished := false
	for attempt in 120:
		finished = tasks.all(func(task: int) -> bool: return WorkerThreadPool.is_task_completed(task))
		if finished:
			break
		await process_frame
	_check(finished, "The superseded workers completed before publication is tested.")
	navigation.update()
	_check(NavigationServer2D.map_get_iteration_id(map) == iteration and not navigation._ready_to_publish,
		"The older worker results cannot become the next map revision.")
	_check(navigation.path(START, END).is_empty(),
		"A finished stale snapshot cannot reopen a lane across the replacement.")
	navigation.remove_obstacle(replacement)
	for attempt in 120:
		navigation.update()
		if navigation._ready_to_publish:
			break
		await process_frame
	_check(navigation._ready_to_publish, "The replacement geometry finishes off the simulation thread.")
	var blocked_iteration := NavigationServer2D.map_get_iteration_id(map)
	_check_route(navigation, START, END)
	_check(NavigationServer2D.map_get_iteration_id(map) != blocked_iteration,
		"The detour activates the ready snapshot and uses the reopened lane.")
	navigation.add_obstacle(bounds)
	navigation.update()
	navigation = null
	await physics_frame
	await process_frame
	_check(not NavigationServer2D.get_maps().has(map), "Dropping the owner releases its map.")


func _test_route_retention() -> void:
	var battle := Battle.new(Vector2(-27, 0), Vector2(27, 0), 4.0, BOUNDS)
	var economy := MatchEconomy.new()
	var unit := battle.spawn_unit(MatchRegion.Owner.PLAYER, START)
	battle.navigation.add_obstacle(Rect2(-0.4, -3, 0.8, 6), 0.2)
	_check(battle.issue_move(unit.id, END), "The initial detouring order is accepted.")
	var retained := unit.waypoints.duplicate()
	var space := battle.navigation.add_obstacle(Rect2(10, 13, 1, 1))
	battle.advance(Battle.STEP, economy)
	battle.navigation.remove_obstacle(space)
	battle.advance(Battle.STEP, economy)
	_check(unit.waypoints == retained and unit.route_revision == battle.navigation.revision,
		"Nonintersecting construction and demolition keep the same active route.")


func _test_placement_during_attack() -> void:
	var player := MatchRegion.Owner.PLAYER
	var cpu := MatchRegion.Owner.CPU
	var battle := Battle.new(Vector2(-27, 0), Vector2(27, 0), 4.0, BOUNDS)
	var economy := MatchEconomy.new()
	var start := Vector2(-2, 0)
	var mover := battle.spawn_unit(player, start)
	var attacker := battle.spawn_unit(player, Vector2(-4, -5))
	var defender := battle.spawn_unit(cpu, Vector2(-3.5, -5))
	battle.order_hold(player, attacker.id)
	battle.order_hold(cpu, defender.id)
	_check(battle.issue_move(mover.id, Vector2(4, 0)), "The unobstructed move is accepted.")
	battle.attack_resolved.connect(func(_event: Battle.AttackResolved) -> void:
		battle.navigation.add_obstacle(Rect2(-1.99, -1, 1, 2)), CONNECT_ONE_SHOT)
	battle.advance(Battle.STEP, economy)
	_check(mover.position == start, "A placement made after planning prevents that step's movement.")
	battle.advance(Battle.STEP, economy)
	_check(mover.waypoints.size() > 1, "The next fixed step takes a safe detour.")


func _check_route(routes: Navigation, start: Vector2, end: Vector2) -> void:
	var path := routes.path(start, end)
	_check(path.size() > 1 and path[-1] == end, "A cross-chunk detour reaches its destination.")
	var previous := start
	for point in path:
		_check(routes.line_clear(previous, point), "Every cross-chunk segment is safe.")
		previous = point


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
