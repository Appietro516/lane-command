extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	var player := MatchRegion.Owner.PLAYER
	scene.economy.advance(40.0)
	assert(ScoutFixture.claim(scene, player, &"region_1"))
	assert(scene.try_place_building(player, &"barracks", Vector3(-10.2, 0, -1.2)))
	assert(scene.try_place_building(player, &"generator", Vector3(-11.5, 0, -4.9)))
	assert(scene.try_place_building(player, &"farm", Vector3(-12.7, 0, 4.5)))
	var expansion: MatchRegion = scene.get_region(&"region_1")
	var site := expansion.interior_point(func(point: Vector2) -> bool:
		return scene._placement_block_reason(player, &"mine", scene._world_position(point)).is_empty())
	assert(scene.try_place_building(player, &"mine", scene._world_position(site)))
	scene._process(5.5)
	scene._toggle_build_menu()
