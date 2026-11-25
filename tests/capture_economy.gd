extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._process(30.0)
	for side in [MatchRegion.Owner.PLAYER, MatchRegion.Owner.CPU]:
		assert(scene.try_build(side))
		assert(scene.try_build(side))
