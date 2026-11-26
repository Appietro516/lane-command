extends SceneTree

const MATCH := preload("res://main.tscn")
const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.tscn")
const ScoutFixture := preload("res://tests/scout_fixture.gd")
const Expeditions := preload("res://match/scout_expeditions.gd")
const TRIGGER := &"claim_completed"
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const FIRST := &"region_1"
const SECOND := &"region_3"
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS

var failures := 0
var _catalog := load("res://match/narrative/claim_discoveries.tres") as NarrativeCatalog


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_test_catalog()
	_test_scarcity()
	_test_production_claim()
	_test_concurrent_claims()
	_test_failed_claims()
	if failures == 0:
		print("Claim discovery catalog, player and CPU resolution, replay, FIFO and reclaim checks passed.")
	quit(int(failures > 0))


func _test_catalog() -> void:
	_check(_catalog.validation_errors().is_empty() and _catalog.events.size() >= 6,
		"The production catalog has at least six valid discoveries.")
	var titles := {}
	for definition in _catalog.events:
		_check(definition.trigger == TRIGGER and definition.weight > 0
			and definition.eligible_side == NEUTRAL and not titles.has(definition.title),
			"Each discovery has a unique title and is available to both factions.")
		titles[definition.title] = true
		var isolated := NarrativeCatalog.new()
		isolated.events.append(definition)
		for option in definition.options:
			var economy := MatchEconomy.new()
			var events := NarrativeEvents.new(17, economy, isolated)
			var id := &"test-option"
			var stock := _stock(economy, PLAYER)
			_check(events.submit(id, TRIGGER, PLAYER, FIRST) and events.resolve_player(id, option.id)
				and not events.resolve_player(id, option.id)
				and events.instance(id).selected_option == option.id,
				"Each catalog option applies once through the narrative service.")
			_check(_stock(economy, PLAYER) == _expected_stock(stock, option),
				"Each catalog option produces its configured net stock change.")
			_check(not option.effects.is_empty(), "Every choice has a gameplay effect.")
			for index in option.effects.size():
				var effect := option.effects[index]
				_check(option.preview().contains("Spend") if effect.operation == NarrativeEffect.Operation.SPEND
					else option.preview().contains(effect.preview()), "Every effect is disclosed in the preview.")
				match effect.operation:
					NarrativeEffect.Operation.GRANT:
						_check(effect.amount <= 15, "Stock rewards stay below an early construction cost.")
					NarrativeEffect.Operation.SPEND:
						_check(effect.amount <= 5, "Optional investments have modest costs.")
					NarrativeEffect.Operation.MODIFIER:
						_check(effect.duration > 0.0 and effect.duration <= 20.0,
							"Discovery modifiers are short-lived.")
						var source := StringName("narrative/%s/%d" % [id, index])
						var contribution: Dictionary = economy.stats.inspect_source(effect.key, source)
						_check(contribution.total == effect.magnitude and contribution.breakdown.size() == 1
							and contribution.breakdown[0].owner == PLAYER
							and contribution.breakdown[0].region_id == FIRST,
							"Temporary effects affect the deciding faction and record the claim region.")
						events.advance_time(effect.duration - 0.01)
						_check(economy.stats.inspect_source(effect.key, source).total == effect.magnitude,
							"The modifier lasts until its deadline.")
						events.advance_time(effect.duration)
						_check(economy.stats.inspect_source(effect.key, source).breakdown.is_empty(),
							"The modifier expires at its deadline.")

	var selected := {}
	var draws := NarrativeEvents.new(17, MatchEconomy.new(), _catalog)
	for index in 120:
		var id := StringName("test-draw/%d" % index)
		if draws.submit(id, TRIGGER, CPU, FIRST):
			selected[draws.instance(id).event_id] = true
	_check(selected.size() == _catalog.events.size(), "The weighted pool can draw every discovery.")


func _test_scarcity() -> void:
	var catalog := NarrativeCatalog.new()
	catalog.events.append(_definition(&"abandoned_depot"))
	for scarce in [ENERGY, MATERIALS]:
		var economy := MatchEconomy.new()
		var abundant := MATERIALS if scarce == ENERGY else ENERGY
		economy.grant_resource(CPU, abundant, 200)
		var events := NarrativeEvents.new(17, economy, catalog)
		var id := &"cpu-scarcity"
		var stock := economy.stockpile(CPU, scarce)
		_check(events.submit(id, TRIGGER, CPU, FIRST) and events.resolve_cpu(id)
			and economy.stockpile(CPU, scarce) > stock and events.pending_player_id().is_empty(),
			"With identical seed and ID, CPU utility favors the scarcer resource.")


