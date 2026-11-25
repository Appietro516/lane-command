extends RefCounted


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._process(5.5)
