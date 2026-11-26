extends SceneTree

const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const BOUNDS := Rect2(-12, -8, 24, 16)
const CLEARANCES := [0.0, 0.10, 0.34]
const KEEP := Rect2(-0.6, -2.0, 1.2, 4.0)
const OVERLAP := Rect2(-0.9, -2.5, 0.8, 1.1)
const SCREEN := Rect2(2.0, -3.0, 0.7, 2.4)

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_demolition_step()
	_test_links_with_two_blockers()
	_test_repeated_removals()
	_test_indexed_visibility()
	if _failures == 0:
		print("Simultaneous destruction, clearance and repeated navigation updates passed.")
	quit(1 if _failures > 0 else 0)


func _test_demolition_step() -> void:
	var battle := MatchBattle.new(Vector2(-10, 0), Vector2(10, 0), 0.1, BOUNDS)
	var economy := MatchEconomy.new()
	var upper := battle.add_fortification(Rules.WALL, CPU, Vector2(0, -1.2), PI * 0.5)
	var lower := battle.add_fortification(Rules.WALL, CPU, Vector2(0, 1.2), PI * 0.5)
	var remaining := battle.add_fortification(Rules.WALL, CPU, Vector2(0, 0), PI * 0.5)
	var destroyed: Array[int] = []
	battle.fortification_destroyed.connect(func(fort: MatchBattle.Fortification) -> void:
		destroyed.append(fort.id))
	var lost := battle.spawn_unit(PLAYER, Vector2(-3, -3))
	var removed: Array[int] = []
	battle.unit_removed.connect(func(id: int) -> void: removed.append(id))
	var orders: Array[MatchBattle.Unit] = []
	for i in Catalog.COMBAT_TYPES.size():
		var unit := battle.spawn_unit(PLAYER, Vector2(-4, 1.1 + 0.1 * i), Catalog.COMBAT_TYPES[i])
		_check(battle.issue_move(unit.id, Vector2(4, unit.position.y)), "Move order accepted.")
		_check(unit.waypoints.size() > 1, "An intact wall forces a detour.")
		orders.append(unit)

	upper.hp = 0.0
	lower.hp = 0.0
	lost.hp = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(destroyed == [upper.id, lower.id] and removed == [lost.id],
		"Both walls and the unit emit exactly one removal in the lethal step.")
	_check(battle.get_fortification(upper.id) == null and battle.get_fortification(lower.id) == null
		and battle.get_unit(lost.id) == null and battle.get_fortification(remaining.id) == remaining,
		"Destruction removes only the dead units and structures immediately.")

	battle.advance(MatchBattle.STEP, economy)
	for unit in orders:
		var routes := battle.navigation.with_clearance(unit.definition.clearance)
		_check(unit.waypoints == PackedVector2Array([unit.ordered_destination]),
			"Existing move orders use the new opening on the next plan.")
		_check(routes.path(Vector2(-4, 0), Vector2(4, 0)).size() > 1,
			"Each clearance still routes around the surviving wall.")
	_check(destroyed.size() == 2 and removed.size() == 1, "Later steps emit no duplicate removals.")


func _test_links_with_two_blockers() -> void:
	var navigation := BattleNavigation.new(BOUNDS)
	var left := navigation.add_obstacle(Rect2(-4.5, -0.5, 1, 1))
	var right := navigation.add_obstacle(Rect2(3.5, -0.5, 1, 1))
	var first := navigation.add_obstacle(Rect2(-1.8, -1, 0.8, 2))
	var second := navigation.add_obstacle(Rect2(1, -1, 0.8, 2))
	var start := Vector2(-8, 0)
	var end := Vector2(8, 0)
	for clearance: float in CLEARANCES:
		var routes := navigation.with_clearance(clearance)
		routes.path(start, end)
		_check(not routes._graph.are_points_connected(left * 4 + 1, right * 4),
			"The two blocks prevent an edge between the facing upper corners.")
	navigation.remove_obstacle(first)
	for clearance: float in CLEARANCES:
		var routes := navigation.with_clearance(clearance)
		routes.path(start, end)
		_check(not routes._graph.are_points_connected(left * 4 + 1, right * 4),
			"A second footprint still prevents the same edge.")
	navigation.remove_obstacle(second)
	for clearance: float in CLEARANCES:
		var routes := navigation.with_clearance(clearance)
		routes.path(start, end)
		_check(routes._graph.are_points_connected(left * 4 + 1, right * 4),
			"The last removal restores the edge between previously visible corners.")


func _test_repeated_removals() -> void:
	var navigation := BattleNavigation.new(BOUNDS)
	navigation.add_obstacle(KEEP)
	var start := Vector2(-5, -1.8)
	var end := Vector2(6, -1.4)
	for cycle in 300:
		var overlap := navigation.add_obstacle(OVERLAP, 0.1)
		var screen := navigation.add_obstacle(SCREEN, -0.23)
		var survivor := navigation.add_obstacle(SCREEN, 0.23)
		# Warm the graph and both endpoint caches with obstacles still present.
		var routes_by_clearance: Array[BattleNavigation] = []
		for clearance: float in CLEARANCES:
			var routes := navigation.with_clearance(clearance)
			_check(routes.path(start, end).size() > 1,
				"Initial route detours around the obstacles.")
			routes_by_clearance.append(routes)
		navigation.remove_obstacle(overlap)
		navigation.remove_obstacle(screen)
		var fresh := BattleNavigation.new(BOUNDS)
		fresh.add_obstacle(KEEP)
		fresh.add_obstacle(SCREEN, 0.23)
		for i in CLEARANCES.size():
			var routes := routes_by_clearance[i]
			var actual := routes.path(start, end)
			var expected := fresh.with_clearance(CLEARANCES[i]).path(start, end)
			_check(not expected.is_empty() and is_equal_approx(
				_route_length(start, actual), _route_length(start, expected)),
				"Incremental and freshly constructed graphs find equally short routes.")
			var previous := start
			for point in actual:
				_check(routes.line_clear(previous, point), "Every route segment remains passable.")
				previous = point
			_check(previous == end, "The detour reaches its original destination.")
		navigation.remove_obstacle(survivor)


func _test_indexed_visibility() -> void:
	var bounds := Rect2(-32, -20, 64, 40)
	var navigation := BattleNavigation.new(bounds)
	var individual: Array[BattleNavigation] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 28:
		var footprint := Rect2(Vector2(rng.randf_range(-28, 27), rng.randf_range(-17, 16)),
			Vector2(rng.randf_range(0.4, 3.0), rng.randf_range(0.4, 3.0)))
		var angle := rng.randf_range(-PI, PI)
		navigation.add_obstacle(footprint, angle)
		var single := BattleNavigation.new(bounds)
		single.add_obstacle(footprint, angle)
		individual.append(single)
	for ignored in [-1, 7]:
		for allow_exit in [false, true]:
			for i in 250:
				var start := Vector2(rng.randf_range(-31, 31), rng.randf_range(-19, 19))
				var end := Vector2(rng.randf_range(-31, 31), rng.randf_range(-19, 19))
				var expected := true
				for index in individual.size():
					if index != ignored and not individual[index].line_clear(start, end, -1, allow_exit):
						expected = false
						break
				_check(navigation.line_clear(start, end, ignored, allow_exit) == expected,
					"Indexed and individual obstacles agree about rotated segment visibility.")


func _route_length(start: Vector2, route: PackedVector2Array) -> float:
	var length := 0.0
	for point in route:
		length += start.distance_to(point)
		start = point
	return length


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		if _failures <= 10:
			push_error(message)
