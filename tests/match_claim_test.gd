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
	_test_scout_choice(scene)
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


func _test_scout_choice(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	var expeditions: Expeditions = scene._expeditions
	var scouts := expeditions.available(PLAYER)
	var first := battle.get_unit(scouts[0].unit_id)
	var second := battle.get_unit(scouts[1].unit_id)
	var original := second.position
	second.position = first.position
	var plan := expeditions.preview_claim(PLAYER, FIRST)
	_check(plan != null and plan.unit_id == first.id, "Equal routes prefer the lower stable ID.")
	second.position = scene._map_position(scene.get_region(FIRST).global_position)
	plan = expeditions.preview_claim(PLAYER, FIRST)
	_check(plan != null and plan.unit_id == second.id, "The shorter travel time beats slot order.")
	var barrier := battle.navigation.add_obstacle(Rect2(-15, 0, 30, 0.2))
	plan = expeditions.preview_claim(PLAYER, FIRST)
	_check(plan != null and plan.unit_id == second.id, "An unreachable scout is skipped.")
	second.hp = 0.0
	_check(scene.dispatch_scout(PLAYER, FIRST) == "No reachable outpost site"
		and scene.economy.energy(PLAYER) == 50.0 and expeditions.assignments.is_empty(),
		"A dying scout cannot take a claim even before the battle removes it.")
	second.hp = second.definition.hp
	second.position = original
	battle.navigation.remove_obstacle(barrier)


func _test_concurrent_claims(scene: Node, events: Array[Array]) -> void:
	await process_frame
	await process_frame
	var battle: MatchBattle = scene._battle
	var claim := scene.get_node("%Claim") as Button
	var selection := scene.get_node("%SelectedRegion") as Label
	var region_progress := scene.get_node("%RegionClaimProgress") as ProgressBar
	var inspector_progress := scene.get_node("%UnitClaimProgress") as ProgressBar
	var camera := root.get_camera_3d()
	_check(claim.disabled and claim.text == "Claim\n50 Energy", "Claim displays the configured price.")
	_click(camera.unproject_position(scene.get_region(FRONTIER).global_position))
	_check(claim.disabled and selection.text.contains("Not adjacent"), "Distant neutral regions remain ineligible.")
	_click(camera.unproject_position(scene.get_region(FIRST).global_position))
	_check(not claim.disabled and scene.selected_unit() == null,
		"Selecting an eligible region enables Claim without a selected unit.")
	_click(claim.get_global_rect().get_center())
	var first := scene._expeditions.assignments.get(FIRST) as Expeditions.Scout
	_check(first != null and first.state == Expeditions.State.TRAVELING and scene.economy.energy(PLAYER) == 0.0
		and scene._selected_region_id == FIRST and scene.selected_unit() == null
		and scene.owns_region(NEUTRAL, FIRST) and scene._outposts_by_region.is_empty(),
		"Claim dispatches on one click, consumes the click and keeps the target neutral.")
	if first == null:
		return
	_check(scene.dispatch_scout(PLAYER, OTHER) == "Need more energy"
		and scene._expeditions.available(PLAYER).size() == 1,
		"Insufficient funds leave the free scout unreserved.")
	scene.economy.advance(17.0)
	_check(not battle.issue_move(first.unit_id, Vector2.ZERO),
		"A committed Scout cannot take a move order.")
	var infantry := battle.spawn_unit(PLAYER, Vector2.ZERO)
	_check(infantry != null and battle.order_hold(PLAYER, infantry.id), "The inspection fixture deploys infantry.")
	if infantry == null:
		return
	_click(camera.unproject_position(scene.get_region(OTHER).global_position))
	_click(camera.unproject_position(scene._unit_views[infantry.id].global_position))
	_check(not claim.disabled and scene.selected_unit() == infantry, "Claim remains available while inspecting infantry.")
	_click(claim.get_global_rect().get_center())
	var second := scene._expeditions.assignments.get(OTHER) as Expeditions.Scout
	_check(second != null and second != first and second.state == Expeditions.State.TRAVELING
		and scene._expeditions.assignments.size() == 2 and scene.selected_unit() == infantry
		and scene.economy.energy(PLAYER) == 1.0 and scene.get_node("%ScoutCount").text == "Scouts 0/2 available",
		"A second Scout can take a simultaneous paid claim through the UI.")
	if second == null:
		return
	# Give the fixture a third adjacent target to exercise the unavailable state.
	var frontier: MatchRegion = scene.get_region(FRONTIER)
	frontier.neighbor_ids.append(TerritoryLayout.PLAYER_START)
	_click(camera.unproject_position(frontier.global_position))
	_click(claim.get_global_rect().get_center())
	_check(claim.disabled and selection.text.contains("No scouts available")
		and scene.dispatch_scout(PLAYER, FRONTIER) == "No scouts available"
		and scene._expeditions.assignments.size() == 2 and scene.economy.energy(PLAYER) == 1.0,
		"A third attempt has a clear explanation and does not reserve or charge.")
	frontier.neighbor_ids.erase(TerritoryLayout.PLAYER_START)
	battle.get_unit(infantry.id).hp = 0.0
	scene._select_unit(second.unit_id)
	_click(camera.unproject_position(scene.get_region(OTHER).global_position))
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
	_check(ScoutFixture.dispatch(scene, CPU, CPU_FIRST), "The CPU can dispatch by region.")
	var cpu := scene._expeditions.assignments.get(CPU_FIRST) as Expeditions.Scout
	if cpu == null:
		return
	_check(ScoutFixture.finish_claim(scene, CPU, CPU_FIRST)
		and events.count([CPU, CPU_FIRST, cpu.unit_id, true, true]) == 1, "The CPU uses the same completion lifecycle.")
	scene.economy.advance(34.0)
	var cpu_energy: float = scene.economy.energy(CPU)
	_check(scene.dispatch_scout(PLAYER, FRONTIER).is_empty()
		and scene.dispatch_scout(CPU, FRONTIER) == "Expedition assigned"
		and scene.economy.energy(CPU) == cpu_energy, "An active claim reserves a shared frontier without charging rivals.")
	var player := scene._expeditions.assignments.get(FRONTIER) as Expeditions.Scout
	if player == null:
		return
	scene._battle.advance(0.5, scene.economy)
	var paid_energy: float = scene.economy.energy(PLAYER)
	scene._use_scout_slot(scene._expeditions.slots[PLAYER].find(player))
	scene.get_node("%Recall").pressed.emit()
	_check(player.state == Expeditions.State.RETURNING and scene.owns_region(NEUTRAL, FRONTIER)
		and not scene._expeditions.available(PLAYER).has(player)
		and scene.economy.energy(PLAYER) == paid_energy and scene.get_node("%ScoutNotice").text.contains("Energy spent"),
		"Recall returns the same Scout, releases the target and keeps the payment.")
	_check(scene.dispatch_scout(CPU, FRONTIER).is_empty(), "The rival can reserve a recalled target.")
	cpu = scene._expeditions.assignments.get(FRONTIER) as Expeditions.Scout
	if cpu == null:
		return
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
	scene.economy.advance(17.0)
	_check(scene.dispatch_scout(PLAYER, FIRST).is_empty(), "The first Scout can dispatch.")
	var first := scene._expeditions.assignments.get(FIRST) as Expeditions.Scout
	if first == null:
		return
	_wait_for_arrival(scene, first)
	battle.advance(scene.claim_duration - MatchBattle.STEP, scene.economy)
	_check(scene.dispatch_scout(PLAYER, OTHER).is_empty(), "The second Scout can dispatch on the final tick.")
	var second := scene._expeditions.assignments.get(OTHER) as Expeditions.Scout
	if second == null:
		return
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
	var wall := battle.navigation.add_obstacle(Rect2(-15, 0, 30, 0.2))
	_check(scene.dispatch_scout(PLAYER, FIRST) == "No reachable outpost site"
		and scene.economy.energy(PLAYER) == 50.0 and scene._expeditions.assignments.is_empty(),
		"A barrier across the map rejects dispatch without spending Energy.")
	battle.navigation.remove_obstacle(wall)
	var approach_wall := battle.navigation.add_obstacle(Rect2(-15, 0, 14, 0.2))
	_check(scene.dispatch_scout(PLAYER, FIRST).is_empty(), "A Scout can dispatch around a wall.")
	var scout := scene._expeditions.assignments.get(FIRST) as Expeditions.Scout
	if scout == null:
		return
	_check(battle.get_unit(scout.unit_id).waypoints.size() > 1,
		"A Scout routes around a wall instead of crossing its collision footprint.")
	wall = battle.navigation.add_obstacle(Rect2(-15, 0, 30, 0.2))
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(not scout.assigned() and scene.economy.energy(PLAYER) == 0.0
		and scene.owns_region(NEUTRAL, FIRST), "Losing a route cancels the claim and preserves the charge.")
	battle.navigation.remove_obstacle(wall)
	battle.navigation.remove_obstacle(approach_wall)
	scene.economy.advance(30.0)
	_check(scene.dispatch_scout(PLAYER, FIRST).is_empty(), "A cleared route allows a fresh expedition.")
	scout = scene._expeditions.assignments.get(FIRST) as Expeditions.Scout
	if scout == null:
		return
	var slot: int = scene._expeditions.slots[PLAYER].find(scout)
	var unit := battle.get_unit(scout.unit_id)
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
	_check(not scene._expeditions.replace(PLAYER, slot), "A dead slot cannot skip the replacement cooldown.")
	battle.advance(scene.scout_replacement_delay, scene.economy)
	var energy: float = scene.economy.energy(PLAYER)
	scene._refresh_hud()
	scene._scout_buttons[slot].pressed.emit()
	_check(scout.unit_id != old_id and scout.state == Expeditions.State.AVAILABLE
		and scene.economy.energy(PLAYER) == energy - scene.scout_replacement_energy
		and not scene._expeditions.replace(PLAYER, slot) and battle.active_units().size() == 4,
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
