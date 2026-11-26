extends Node
## Fixed-step workloads for the original battle code and the real match scene.

const UnitCatalog := preload("res://match/unit_catalog.gd")
const Probe := preload("res://tests/performance/navigation_probe.gd")
const MATCH := preload("res://main.tscn")
const Fortifications := preload("res://match/fortification_rules.gd")
const SEED := 17
const ORIGINAL_ROSTER := [UnitCatalog.INFANTRY, UnitCatalog.RANGED, UnitCatalog.HEAVY]
const BOUNDS := Rect2(-30, -18, 60, 36)
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const STEP := MatchBattle.STEP

var _probe := Probe.new()
var _mode: String
var _screen: String
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 6:
		push_error("Run this scene through tests/performance/run_navigation_benchmark.py.")
		get_tree().quit(2)
		return
	Engine.register_singleton(&"LaneNavigationProbe", _probe)
	_mode = args[1]
	_screen = DisplayServer.get_name()
	_emit({
		"kind": "environment", "sha": args[2], "mode": _mode, "seed": SEED,
		"map_size": [BOUNDS.size.x, BOUNDS.size.y], "godot": Engine.get_version_info(),
		"os": OS.get_name(),
		"debug_build": OS.is_debug_build(), "display": _screen,
		"adapter": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
	})
	if args[0] in ["all", "matrix", "targeting"]:
		if not args[5].is_empty():
			for entry in args[5].split(","):
				var pair := entry.split(":")
				await _run_matrix_case(int(pair[0]), int(pair[1]), args[0] == "targeting")
		else:
			for obstacle_count in args[3].split(","):
				for unit_count in args[4].split(","):
					await _run_matrix_case(int(obstacle_count), int(unit_count), args[0] == "targeting")
	if args[0] in ["all", "match", "normal"]:
		await _run_normal_match()
	if args[0] in ["all", "match", "ownership"]:
		await _run_ownership()
	Engine.unregister_singleton(&"LaneNavigationProbe")
	_emit({"complete": _failures == 0})
	get_tree().quit(int(_failures != 0))


