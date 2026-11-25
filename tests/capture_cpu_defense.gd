extends RefCounted
## Repeatable pressure on the CPU base, with construction and combat driven by the match.

const Rules := preload("res://match/fortification_rules.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER


func setup(scene: Node) -> void:
	# The fast-forwarded steps share a rendered frame. Skip accumulating expired effects.
	scene._battle.fortification_fired.disconnect(scene._show_fortification_shot)
	var shots := exercise(scene, 9)
	scene._battle.fortification_fired.connect(scene._show_fortification_shot)
	assert(shots.has(Rules.NEST) and shots.has(Rules.MORTAR))
	assert(scene._fortifications.values().any(func(placed: RefCounted) -> bool:
		return placed.defense.kind == Rules.WALL))
	var camera := scene.get_viewport().get_camera_3d() as StrategyCamera
	camera._focus = scene._battle._bases[CPU] + Vector2(-2.5, 0.0)
	camera.size = 15.0
	camera._target_size = camera.size
	camera._update_position()
	camera.set_process(false)


static func exercise(scene: Node, decisions := 10) -> Dictionary:
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.economy.advance(90.0)
	var shots := {}
	var battle: MatchBattle = scene._battle
	var targets: Dictionary[int, MatchBattle.Unit] = {}
	battle.fortification_fired.connect(func(fort: MatchBattle.Fortification, impact: Vector2) -> void:
		if fort.side == CPU:
			var hits: Array = shots.get_or_add(fort.kind, [])
			var damaged := false
			for unit in targets.values():
				if unit.side == PLAYER and unit.position.is_equal_approx(impact) \
						and unit.hp < MatchBattle.UNIT_HP:
					damaged = true
					break
			hits.append(damaged and fort.position.distance_to(impact) <= fort.profile.range))
	var hub: Vector2 = battle._bases[CPU]
	for decision in range(decisions):
		# Reinforce the same approach on each decision, using ordinary units as targets.
		for i in range(8):
			var id := 1000 + i
			if battle.get_unit(id) != null:
				continue
			var site := hub + Vector2(-4.65 - (i % 2) * 0.45, (i - 3.5) * 0.36)
			var unit := MatchBattle.Unit.new(id, PLAYER, site)
			unit.order = MatchBattle.Order.HOLD
			unit.ordered_destination = site
			targets[id] = unit
			battle._units[id] = unit
			battle.unit_produced.emit(unit)
		scene._process(scene.cpu_decision_interval)
		# Include a combat step after each purchase.
		scene._process(MatchBattle.STEP)
	return shots
