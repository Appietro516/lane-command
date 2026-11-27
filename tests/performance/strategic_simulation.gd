extends SceneTree
## godot --headless --path . --script tests/performance/strategic_simulation.gd -- 17 1 Rectangle 1200

const CpuStrategy := preload("res://match/cpu_strategy.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const P := MatchBattle.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL

var _first_engagement := -1.0
var _claims := 0
var _camp_attacks := 0
var _casualties := 0
var _unit_types := {}
var _foes := {}
var _trajectory: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map_seed := int(args[0]) if args.size() > 0 else 17
	var opponents := int(args[1]) if args.size() > 1 else 1
	var shape := MapSettings.Shape.CIRCLE if args.size() > 2 and args[2] == "Circle" else MapSettings.Shape.RECTANGLE
	var duration := float(args[3]) if args.size() > 3 else 1200.0
	var size := MapSettings.scaled_dimensions(shape, 7)
	var layout := TerritoryLayout.new(map_seed, 7, size, 1, 1, opponents, shape)
	var levels: Array[int] = []
	for index in opponents:
		levels.append(3)
	var scene: Node = load("res://main.tscn").instantiate()
	scene.configure_match(MatchSettings.new(layout.settings, levels), layout)
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var bot := CpuStrategy.new(map_seed, 3, P)
	bot.time_until_decision = scene._decision_period(bot) + 0.17
	scene._cpu_strategies[P] = bot
	scene.claim_completed.connect(func(_side: MatchRegion.Owner, _region: StringName, _scout: int) -> void:
		_claims += 1)
	battle.attack_resolved.connect(_record_attack)
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		_unit_types[unit.id] = unit.type_id
		_foes[unit.id] = unit.side)
	battle.unit_removed.connect(func(id: int) -> void:
		if _unit_types.has(id) and _foes[id] != NEUTRAL and _unit_types[id] != Catalog.SCOUT:
			_casualties += 1
		_unit_types.erase(id)
		_foes.erase(id))
	var next_report := 0.0
	var wall_start := Time.get_ticks_msec()
	while not battle.is_finished() and battle.elapsed_time() < duration:
		scene._process(minf(1.0, duration - battle.elapsed_time() + 0.00001))
		while scene._has_narrative_decision():
			var dialogue: Dictionary = scene.narrative_events.player_dialogue()
			var chosen := false
			for option in dialogue.options:
				if option.blocked.is_empty() and scene.narrative_events.resolve_player(dialogue.id, option.id):
					chosen = true
					break
			if not chosen:
				push_error("No affordable narrative option in simulation")
				quit(1)
				return
		if battle.elapsed_time() >= next_report:
			next_report += 60.0
			var snapshot := _snapshot(scene, battle)
			_trajectory.append(snapshot)
			print("SAMPLE ", JSON.stringify(snapshot))
	if _trajectory.is_empty() or _trajectory[-1].seconds != snappedf(battle.elapsed_time(), 0.1):
		_trajectory.append(_snapshot(scene, battle))
	print("RESULT ", JSON.stringify({
		"seed": map_seed, "opponents": opponents, "shape": MapSettings.SHAPE_NAMES[shape],
		"seconds": snappedf(battle.elapsed_time(), 0.01), "wall_seconds": (Time.get_ticks_msec() - wall_start) / 1000.0,
		"outcome": MatchBattle.Outcome.keys()[battle.outcome()], "first_engagement": snappedf(_first_engagement, 0.01),
		"claims": _claims, "camp_attacks": _camp_attacks, "camp_kills": battle.objectives.defeated,
		"stronghold_pickups": battle.objectives.stronghold_pickups, "boons": battle.objectives.pickups,
		"casualties": _casualties, "bounties": scene._strength.awarded, "trajectory": _trajectory,
	}))
	scene.queue_free()
	await process_frame
	quit()


func _record_attack(attack: MatchBattle.AttackResolved) -> void:
	if attack.attacker_side == NEUTRAL or attack.target_side == NEUTRAL:
		_camp_attacks += 1
	elif _first_engagement < 0.0:
		_first_engagement = attack.simulation_time


func _snapshot(scene: Node, battle: MatchBattle) -> Dictionary:
	var bases := {}
	var composition := {}
	for side in battle._bases:
		bases[side] = snappedf(battle.base_hp(side), 0.1)
		composition[side] = {}
	for unit in battle.active_units():
		if unit.side != NEUTRAL:
			var counts: Dictionary = composition[unit.side]
			counts[unit.type_id] = counts.get(unit.type_id, 0) + 1
	return {"seconds": snappedf(battle.elapsed_time(), 0.1), "bases": bases, "army": composition,
		"scores": scene._strength.scores.duplicate(), "claims": _claims, "camp_kills": battle.objectives.defeated,
		"stronghold_pickups": battle.objectives.stronghold_pickups, "casualties": _casualties,
		"bounties": scene._strength.awarded}
