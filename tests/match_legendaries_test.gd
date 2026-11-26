extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MATCH_SCENE := preload("res://main.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const ENERGY := FactionStats.ENERGY
const HP := FactionStats.BUILDING_MAX_HP
const DPS := FactionStats.UNIT_DPS

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_test_generation()
	for stat in [ENERGY, FactionStats.MATERIALS, FactionStats.FOOD, HP, DPS]:
		_test_claim_lifecycle(stat)
	_test_stacking()
	_test_different_bonuses()
	_test_starting_ownership()
	if failures == 0:
		print("Legendary generation, placement, capture, stacking, gameplay stats and restart checks passed.")
	quit(1 if failures > 0 else 0)


func _match(count: int, regions: int, map_seed := 17, probability := 1.0,
		catalog: Array[LegendaryBuff] = [], neutral_only := true) -> Node:
	var scene := MATCH_SCENE.instantiate()
	scene.narrative_catalog = null
	scene.legendary_count = count
	scene.region_count = regions
	scene.map_seed = map_seed
	scene.legendary_spawn_probability = probability
	scene.legendary_neutral_only = neutral_only
	scene.outpost_hp = 1
	if not catalog.is_empty():
		scene.legendary_catalog = catalog
	root.add_child(scene)
	scene.set_process(false)
	return scene


func _test_generation() -> void:
	for config in [[0, 6, 1.0], [5, 2, 1.0], [5, 6, 0.0], [1, 6, 1.0], [10, 6, 1.0]]:
		var scene := _match(config[0], config[1], 17, config[2])
		var expected := mini(config[0], config[1] - 2) if config[2] > 0.0 else 0
		_check(scene._landmarks.size() == expected, "Spawn settings respect the cap and available neutral cells.")
		for landmark: LegendaryLandmark in scene._landmarks.values():
			var region: MatchRegion = scene.get_region(landmark.region_id)
			_check(landmark.visible and landmark.get_parent() == region
				and scene.region_at_world_position(landmark.global_position) == region.region_id
				and region.region_owner == NEUTRAL
				and not scene._battle.navigation.is_passable(landmark.footprint.get_center()),
				"A landmark has a visible node and solid footprint in its neutral region.")
			for corner in BattleNavigation.corners_of(landmark.footprint):
				_check(Geometry2D.is_point_in_polygon(corner, region.polygon),
					"The entire structure footprint fits inside the generated polygon.")
			for side in [NEUTRAL, PLAYER, CPU]:
				_check(scene.faction_stats.inspect(side, landmark.stat, 80.0).breakdown.size() == 1,
					"Neutral landmarks contribute no stats to any faction.")
		scene.free()

	var ignored := LegendaryBuff.new("Disabled", DPS, 100.0)
	ignored.weight = 0
	var chosen := LegendaryBuff.new("Guaranteed", ENERGY)
	chosen.weight = 15
	var weighted := _match(4, 6, 17, 1.0, [ignored, chosen, null])
	_check(weighted._landmarks.size() == 4, "A valid positive-weight entry supplies each placed site.")
	for landmark: LegendaryLandmark in weighted._landmarks.values():
		_check(landmark.stat == ENERGY, "Zero-weight and null catalog rows cannot be rolled.")
	weighted.free()
	var invalid := _match(4, 6, 17, 1.0, [ignored, LegendaryBuff.new("Invalid", &"unknown")])
	_check(invalid._landmarks.is_empty(), "A catalog with no valid rows safely produces zero sites.")
	invalid.free()

	var original := _match(15, 18, 17, 0.5)
	var repeated := _match(15, 18, 17, 0.5)
	var different := _match(15, 18, 71, 0.5)
	var snapshot := _snapshot(original)
	_check(snapshot.size() > 0 and snapshot.size() < 15 and snapshot == _snapshot(repeated),
		"Identical seeds reproduce the probabilistic subset, positions, IDs and weighted rolls.")
	_check(snapshot.keys() != _snapshot(different).keys(),
		"A different seed changes which regions receive landmarks.")
	for scene in [original, repeated, different]:
		scene.free()


func _test_claim_lifecycle(stat: StringName) -> void:
	var amount := 10.0 if stat == HP else 1.0
	var scene := _match(1, 3, 17, 1.0, [LegendaryBuff.new("Test Shrine", stat, amount)])
	var region_id := &"region_1"
	var landmark := scene._landmarks.get(region_id) as LegendaryLandmark
	if landmark == null:
		_check(false, "The sole neutral region has its configured landmark.")
		scene.free()
		return
	var snapshot := _snapshot(scene)
	var battle: MatchBattle = scene._battle
	var stats: FactionStats = scene.faction_stats
	var economy: MatchEconomy = scene.economy
	var details := scene.get_node("%LandmarkDetails") as Label
	var region_title := scene.get_node("%SelectedRegion") as Label
	var camera := root.get_camera_3d()
	var mesh := landmark.get_node("Crystal/Upper") as MeshInstance3D
	var pointer := camera.unproject_position(mesh.global_position)
	_check(scene._pick_building(pointer) == landmark, "The landmark model is clickable through the camera.")
	scene._pick_map(pointer)
	_check(scene._selected_region_id == region_id and region_title.text.contains("Region 1 · Neutral")
		and details.text.contains("Test Shrine · Inactive"),
		"Selecting the landmark shows its name, region, and inactive status.")
	var claim := scene.get_node("%Claim") as Button
	_check(not claim.disabled and scene.selected_unit() == null,
		"The neutral landmark enables the region's Claim without selecting a scout.")
	claim.pressed.emit()
	if not ScoutFixture.finish_claim(scene, PLAYER, region_id):
		_check(false, "The player can claim the landmark region.")
		scene.free()
		return
	var outpost := scene._outposts_by_region[region_id] as MatchBattle.Outpost
	_check(not landmark.footprint.intersects(Rect2(outpost.position - MatchBattle.OUTPOST_FOOTPRINT,
		MatchBattle.OUTPOST_FOOTPRINT * 2.0)), "The claim outpost stands apart from the landmark.")
	_check(details.text.contains("Test Shrine · Active") and region_title.text.contains("Player"), "Claiming updates landmark details and active bonuses.")
	_check(stats.value(PLAYER, stat, 80.0) == 80.0 + amount and stats.value(CPU, stat, 80.0) == 80.0,
		"The claimed modifier applies only to the controlling faction.")
	var source: Dictionary = stats.inspect(PLAYER, stat, 80.0).breakdown[1]
	_check(source.source_id == landmark.source_id and source.source_type == &"legendary"
		and source.region_id == region_id, "Provenance identifies the stable source and region.")
	if MatchEconomy.RESOURCES.has(stat):
		var baseline: float = MatchEconomy.RESOURCES[stat].baseline
		var stock := economy.stockpile(PLAYER, stat)
		economy.advance(2.0)
		_check(economy.income_rate(PLAYER, stat) == baseline + amount
			and economy.income_rate(CPU, stat) == baseline
			and economy.stockpile(PLAYER, stat) == stock + 2.0 * (baseline + amount),
			"The resource rate contributes to normal stockpile accrual only for its owner.")
	if stat == HP:
		_check(outpost.hp == 11.0 and outpost.max_hp == 11.0
			and battle.base_health_stat(PLAYER).total == MatchBattle.BASE_HP + amount
			and battle.base_health_stat(CPU).total == MatchBattle.BASE_HP,
			"Building health uses the modifier for existing caps and newly spawned outposts.")
	if stat == DPS:
		var player_unit := _spawn(battle, economy, PLAYER)
		var base_center: Vector2 = battle._bases[CPU]
		player_unit.position = _attack_position(battle, base_center, battle._base_obstacles[CPU],
			MatchBattle.BASE_ATTACK_RANGE)
		battle.advance(MatchBattle.STEP, economy)
		_check(battle.base_hp(CPU) == MatchBattle.BASE_HP - MatchBattle.ATTACK_DAMAGE - amount,
			"A normal attack uses the landmark damage bonus.")
		player_unit.hp = 0
		battle.advance(MatchBattle.STEP, economy)

	economy.advance(50.0)
	for building_id in [&"barracks", &"generator", &"machine_gun_nest"]:
		_check(not scene.try_place_building(PLAYER, building_id, landmark.global_position),
			"Freeform buildings cannot overlap the landmark.")
	_check(not scene.try_place_wall(PLAYER, landmark.global_position - Vector3.RIGHT,
		landmark.global_position + Vector3.RIGHT), "Wall segments cannot overlap the landmark.")
	var region: MatchRegion = scene.get_region(region_id)
	var build_site := region.interior_point(func(point: Vector2) -> bool:
		return scene._placement_block_reason(PLAYER, &"barracks", scene._world_position(point)).is_empty())
	if not scene.try_place_building(PLAYER, &"barracks", scene._world_position(build_site)):
		_check(false, "A separate free site still accepts a barracks.")
		scene.free()
		return
	var barracks := scene.get_node("Buildings/Player").get_child(0)
	battle.set_barracks_active(battle._timers.back(), false)
	var enemy := _spawn(battle, economy, CPU)
	enemy.position = _attack_position(battle, outpost.position, outpost.obstacle, MatchBattle.OUTPOST_ATTACK_RANGE)
	_check(battle.unit_attack_stat(enemy).total == MatchBattle.ATTACK_DAMAGE,
		"The opposing unit does not inherit the player's damage bonus.")
	battle.advance(9.0, economy)
	_check(battle.get_outpost(outpost.id) == null and scene.owns_region(NEUTRAL, region_id)
		and scene._landmarks[region_id] == landmark and landmark.is_visible_in_tree()
		and barracks.is_inside_tree(), "Destroying the outpost preserves both the landmark and the barracks.")
	_check(stats.value(PLAYER, stat, 80.0) == 80.0 and region_title.text.contains("Neutral")
		and details.text.contains("Test Shrine · Inactive"), "Outpost loss immediately revokes the source.")
	enemy.hp = 0.0
	_check(ScoutFixture.claim(scene, CPU, region_id) and stats.value(CPU, stat, 80.0) == 80.0 + amount
		and stats.value(PLAYER, stat, 80.0) == 80.0 and region_title.text.contains("CPU")
		and details.text.contains("Test Shrine · Active"),
		"The CPU reclaims the same source without a stale player modifier.")
	scene.restart_match()
	_check(scene.faction_stats != stats and snapshot == _snapshot(scene)
		and scene._landmarks[region_id] == landmark and scene.owns_region(NEUTRAL, region_id)
		and scene.faction_stats.value(CPU, stat, 80.0) == 80.0
		and scene.faction_stats.value(PLAYER, stat, 80.0) == 80.0
		and not details.is_visible_in_tree(),
		"Restart keeps the original landmarks and rolls and restores the neutral effects and selection.")
	scene.free()


func _test_stacking() -> void:
	var scene := _match(10, 6, 17, 1.0, [LegendaryBuff.new("Twin Vault", ENERGY)])
	var first := &"region_1"
	_check(ScoutFixture.claim(scene, PLAYER, first), "The first stack source can be claimed normally.")
	scene.economy.advance(50.0)
	var claimed: Array[StringName] = [first]
	for claim_number in range(2):
		for id in scene._landmarks:
			if ScoutFixture.claim(scene, PLAYER, id):
				claimed.append(id)
				break
	var inspected: Dictionary = scene.economy.income_stat(PLAYER, ENERGY)
	_check(claimed.size() == 3 and inspected.total == 6.0 and inspected.breakdown.size() == 4,
		"Three separately claimed sources with the same stat stack additively.")
	var first_outpost := scene._outposts_by_region.get(first) as MatchBattle.Outpost
	if first_outpost != null:
		first_outpost.hp = 0.0
		scene._battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.economy.income_rate(PLAYER, ENERGY) == 5.0,
		"Neutralizing one source leaves both other contributions active.")
	scene._set_region_owner(first, CPU)
	_check(scene.economy.income_rate(PLAYER, ENERGY) == 5.0
		and scene.economy.income_rate(CPU, ENERGY) == 4.0,
		"A direct owner change moves only the affected source.")
	scene.free()


