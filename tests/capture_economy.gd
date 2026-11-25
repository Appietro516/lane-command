extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene.try_build(MatchRegion.Owner.PLAYER)
	scene._process(10.0)
	scene.try_build(MatchRegion.Owner.PLAYER)
	scene._process(3.5)
