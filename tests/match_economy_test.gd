extends SceneTree

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const ENERGY := MatchEconomy.ENERGY
const MATERIALS := MatchEconomy.MATERIALS
const FOOD := MatchEconomy.FOOD

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rules(PLAYER, CPU)
	_test_rules(CPU, PLAYER)
	_test_atomic_purchases(PLAYER, CPU)
	_test_atomic_purchases(CPU, PLAYER)
	_test_income_sources()
	await _test_match_controls()
	await _test_claimed_placement()
	await _test_producers()
	_test_food_starvation()
	_test_cpu_purchases()
	_test_symmetric_production()
	_test_expanded_production()
	if failures == 0:
		print("Match economy, controls, CPU purchases and symmetric production passed.")
	quit(1 if failures > 0 else 0)


func _test_rules(side: MatchRegion.Owner, other_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	_check_state(economy, side, [50.0, 0, 3.5], "Initial state")
	economy.advance(-20.0)
	_check_state(economy, side, [50.0, 0, 3.5], "Negative elapsed time")
	economy.advance(0.5)
	_check_state(economy, side, [51.5, 0, 3.5], "Fractional income")
	economy.advance(0.5)
	_check_state(economy, side, [53.0, 0, 3.5], "Income after one second")

	_check(not economy.try_upgrade(side), "Reject an unaffordable upgrade.")
	_check_state(economy, side, [53.0, 0, 3.5], "Unaffordable upgrade")
	_check(economy.try_build(side, MatchEconomy.BARRACKS_COST), "Accept the first barracks.")
	_check_state(economy, side, [13.0, 1, 3.5], "First barracks")
	_check(not economy.try_build(side, MatchEconomy.BARRACKS_COST), "Reject an unaffordable barracks.")
	_check_state(economy, side, [13.0, 1, 3.5], "Unaffordable barracks")
	_check_state(economy, other_side, [53.0, 0, 3.5], "Other side after first barracks")

	economy.advance(9.0)
	_check(economy.try_build(side, MatchEconomy.BARRACKS_COST), "Accept a barracks at the exact price.")
	_check_state(economy, side, [0.0, 2, 3.5], "Second barracks at the exact price")
	economy.advance(20.0)
	_check(economy.try_build(side, MatchEconomy.BARRACKS_COST)
		and economy.stockpile(side, MATERIALS) == 30.0, "A third barracks costs the normal price.")
	_check_state(economy, side, [20.0, 3, 3.5], "Third barracks")
	economy.advance(40.0 / 3.0)
	_check(economy.try_upgrade(side), "Accept an upgrade at the exact price.")
	_check_state(economy, side, [0.0, 3, 2.5], "Production upgrade at the exact price")
	economy.advance(20.0)
	_check(not economy.try_upgrade(side), "Reject a repeat upgrade with sufficient energy.")
	_check_state(economy, side, [60.0, 3, 2.5], "Repeat upgrade")
	_check_state(economy, other_side, [240.0, 0, 3.5], "Other side after all purchases")


func _test_atomic_purchases(side: MatchRegion.Owner, other_side: MatchRegion.Owner) -> void:
	var economy := MatchEconomy.new()
	_check(economy.cost_block_reason(side, {ENERGY: 40, MATERIALS: 31}) == "Need more materials"
		and not economy.try_build(side, {ENERGY: 40, MATERIALS: 31}),
		"Enough Energy alone cannot buy a building when Materials are short.")
	_check(not economy.try_spend(side, {ENERGY: 1, &"missing": 1})
		and not economy.try_spend(side, {ENERGY: 1, FOOD: -1}),
		"Unknown resources and negative costs reject the whole purchase.")
	_check(economy.stockpile(side, ENERGY) == 50.0 and economy.stockpile(side, MATERIALS) == 30.0
		and economy.stockpile(side, FOOD) == 20.0 and economy.barracks_count(side) == 0,
		"A rejected purchase never debits a stockpile or changes barracks count.")
	_check(economy.try_spend(side, {ENERGY: 50, MATERIALS: 30, FOOD: 20})
		and economy.stockpile(side, ENERGY) == 0.0 and economy.stockpile(side, MATERIALS) == 0.0
		and economy.stockpile(side, FOOD) == 0.0,
		"A purchase can debit every resource at exact affordability.")
	_check(economy.stockpile(other_side, ENERGY) == 50.0
		and economy.stockpile(other_side, MATERIALS) == 30.0
		and economy.stockpile(other_side, FOOD) == 20.0,
		"A purchase changes only the paying side's stockpiles.")
	economy.advance(0.5)
	_check(economy.stockpile(side, ENERGY) == 1.5 and economy.stockpile(side, MATERIALS) == 1.0
		and economy.stockpile(side, FOOD) == 0.5, "Purchases leave baseline income rates intact.")
	economy.advance(20.0)
	_check(economy.try_spend(side, {FOOD: 6}) and not economy.try_upgrade(side)
		and economy.energy(side) == 61.5 and economy.stockpile(side, FOOD) == 14.5
		and not economy.has_upgrade(side), "A Food shortage prevents a production upgrade.")
	economy.advance(0.5)
	_check(economy.try_upgrade(side) and economy.energy(side) == 3.0
		and economy.stockpile(side, FOOD) == 0.0 and economy.has_upgrade(side),
		"An upgrade spends Energy and Food together.")


func _test_income_sources() -> void:
	var economy := MatchEconomy.new()
	economy.set_income_source(PLAYER, ENERGY, &"generator_2", "Generator #2", 2.0)
	economy.set_income_source(PLAYER, ENERGY, &"landmark", "Landmark", 1.0)
	economy.set_income_source(PLAYER, MATERIALS, &"landmark", "Landmark", 0.5)
	var sources := economy.income_sources(PLAYER, ENERGY)
	_check(sources.keys() == [MatchEconomy.BASE_INCOME, &"generator_2", &"landmark"]
		and sources[MatchEconomy.BASE_INCOME].rate == 3.0
		and sources[&"generator_2"].label == "Generator #2", "Income records preserve source IDs.")
	sources[MatchEconomy.BASE_INCOME].rate = 0.0
	economy.advance(2.0)
	_check(economy.income_rate(PLAYER, ENERGY) == 6.0 and economy.energy(PLAYER) == 62.0
		and economy.stockpile(PLAYER, MATERIALS) == 35.0 and economy.energy(CPU) == 56.0,
		"Simulation uses attributed rates, independently for each side and resource.")
	economy.set_income_source(PLAYER, ENERGY, &"generator_2", "Generator #2", 0.5)
	economy.set_income_source(PLAYER, ENERGY, &"landmark", "", 0.0)
	_check(economy.income_rate(PLAYER, ENERGY) == 3.5
		and not economy.income_sources(PLAYER, ENERGY).has(&"landmark"),
		"Sources can be replaced or removed by ID.")


func _test_match_controls() -> void:
	root.size = Vector2i(1280, 800)
	var match_scene := MATCH_FIXTURE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	# Let the nested containers finish layout before sending viewport clicks.
	await process_frame
	await process_frame

	var build: Button = match_scene.get_node("%Build")
	var upgrade: Button = match_scene.get_node("%Upgrade")
	var energy_label: Label = match_scene.get_node("%Resources/energy/Stockpile")
	var income_label := match_scene.get_node("%Resources/energy/Rate") as Label
	var materials_label := match_scene.get_node("%Resources/materials/Stockpile") as Label
	var food_label := match_scene.get_node("%Resources/food/Stockpile") as Label
	var barracks_label: Label = match_scene.get_node("%BarracksCount")
	var player_buildings := match_scene.get_node("Buildings/Player")
	var cpu_buildings := match_scene.get_node("Buildings/CPU")
	var placement_panel := match_scene.get_node("%PlacementPanel") as PanelContainer
	var cancel := match_scene.get_node("%CancelPlacement") as Button
	var status := match_scene.get_node("%PlacementStatus") as Label

	_check(energy_label.text == "Energy 50" and income_label.text == "+3/s"
		and materials_label.text == "Materials 30" and food_label.text == "Food 20"
		and match_scene.get_node("%Resources/materials/Rate").text == "+2/s"
		and match_scene.get_node("%Resources/food/Rate").text == "+1/s"
		and barracks_label.text == "Barracks 0", "The HUD renders initial economy values. Rates were %s, %s, %s." % [
			income_label.text, match_scene.get_node("%Resources/materials/Rate").text,
			match_scene.get_node("%Resources/food/Rate").text,
		])
	_check(not build.disabled and upgrade.disabled, "Only Build is affordable at startup.")
	var food_readout := food_label.get_parent() as Control
	match_scene.economy.set_income_source(PLAYER, FOOD, &"bonus", "Supply bonus", 0.5)
	match_scene._process(0.0)
	_check(food_readout.tooltip_text == "Food income\nPassive trickle  +1/s\nSupply bonus  +0.5/s\nTotal  +1.5/s"
		and food_readout.get_node("Rate").text == "+1.5/s",
		"Unexpected HUD source text: %s" % food_readout.tooltip_text)
	match_scene.economy.set_income_source(PLAYER, FOOD, &"bonus", "", 0.0)

	await _choose_barracks(build)
	_check(placement_panel.visible and player_buildings.get_child_count() == 0
		and energy_label.text == "Energy 50", "Choosing a menu item enters placement without buying.")
	await _click_world(Vector3(-3.4, 0.0, -3.2))
	_check(status.text.contains("your territory") and placement_panel.visible,
		"A neutral click shows an ownership message and keeps placement active.")
	await _click_world(Vector3(10.0, 0.0, -1.25))
	await _click_at(Vector2(20, 140))
	_check(player_buildings.get_child_count() == 0 and energy_label.text == "Energy 50",
		"Neutral, enemy and off-map clicks spend no energy and create no building.")
	_click(cancel)
	_check(not placement_panel.visible, "Cancel exits placement.")
	await _click_world(Vector3(-9.65, 0.0, -1.37))
	_check(player_buildings.get_child_count() == 0 and energy_label.text == "Energy 50",
		"A world click after cancel only selects the region.")

	await _choose_barracks(build)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_check(not placement_panel.visible, "Escape exits placement.")

	await _choose_barracks(build)
	_send_click(root.get_camera_3d().unproject_position(Vector3(-9.65, 0.0, -1.37)),
		MOUSE_BUTTON_RIGHT)
	_check(not placement_panel.visible, "Right-click exits placement.")

	await _choose_barracks(build)
	var first_position := Vector3(-9.65, 0.0, -1.37)
	await _click_world(first_position)
	_check_state(match_scene.economy, PLAYER, [10.0, 1, 3.5], "First placed barracks")
	_check(player_buildings.get_child_count() == 1
		and _building_at(player_buildings, first_position),
		"The barracks appears at the unsnapped cursor position.")
	_check(energy_label.text == "Energy 10" and barracks_label.text == "Barracks 1"
		and materials_label.text == "Materials 10" and income_label.text == "+3/s"
		and not build.disabled and match_scene._build_options[&"barracks"].disabled
		and upgrade.disabled and not placement_panel.visible,
		"Placement updates the HUD immediately and exits placement mode.")

	match_scene._process(17.0)
	_check(energy_label.text == "Energy 61" and materials_label.text == "Materials 44"
		and food_label.text == "Food 21" and not upgrade.disabled,
		"Income and unit costs refresh the HUD and enable Upgrade.")
	_click(upgrade)
	_check_state(match_scene.economy, PLAYER, [1.0, 1, 2.5], "Upgrade button")
	_check(energy_label.text == "Energy 1" and food_label.text == "Food 6"
		and upgrade.disabled and upgrade.text == "Upgraded",
		"Upgrade updates the HUD immediately.")

	_check(cpu_buildings.get_child_count() == 3 and match_scene.economy.barracks_count(CPU) == 2,
		"The CPU places both barracks and a Farm autonomously.")
	match_scene._process(13.0)
	await _choose_barracks(build)
	var second_position := Vector3(-12.73, 0.0, 0.41)
	await _click_world(second_position)
	_check_state(match_scene.economy, PLAYER, [0.0, 2, 2.5], "Second placed barracks")
	_check(_building_at(player_buildings, second_position)
		and barracks_label.text == "Barracks 2" and not build.disabled
		and match_scene._build_options[&"barracks"].disabled and upgrade.disabled,
		"The second freeform placement works and the menu still checks affordability.")

	match_scene.economy.advance(14.0)
	match_scene._process(0.0)
	_check(not match_scene._build_options[&"barracks"].disabled,
		"An affordable third barracks is enabled in the Build menu.")
	await _choose_barracks(build)
	var stock := _stockpiles(match_scene.economy, PLAYER)
	await _click_world(Vector3(10.0, 0.0, -1.25))
	_check(_stockpiles(match_scene.economy, PLAYER) == stock and placement_panel.visible,
		"An invalid third placement preserves all resources and keeps placement active.")
	await _click_world(Vector3(-12.0, 0.0, -3.0))
	_check(barracks_label.text == "Barracks 3" and player_buildings.get_child_count() == 3
		and energy_label.text == "Energy 2" and not placement_panel.visible,
		"The Build menu places the third barracks and charges the normal price.")
	stock = _stockpiles(match_scene.economy, PLAYER)
	_check(not match_scene.try_place_building(PLAYER, &"barracks", Vector3(-12.0, 0.0, 4.0))
		and _stockpiles(match_scene.economy, PLAYER) == stock,
		"An unaffordable fourth placement leaves all stockpiles intact.")

	match_scene.free()


func _test_claimed_placement() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame
	var region: MatchRegion = scene.get_region(&"region_1")
	var start: MatchRegion = scene.get_region(TerritoryLayout.PLAYER_START)
	# This point is on the claimed side of the bisector, inside the visual gap.
	var claimed_position := start.global_position.lerp(region.global_position, 0.505)
	await _click_world(claimed_position)
	_click(scene.get_node("%Claim"))
	_check(scene.owns_region(PLAYER, region.region_id), "Claim transfers the clicked region.")
	scene.economy.advance(27.0)
	scene._process(0.0)
	var build := scene.get_node("%Build") as Button
	var player_buildings := scene.get_node("Buildings/Player")
	await _choose_barracks(build)
	await _click_world(claimed_position)
	_check_state(scene.economy, PLAYER, [41.0, 1, 3.5], "Building in a newly claimed region")
	_check(_building_at(player_buildings, claimed_position),
		"Claimed territory accepts building placement at the clicked point.")
	await _choose_barracks(build)
	await _click_world(claimed_position)
	_check_state(scene.economy, PLAYER, [1.0, 2, 3.5], "Overlapping placement")
	_check(player_buildings.get_child_count() == 2
		and (player_buildings.get_child(1) as Node3D).position.distance_to(claimed_position) < 0.001,
		"An existing building at the point does not block placement.")
	scene.restart_match()
	scene.set_process(false)
	await _choose_barracks(build)
	_click(scene.get_node("%Restart"))
	scene.set_process(false)
	_check(not scene.get_node("%PlacementPanel").visible and player_buildings.get_child_count() == 0,
		"Restart cancels active placement and clears constructed buildings.")
	scene.free()


func _test_producers() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame
	var economy: MatchEconomy = scene.economy
	var battle: MatchBattle = scene._battle
	var home := TerritoryLayout.PLAYER_START
	var expansion := &"region_1"
	var enemy: MatchRegion = scene.get_region(TerritoryLayout.CPU_START)
	var stock := _stockpiles(economy, PLAYER)
	_check(not scene.try_place_building(PLAYER, &"mine", enemy.global_position)
		and _stockpiles(economy, PLAYER) == stock, "Enemy territory rejects a producer without spending.")
	_check(scene.try_claim(PLAYER, expansion), "Claim adjacent territory for producer placement.")
	var mine_site := _clear_producer_point(scene, expansion, &"mine")
	stock = _stockpiles(economy, PLAYER)
	_check(not scene.try_place_building(PLAYER, &"mine", mine_site)
		and _stockpiles(economy, PLAYER) == stock,
		"Missing Energy rejects a multi-resource producer without spending Materials.")
	economy.advance(60.0)
	scene._refresh_hud()

	var cases := [[&"generator", ENERGY, 2.0, "Generator · 26 Materials\n+2/s Energy"],
		[&"mine", MATERIALS, 2.0, "Mine · 24 Materials + 15 Energy\n+2/s Materials"],
		[&"farm", FOOD, 3.0, "Farm · 20 Materials\n+3/s Food"]]
	for item in cases:
		var kind: StringName = item[0]
		var resource_id: StringName = item[1]
		var rate: float = item[2]
		stock = _stockpiles(economy, PLAYER)
		var site := _clear_producer_point(scene, expansion, kind)
		_click(scene.get_node("%Build"))
		await process_frame
		await process_frame
		var button: Button = scene._build_options[kind]
		_check(button.text == item[3] and not button.disabled, "%s shows its price and effect." % kind)
		_click(button)
		await process_frame
		await _click_world(site)
		var cost: Dictionary = scene.BUILDINGS[kind].cost
		for checked_resource: StringName in MatchEconomy.RESOURCES:
			_check(economy.stockpile(PLAYER, checked_resource) == stock[checked_resource] -
				cost.get(checked_resource, 0), "%s charges its configured cost exactly once." % kind)
		var income := economy.income_stat(PLAYER, resource_id)
		_check(income.breakdown.size() == 2 and income.total == income.breakdown[0].magnitude + rate,
			"%s adds the configured income." % kind)
		if income.breakdown.size() != 2:
			continue
		var source: Dictionary = income.breakdown[1]
		var structure := battle.get_fortification(source.building_id)
		_check(source.region_id == expansion and source.owner == PLAYER
			and source.magnitude == rate and source.source_id == structure.source_id,
			"%s retains building, region and owner attribution." % kind)

		_check(scene.try_place_building(PLAYER, kind, _clear_producer_point(scene, home, kind)),
			"A second %s can be placed in starting territory." % kind)
		var sources := economy.income_sources(PLAYER, resource_id)
		_check(sources.size() == 3 and sources[source.source_id].region_id == expansion
			and economy.income_rate(PLAYER, resource_id) == income.total + rate,
			"Two %s buildings stack as separate sources." % kind)
		var readout: Control = scene.get_node("%%Resources/%s" % resource_id)
		_check(readout.get_node("Rate").text == "+%d/s" % (income.total + rate)
			and readout.tooltip_text.contains(source.source_name + "  +%d/s" % rate),
			"The HUD shows the same %s total and source." % resource_id)

	var food_before := economy.stockpile(PLAYER, FOOD)
	economy.advance(2.0)
	_check(economy.stockpile(PLAYER, FOOD) == food_before + 14.0, "Stacked farms accrue Food over time.")
	var farm_sources := economy.income_sources(PLAYER, FOOD)
	var expansion_farm: StringName
	for source_id in farm_sources:
		if farm_sources[source_id].get("region_id") == expansion:
			expansion_farm = source_id
	var outpost: MatchBattle.Outpost = scene._outposts_by_region[expansion]
	outpost.hp = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(economy.income_rate(PLAYER, FOOD) == 4.0
		and not economy.income_sources(PLAYER, FOOD).has(expansion_farm)
		and not economy.income_stat(PLAYER, FOOD).breakdown.filter(
			func(entry: Dictionary) -> bool: return entry.source_id == expansion_farm)[0].active,
		"Losing the outpost immediately disables the local source.")
	_check(scene.try_claim(PLAYER, expansion), "The original owner can reclaim the region.")
	scene._set_region_owner(expansion, PLAYER)
	_check(economy.income_rate(PLAYER, FOOD) == 7.0
		and economy.income_sources(PLAYER, FOOD).size() == 3,
		"Reactivation restores each original contribution once.")
	var farm := battle.get_fortification(farm_sources[expansion_farm].building_id)
	farm.hp = 0.0
	battle.advance(MatchBattle.STEP, economy)
	_check(economy.income_rate(PLAYER, FOOD) == 4.0 and economy.income_stat(PLAYER, FOOD).breakdown.size() == 2,
		"Destroying a Farm removes its registry entry entirely.")
	scene.restart_match()
	scene.set_process(false)
	_check(scene.economy.income_rate(PLAYER, FOOD) == 1.0
		and scene.get_node("Buildings/Player").get_child_count() == 0,
		"Restart clears producer sources and their views.")
	scene.free()


func _clear_producer_point(scene: Node, region_id: StringName, kind: StringName) -> Vector3:
	var region: MatchRegion = scene.get_region(region_id)
	var point := region.interior_point(func(candidate: Vector2) -> bool:
		var reason: String = scene._placement_block_reason(PLAYER, kind, scene._world_position(candidate))
		return reason.is_empty() or reason.begins_with("Need more"))
	return scene._world_position(point)


func _stockpiles(economy: MatchEconomy, side: MatchRegion.Owner) -> Dictionary:
	var stock := {}
	for resource_id in MatchEconomy.RESOURCES:
		stock[resource_id] = economy.stockpile(side, resource_id)
	return stock


func _test_food_starvation() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(Vector2(-10, 0), Vector2(10, 0))
	var barracks := battle.add_barracks(PLAYER, Vector2(-8, 0))
	economy.try_spend(PLAYER, {FOOD: 20})
	battle.advance(3.75, economy, true)
	_check(battle.active_units().is_empty() and is_equal_approx(barracks.elapsed, 3.5)
		and is_equal_approx(economy.stockpile(PLAYER, FOOD), 3.75),
		"An unaffordable unit waits at a ready timer without debiting Food.")
	battle.advance(0.25, economy, true)
	_check(battle.active_units().size() == 1 and barracks.elapsed < MatchBattle.STEP
		and economy.stockpile(PLAYER, FOOD) == 0.0,
		"The ready barracks spends Food once when affordable without banking additional spawns.")


func _choose_barracks(build: Button) -> void:
	_click(build)
	var scene := build.owner
	var list := scene.get_node("%BuildList") as VBoxContainer
	var option := list.get_child(0) as Button
	await process_frame
	await process_frame
	_check(list.is_visible_in_tree() and list.get_child_count() == scene.BUILDINGS.size()
		and option.text == "Barracks · 40 Energy + 20 Materials\nAuto-spawn · 4 Food per unit",
		"Build opens the catalog menu with the configured price.")
	_click(option)
	await process_frame


func _building_at(buildings: Node, point: Vector3) -> bool:
	for child: Node3D in buildings.get_children():
		if child.global_position.distance_to(point) < 0.001:
			return true
	return false


func _click_world(point: Vector3) -> void:
	await _click_at(root.get_camera_3d().unproject_position(point))


func _click_at(position: Vector2) -> void:
	_send_click(position)
	await physics_frame
	await physics_frame


func _test_cpu_purchases() -> void:
	var match_scene := MATCH_FIXTURE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var cpu_buildings := match_scene.get_node("Buildings/CPU")

	match_scene._process(1.75)
	_check_state(match_scene.economy, CPU, [55.25, 0, 3.5], "Before the first CPU decision")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [16.0, 1, 3.5], "First CPU purchase at 2 seconds")
	_check(cpu_buildings.get_child_count() == 1
		and match_scene.owns_region(CPU, match_scene.region_at_world_position(
			cpu_buildings.get_child(0).global_position)),
		"The first CPU barracks appears inside CPU territory.")
	_check(match_scene.economy.stockpile(CPU, MATERIALS) == 14.0
		and match_scene.economy.stockpile(PLAYER, MATERIALS) == 34.0,
		"The CPU spends Materials from its own stockpile.")

	match_scene._process(7.75)
	_check_state(match_scene.economy, CPU, [39.25, 1, 3.5], "Before the CPU can afford its second barracks")
	_check(match_scene.get_node("Units").get_child_count() == 2,
		"The first CPU barracks spawns at 5.5 and 9 seconds without player input.")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 3.5], "Second CPU purchase at 10 seconds")
	_check(cpu_buildings.get_child_count() == 2
		and match_scene.owns_region(CPU, match_scene.region_at_world_position(
			cpu_buildings.get_child(1).global_position)),
		"The second CPU barracks also appears inside CPU territory.")
	_check_state(match_scene.economy, PLAYER, [80.0, 0, 3.5], "Idle player")
	match_scene.free()

	# Keep both bases defended while checking the CPU's later economy decisions.
	match_scene = MATCH_FIXTURE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	match_scene._process(2.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)), "Build the player's first defending barracks.")
	match_scene._process(8.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -3.65)), "Build the player's second defending barracks.")
	match_scene._process(6.0)
	_check(match_scene.try_place_building(PLAYER, &"farm",
		_clear_producer_point(match_scene, TerritoryLayout.PLAYER_START, &"farm")),
		"The player can fund sustained production on the same schedule as the CPU.")
	match_scene._process(13.75)
	_check_state(match_scene.economy, CPU, [59.25, 2, 3.5], "Before the CPU can afford its upgrade")
	match_scene._process(0.25)
	_check_state(match_scene.economy, CPU, [0.0, 2, 2.5], "CPU upgrade at 30 seconds")
	_check(match_scene.economy.stockpile(CPU, FOOD) == 21.0
		and match_scene.economy.stockpile(PLAYER, FOOD) == 40.0,
		"The CPU's units and upgrade spend Food from its own stockpile.")
	_check(match_scene.try_upgrade(PLAYER), "Keep both sides on the upgraded production rate.")
	var cpu_deployments: Array[int] = []
	match_scene._battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		if unit.side == CPU:
			cpu_deployments.append(unit.id))
	match_scene._process(22.0)
	for resource_id in MatchEconomy.RESOURCES:
		_check(match_scene.economy.income_rate(CPU, resource_id) > MatchEconomy.RESOURCES[resource_id].baseline,
			"The CPU builds a producer for %s." % resource_id)
	_check(cpu_deployments.size() == 16,
		"The CPU continues to fund both barracks at the upgraded rate.")
	match_scene.free()


