extends SceneTree
## Paired seeded trials against scripted opponents using shared match APIs.

const ScoutFixture := preload("res://tests/scout_fixture.gd")
const MatchScene := preload("res://main.tscn")
const Profiles := preload("res://match/difficulty_profile.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const SEEDS := [2, 7, 17, 26, 41, 59, 71, 93, 107]
const OPPONENTS := [
	[&"barracks", &"barracks", &"farm", &"barracks"],
	[&"barracks", &"training_range", &"farm", &"heavy_factory"],
	[&"barracks", &"machine_gun_nest", &"farm", &"training_range"],
]
const TIME_LIMIT := 80.0
const TICK := 1.0


class TimedMatch extends "res://match/match.gd":
	var decision_count := 0
	var decision_usec := 0

	func _try_cpu_purchase() -> void:
		var start := Time.get_ticks_usec()
		super._try_cpu_purchase()
		decision_usec += Time.get_ticks_usec() - start
		decision_count += 1


class Trial:
	var won := false
	var unresolved := false
	var lost_scout_energy := 0
	var first_claim := -1.0
	var player_builds := 0
	var cpu_builds := 0
	var kinds := {}
	var decisions := 0
	var decision_usec := 0

	func outcome_signature() -> Array:
		return [won, unresolved, lost_scout_energy, first_claim, player_builds, cpu_builds, kinds.keys(), decisions]


var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var levels := range(1, 6)
	if not args.is_empty():
		if args.size() != 1 or not args[0].is_valid_int() or args[0].to_int() not in levels:
			printerr("Pass one difficulty from 1 to 5 after --, or omit it to evaluate all levels.")
			quit(2)
			return
		levels = [args[0].to_int()]
	print("CPU vs scripted opponents. %d paired maps per level, %d seconds per match." % [SEEDS.size(), TIME_LIMIT])
	print("Level | CPU wins | Timeouts | Lost scout Energy | First claim (s) | Build kinds | Decision (ms)")
	for level: int in levels:
		var trials: Array[Trial] = []
		for index in SEEDS.size():
			var trial := _play(level, SEEDS[index], index)
			trials.append(trial)
			print("Level %d, seed %d: %s" % [level, SEEDS[index], trial.outcome_signature()])
			await process_frame
		_report(level, trials)
		var repeated := _play(level, SEEDS[0], 0)
		_check(repeated.outcome_signature() == trials[0].outcome_signature(),
			"Level %d repeats the same gameplay outcome with the same fixture seed." % level)
	quit(int(_failures > 0))


func _play(level: int, map_seed: int, index: int) -> Trial:
	# Use the gameplay scene with timing instrumentation only at the strategy entry point.
	var instance := MatchScene.instantiate()
	instance.set_script(TimedMatch)
	var scene := instance as TimedMatch
	scene.cpu_difficulty = level
	scene.map_seed = map_seed
	scene.region_count = 6 + index % 2
	scene.map_width = 30.0 + 6.0 * (index % 2)
	scene.map_height = 19.0 + 3.0 * (index % 2)
	root.add_child(scene)
	scene.set_process(false)

	var trial := Trial.new()
	scene.claim_completed.connect(func(side: MatchRegion.Owner, _region: StringName, _scout_id: int) -> void:
		if side == CPU and trial.first_claim < 0.0:
			trial.first_claim = scene._battle.elapsed_time())
	scene._expeditions.assignment_interrupted.connect(
		func(side: MatchRegion.Owner, _region: StringName, _elapsed: float) -> void:
			if side == CPU:
				trial.lost_scout_energy += scene.claim_energy)
	var opponent: Array = OPPONENTS[index % OPPONENTS.size()]
	var next_purchase := 0
	var seen := {}
	var battle: MatchBattle = scene._battle
	for tick in range(ceili(TIME_LIMIT / TICK)):
		if battle.is_finished():
			break
		if tick % 2 == 0 and next_purchase < opponent.size():
			var kind: StringName = opponent[next_purchase]
			if scene._purchase_block_reason(PLAYER, kind).is_empty():
				next_purchase += 1
				if _place(scene, PLAYER, kind):
					trial.player_builds += 1
		if tick == 45:
			scene.try_upgrade(PLAYER, ScoutFixture.barracks(scene._battle, PLAYER).id)
		scene._process(TICK)
		for placed in scene._fortifications.values():
			var fort: MatchBattle.Fortification = placed.defense
			if fort.side == CPU and not seen.has(fort.id):
				seen[fort.id] = true
				trial.kinds[fort.kind] = true

	trial.won = battle.outcome() == MatchBattle.Outcome.DEFEAT
	trial.unresolved = not battle.is_finished()
	trial.cpu_builds = seen.size()
	trial.decisions = scene.decision_count
	trial.decision_usec = scene.decision_usec
	_check(trial.player_builds >= 2 and trial.cpu_builds > 0 and trial.decisions > 0,
		"Both sides purchase buildings in seed %d at level %d." % [map_seed, level])
	scene.free()
	return trial


func _place(scene: Node, side: MatchRegion.Owner, kind: StringName) -> bool:
	var region: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	var point := region.interior_point(func(site: Vector2) -> bool:
		return scene._placement_block_reason(side, kind, scene._world_position(site)).is_empty())
	return point.is_finite() and scene.try_place_building(side, kind, scene._world_position(point))


func _report(level: int, trials: Array[Trial]) -> void:
	var totals := {"wins": 0, "timeouts": 0, "energy": 0, "claim_count": 0, "claim_time": 0.0,
		"diversity": 0, "decisions": 0, "usec": 0}
	for trial in trials:
		totals.wins += int(trial.won)
		totals.timeouts += int(trial.unresolved)
		totals.energy += trial.lost_scout_energy
		if trial.first_claim >= 0.0:
			totals.claim_time += trial.first_claim
			totals.claim_count += 1
		totals.diversity += trial.kinds.size()
		totals.decisions += trial.decisions
		totals.usec += trial.decision_usec
	var sample := float(trials.size())
	_check(totals.claim_count > 0, "Level %d completes scout claims in live fixtures." % level)
	var claim_time := "none" if totals.claim_count == 0 else "%.1f (%d/%d)" % [
		totals.claim_time / totals.claim_count, totals.claim_count, trials.size()]
	print("%s | %d/%d (%.0f%%) | %d | %.1f | %s | %.2f | %.3f" % [
		Profiles.display_name(level), totals.wins, trials.size(), 100.0 * totals.wins / sample,
		totals.timeouts, totals.energy / sample, claim_time, totals.diversity / sample,
		totals.usec / (1000.0 * maxi(1, totals.decisions))])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
