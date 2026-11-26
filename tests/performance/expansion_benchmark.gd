extends SceneTree
## Headless timings on the production match and its native navigation at full roster cap.

const MATCH := preload("res://main.tscn")
const Catalog := preload("res://match/unit_catalog.gd")
const Rules := preload("res://match/fortification_rules.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const STEP := MatchBattle.STEP


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results := {}
	for shape in MapSettings.SHAPE_NAMES:
		var generation := Time.get_ticks_usec()
		var layout := TerritoryLayout.new(17, 96, MapSettings.scaled_dimensions(shape, 96), 1, 1, 4, shape)
		assert(layout.configuration_error.is_empty() and layout.cells.size() == 96)
		results[MapSettings.SHAPE_NAMES[shape]] = Time.get_ticks_usec() - generation
	print("World generation microseconds for 96 regions and four CPUs ", JSON.stringify(results))

	var game := MATCH.instantiate()
	game.map_shape = MapSettings.Shape.CIRCLE
	game.map_width = MapSettings.scaled_dimensions(MapSettings.Shape.CIRCLE, 48).x
	game.region_count = 48
	game.cpu_opponent_count = 4
	game.legendary_count = 0
	game.narrative_catalog = null
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var battle: MatchBattle = game._battle
	var formation: Array[int] = []
	for side: MatchRegion.Owner in battle._bases:
		var angle := TAU * (side - PLAYER) / battle._bases.size()
		var forward := Vector2.from_angle(angle)
		for index in MatchBattle.MILITARY_UNIT_CAP:
			var lane := Vector2(index % 8 - 3.5, index / 8 - 2.5)
			var point := forward * 16.0 + lane.rotated(angle) * 0.95
			var unit := battle.spawn_unit(side, point, Catalog.COMBAT_TYPES[index % Catalog.COMBAT_TYPES.size()],
				null, MatchBattle.Stance.IDLE)
			assert(unit != null)
			unit.hp *= 0.65
			if side == PLAYER:
				formation.append(unit.id)
			else:
				battle.order_hold(side, unit.id)
	var army := battle.active_units().size()
	print("Battle population ", army, " including scouts")

	var start := Time.get_ticks_usec()
	assert(battle.order_formation(PLAYER, formation, Vector2(5, 0), MatchBattle.Order.MOVE, true) == formation.size())
	print("Formation enqueue microseconds ", Time.get_ticks_usec() - start)
	await _measure(game, "Formation movement and healing", 90)

	var construction := Time.get_ticks_usec()
	var wall := battle.add_fortification(Rules.WALL, CPU, Vector2(7.5, 0), PI * 0.5)
	print("Wall registration microseconds ", Time.get_ticks_usec() - construction)
	await _measure(game, "Wall construction and reroute", 90)
	wall.hp = 0.0
	await _measure(game, "Wall destruction and local update", 90)
	assert(battle.get_fortification(wall.id) == null)

	for unit in battle.active_units():
		if unit.type_id == Catalog.SCOUT:
			continue
		unit.position *= 0.25
		battle.order_hold(unit.side, unit.id)
	await _measure(game, "Multi-faction targeting and healing", 120)
	assert(battle._unit_grid.count == battle.active_units().size())
	game.free()
	quit()


func _measure(game: Node, label: String, steps: int) -> void:
	var samples: Array[int] = []
	for index in steps:
		var start := Time.get_ticks_usec()
		game._process(STEP)
		samples.append(Time.get_ticks_usec() - start)
		await process_frame
	var first := samples[0]
	samples.sort()
	print(label, " microseconds ", JSON.stringify({
		"first": first, "median": samples[steps / 2], "p95": samples[ceili(steps * 0.95) - 1],
		"max": samples[-1],
	}))
