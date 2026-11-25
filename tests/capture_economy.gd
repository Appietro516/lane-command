extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.try_place_building(MatchRegion.Owner.PLAYER, &"barracks", Vector3(-10.2, 0, -1.2))
	scene._process(10.0)
	scene.try_place_building(MatchRegion.Owner.PLAYER, &"barracks", Vector3(-10.2, 0, -3.65))
	scene._process(3.5)
