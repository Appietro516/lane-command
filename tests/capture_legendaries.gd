extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	const PLAYER := MatchRegion.Owner.PLAYER
	const NEUTRAL := MatchRegion.Owner.NEUTRAL
	scene.set_process(false)
	var landmark: LegendaryLandmark = scene._landmarks.values()[0]
	var region: MatchRegion = scene.get_region(landmark.region_id)
	if not ScoutFixture.claim(scene, PLAYER, region.region_id):
		# Arrange a nearby player frontier for the screenshot.
		for neighbor in region.neighbor_ids:
			if scene.owns_region(NEUTRAL, neighbor) and not scene._landmarks.has(neighbor):
				scene._set_region_owner(neighbor, PLAYER)
				break
		assert(ScoutFixture.claim(scene, PLAYER, region.region_id))
	var crystal := landmark.get_node("Crystal/Upper") as MeshInstance3D
	var camera := scene.get_node("Camera") as Camera3D
	scene._pick_map(camera.unproject_position(crystal.global_position))
	assert(scene._selected_region_id == region.region_id)
