extends RefCounted

const Fixture := preload("res://tests/narrative_fixture.gd")


func setup(scene: Node) -> void:
	scene.narrative_catalog = Fixture.catalog()
	scene.restart_match()
	assert(scene.narrative_events.submit(&"visual-survey", Fixture.TRIGGER, Fixture.PLAYER))
