extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MATCH := preload("res://tests/provenance_match_fixture.tscn")
const FIXTURE := preload("res://tests/capture_provenance.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const ENERGY := FactionStats.ENERGY

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := MATCH.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	for resource_id in MatchEconomy.RESOURCES:
		var readout := scene.get_node("%%Resources/%s" % resource_id) as Button
		_check(readout.tooltip_text.contains("Passive trickle") and readout.tooltip_text.contains("Total"),
			"Every resource starts with a readable baseline.")
	var state := FIXTURE.prepare(scene)
	if state.is_empty() or state.unit == null:
		_check(false, "The match fixture claimed an Energy landmark and deployed a unit.")
		scene.free()
		quit(1)
		return

	var battle: MatchBattle = scene._battle
	var economy: MatchEconomy = scene.economy
	var unit: MatchBattle.Unit = state.unit
	var region_id: StringName = state.frontier.region_id
	var landmark: LegendaryLandmark = state.landmark
	var energy := scene.get_node("%Resources/energy") as Button
	var income_text := scene.get_node("%IncomeSourceText") as Label
	var sources := scene.get_node("%StatSources") as Button
	var stat_text := scene.get_node("%StatSourceText") as Label
	var barracks: Node3D
	var timer: MatchBattle.ProductionTimer
	for placed in scene._fortifications.values():
		if placed.defense.kind == &"barracks":
			barracks = placed.view
			timer = placed.defense
	var producer: MatchBattle.Fortification
	for placed in scene._fortifications.values():
		if placed.defense.kind == &"generator" and region_id in placed.regions:
			producer = placed.defense
	if producer == null:
		_check(false, "The frontier contains an inspectable producer.")
		scene.free()
		quit(1)
		return

	scene._select_unit(unit.id)
	scene._refresh_hud()
	await process_frame
	await process_frame
	_click(sources.get_global_rect().get_center())
	_check(stat_text.is_visible_in_tree(), "Stat Sources opens the selected unit's breakdown.")
	_click(energy.get_global_rect().get_center())
	_check(income_text.is_visible_in_tree() and not stat_text.is_visible_in_tree(),
		"Clicking a resource gives the income details priority over inspection.")
	var income := economy.income_stat(PLAYER, ENERGY)
	var expected_energy := 2.25 + 2.0 + landmark.magnitude + 2.0 * RegionSpecialty.income_factor(
		state.frontier.specialty, &"generator")
	_check(income.breakdown.size() == 4 and _matches(income, economy.income_rate(PLAYER, ENERGY))
		and income_text.text.count("Generator #") == 2 and income_text.text.contains(landmark.display_name)
		and _matches(income, expected_energy)
		and income_text.text.contains("Total  +%s/s" % scene._stat_number(expected_energy)),
		"The open HUD explains passive trickle, both producers, and the real landmark.")
	_check(_matches(battle.unit_dps_stat(unit), 5.5) and _matches(battle.unit_health_stat(unit), 19.0)
		and unit.hp == 19.0 and stat_text.text.count("Frontier Academy") == 3
		and stat_text.text.count("Veteran Training") == 3
		and stat_text.text.contains("Movement speed\nBase  1.584 units/s\nTotal  1.584 units/s"),
		"The inspector lists both applied DPS and HP sources and the unmodified speed.")

	var start := unit.position
	unit.waypoints = PackedVector2Array([start + Vector2.RIGHT])
	scene.faction_stats.set_modifier(&"drill", PLAYER, FactionStats.UNIT_SPEED, 0.6,
		&"upgrade", "Marching Drills")
	battle._move(unit)
	scene._refresh_hud()
	_check(is_equal_approx(start.distance_to(unit.position), 2.184 * MatchBattle.STEP)
		and stat_text.text.contains("Movement speed\nBase  1.584 units/s\nMarching Drills  +0.6 units/s\nTotal  2.184 units/s")
		and scene.get_node("%UnitStats").text.contains("Speed  2.184 units/s"),
		"Movement and inspection use the same modified speed.")

	var stock := economy.energy(PLAYER)
	economy.advance(2.0)
	_check(is_equal_approx(economy.energy(PLAYER) - stock, 2.0 * income.total)
		and economy.try_spend(PLAYER, {ENERGY: 10})
		and economy.income_stat(PLAYER, ENERGY) == income,
		"Recurring income accrues the inspected rate and one-time spending leaves it intact.")
	economy.set_income_source(PLAYER, ENERGY, &"upkeep", "Grid upkeep", -0.5, &"upkeep")
	scene._refresh_hud()
	_check(income_text.text.contains("Grid upkeep  -0.5/s") and income_text.text.contains("Total  +%s/s" % scene._stat_number(expected_energy - 0.5)),
		"Negative recurring flow appears with its sign in the open panel.")
	economy.set_income_source(PLAYER, ENERGY, &"upkeep", "", 0.0)

	var outpost: MatchBattle.Outpost = scene._outposts_by_region[region_id]
	battle.visibility.set_source(-900001, PLAYER, landmark.footprint.get_center(), BattleVisibility.SCOUT_RADIUS)
	scene._record_sightings(battle.elapsed_time())
	scene._refresh_intelligence()
	outpost.hp = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(not producer.active and unit.hp == 15.0 and _matches(battle.unit_health_stat(unit), 15.0)
		and _matches(battle.unit_dps_stat(unit), 4.5)
		and not stat_text.text.contains("Frontier Academy") and stat_text.text.contains("Veteran Training"),
		"Losing the outpost revokes only its modifier and immediately clamps current unit HP. HP: %s. Stats: %s." % [unit.hp, stat_text.text])
	_check(_matches(economy.income_stat(PLAYER, ENERGY), 4.25)
		and not income_text.text.contains(landmark.display_name)
		and income_text.text.contains("+0/s · %s · Inactive" % str(region_id).capitalize()),
		"The already-open income panel removes the landmark and zeros the inactive producer.")
	scene._select_unit(MatchBattle.NO_TARGET)
	scene._select_fortification(producer.id)
	_check(stat_text.text.contains("Maximum HP\nBase  24\nVeteran Training  +5\nTotal  29")
		and stat_text.text.contains("Energy production") and stat_text.text.contains("Total  +0/s"),
		"The producer inspector explains its health cap and paused output.")
	scene._select_region(region_id)
	scene._refresh_hud()
	_click(energy.get_global_rect().get_center())
	var landmark_text: String = scene.get_node("%LandmarkDetails").text
	_check(landmark_text.contains("Inactive")
		and landmark_text.contains("On claim · +%s/s Energy" % scene._stat_number(landmark.magnitude)),
		"Landmark inspection distinguishes current and potential contributions.")

	_check(ScoutFixture.claim(scene, PLAYER, region_id) and producer.active
		and economy.income_stat(PLAYER, ENERGY) == income
		and _matches(battle.unit_health_stat(unit), 19.0) and unit.hp == 15.0
		and _matches(battle.unit_dps_stat(unit), 5.5),
		"Reclaiming restores each source once and restores the HP cap without healing.")
	var camera := scene.get_node("Camera") as Camera3D
	var roof := barracks.get_node("RoofMarking") as MeshInstance3D
	scene._use_scout_slot(0)
	scene._pick_map(camera.unproject_position(roof.global_position))
	_check(scene.get_node("%UnitName").text == "Player Barracks" and sources.visible
		and stat_text.text.contains("Base  0.235294 units/s"), "Clicking the barracks after a Scout exposes baseline capacity.")
	economy.advance(15.0)
	_check(scene.try_upgrade(PLAYER, timer.id), "The real production upgrade is affordable.")
	var production := timer.production_stat(economy)
	_check(_matches(production, 1.0 / timer.interval(economy))
		and stat_text.text.contains("Production upgrade  +0.072398 units/s")
		and stat_text.text.contains("Total  0.307692 units/s")
		and economy.income_stat(PLAYER, ENERGY) == income,
		"The purchased upgrade explains the new production rate without altering income.")
	if timer != null:
		battle.set_barracks_active(timer, false)
		scene._refresh_hud()
		_check(_matches(timer.production_stat(economy), 0.0)
			and stat_text.text.contains("Total  0 units/s"), "Paused barracks have zero production capacity.")

	scene.restart_match()
	scene.set_process(false)
	_check(not income_text.is_visible_in_tree() and not stat_text.is_visible_in_tree()
		and economy != scene.economy and scene.economy.income_stat(PLAYER, ENERGY).breakdown.size() == 1,
		"Restart dismisses both breakdowns and removes previous match sources.")
	scene.free()
	if failures == 0:
		print("Live income and inspector provenance checks completed.")
	quit(1 if failures else 0)


func _click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	root.push_input(up, true)


func _matches(result: Dictionary, expected: float) -> bool:
	var sum := 0.0
	for entry: Dictionary in result.breakdown:
		sum += entry.magnitude
	return is_equal_approx(result.total, expected) and is_equal_approx(sum, expected)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