func _test_symmetric_production() -> void:
	var match_scene := MATCH_FIXTURE.instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	var units := match_scene.get_node("Units")
	var produced: Array[MatchBattle.Unit] = []
	match_scene._battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		produced.append(unit))

	match_scene._process(2.0)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -1.2)), "The player can buy at the same time as the CPU.")
	match_scene._process(3.25)
	_check(units.get_child_count() == 0, "Neither barracks spawns early.")
	match_scene._process(0.25)
	_check(units.get_child_count() == 2, "Both sides spawn at 3.5 seconds after construction.")
	if units.get_child_count() == 2:
		var cpu_unit := units.get_child(0) as MeshInstance3D
		var player_unit := units.get_child(1) as MeshInstance3D
		var token := player_unit.mesh as PrismMesh
		_check(cpu_unit.mesh == token and token != null,
			"Both sides spawn the same triangular token mesh.")
		_check(cpu_unit.position.x > 0 and player_unit.position.x < 0
			and cpu_unit.basis.y.x < 0.0 and player_unit.basis.y.x > 0.0
			and cpu_unit.material_override != player_unit.material_override,
			"Units start on their own side, face the opposing base and use distinct colors.")

	match_scene._process(4.5)
	_check(match_scene.try_place_building(PLAYER, &"barracks", Vector3(-10.2, 0, -3.65)), "Both sides add a second barracks at 10 seconds.")
	match_scene._process(2.5)
	_check(produced.size() == 6, "The first barracks on each side keeps its own timer.")
	match_scene._process(1.0)
	_check(produced.size() == 8, "The second barracks on each side starts a full cycle.")

	match_scene._process(2.5)
	_check(match_scene.try_place_building(PLAYER, &"farm",
		_clear_producer_point(match_scene, TerritoryLayout.PLAYER_START, &"farm")),
		"Both sides add Food income at 16 seconds.")
	match_scene._process(14.0)
	_check(match_scene.try_upgrade(PLAYER), "Both sides upgrade at 30 seconds.")
	match_scene._process(0.0)
	_check(produced.size() == 28, "Both upgrades preserve elapsed production time.")
	match_scene._process(2.25)
	_check(produced.size() == 28, "Upgraded barracks wait for the 2.5-second interval.")
	match_scene._process(0.25)
	_check(produced.size() == 32, "All four barracks spawn at the upgraded interval.")
	var player_units := 0
	for unit in produced:
		if unit.side == PLAYER:
			player_units += 1
	_check(player_units == 16, "Both sides produce the same number of units across both rates.")
	match_scene.free()


