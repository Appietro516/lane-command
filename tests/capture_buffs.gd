extends RefCounted


func setup(scene: Node) -> void:
	const PLAYER := MatchRegion.Owner.PLAYER
	scene.set_process(false)
	assert(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0.0, -1.2)))
	scene.faction_stats.set_modifier(&"training", PLAYER, FactionStats.UNIT_DPS, 1.5, &"upgrade", "Training")
	scene.faction_stats.set_modifier(&"armor", PLAYER, FactionStats.BUILDING_MAX_HP, 5.0,
		&"upgrade", "Armor")
	scene.faction_stats.set_modifier(&"trade", PLAYER, FactionStats.ENERGY, 1.0, &"upgrade", "Trade")
	scene._process(10.0)
	assert(scene.try_claim(PLAYER, &"region_1"))
	scene.set_region_modifier(&"region_1", FactionStats.ENERGY, 1.0, "Reactor")
	scene._select_region(&"region_1")
	for unit in scene._battle.active_units():
		if unit.side == PLAYER:
			scene._select_unit(unit.id)
			break
	assert(scene.selected_unit() != null)
	scene._refresh_hud()
