extends SceneTree

const MatchFixture := preload("res://tests/prototype_match_fixture.gd")
const ScoutFixture := preload("res://tests/scout_fixture.gd")
const Expeditions := preload("res://match/scout_expeditions.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const FIRST := &"region_1"
const OTHER := &"region_3"
const FRONTIER := &"region_4"
const CPU_FIRST := &"region_2"
const ENERGY := MatchEconomy.ENERGY

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MatchFixture.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var initial := _roster(scene)
	var events: Array[Array] = []
	scene.claim_completed.connect(func(faction: MatchRegion.Owner, region: StringName, scout_id: int) -> void:
		events.append([faction, region, scout_id, scene.owns_region(faction, region),
			scene._outposts_by_region.has(region)])
	)
	_check(initial.size() == 4 and scene._expeditions.available(PLAYER).size() == 2
		and scene._expeditions.available(CPU).size() == 2, "Both factions start with two Scouts.")
	_check(not scene.has_method("try_claim")
		and scene._battle.spawn_unit(PLAYER, Vector2.ZERO, Catalog.SCOUT) == null,
		"Instant claims and free Scout spawns are unavailable in a match.")
	await _test_concurrent_claims(scene, events)
	_test_contest_and_recall(scene, events)
	_test_lost_adjacency(scene)
	_test_completion_and_casualty_on_same_step(scene)
	_test_collision_and_death(scene, events)
	scene.restart_match()
	scene.set_process(false)
	_check(_roster(scene) == initial and scene.economy.energy(PLAYER) == 50.0
		and scene.economy.energy(CPU) == 50.0 and scene._expeditions.assignments.is_empty()
		and scene._outposts_by_region.is_empty() and scene._claim_markers.is_empty()
		and scene.owns_region(NEUTRAL, FIRST), "Restart restores roster, balances and neutral ownership.")
	scene.free()
	if failures == 0:
		print("Scout expedition and claim controls checks passed.")
	quit(1 if failures > 0 else 0)


func _test_concurrent_claims(scene: Node, events: Array[Array]) -> void:
	await process_frame
	await process_frame
	var battle: MatchBattle = scene._battle
	var roster: Array = scene._expeditions.slots[PLAYER]
	var first := roster[0] as Expeditions.Scout
	var second := roster[1] as Expeditions.Scout
	var claim := scene.get_node("%Claim") as Button
	var selection := scene.get_node("%SelectedRegion") as Label
	var region_progress := scene.get_node("%RegionClaimProgress") as ProgressBar
	var inspector_progress := scene.get_node("%UnitClaimProgress") as ProgressBar
	var camera := root.get_camera_3d()
	_check(claim.disabled and claim.text == "Claim\n50 Energy", "Claim displays the configured price.")
	_click(camera.unproject_position(scene.get_region(FIRST).global_position))
	_check(claim.disabled and selection.text.contains("Select an available Scout"),
		"A neutral region alone cannot start an expedition.")
	_click(camera.unproject_position(scene._unit_views[first.unit_id].global_position))
	_check(not claim.disabled and scene.selected_unit() == battle.get_unit(first.unit_id),
		"Clicking the Scout opens the assignment control.")
	_click(camera.unproject_position(scene.get_region(FRONTIER).global_position))
	_check(claim.disabled and selection.text.contains("Not adjacent"), "Distant neutral regions remain ineligible.")
	_click(camera.unproject_position(scene.get_region(FIRST).global_position))
	_check(not claim.disabled, "The Scout stays selected when switching neutral targets.")
	_click(claim.get_global_rect().get_center())
	_check(first.state == Expeditions.State.TRAVELING and scene.economy.energy(PLAYER) == 0.0
		and scene.owns_region(NEUTRAL, FIRST) and scene._outposts_by_region.is_empty(),
		"Claim pays once, dispatches on the UI path and keeps the target neutral.")
	_check(not scene.dispatch_scout(PLAYER, second.unit_id, OTHER)
		and not scene.dispatch_scout(CPU, second.unit_id, CPU_FIRST),
		"Insufficient funds and foreign Scouts cannot issue a claim.")
	scene.economy.advance(17.0)
	_check(not scene.dispatch_scout(PLAYER, first.unit_id, OTHER)
		and not battle.issue_move(first.unit_id, Vector2.ZERO),
		"A committed Scout cannot take a second assignment or move order.")
	scene._scout_buttons[1].pressed.emit()
	_click(camera.unproject_position(scene.get_region(OTHER).global_position))
	_click(claim.get_global_rect().get_center())
	_check(second.state == Expeditions.State.TRAVELING and scene._expeditions.assignments.size() == 2
		and scene.economy.energy(PLAYER) == 1.0 and scene.get_node("%ScoutCount").text == "Scouts 0/2 available",
		"A second Scout can take a simultaneous paid claim through the UI.")
	var before := battle.get_unit(second.unit_id).position
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(battle.get_unit(second.unit_id).position != before and second.remaining == scene.claim_duration,
		"Scouts physically travel before their timers count down.")
	_wait_for_arrival(scene, second)
	scene._process(0.0)
	_check(second.state == Expeditions.State.CLAIMING and second.remaining == 20.0
		and scene.region_at_world_position(scene._world_position(battle.get_unit(second.unit_id).position)) == OTHER
		and scene._claim_markers.size() == 2 and inspector_progress.visible and region_progress.visible,
		"Arrival starts the 20-second claim and shows the region and inspector indicators.")
	var build_point: Vector3 = scene.get_region(OTHER).global_position + Vector3(0, 0, 2)
	scene.economy.advance(15.0)
	_check(not scene.try_place_building(PLAYER, &"generator", build_point),
		"Claiming a neutral region does not allow construction there.")
	battle.advance(5.0, scene.economy)
	scene._process(0.0)
	_check(region_progress.value >= 24.0 and region_progress.value <= 26.0
		and inspector_progress.value == region_progress.value and selection.text.contains("15s"),
		"Both inspectors show live progress and remaining time.")
	paused = true
	scene.set_process(true)
	var paused_progress := second.remaining
	await process_frame
	await physics_frame
	_check(second.remaining == paused_progress, "Game pause freezes claim timers.")
	scene.set_process(false)
	paused = false
	battle.advance(15.0 - MatchBattle.STEP, scene.economy)
	_check(scene.owns_region(NEUTRAL, OTHER), "The target remains neutral until the last tick.")
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.owns_region(PLAYER, OTHER) and scene.try_place_building(PLAYER, &"generator", build_point)
		and second.state == Expeditions.State.AVAILABLE, "Completion unlocks construction and frees the Scout.")
	_check(events.has([PLAYER, OTHER, second.unit_id, true, true]), "The event sees the committed owner and outpost.")
	if scene._expeditions.assignments.has(FIRST):
		_check(ScoutFixture.finish_claim(scene, PLAYER, FIRST), "The first expedition also completes.")
	_check(events.count([PLAYER, FIRST, first.unit_id, true, true]) == 1
		and battle._outposts.size() == 2, "Each Scout creates its own outpost and emits one event.")