func _test_expanded_production() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var economy: MatchEconomy = scene.economy
	var battle: MatchBattle = scene._battle
	economy.advance(120.0)
	var claimed := &"region_1"
	_check(scene.try_claim(PLAYER, claimed), "Claim a second region for barracks production.")
	for point in [Vector3(-10.2, 0, -1.2), Vector3(-12.73, 0, 0.41),
			Vector3(-12.0, 0, -3.0), _clear_producer_point(scene, claimed, &"barracks")]:
		var before := _stockpiles(economy, PLAYER)
		_check(scene.try_place_building(PLAYER, &"barracks", point)
			and economy.stockpile(PLAYER, ENERGY) == before[ENERGY] - 40.0
			and economy.stockpile(PLAYER, MATERIALS) == before[MATERIALS] - 20.0
			and economy.stockpile(PLAYER, FOOD) == before[FOOD],
			"Each player barracks in owned territory charges its full construction price.")
	_check(battle.active_barracks_count(PLAYER) == 4, "All four player barracks are operational.")

	economy.set_income_source(CPU, FOOD, &"test_supply", "Test supply", 10.0)
	for decision in range(16):
		var count := economy.barracks_count(CPU)
		var before := _stockpiles(economy, CPU)
		scene._try_cpu_purchase()
		if economy.barracks_count(CPU) > count:
			_check(economy.barracks_count(CPU) == count + 1
				and economy.stockpile(CPU, ENERGY) == before[ENERGY] - 40.0
				and economy.stockpile(CPU, MATERIALS) == before[MATERIALS] - 20.0
				and economy.stockpile(CPU, FOOD) == before[FOOD],
				"Autonomous CPU construction uses the shared barracks price.")
		if economy.barracks_count(CPU) == 4:
			break
	_check(battle.active_barracks_count(CPU) == 4,
		"The CPU grows beyond two barracks when its economy supports expansion.")
	var sources := {}
	for timer: MatchBattle.ProductionTimer in battle._timers:
		_check(not sources.has(timer.source_id), "Each barracks has a unique source ID.")
		sources[timer.source_id] = true
		_check(scene.owns_region(timer.side, scene.region_at_world_position(scene._world_position(timer.position))),
			"Every barracks belongs to the faction that owns its placement point.")

	_check(scene.try_upgrade(PLAYER) and economy.has_upgrade(CPU), "Both factions fund their upgrade.")
	var deployments := {PLAYER: 0, CPU: 0}
	var unit_ids := {}
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		_check(not unit_ids.has(unit.id), "Deployments from different barracks have unique unit IDs.")
		unit_ids[unit.id] = true
		deployments[unit.side] += 1)
	var player_food := economy.stockpile(PLAYER, FOOD)
	var cpu_food := economy.stockpile(CPU, FOOD)
	battle.advance(2.25, economy)
	_check(deployments == {PLAYER: 0, CPU: 0}, "No barracks deploys before the upgraded cycle completes.")
	battle.advance(0.25, economy)
	_check(deployments == {PLAYER: 4, CPU: 4}
		and economy.stockpile(PLAYER, FOOD) == player_food - 16.0
		and economy.stockpile(CPU, FOOD) == cpu_food - 16.0,
		"Each upgraded barracks independently deploys one unit and spends four Food.")

	scene._set_region_owner(claimed, MatchRegion.Owner.NEUTRAL)
	battle.advance(2.5, economy)
	_check(battle.active_barracks_count(PLAYER) == 3 and economy.barracks_count(PLAYER) == 4
		and deployments == {PLAYER: 7, CPU: 8} and economy.stockpile(PLAYER, FOOD) == player_food - 28.0,
		"The barracks in lost territory pauses while the other barracks still deploy and spend Food.")

	scene.restart_match()
	scene.set_process(false)
	for side in [PLAYER, CPU]:
		_check(scene.economy.barracks_count(side) == 0 and scene._battle.active_barracks_count(side) == 0
			and not scene.economy.has_upgrade(side)
			and _stockpiles(scene.economy, side) == {ENERGY: 50.0, MATERIALS: 30.0, FOOD: 20.0}
			and scene._buildings[side].get_child_count() == 0,
			"Restart clears expanded production and restores the starting economy for both factions.")
	_check(scene._battle.active_units().is_empty()
		and scene.get_node("%BarracksCount").text == "Barracks 0", "Restart clears units and the HUD count.")
	scene.free()


func _click(button: BaseButton) -> void:
	_send_click(button.get_global_rect().get_center())


func _send_click(position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _check_state(economy: MatchEconomy, side: MatchRegion.Owner, expected: Array,
		context: String) -> void:
	var actual := [economy.energy(side), economy.barracks_count(side),
		economy.production_interval(side)]
	_check(is_equal_approx(actual[0], expected[0]) and actual.slice(1) == expected.slice(1),
		"%s for %s. Expected %s, got %s." % [
		context, MatchRegion.Owner.keys()[side], expected, actual,
	])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
