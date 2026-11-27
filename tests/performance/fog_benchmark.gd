extends SceneTree
## godot --headless --path . --script tests/performance/fog_benchmark.gd -- 500 4 Circle on

const Catalog := preload("res://match/unit_catalog.gd")
const Rules := preload("res://match/fortification_rules.gd")
const RECT_SIZE := Vector2(108, 72)
const FRAMES := 120


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "matrix":
		var matrix_shape := MapSettings.Shape.CIRCLE if args.size() > 1 and args[1] == "Circle" else MapSettings.Shape.RECTANGLE
		for opponents in [1, 2, 4]:
			for count in [100, 250, 500]:
				for enabled in [false, true]:
					await _run_case(count, opponents, matrix_shape, enabled)
	else:
		var count := int(args[0]) if args.size() > 0 else 250
		var opponents := int(args[1]) if args.size() > 1 else 4
		var shape := MapSettings.Shape.CIRCLE if args.size() > 2 and args[2] == "Circle" else MapSettings.Shape.RECTANGLE
		var enabled := args.size() < 4 or args[3] == "on"
		await _run_case(count, opponents, shape, enabled)
	quit()


func _run_case(count: int, opponents: int, shape: MapSettings.Shape, enabled: bool) -> void:
	var render_frames := DisplayServer.get_name() != "headless"
	var size := Vector2(100, 100) if shape == MapSettings.Shape.CIRCLE else RECT_SIZE
	var layout := TerritoryLayout.new(1729, 36, size, 1, 1, opponents, shape)
	var levels: Array[int] = []
	for i in opponents:
		levels.append(3)
	var before := OS.get_static_memory_usage()
	var scene: Node = load("res://main.tscn").instantiate()
	scene.fog_enabled = enabled
	scene.neutral_objectives_enabled = false
	scene.configure_match(MatchSettings.new(layout.settings, levels), layout)
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	battle.radar.pulse_interval = 0.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 9601
	var actors: Array[MatchBattle.Unit] = []
	var factions := battle._bases.keys()
	for i in count:
		var side: MatchRegion.Owner = factions[i % factions.size()]
		var base: Vector2 = battle._bases[side]
		# The benchmark exceeds the live production cap while using the same unit index and views.
		var point := base.lerp(Vector2.ZERO, 0.35) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		var unit := MatchBattle.Unit.new(battle._next_unit_id, side, point, Catalog.INFANTRY)
		battle._next_unit_id += 1
		battle._military_count[side] += 1
		battle._units[unit.id] = unit
		battle._index_unit(unit)
		battle.unit_produced.emit(unit)
		actors.append(unit)

	var watchtowers: Array[MatchBattle.Fortification] = []
	var silo: MatchBattle.MissileSilo
	var structure_profile := {"size": Vector2.ONE, "hp": 20.0}
	for side: MatchRegion.Owner in factions:
		var base: Vector2 = battle._bases[side]
		var toward := base.direction_to(Vector2.ZERO)
		for i in 2:
			var position := base + toward.rotated(-0.5 + i * 0.9) * 3.2
			battle.add_structure(BattleRadar.RADAR, structure_profile, side, position)
		if side == MatchBattle.CPU:
			var place := base + toward.rotated(1.2) * 4.8
			var sites: Array[StringName] = [layout.region_at(place)]
			scene._add_fortification(side, Rules.SILO, place, 0.0, sites)
			silo = battle._fortifications.values()[-1] as MatchBattle.MissileSilo

	var command_start := Time.get_ticks_usec()
	var move_orders := 0
	for unit in actors:
		var toward := unit.position.direction_to(Vector2.ZERO)
		if battle.order_move(unit.side, unit.id, unit.position + toward * 9.0, true):
			move_orders += 1
	var command_usec := Time.get_ticks_usec() - command_start
	var frames := PackedFloat64Array()
	var presentations := PackedFloat64Array()
	var query_usec := 0
	var queries := 0
	var field := battle.visibility
	for frame in FRAMES:
		var start := Time.get_ticks_usec()
		if frame == 20:
			for side: MatchRegion.Owner in factions:
				var point: Vector2 = battle._bases[side].lerp(Vector2.ZERO, 0.3)
				watchtowers.append(battle.add_structure(BattleRadar.WATCHTOWER,
					{"size": Vector2.ONE, "hp": 24.0, "vision": 11.0}, side, point))
		elif frame == 42:
			battle.prepare_missile(silo.side, silo.id, Vector2.ZERO)
		elif frame == 70:
			for tower in watchtowers:
				tower.hp = 0.0
		elif frame == 86:
			for i in range(0, actors.size(), 2):
				actors[i].hp = 0.0
		battle.advance(MatchBattle.STEP, scene.economy)
		if frame % 12 == 0:
			var query_start := Time.get_ticks_usec()
			for side: MatchRegion.Owner in factions:
				battle.visible_units(side)
				queries += 1
			query_usec += Time.get_ticks_usec() - query_start
		var present := Time.get_ticks_usec()
		scene._refresh_intelligence()
		for unit in battle.active_units():
			scene._update_unit_view(unit, scene._unit_views[unit.id])
		scene._update_missile_warning()
		presentations.append((Time.get_ticks_usec() - present) / 1000.0)
		if render_frames:
			await process_frame
		frames.append((Time.get_ticks_usec() - start) / 1000.0)
	print("BENCH ", JSON.stringify({
		"shape": MapSettings.SHAPE_NAMES[shape], "cpu": opponents, "units": count, "fog": enabled,
		"render_frames": render_frames, "frames": FRAMES, "milliseconds": _percentiles(frames),
		"presentation_cpu_milliseconds": _percentiles(presentations),
		"vision_mean_milliseconds": float(field.update_usec) / maxi(1, field.ticks) / 1000.0 if field != null else 0.0,
		"vision_max_milliseconds": field.max_update_usec / 1000.0 if field != null else 0.0,
		"dirty_chunks": field.processed_chunks if field != null else 0,
		"source_rasters": field.evaluated_sources if field != null else 0,
		"visibility_queries": field.query_count if field != null else 0,
		"upload_cpu_milliseconds": scene._fog_overlay.upload_usec / 1000.0,
		"memory_delta_mib": (OS.get_static_memory_usage() - before) / 1048576.0,
		"ai_query_mean_milliseconds": float(query_usec) / queries / 1000.0,
		"radar_pulses": battle.radar.pulse_count, "move_orders": move_orders,
		"command_milliseconds": command_usec / 1000.0,
		"nav_revision": battle.navigation.revision, "path_cache_entries": battle.navigation._requests.size(),
		"final_units": battle.active_units().size(),
	}))
	scene.queue_free()
	await process_frame


func _percentiles(values: PackedFloat64Array) -> Array[float]:
	values.sort()
	var result: Array[float] = []
	for percentile in [0.5, 0.95, 0.99]:
		result.append(values[clampi(ceili(values.size() * percentile) - 1, 0, values.size() - 1)])
	return result