func _test_contest_and_recall(scene: Node, events: Array[Array]) -> void:
	var player: Expeditions.Scout = scene._expeditions.slots[PLAYER][0]
	var cpu: Expeditions.Scout = scene._expeditions.slots[CPU][0]
	_check(ScoutFixture.claim(scene, CPU, CPU_FIRST)
		and events.count([CPU, CPU_FIRST, cpu.unit_id, true, true]) == 1, "The CPU uses the same completion lifecycle.")
	scene.economy.advance(34.0)
	var cpu_energy: float = scene.economy.energy(CPU)
	_check(scene.dispatch_scout(PLAYER, player.unit_id, FRONTIER)
		and not scene.dispatch_scout(CPU, cpu.unit_id, FRONTIER)
		and scene.economy.energy(CPU) == cpu_energy, "An active claim reserves a shared frontier without charging rivals.")
	scene._battle.advance(0.5, scene.economy)
	var paid_energy: float = scene.economy.energy(PLAYER)
	scene._use_scout_slot(0)
	scene.get_node("%Recall").pressed.emit()
	_check(player.state == Expeditions.State.RETURNING and scene.owns_region(NEUTRAL, FRONTIER)
		and scene.economy.energy(PLAYER) == paid_energy and scene.get_node("%ScoutNotice").text.contains("Energy spent"),
		"Recall returns the same Scout, releases the target and keeps the payment.")
	_check(scene.dispatch_scout(CPU, cpu.unit_id, FRONTIER), "The rival can reserve a recalled target.")
	_check(ScoutFixture.finish_claim(scene, CPU, FRONTIER)
		and player.state == Expeditions.State.AVAILABLE
		and events.count([CPU, FRONTIER, cpu.unit_id, true, true]) == 1,
		"The recalled Scout is reusable and only the rival establishes an outpost.")


func _test_lost_adjacency(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	_check(ScoutFixture.claim(scene, PLAYER, FIRST), "The first outpost anchors a new frontier.")
	scene.economy.advance(17.0)
	_check(ScoutFixture.dispatch(scene, PLAYER, FRONTIER), "A Scout can dispatch from the new frontier.")
	var hub: MatchBattle.Outpost = scene._outposts_by_region.get(FIRST)
	if hub == null:
		return
	hub.hp = 0.0
	scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene._expeditions.assignments.is_empty() and scene._outposts_by_region.is_empty()
		and scene.owns_region(NEUTRAL, FRONTIER) and scene.economy.energy(PLAYER) == 1.0,
		"Losing the outpost that granted adjacency cancels the paid expedition.")


