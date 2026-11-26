extends RefCounted


func setup(scene: Node) -> void:
	var modal := scene.get_node("%MatchSetup")
	var picker := modal.get_node("%Difficulty") as OptionButton
	picker.select(3)
	modal.get_node("%Confirm").pressed.emit()
	scene.get_node("%Restart").pressed.emit()
	picker.select(4)
	picker.item_selected.emit(4)
