extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.economy.advance(120.0)
	var player := MatchRegion.Owner.PLAYER
	assert(scene.try_place_building(player, &"barracks", Vector3(-13.0, 0, -1.3)))
	assert(scene.try_place_building(player, &"training_range", Vector3(-8.5, 0, -0.8)))
	assert(scene.try_place_building(player, &"heavy_factory", Vector3(-10.2, 0, -5.0)))
	var battle: MatchBattle = scene._battle
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		unit.order = MatchBattle.Order.HOLD
		unit.ordered_destination = unit.position)
	battle.advance(6.0, scene.economy)
	var factory: MatchBattle.ProductionTimer = battle._timers.back()
	scene._select_fortification(factory.id)
	scene._toggle_build_menu()