func _test_completion_and_casualty_on_same_step(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var first: Expeditions.Scout = scene._expeditions.slots[PLAYER][0]
	var second: Expeditions.Scout = scene._expeditions.slots[PLAYER][1]
	scene.economy.advance(17.0)
	_check(scene.dispatch_scout(PLAYER, first.unit_id, FIRST), "The first Scout can dispatch.")
	_wait_for_arrival(scene, first)
	battle.advance(scene.claim_duration - MatchBattle.STEP, scene.economy)
	_check(scene.dispatch_scout(PLAYER, second.unit_id, OTHER), "The second Scout can dispatch on the final tick.")
	battle.get_unit(second.unit_id).hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	scene._refresh_hud()
	_check(scene.owns_region(PLAYER, FIRST) and scene.owns_region(NEUTRAL, OTHER)
		and second.state == Expeditions.State.DEAD and scene._claim_markers.is_empty(),
		"A Scout can complete on the same tick the other Scout is killed in transit.")


func _test_collision_and_death(scene: Node, events: Array[Array]) -> void:
	scene.restart_match()
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var scout: Expeditions.Scout = scene._expeditions.slots[PLAYER][0]
	var unit := battle.get_unit(scout.unit_id)
	var wall := battle.navigation.add_obstacle(Rect2(-15, 0, 30, 0.2))
	_check(not scene.dispatch_scout(PLAYER, scout.unit_id, FIRST) and scene.economy.energy(PLAYER) == 50.0,
		"A barrier across the map rejects dispatch without spending Energy.")
	battle.navigation.remove_obstacle(wall)
	var approach_wall := battle.navigation.add_obstacle(Rect2(-15, 0, 14, 0.2))
	_check(scene.dispatch_scout(PLAYER, scout.unit_id, FIRST) and unit.waypoints.size() > 1,
		"A Scout routes around a wall instead of crossing its collision footprint.")
	wall = battle.navigation.add_obstacle(Rect2(-15, 0, 30, 0.2))
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(not scout.assigned() and scene.economy.energy(PLAYER) == 0.0
		and scene.owns_region(NEUTRAL, FIRST), "Losing a route cancels the claim and preserves the charge.")
	battle.navigation.remove_obstacle(wall)
	battle.navigation.remove_obstacle(approach_wall)
	scene.economy.advance(30.0)
	_check(scene.dispatch_scout(PLAYER, scout.unit_id, FIRST), "A cleared route allows a fresh expedition.")
	_wait_for_arrival(scene, scout)
	var old_id := scout.unit_id
	var enemy := battle.spawn_unit(CPU, unit.position + Vector2(0, 0.5))
	_check(enemy != null, "The interruption fixture deploys a hostile infantry unit.")
	if enemy == null:
		return
	var event_count := events.size()
	battle.advance(4.0, scene.economy)
	_check(battle.get_unit(old_id) == null and scout.state == Expeditions.State.DEAD
		and enemy.hp == enemy.definition.hp and scene.owns_region(NEUTRAL, FIRST)
		and scene._outposts_by_region.is_empty() and events.size() == event_count,
		"Enemy combat kills the noncombat Scout and cancels its pending claim.")
	enemy.hp = 0
	_check(not scene._expeditions.replace(PLAYER, 0), "A dead slot cannot skip the replacement cooldown.")
	battle.advance(scene.scout_replacement_delay, scene.economy)
	var energy: float = scene.economy.energy(PLAYER)
	scene._refresh_hud()
	scene._scout_buttons[0].pressed.emit()
	_check(scout.unit_id != old_id and scout.state == Expeditions.State.AVAILABLE
		and scene.economy.energy(PLAYER) == energy - scene.scout_replacement_energy
		and not scene._expeditions.replace(PLAYER, 0) and battle.active_units().size() == 4,
		"Replacement debits the configured cost once and restores the capped roster.")


func _wait_for_arrival(scene: Node, scout: Expeditions.Scout) -> void:
	for step in range(900):
		if scout.state != Expeditions.State.TRAVELING:
			return
		scene._battle.advance(MatchBattle.STEP, scene.economy)


func _roster(scene: Node) -> Array:
	var roster := []
	for unit: MatchBattle.Unit in scene._battle.active_units():
		roster.append([unit.id, unit.side, unit.type_id, unit.position])
	return roster


func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
