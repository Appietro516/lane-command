extends RefCounted


func setup(scene: Node) -> void:
	scene.cpu_opponent_count = 4
	scene.cpu_difficulty = 2
	scene.additional_cpu_difficulties.assign([3, 4, 5])
	scene.restart_match()
	scene.set_process(false)
