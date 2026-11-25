extends RefCounted

const ScoutFixture := preload("res://tests/scout_fixture.gd")


func setup(scene: Node) -> void:
	scene.set_process(false)
	var player := MatchRegion.Owner.PLAYER
	var cpu := MatchRegion.Owner.CPU
	scene.outpost_hp = MatchBattle.ATTACK_DAMAGE
	ScoutFixture.claim(scene, player, &"region_1")
	scene.outpost_hp = MatchBattle.DEFAULT_OUTPOST_HP
	scene.economy.advance(35.0)
	ScoutFixture.claim(scene, player, &"region_3")

	var contested: MatchRegion = scene.get_region(&"region_1")
	scene.try_place_building(player, &"barracks", contested.global_position + Vector3(-2.6, 0, 0))
	var battle: MatchBattle = scene._battle
	var hub: MatchBattle.Outpost = scene._outposts_by_region[&"region_1"]
	var attacker := battle.add_barracks(cpu, hub.position + Vector2(2.8, 0))
	attacker.elapsed = scene.economy.production_interval(cpu)
	battle.advance(0.0, scene.economy)
	battle.set_barracks_active(attacker, false)
	battle.advance(1.0, scene.economy)
	scene._process(0.0)

	await scene.get_tree().process_frame
	var view: Node3D = scene._outpost_views[&"region_3"]
	var camera := scene.get_viewport().get_camera_3d()
	scene._pick_map(camera.unproject_position(view.global_position + Vector3.UP * 0.9))
