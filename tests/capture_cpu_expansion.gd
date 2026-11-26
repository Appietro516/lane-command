extends RefCounted

const CPU := MatchRegion.Owner.CPU


func setup(scene: Node) -> void:
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var garrison: Array[MatchBattle.Unit] = []
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		if unit.side == CPU and unit.type_id != MatchBattle.UnitCatalog.SCOUT:
			unit.order = MatchBattle.Order.HOLD
			unit.ordered_destination = unit.position
			garrison.append(unit)
			if garrison.size() > 5:
				var retired: MatchBattle.Unit = garrison.pop_front()
				retired.hp = 0.0)

	for decision in range(60):
		scene._process(scene.cpu_decision_interval)
		if scene._outposts_by_region.is_empty():
			continue
		for scout in scene._expeditions.assignments.values():
			if scout.side != CPU:
				continue
			var outpost: MatchBattle.Outpost = scene._outposts_by_region.values()[0]
			var area := Rect2(battle._bases[CPU], Vector2.ZERO)
			area = area.expand(outpost.position).expand(scout.site)
			area = area.expand(battle.get_unit(scout.unit_id).position)
			var camera := scene.get_viewport().get_camera_3d() as StrategyCamera
			camera._focus = area.get_center()
			camera.size = maxf(21.0, area.size.length() + 14.0)
			camera._update_position()
			camera.set_process(false)
			scene._select_region(scout.region_id)
			scene._process(0.0)
			return
	assert(false, "Expected a completed CPU outpost and a second active expedition.")
