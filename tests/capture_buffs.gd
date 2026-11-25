extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	const PLAYER := MatchRegion.Owner.PLAYER
	scene.set_process(false)
	assert(ScoutFixture.claim(scene, PLAYER, &"region_1"))
	scene.economy.advance(14.0)
	assert(scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0.0, -1.2)))
	scene.faction_stats.set_modifier(&"training", PLAYER, FactionStats.UNIT_DPS, 1.5, &"upgrade", "Training")
	scene.faction_stats.set_modifier(&"armor", PLAYER, FactionStats.BUILDING_MAX_HP, 5.0,
		&"upgrade", "Armor")
	scene.faction_stats.set_modifier(&"trade", PLAYER, FactionStats.ENERGY, 1.0, &"upgrade", "Trade")
	scene._time_until_cpu_decision = 120.0
	scene._process(10.0)
	scene.set_region_modifier(&"region_1", FactionStats.ENERGY, 1.0, "Reactor")
	scene._select_region(&"region_1")
	for unit in ScoutFixture.combat_units(scene._battle):
		if unit.side == PLAYER:
			scene._select_unit(unit.id)
			break
	assert(scene.selected_unit() != null)
	scene._refresh_hud()