func _run_matrix_case(obstacles: int, unit_count: int, targeting_only: bool) -> void:
	var battle := MatchBattle.new(Vector2(-26, 0), Vector2(26, 0), 4.0, BOUNDS)
	var economy := MatchEconomy.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var wall := battle.add_fortification(Fortifications.WALL, CPU, Vector2.ZERO, PI / 2.0)
	var batch: Array[MatchBattle.Fortification] = [
		battle.add_fortification(Fortifications.WALL, CPU, Vector2(0, -1.35), PI / 2.0),
		battle.add_fortification(Fortifications.WALL, CPU, Vector2(0, 1.35), PI / 2.0),
		battle.add_barracks(CPU, Vector2(0, 4)),
	]
	# Shuffle positions with this RNG so larger cases extend the same layout.
	var sites: Array[Vector2] = []
	for row in range(10):
		for column in range(12):
			sites.append(Vector2((column - 5.5) * 2.0, (row - 4.5) * 2.5))
	_expect(obstacles >= 6 and obstacles <= 6 + sites.size(), "Unsupported matrix population")
	for i in range(obstacles - 6):
		var index := rng.randi_range(0, sites.size() - 1)
		var center := sites.pop_at(index) as Vector2
		var angle := rng.randf_range(-0.5, 0.5)
		battle.add_fortification(Fortifications.WALL, CPU, center, angle)

	var units: Array[MatchBattle.Unit] = []
	for i in range(unit_count):
		var side := PLAYER if i % 2 == 0 else CPU
		var direction := -1.0 if side == CPU else 1.0
		var lane := 0.18 * (fmod(floorf(i / 6.0), 16.0) - 1.5) if i % 4 < 2 else -15.0
		# This stress fixture intentionally exceeds the match's production cap.
		if battle._military_count[side] >= MatchBattle.MILITARY_UNIT_CAP:
			battle._military_count[side] = 0
		var unit := battle.spawn_unit(side, Vector2(-18 * direction, lane),
			ORIGINAL_ROSTER[floori(i / 2.0) % ORIGINAL_ROSTER.size()])
		_expect(unit != null, "Matrix unit spawn")
		units.append(unit)

	battle._military_count[PLAYER] = (unit_count + 1) / 2
	battle._military_count[CPU] = unit_count / 2
	var step := func() -> void: battle.advance(STEP, economy)
	var id := "%d obstacles / %d units" % [obstacles, unit_count]
	if targeting_only:
		for unit in units:
			var column := (unit.id - 1) / 2 % 20
			unit.position = Vector2(-0.4 if unit.side == PLAYER else 0.4, -16.0 + column * 0.07)
			_expect(battle.order_hold(unit.side, unit.id), "Stationary targeting order")
		await _phase(id, "stationary_targeting", battle, 30, step)
		_expect(units.any(func(unit: MatchBattle.Unit) -> bool:
			return unit.target > MatchBattle.NO_TARGET), "The stress armies engage.")
		return

	var issue_orders := func() -> void:
		for unit in units:
			var destination := Vector2(-unit.position.x, unit.position.y)
			_expect(battle.order_move(unit.side, unit.id, destination), "Matrix move order")
	await _phase(id, "cold_orders", battle, 1, Callable(), issue_orders)
	await _phase(id, "warm_orders", battle, 1, Callable(), issue_orders)
	_check_routes(battle, units)
	await _phase(id, "ordered_movement", battle, 60, step)
	await _phase(id, "wall_construction", battle, 30, step, func() -> void:
		battle.add_fortification(Fortifications.WALL, CPU, Vector2(0, -15), PI / 2.0)
	)
	await _phase(id, "single_wall_destruction", battle, 30, step, func() -> void:
		wall.hp = 0.0
	)
	_expect(battle.get_fortification(wall.id) == null, "Individual wall cleanup")
	await _phase(id, "batch_destruction", battle, 30, step, func() -> void:
		for building in batch:
			building.hp = 0.0
	)
	for building in batch:
		_expect(battle.get_fortification(building.id) == null, "Batch structure cleanup")
	_check_routes(battle, units)

	if obstacles != 20:
		return

	# Stage an engagement across the newly built wall with live targeting and combat.
	for i in range(units.size()):
		var unit := units[i]
		unit.position = Vector2(-1.2 if unit.side == PLAYER else 1.2,
			-15.0 + (fmod(floorf(i / 6.0), 16.0) - 2.0) * 0.04)
		battle.set_unit_stance(unit.side, unit.id, MatchBattle.Stance.SEEK_NEAREST, true)
	await _phase(id, "local_engagement", battle, 30, step)


func _new_match() -> Node:
	var game := MATCH.instantiate()
	game.map_seed = SEED
	add_child(game)
	game.set_process(false)
	return game


func _run_normal_match() -> void:
	var game := _new_match()
	var battle: MatchBattle = game._battle
	var tick := func() -> void: game._process(STEP)
	var case_id := "%d-region match" % game.region_count
	await _phase(case_id, "normal_match", battle, 360, tick)
	_expect(battle.elapsed_time() > 5.9, "Normal match advanced for six seconds")
	game.free()