func _test_production_claim() -> void:
	var scene := MATCH.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var events: NarrativeEvents = scene.narrative_events
	var dialogue := scene.get_node("NarrativeOverlay/EventDialogue") as Control
	var region := _frontier(scene, PLAYER)
	var id := _id(PLAYER, region)
	var start: StringName = scene._layout.player_start_ids[0]
	scene._select_region(region)
	_check(not paused and not dialogue.visible and events.instance(id).is_empty()
		and events.instance(_id(PLAYER, start)).is_empty(),
		"Initial ownership and inspecting a neutral region create no discovery.")

	var established: Array[bool] = []
	scene.claim_completed.connect(func(side: MatchRegion.Owner, region_id: StringName, _scout: int) -> void:
		established.append(scene.owns_region(side, region_id)
			and scene._outposts_by_region.has(region_id)))
	if not _check(ScoutFixture.dispatch(scene, PLAYER, region), "The player can dispatch in the main scene."):
		scene.free()
		return
	_check(events.instance(id).is_empty() and not paused, "Dispatch itself does not trigger a discovery.")
	var battle: MatchBattle = scene._battle
	while events.pending_player_id().is_empty() and battle.elapsed_time() < 45.0:
		scene._advance_simulation(0.5)
	if not _check(paused and dialogue.visible and established == [true] and events.pending_player_id() == id,
			"A successful claim establishes ownership and its outpost, then pauses for one choice."):
		scene.free()
		return
	var original := events.instance(id)
	var time := battle.elapsed_time()
	var stock := _stock(scene.economy, PLAYER)
	scene._select_region(region)
	scene._process(5.0)
	_check(battle.elapsed_time() == time and _stock(scene.economy, PLAYER) == stock
		and events.instance(id) == original, "Inspecting again and waiting cannot reroll or advance a paused match.")
	var first_option := _definition(original.event_id).options[0]
	var first_button := dialogue.get_node("%Choices").get_child(0).get_child(0) as Button
	var preview := dialogue.get_node("%Choices").get_child(0).get_child(1) as Label
	_check(first_button.has_focus() and preview.text == first_option.preview(), "The modal shows the real option and focuses it.")
	first_button.pressed.emit()
	first_button.pressed.emit()
	_check(not paused and not dialogue.visible and events.pending_player_id().is_empty()
		and events.instance(id).selected_option == first_option.id
		and _stock(scene.economy, PLAYER) == _expected_stock(stock, first_option),
		"Choosing via the modal applies the effect once and resumes the match.")

	var outpost := scene._outposts_by_region[region] as MatchBattle.Outpost
	outpost.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(scene.owns_region(NEUTRAL, region) and not paused and not dialogue.visible,
		"Losing the outpost does not trigger a discovery.")
	scene.economy.grant_resource(PLAYER, ENERGY, scene.claim_energy)
	var resolved := events.instance(id)
	_check(ScoutFixture.dispatch(scene, PLAYER, region), "The player can dispatch to reclaim the same region.")
	stock = _stock(scene.economy, PLAYER)
	_check(ScoutFixture.finish_claim(scene, PLAYER, region)
		and events.instance(id) == resolved and _stock(scene.economy, PLAYER) == stock and not paused,
		"Reclaiming with the same faction preserves the original decision and applies no second reward.")

	var cpu_region := _frontier(scene, CPU)
	var cpu_id := _id(CPU, cpu_region)
	_check(ScoutFixture.dispatch(scene, CPU, cpu_region), "A CPU scout can dispatch normally.")
	stock = _stock(scene.economy, CPU)
	_check(ScoutFixture.finish_claim(scene, CPU, cpu_region), "The CPU scout completes its claim.")
	var cpu := events.instance(cpu_id)
	if _check(not cpu.is_empty() and cpu.status == NarrativeEvents.Status.RESOLVED
			and not paused and not dialogue.visible, "A CPU discovery resolves without a modal or pause."):
		var options := _definition(cpu.event_id).options
		var chosen := options.filter(func(option: NarrativeOption) -> bool: return option.id == cpu.selected_option)
		_check(chosen.size() == 1 and _stock(scene.economy, CPU) == _expected_stock(stock, chosen[0]),
			"The CPU's valid choice affects CPU state.")

	var landmarks: Array = scene._landmarks.values()
	scene.restart_match()
	scene.set_process(false)
	_check(scene._landmarks.values() == landmarks and scene.narrative_events.instance(id).is_empty()
		and scene.economy.energy(PLAYER) == MatchEconomy.STARTING_ENERGY,
		"Restart clears discovery effects and history while retaining the seeded landmarks.")
	_check(ScoutFixture.claim(scene, PLAYER, region)
		and scene.narrative_events.instance(id) == original, "A same-seed restart reproduces the original draw.")
	scene.free()


