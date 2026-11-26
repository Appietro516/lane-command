extends RefCounted


func setup(scene: Node) -> void:
	var setup_screen: MatchSetup = scene.get_node("MatchSetup")
	var picker := setup_screen._difficulty_pickers[0]
	picker.select(picker.get_item_index(5))
	picker.item_selected.emit(picker.selected)