func _run_ownership() -> void:
	var game := _new_match()
	# Keep claim discovery UI outside this fixture so combat continues immediately.
	game.claim_completed.disconnect(game._discover_on_claim)
	var battle: MatchBattle = game._battle
	var case_id := "%d-region match" % game.region_count
	var region: MatchRegion
	for candidate: MatchRegion in game._regions_by_id.values():
		if candidate.region_owner == NEUTRAL:
			region = candidate
			break
	var site := region.interior_point(battle.outpost_site_clear)
	_expect(site.is_finite(), "Outpost site available")
	# Complete the claim directly. Time the real ownership and footprint callbacks.
	var id := region.region_id
	var outpost_tick := func() -> void: game._process(STEP)
	await _phase(case_id, "outpost_claim", battle, 30, outpost_tick, func() -> void:
		game._complete_claim(PLAYER, id, 0, site)
	)
	_expect(region.region_owner == PLAYER, "Outpost claim sets ownership")

	var start := Vector2.INF
	var end := Vector2.INF
	for offset in [Vector2(0, 1.5), Vector2(0, -1.5), Vector2(0, 2.5), Vector2(0, -2.5)]:
		var a: Vector2 = site + offset - Vector2(1.5, 0)
		var b: Vector2 = site + offset + Vector2(1.5, 0)
		if game._wall_plan(PLAYER, a, b).reason.is_empty():
			start = a
			end = b
			break
	_expect(start.is_finite(), "Found legal wall placement inside the claimed region")
	await _phase(case_id, "purchase_wall", battle, 30, outpost_tick, func() -> void:
		_expect(game.try_place_wall(PLAYER, game._world_position(start),
			game._world_position(end)), "Purchased wall through match rules")
	)
	var outpost: MatchBattle.Outpost = game._outposts_by_region[id]
	await _phase(case_id, "outpost_destruction", battle, 30, outpost_tick, func() -> void:
		outpost.hp = 0.0
	)
	_expect(is_equal_approx(battle.elapsed_time(), 90 * STEP), "Ownership simulation advanced")
	_expect(region.region_owner == NEUTRAL and battle.get_outpost(outpost.id) == null,
		"Outpost destruction returns region to neutral")
	_expect(battle._fortifications.size() == 3, "All three wall segments remain placed")
	for building: MatchBattle.Fortification in battle._fortifications.values():
		_expect(not building.active, "Loss of ownership deactivates each wall segment")
	game.free()


func _check_routes(battle: MatchBattle, units: Array[MatchBattle.Unit]) -> void:
	for unit in units:
		var nav := battle.navigation.with_clearance(unit.definition.clearance)
		var point := unit.position
		_expect(not unit.waypoints.is_empty(), "Ordered route exists")
		for waypoint in unit.waypoints:
			_expect(nav.is_passable(waypoint) and nav.line_clear(point, waypoint, -1, true),
				"Ordered route clears static footprints")
			point = waypoint


func _phase(case_id: String, name: String, battle: MatchBattle, frames: int, tick: Callable,
		event := Callable()) -> void:
	await get_tree().process_frame
	_probe.reset()
	_probe.active = _mode == "probes"
	var frame_us: Array[int] = []
	var work_us: Array[int] = []
	var obstacle_start := battle.navigation._obstacles.size()
	var unit_start := battle.active_units().size()
	var revision_start := battle.navigation.revision
	for i in range(frames):
		var start := Time.get_ticks_usec()
		if i == 0 and event.is_valid():
			event.call()
		if tick.is_valid():
			tick.call()
		var work := Time.get_ticks_usec() - start
		await get_tree().process_frame
		frame_us.append(Time.get_ticks_usec() - start)
		work_us.append(work)
	_probe.active = false
	var units := battle.active_units()
	var state: Array = []
	for unit in units:
		state.append([unit.id, unit.position, unit.hp, unit.target, unit.waypoints])
	_emit({
		"kind": "phase", "case": case_id, "phase": name, "elapsed_sim_s": battle.elapsed_time(),
		"obstacles": [obstacle_start, battle.navigation._obstacles.size()],
		"units": [unit_start, units.size()], "revision_delta": battle.navigation.revision - revision_start,
		"unit_state_hash": hash(state), "frame_us": frame_us, "work_us": work_us,
		"timings": _probe.timings, "counts": _probe.counts,
		"draw_calls_last_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	})


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)


func _emit(row: Dictionary) -> void:
	print("NAV_BENCH ", JSON.stringify(row))
