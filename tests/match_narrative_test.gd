extends SceneTree

const Fixture := preload("res://tests/narrative_fixture.gd")
const MatchFixture := preload("res://tests/prototype_match_fixture.gd")
const ScoutFixture := preload("res://tests/scout_fixture.gd")
const Expeditions := preload("res://match/scout_expeditions.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const TRIGGER := Fixture.TRIGGER
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS
const REGION := &"region_1"

class PauseObserver extends Node:
	var pauses := 0
	var resumes := 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PAUSED:
			pauses += 1
		elif what == NOTIFICATION_UNPAUSED:
			resumes += 1


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_catalog_and_selection()
	_test_effects_and_cpu()
	await _test_modal_and_simulation()
	_test_restart_and_finish()
	if failures == 0:
		print("Narrative catalog, effects, deterministic selection, modal input and match lifecycle verified.")
	quit(int(failures > 0))


func _test_catalog_and_selection() -> void:
	var catalog := Fixture.catalog()
	var primary := catalog.events[0]
	var alternate := primary.duplicate_deep() as NarrativeEvent
	alternate.id = &"survey_bonus"
	alternate.eligible_side = PLAYER
	alternate.eligible_regions = [REGION]
	alternate.required_facts = [&"secured"]
	alternate.minimum_stock = {ENERGY: 50}
	alternate.weight = 17
	catalog.events.append(alternate)
	_check(catalog.validation_errors().is_empty(), "Multiple declarative event definitions validate.")
	var bad := alternate.duplicate_deep() as NarrativeEvent
	bad.options[0].effects[0].key = &"unknown"
	bad.options[1].id = bad.options[0].id
	var invalid := NarrativeCatalog.new()
	invalid.events.assign([bad, bad, null])
	_check(not bad.validation_error().is_empty() and invalid.validation_errors().size() == 4,
		"Invalid references, duplicate events and missing entries are reported.")
	var economy := MatchEconomy.new()
	var first := NarrativeEvents.new(17, economy, catalog)
	catalog.events.reverse()
	var replay := NarrativeEvents.new(17, MatchEconomy.new(), catalog)
	var other_seed := NarrativeEvents.new(71, MatchEconomy.new(), catalog)
	primary.weight = 0
	var selected := {}
	var changed_seed := false
	for index in 40:
		var id := StringName("survey/%d" % index)
		var created := first.submit(id, TRIGGER, PLAYER, REGION, [&"secured"])
		var recreated := replay.submit(id, TRIGGER, PLAYER, REGION, [&"secured"])
		other_seed.submit(id, TRIGGER, PLAYER, REGION, [&"secured"])
		var event_id: StringName = first.instance(id).get("event_id", &"")
		selected[event_id] = true
		changed_seed = changed_seed or event_id != other_seed.instance(id).get("event_id")
		_check(created and recreated and event_id == replay.instance(id).get("event_id"),
			"The same seed and occurrence select the same event across catalog order and restart.")
	_check(selected.has(primary.id) and selected.has(alternate.id) and changed_seed,
		"Weighted selection varies by occurrence and match seed.")
	economy.try_spend(PLAYER, {ENERGY: 1})
	_check(first.submit(&"low-stock", TRIGGER, PLAYER, REGION, [&"secured"])
		and first.instance(&"low-stock").event_id == primary.id,
		"Minimum stock gates eligibility.")
	for context in [[PLAYER, REGION, []], [CPU, REGION, [&"secured"]], [PLAYER, &"elsewhere", [&"secured"]]]:
		var service := NarrativeEvents.new(17, MatchEconomy.new(), catalog)
		_check(not service.submit(&"no-match", TRIGGER, context[0], context[1], Array(context[2], TYPE_STRING_NAME, &"", null)),
			"Fact, side and region requirements exclude incompatible events.")
	_check(not first.submit(&"wrong-trigger", &"timed", PLAYER, REGION)
		and not first.submit(&"survey/0", TRIGGER, CPU, REGION),
		"Trigger mismatches and conflicting occurrence IDs are rejected.")


func _test_effects_and_cpu() -> void:
	var economy := MatchEconomy.new()
	var catalog := Fixture.catalog()
	var events := NarrativeEvents.new(17, economy, catalog)
	var repeated: Array[bool] = []
	var on_stat_changed := func(_stat: StringName) -> void:
		repeated.append(events.resolve_player(&"first", Fixture.INVEST))
	economy.stats.stat_changed.connect(on_stat_changed)
	events.submit(&"first", TRIGGER, PLAYER, REGION)
	events.submit(&"second", TRIGGER, PLAYER, REGION)
	_check(not events.resolve_player(&"second", Fixture.TAKE)
		and not events.resolve_player(&"first", &"unknown"), "Only a known option on the queue head can resolve.")
	_check(events.resolve_player(&"first", Fixture.INVEST) and repeated == [false]
		and is_equal_approx(economy.energy(PLAYER), 10.0),
		"A reentrant notification cannot repeat the choice, and all spend entries are aggregated.")
	economy.stats.stat_changed.disconnect(on_stat_changed)
	var state := events.instance(&"first")
	var source := economy.stats.inspect_source(ENERGY, &"narrative/first/2").breakdown as Array
	_check(state.status == NarrativeEvents.Status.RESOLVED and state.selected_option == Fixture.INVEST
		and state.side == PLAYER and state.origin == TRIGGER and state.region == REGION
		and source.size() == 1 and source[0].owner == PLAYER and source[0].region_id == REGION
		and source[0].source_name == "Field relay" and economy.income_rate(PLAYER, ENERGY) == 5.0,
		"Resolution records the selection and registers a named, owned, region-attributed modifier.")
	_check(events.submit(&"first", TRIGGER, PLAYER, REGION)
		and events.pending_player_id() == &"second"
		and not events.resolve_player(&"first", Fixture.TAKE)
		and not events.resolve_player(&"second", Fixture.INVEST)
		and events.player_dialogue().options[1].blocked == "Need more energy",
		"Duplicate delivery is idempotent and later choices recheck affordability.")
	_check(events.resolve_player(&"second", Fixture.TAKE) and not events.resolve_player(&"second", Fixture.TAKE)
		and economy.stockpile(PLAYER, MATERIALS) == 42.0, "A stock grant applies exactly once.")
	events.advance_time(1.99)
	_check(economy.income_rate(PLAYER, ENERGY) == 5.0, "The modifier survives until its simulation deadline.")
	events.advance_time(2.0)
	_check(economy.income_rate(PLAYER, ENERGY) == 3.0, "The timed modifier expires through FactionStats.")

	var until_end := Fixture.catalog()
	until_end.events[0].options[1].effects[2].duration = 0.0
	var cpu := NarrativeEvents.new(17, economy, until_end)
	var replay := NarrativeEvents.new(17, MatchEconomy.new(), until_end)
	for service in [cpu, replay]:
		service.submit(&"cpu-survey", TRIGGER, CPU)
		_check(service.resolve_cpu(&"cpu-survey") and not service.resolve_cpu(&"cpu-survey"),
			"CPU decisions can resolve exactly once without human input.")
	_check(cpu.instance(&"cpu-survey").selected_option == replay.instance(&"cpu-survey").selected_option
		and cpu.pending_player_id().is_empty(), "The CPU uses a deterministic, independent non-modal policy.")
	cpu.submit(&"cpu-funded", TRIGGER, CPU)
	economy.grant_resource(CPU, ENERGY, 40)
	_check(cpu.resolve_cpu(&"cpu-funded", Fixture.INVEST), "CPU callers may explicitly select a valid option.")
	cpu.advance_time(1000.0)
	_check(economy.stats.inspect_source(ENERGY, &"narrative/cpu-funded/2").total == 2.0,
		"A match-long modifier survives simulation deadlines.")


func _test_modal_and_simulation() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MatchFixture.instantiate()
	scene.narrative_catalog = Fixture.catalog()
	root.add_child(scene)
	scene.set_process(false)
	var observer := PauseObserver.new()
	scene.add_child(observer)
	var battle: MatchBattle = scene._battle
	var events: NarrativeEvents = scene.narrative_events
	_check(ScoutFixture.dispatch(scene, PLAYER, REGION), "A claim can be active before a decision.")
	var expedition := scene._expeditions.assignments.get(REGION) as Expeditions.Scout
	if expedition == null:
		scene.free()
		return
	while expedition.state == Expeditions.State.TRAVELING and battle.elapsed_time() < 15.0:
		scene._advance_simulation(MatchBattle.STEP)
	_check(expedition.state == Expeditions.State.CLAIMING, "The Scout reaches an active claim timer.")
	var timer := battle.add_barracks(PLAYER, Vector2(-6, 0))
	scene.economy.grant_resource(PLAYER, ENERGY, 50)
	var unit := battle.spawn_unit(PLAYER, Vector2(-4, 1))
	var enemy := battle.spawn_unit(CPU, Vector2(-3, 1))
	if unit == null or enemy == null:
		_check(false, "Pause fixture has an expedition and two combat units.")
		scene.free()
		return
	var start_time := battle.elapsed_time()
	scene._advance_simulation(0.5 * MatchBattle.STEP)
	var steps: Array[float] = []
	var on_step := func() -> void:
		steps.append(battle.elapsed_time())
		if steps.size() == 1:
			events.submit(&"modal/one", TRIGGER, PLAYER, REGION)
			events.submit(&"modal/two", TRIGGER, PLAYER, REGION)
	battle.step_finished.connect(on_step)
	scene._time_until_cpu_decision = 0.1
	scene._process(0.6)
	var dialogue := scene.get_node("NarrativeOverlay/EventDialogue") as Control
	var choices := dialogue.get_node("%Choices")
	var first_button := choices.get_child(0).get_child(0) as Button
	_check(paused and observer.pauses == 1 and dialogue.visible and first_button.has_focus()
		and dialogue.get_node("%Title").text == "The Supply Manifest" and choices.get_child_count() == 3,
		"The first queued event opens a focused modal and pauses the tree once.")
	_check(steps.size() == 1 and is_equal_approx(battle.elapsed_time() - start_time, MatchBattle.STEP)
		and is_equal_approx(scene._time_until_cpu_decision, 0.1 - 0.5 * MatchBattle.STEP),
		"The trigger step finishes, preserving fractional timing and dropping the rest of the frame.")
	var frozen := _simulation_state(scene, unit, timer, expedition)
	var build := scene.get_node("%Build") as Button
	scene.set_process(true)
	_mouse(build.get_global_rect().get_center())
	_key(KEY_ESCAPE)
	await process_frame
	await physics_frame
	await process_frame
	_check(paused and dialogue.visible and events.pending_player_id() == &"modal/one"
		and not scene.get_node("%BuildMenu").visible and scene._placement_id.is_empty(),
		"Escape and clicks over the gameplay HUD cannot dismiss the event or start placement.")
	_check(frozen == _simulation_state(scene, unit, timer, expedition) and steps.size() == 1,
		"Movement, combat, production, claims, economy, CPU cadence and step scheduling remain frozen.")
	scene.set_process(false)

	_key(KEY_TAB)
	var second_button := choices.get_child(1).get_child(0) as Button
	_check(second_button.has_focus(), "Tab moves focus between enabled choices.")
	_key(KEY_ENTER)
	_check(paused and observer.pauses == 1 and observer.resumes == 0
		and events.pending_player_id() == &"modal/two",
		"A keyboard choice opens the next queued event without resuming or pausing again.")
	var initial_materials: float = scene.economy.stockpile(PLAYER, MATERIALS)
	root.size = Vector2i(960, 600)
	await process_frame
	await process_frame
	first_button = choices.get_child(0).get_child(0) as Button
	var panel := dialogue.get_node("Panel") as Control
	_check(dialogue.get_global_rect().encloses(panel.get_global_rect())
		and panel.get_global_rect().encloses(first_button.get_global_rect()),
		"The resized viewport still contains the modal and its controls.")
	_mouse(first_button.get_global_rect().get_center())
	_check(not paused and not dialogue.visible and observer.resumes == 1
		and scene.economy.stockpile(PLAYER, MATERIALS) == initial_materials + 12.0,
		"A mouse choice applies its grant and releases the pause once.")
	var before := battle.elapsed_time()
	var claim_before := expedition.remaining
	scene._process(MatchBattle.STEP)
	_check(is_equal_approx(battle.elapsed_time() - before, MatchBattle.STEP)
		and is_equal_approx(scene._time_until_cpu_decision, 0.1 - 1.5 * MatchBattle.STEP)
		and is_equal_approx(claim_before - expedition.remaining, MatchBattle.STEP)
		and steps.size() == 2, "Resuming advances only new delta without a catch-up burst.")
	battle.step_finished.disconnect(on_step)
	scene.free()


func _test_restart_and_finish() -> void:
	var scene := preload("res://main.tscn").instantiate()
	scene.narrative_catalog = Fixture.catalog()
	root.add_child(scene)
	scene.set_process(false)
	var dialogue := scene.get_node("NarrativeOverlay/EventDialogue") as Control
	var landmarks: Array = scene._landmarks.values()
	var old: NarrativeEvents = scene.narrative_events
	old.submit(&"cpu-only", TRIGGER, CPU)
	_check(old.resolve_cpu(&"cpu-only") and not paused and not dialogue.visible,
		"A CPU-only event never opens or pauses the human match.")
	old.submit(&"replay", TRIGGER, PLAYER)
	var original := old.instance(&"replay")
	old.submit(&"discard", TRIGGER, PLAYER)
	scene.restart_match()
	scene.set_process(false)
	_check(not paused and not dialogue.visible and old.instance(&"discard").is_empty()
		and not old.resolve_player(&"replay", Fixture.TAKE) and scene._landmarks.values() == landmarks,
		"Restart clears old decisions, releases the modal, and leaves seeded landmarks intact.")
	var current: NarrativeEvents = scene.narrative_events
	current.submit(&"replay", TRIGGER, PLAYER)
	_check(current.instance(&"replay") == original, "Identical match settings and ID reproduce the pending event.")
	var battle: MatchBattle = scene._battle
	battle._base_health[CPU].hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(battle.is_finished() and not paused and not dialogue.visible
		and current.instance(&"replay").is_empty() and not current.submit(&"late", TRIGGER, PLAYER),
		"Match end dismisses an open event and closes the queue.")

	scene.restart_match()
	paused = true
	var energy: float = scene.economy.energy(PLAYER)
	scene.narrative_events.submit(&"external-pause", TRIGGER, PLAYER)
	scene.narrative_events.resolve_player(&"external-pause", Fixture.LEAVE)
	_check(paused and not dialogue.visible and scene.economy.energy(PLAYER) == energy,
		"A no-op decision preserves the economy and a pause which the match did not acquire.")
	paused = false
	scene.narrative_events.submit(&"exit", TRIGGER, PLAYER)
	scene.free()
	_check(not paused, "Removing the match releases its narrative pause.")


func _simulation_state(scene: Node, unit: MatchBattle.Unit, timer: MatchBattle.ProductionTimer,
		expedition: Expeditions.Scout) -> Array:
	return [scene._battle.elapsed_time(), unit.position, unit.hp, unit.cooldown, timer.elapsed,
		expedition.remaining, scene.economy.energy(PLAYER), scene.economy.energy(CPU),
		scene._time_until_cpu_decision]


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _mouse(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
