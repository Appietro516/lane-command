extends RefCounted

const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchBattle.PLAYER
const CPU := MatchBattle.CPU


func setup(scene: Node) -> void:
	scene.set_process(false)
	scene._time_until_cpu_decision = 120.0
	var battle: MatchBattle = scene._battle
	for unit in battle.active_units():
		unit.hp = 0.0
	var attacks: Array[MatchBattle.AttackResolved] = []
	battle.attack_resolved.connect(attacks.append)

	# Keep the three attacks separated at the normal overview zoom.
	battle.spawn_unit(PLAYER, Vector2(-6.4, 0.0), Catalog.INFANTRY)
	battle._spawn_unit(CPU, Vector2(-5.6, 0.0), Catalog.SCOUT)
	battle.spawn_unit(CPU, Vector2(-0.7, -2.1), Catalog.RANGED)
	battle._spawn_unit(PLAYER, Vector2(1.96, -1.65), Catalog.SCOUT)
	var base := scene.get_node("Regions/CPUStart/CPUBase") as Node3D
	var base_position: Vector2 = scene._map_position(base.global_position)
	battle.spawn_unit(PLAYER, base_position - Vector2(1.92, 0.0), Catalog.HEAVY)

	scene._process(MatchBattle.STEP * 5.0)
	assert(attacks.size() == 3)
	assert(attacks[0].attacker_type == Catalog.INFANTRY and attacks[0].target_id > 0)
	assert(attacks[1].attacker_type == Catalog.RANGED and attacks[1].target_id > 0)
	assert(attacks[2].attacker_type == Catalog.HEAVY and attacks[2].target_id == MatchBattle.BASE_TARGET)
	assert(scene._unit_attack_effects.mesh.get_surface_count() == 1)
