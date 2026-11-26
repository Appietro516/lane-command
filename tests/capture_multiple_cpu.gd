extends RefCounted


func setup(scene: Node) -> void:
	scene._open_match_setup(false)
	scene._opponent_picker.select(3)
	scene._opponent_picker.item_selected.emit(3)
	for i in 4:
		scene._difficulty_pickers[i].select(i + 1)
	scene._confirm_setup.pressed.emit()
	scene.set_process(false)
