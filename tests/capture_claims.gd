extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	var player := MatchRegion.Owner.PLAYER
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	var first := start.neighbor_ids[0]
	var second := start.neighbor_ids[1]
	scene.economy.advance(17.0)
	assert(ScoutFixture.dispatch(scene, player, first))
	scene._advance_simulation(9.0)
	assert(ScoutFixture.dispatch(scene, player, second))
	scene._advance_simulation(0.8)
	scene._select_region(first)
	scene._use_scout_slot(0)
	scene._process(0.0)
