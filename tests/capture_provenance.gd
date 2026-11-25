extends RefCounted
## Map seed 22 puts an Energy landmark on the player's frontier.

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const PLAYER := MatchRegion.Owner.PLAYER
const ENERGY := FactionStats.ENERGY


func setup(scene: Node) -> void:
	var state := prepare(scene)
	assert(not state.is_empty())
	scene._select_unit(state.unit.id)
	scene._refresh_hud()
	scene.get_node("%Resources/energy").pressed.emit()
	scene.get_node("%StatSources").button_pressed = true


static func prepare(scene: Node) -> Dictionary:
	scene.set_process(false)
	scene.economy.advance(55.0)
	var landmark: LegendaryLandmark
	for candidate: LegendaryLandmark in scene._landmarks.values():
		if candidate.stat == ENERGY and ScoutFixture.claim(scene, PLAYER, candidate.region_id):
			landmark = candidate
			break
	if landmark == null:
		return {}

	var frontier: MatchRegion = scene.get_region(landmark.region_id)
	var home: MatchRegion = scene.get_region(scene._initial_owners.find_key(PLAYER))
	if not _place(scene, frontier, &"generator") or not _place(scene, home, &"generator") \
			or not _place(scene, frontier, &"barracks"):
		return {}

	scene.set_region_modifier(frontier.region_id, FactionStats.UNIT_DPS, 1.0, "Frontier Academy")
	scene.set_region_modifier(frontier.region_id, FactionStats.UNIT_MAX_HP, 4.0, "Frontier Academy")
	scene.faction_stats.set_modifier(&"veteran", PLAYER, FactionStats.UNIT_DPS, 1.5,
		&"upgrade", "Veteran Training")
	scene.faction_stats.set_modifier(&"veteran", PLAYER, FactionStats.UNIT_MAX_HP, 3.0,
		&"upgrade", "Veteran Training")
	scene.faction_stats.set_modifier(&"veteran", PLAYER, FactionStats.BUILDING_MAX_HP, 5.0,
		&"upgrade", "Veteran Training")
	scene._battle.advance(scene.economy.production_interval(PLAYER), scene.economy)
	return {"unit": ScoutFixture.combat_units(scene._battle).front(), "landmark": landmark, "frontier": frontier}


static func _place(scene: Node, region: MatchRegion, kind: StringName) -> bool:
	var site := region.interior_point(func(point: Vector2) -> bool:
		return scene._placement_block_reason(PLAYER, kind, scene._world_position(point)).is_empty())
	return site.is_finite() and scene.try_place_building(PLAYER, kind, scene._world_position(site))