func _test_different_bonuses() -> void:
	var scene := _match(16, 18)
	var first: LegendaryLandmark = scene._landmarks.values()[0]
	for landmark: LegendaryLandmark in scene._landmarks.values():
		if landmark.stat == first.stat:
			continue
		scene._set_region_owner(first.region_id, PLAYER)
		scene._set_region_owner(landmark.region_id, PLAYER)
		_check(scene.faction_stats.value(PLAYER, first.stat, 80.0) == 80.0 + first.magnitude
			and scene.faction_stats.value(PLAYER, landmark.stat, 80.0) == 80.0 + landmark.magnitude
			and scene.faction_stats.value(CPU, first.stat, 80.0) == 80.0
			and scene.faction_stats.value(CPU, landmark.stat, 80.0) == 80.0,
			"Independent stats from two regions apply simultaneously to the same faction.")
		scene.free()
		return
	_check(false, "The seeded default catalog rolls more than one effect across the map.")
	scene.free()


func _test_starting_ownership() -> void:
	var scene := _match(2, 2, 17, 1.0, [LegendaryBuff.new("Bastion", HP, 7.0)], false)
	_check(scene._landmarks.size() == 2 and scene._battle.base_hp(PLAYER) == MatchBattle.BASE_HP + 7
		and scene._battle.base_hp(CPU) == MatchBattle.BASE_HP + 7,
		"Opting into starting territories activates their sources before base initialization.")
	var snapshot := _snapshot(scene)
	scene.restart_match()
	_check(snapshot == _snapshot(scene) and scene._battle.base_hp(PLAYER) == MatchBattle.BASE_HP + 7,
		"Restart reapplies an initially owned landmark once.")
	scene.free()


func _snapshot(scene: Node) -> Dictionary:
	var snapshot := {}
	for landmark: LegendaryLandmark in scene._landmarks.values():
		snapshot[landmark.region_id] = [
			landmark.source_id, landmark.footprint, landmark.stat, landmark.magnitude, landmark.display_name,
		]
	return snapshot


func _spawn(battle: MatchBattle, economy: MatchEconomy, side: MatchRegion.Owner) -> MatchBattle.Unit:
	var timer := battle.add_barracks(side, battle._bases[side] + Vector2(0, -3))
	timer.elapsed = economy.production_interval(side)
	battle.advance(0.0, economy)
	battle.set_barracks_active(timer, false)
	for unit in ScoutFixture.combat_units(battle):
		if unit.side == side:
			return unit
	return null


func _attack_position(battle: MatchBattle, center: Vector2, obstacle: int, attack_range: float) -> Vector2:
	for i in range(16):
		var point := center + Vector2.RIGHT.rotated(i * TAU / 16.0) * (attack_range - 0.01)
		if battle.navigation.is_passable(point) and battle.navigation.line_clear(point, center, obstacle):
			return point
	return Vector2.INF


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
