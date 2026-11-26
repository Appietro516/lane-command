extends RefCounted

func setup(scene: Node) -> void:
	scene.set_process(false)
	var player := MatchRegion.Owner.PLAYER
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	var first := start.neighbor_ids[0]
	var second := start.neighbor_ids[1]
	scene.economy.advance(17.0)
	scene._select_region(first)
	scene._refresh_hud()
	var claim := scene.get_node("%Claim") as Button
	assert(not claim.disabled and scene.selected_unit() == null)
	claim.pressed.emit()
	var scout = scene._expeditions.assignments[first]
	scene._advance_simulation(scene._expeditions.eta(scout) - scene.claim_duration + 5.0)
	scene._select_region(second)
	scene._process(0.0)
	assert(not claim.disabled and scene.selected_unit() == null)
