extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var deployed := {}
	var hold_latest := func(unit: MatchBattle.Unit) -> void:
		if unit.side != MatchRegion.Owner.CPU:
			return
		unit.order = MatchBattle.Order.HOLD
		unit.ordered_destination = unit.position
		if deployed.has(unit.type_id):
			deployed[unit.type_id].hp = 0.0
		deployed[unit.type_id] = unit
	battle.unit_produced.connect(hold_latest)
	for decision in range(60):
		scene._process(scene.cpu_decision_interval)
		if deployed.size() == MatchBattle.UnitCatalog.DEFINITIONS.size():
			break
	assert(deployed.size() == MatchBattle.UnitCatalog.DEFINITIONS.size())
	battle.unit_produced.disconnect(hold_latest)

	# Let one unit of each type clear the exits so their silhouettes are visible.
	for unit: MatchBattle.Unit in deployed.values():
		unit.order = MatchBattle.Order.MOVE
		unit.ordered_destination = unit.position + unit.heading * 3.0
	scene._time_until_cpu_decision = 3.0
	scene._process(2.0)

	var area := Rect2(battle._bases[MatchRegion.Owner.CPU], Vector2.ZERO)
	for timer in battle._timers:
		if timer.side == MatchRegion.Owner.CPU and timer.active:
			area = area.expand(timer.position)
	for unit: MatchBattle.Unit in deployed.values():
		area = area.expand(unit.position)
	var camera := scene.get_viewport().get_camera_3d() as StrategyCamera
	camera._focus = area.get_center()
	camera.size = maxf(14.0, area.size.length() + 7.0)
	camera._update_position()
	camera.set_process(false)