func _test_concurrent_claims() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	scene.narrative_catalog = _catalog
	root.add_child(scene)
	scene.set_process(false)
	scene.economy.grant_resource(PLAYER, ENERGY, scene.claim_energy)
	var dispatched := ScoutFixture.dispatch(scene, PLAYER, FIRST) and ScoutFixture.dispatch(scene, PLAYER, SECOND)
	if not _check(dispatched, "Two Scouts can dispatch to different regions."):
		scene.free()
		return
	var first := scene._expeditions.assignments[FIRST] as Expeditions.Scout
	var second := scene._expeditions.assignments[SECOND] as Expeditions.Scout
	var battle: MatchBattle = scene._battle
	while (first.state == Expeditions.State.TRAVELING or second.state == Expeditions.State.TRAVELING) \
			and battle.elapsed_time() < 15.0:
		scene._advance_simulation(MatchBattle.STEP)
	_check(first.state == Expeditions.State.CLAIMING and second.state == Expeditions.State.CLAIMING,
		"Both concurrent scouts reach their independent claim timers.")
	first.remaining = MatchBattle.STEP
	second.remaining = MatchBattle.STEP
	scene._advance_simulation(1.0)
	var events: NarrativeEvents = scene.narrative_events
	# Simultaneous completions are emitted in roster order.
	var roster: Array = scene._expeditions.slots[PLAYER]
	var first_completes_first := roster.find(first) < roster.find(second)
	var first_id := _id(PLAYER, FIRST if first_completes_first else SECOND)
	var second_id := _id(PLAYER, SECOND if first_completes_first else FIRST)
	if _check(paused and events.pending_player_id() == first_id and events.instance(second_id).has("event_id")
			and scene._outposts_by_region.size() == 2, "Both completions finish the same step and enter the FIFO."):
		_choose_free(events)
		_check(paused and events.pending_player_id() == second_id, "The second discovery opens without resuming gameplay.")
		_choose_free(events)
		_check(not paused and events.pending_player_id().is_empty(), "The queue resumes gameplay after the last choice.")
	scene.free()


func _test_failed_claims() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	scene.narrative_catalog = _catalog
	root.add_child(scene)
	scene.set_process(false)
	_check(ScoutFixture.dispatch(scene, PLAYER, FIRST), "The recall test dispatches a real expedition.")
	var first := scene._expeditions.assignments.get(FIRST) as Expeditions.Scout
	if first != null:
		_check(scene._expeditions.recall(PLAYER, first.unit_id), "The first expedition can be recalled.")
	scene.economy.grant_resource(PLAYER, ENERGY, scene.claim_energy)
	_check(ScoutFixture.dispatch(scene, PLAYER, SECOND), "The casualty test dispatches a second expedition.")
	var second := scene._expeditions.assignments.get(SECOND) as Expeditions.Scout
	if second != null:
		scene._battle.get_unit(second.unit_id).hp = 0.0
	scene._advance_simulation(30.0)
	_check(not paused and scene.narrative_events.instance(_id(PLAYER, FIRST)).is_empty()
		and scene.narrative_events.instance(_id(PLAYER, SECOND)).is_empty()
		and scene._outposts_by_region.is_empty() and scene._expeditions.assignments.is_empty(),
		"Recalled and defeated expeditions produce neither outposts nor narrative decisions.")
	scene.free()


func _frontier(scene: Node, side: MatchRegion.Owner) -> StringName:
	for region_id: StringName in scene._regions_by_id:
		if scene._expeditions.eligibility(side, region_id).is_empty():
			return region_id
	return &""


func _id(side: MatchRegion.Owner, region: StringName) -> StringName:
	return StringName("claim/%d/%s" % [side, region])


func _definition(id: StringName) -> NarrativeEvent:
	for definition in _catalog.events:
		if definition.id == id:
			return definition
	return null


func _choose_free(events: NarrativeEvents) -> void:
	var dialogue := events.player_dialogue()
	for option: Dictionary in dialogue.options:
		if option.blocked.is_empty():
			_check(events.resolve_player(dialogue.id, option.id), "An enabled queued option resolves.")
			return
	_check(false, "A queued decision always has an enabled option.")


func _stock(economy: MatchEconomy, side: MatchRegion.Owner) -> Dictionary:
	var stock := {}
	for key in MatchEconomy.RESOURCES:
		stock[key] = economy.stockpile(side, key)
	return stock


func _expected_stock(initial: Dictionary, option: NarrativeOption) -> Dictionary:
	var result := initial.duplicate()
	for effect in option.effects:
		match effect.operation:
			NarrativeEffect.Operation.GRANT:
				result[effect.key] += effect.amount
			NarrativeEffect.Operation.SPEND:
				result[effect.key] -= effect.amount
	return result


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
