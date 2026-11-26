extends RefCounted
## Run the real dispatch, movement and timer for tests arranging an owned region.
## Advance only battle steps so CPU decisions and passive income keep their own schedules.

const Catalog := preload("res://match/unit_catalog.gd")


static func dispatch(scene: Node, side: MatchRegion.Owner, region_id: StringName) -> bool:
	return scene.dispatch_scout(side, region_id).is_empty()


static func finish_claim(scene: Node, side: MatchRegion.Owner, region_id: StringName) -> bool:
	var battle: MatchBattle = scene._battle
	var expedition = scene._expeditions.assignments.get(region_id)
	if expedition == null or expedition.side != side:
		return false
	var steps := ceili((scene._expeditions.eta(expedition) + 2.0) / MatchBattle.STEP)
	for step in steps:
		battle.advance(MatchBattle.STEP, scene.economy)
		if not scene._expeditions.assignments.has(region_id):
			break
	scene._process(0.0)
	return scene.owns_region(side, region_id)


static func claim(scene: Node, side: MatchRegion.Owner, region_id: StringName) -> bool:
	return dispatch(scene, side, region_id) and finish_claim(scene, side, region_id)


static func combat_units(battle: MatchBattle) -> Array[MatchBattle.Unit]:
	return battle.active_units().filter(func(unit: MatchBattle.Unit) -> bool:
		return unit.type_id != Catalog.SCOUT)
