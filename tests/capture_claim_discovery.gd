extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	var player := MatchRegion.Owner.PLAYER
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	for region_id in start.neighbor_ids:
		if ScoutFixture.dispatch(scene, player, region_id):
			scene._select_region(region_id)
			scene._advance_simulation(60.0)
			assert(scene.get_tree().paused and scene.owns_region(player, region_id))
			return
	assert(false, "No reachable claim site for the discovery capture.")
