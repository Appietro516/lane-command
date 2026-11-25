extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._process(2.0)
	scene.try_build(MatchRegion.Owner.PLAYER)
	scene._process(7.0)
