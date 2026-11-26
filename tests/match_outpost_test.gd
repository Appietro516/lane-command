extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const CONTESTED := &"region_1"
const BACKUP := &"region_2"
const BEYOND := &"region_4"
const BARRACKS := &"barracks"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interior_points()
	var scene := MATCH_FIXTURE.instantiate()
	scene.outpost_hp = 2 * MatchBattle.ATTACK_DAMAGE
	root.add_child(scene)
	scene.set_process(false)
	_test_lifecycle(scene)
	scene.free()
	_test_obstructed_site()
	if failures == 0:
		print("Outpost placement, combat, territory loss, barracks reactivation and restart checks passed.")
	quit(1 if failures > 0 else 0)


func _test_interior_points() -> void:
	for region_count in [2, 6, TerritoryLayout.DEFAULT_REGION_COUNT, 42]:
		for map_seed in [0, 17, 71, -1]:
			var layout := TerritoryLayout.new(map_seed, region_count)
			for cell in layout.cells:
				var region := MatchRegion.new(cell)
				_check(layout.region_at(region.interior_point()) == cell.id,
					"Each generated cell supplies an interior point in its own territory.")
				region.free()
	var polygon := PackedVector2Array([
		Vector2(0, 0), Vector2(6, 0), Vector2(6, 2),
		Vector2(2, 2), Vector2(2, 6), Vector2(0, 6),
	])
	for site in [Vector2(3, 3), Vector2(2, 3)]:
		var cell := TerritoryLayout.Cell.new(&"authored", site)
		cell.polygon = polygon
		var region := MatchRegion.new(cell)
		var point := region.interior_point()
		_check(point != site and Geometry2D.is_point_in_polygon(point, polygon),
			"An authored concave region supplies an interior fallback for exterior and edge sites.")
		region.free()


func _test_lifecycle(scene: Node) -> void:
	var battle: MatchBattle = scene._battle
	# Keep this fixture focused on structure targeting when Scouts are nearby.
	battle.aggro_radius = 0.1
	var economy: MatchEconomy = scene.economy
	var region: MatchRegion = scene.get_region(CONTESTED)
	var selection := scene.get_node("%SelectedRegion") as Label
	var region_status := scene.get_node("%RegionStatus") as Label
	var claim_button := scene.get_node("%Claim") as Button
	var tile := region.geometry.material_override as StandardMaterial3D
	var player_buildings := scene.get_node("Buildings/Player")
	var backup: MatchRegion = scene.get_region(BACKUP)
	var build_point := region.global_position + Vector3(-2.6, 0, 0)
	scene._select_region(CONTESTED)
	scene._use_scout_slot(1)
	_check(battle._outposts.is_empty() and not ScoutFixture.claim(scene, PLAYER, BEYOND),
		"Starting bases and invalid claims create no optional outposts.")
	_check(ScoutFixture.claim(scene, PLAYER, CONTESTED), "An adjacent neutral region can be claimed.")
	var hub := scene._outposts_by_region.get(CONTESTED) as MatchBattle.Outpost
	if hub == null:
		_check(false, "The claim creates its outpost.")
		return
	var view := scene._outpost_views.get(CONTESTED) as Node3D
	_check(battle._outposts.size() == 1 and region.get_children().count(view) == 1
		and scene.region_at_world_position(view.global_position) == CONTESTED
		and hub.region_id == CONTESTED and hub.side == PLAYER and hub.hp == scene.outpost_hp,
		"The claim creates one visible, configurable outpost in the claimed region.")
	_check(economy.energy(PLAYER) == 0.0 and scene.owns_region(PLAYER, CONTESTED)
		and tile.albedo_color == MatchRegion.OWNER_COLORS[PLAYER]
		and claim_button.disabled and region_status.text.contains("Outpost · 6/6 HP"),
		"The claim spends the configured cost and immediately updates ownership, color and selection.")

	economy.advance(50.0)
	var energy := economy.energy(PLAYER)
	_check(not ScoutFixture.claim(scene, PLAYER, CONTESTED) and not ScoutFixture.claim(scene, CPU, CONTESTED)
		and economy.energy(PLAYER) == energy and battle._outposts.size() == 1,
		"Repeated and enemy claims leave the original outpost and energy intact.")
	_check(ScoutFixture.claim(scene, CPU, BACKUP), "A second territory can host its own outpost.")
	var backup_hub := scene._outposts_by_region.get(BACKUP) as MatchBattle.Outpost
	_check(not scene.try_place_building(PLAYER, BARRACKS, view.global_position),
		"Building placement keeps the outpost footprint clear.")
	if not scene.try_place_building(PLAYER, BARRACKS, build_point):
		_check(false, "A clear spot in the claimed territory accepts a barracks.")
		return
	var building := player_buildings.get_child(0) as Node3D
	var timer := battle._timers[0]
	_check(scene._expeditions.eligibility(PLAYER, BEYOND).is_empty(),
		"The contested region currently anchors a further claim.")

	var cpu_unit := _deploy_attacker(battle, economy, CPU, hub.position + Vector2(2.2, 0))
	if cpu_unit == null:
		_check(false, "A CPU combat unit was produced.")
		return
	battle.advance(MatchBattle.STEP, economy)
	_check(cpu_unit.target == hub.id and not cpu_unit.waypoints.is_empty(),
		"The CPU routes toward the outpost from outside attack range.")
	for step in range(120):
		if hub.hp < hub.max_hp:
			break
		battle.advance(MatchBattle.STEP, economy)
	scene._refresh_hud()
	_check(hub.hp == MatchBattle.ATTACK_DAMAGE and region_status.text.contains("Outpost · 3/6 HP")
		and scene._target_label(cpu_unit).contains("Player outpost · 3/6 HP"),
		"A normal CPU attack deals damage and both inspection surfaces show the remaining HP.")
	battle.advance(1.0, economy)
	_check(hub.hp == 0 and battle.get_outpost(hub.id) == null and view.get_parent() == null
		and cpu_unit.target != hub.id and battle.navigation.is_passable(hub.position),
		"Combat removes the destroyed hub, its footprint, and the unit's discarded target.")
	_check(scene.owns_region(NEUTRAL, CONTESTED) and tile.albedo_color == MatchRegion.OWNER_COLORS[NEUTRAL]
		and selection.text.contains("Neutral") and not region_status.text.contains("Outpost")
		and not claim_button.disabled, "Loss immediately updates the selected tile and claim control.")
	_check(scene._expeditions.eligibility(PLAYER, BEYOND) == "Not adjacent"
		and not scene.try_place_building(PLAYER, BARRACKS, build_point),
		"Lost territory provides neither claim adjacency nor building-placement access.")
	_check(backup_hub != null and backup_hub.hp == backup_hub.max_hp
		and scene.owns_region(CPU, backup.region_id), "The other outpost and territory survive.")

	_check(building.get_parent() == player_buildings and building.visible
		and building.global_position.is_equal_approx(build_point) and not timer.active,
		"The original barracks remains visible in place with production suspended.")
	var paused_progress := timer.elapsed
	cpu_unit.hp = 0
	_check(scene.try_upgrade(PLAYER, timer.id), "The faction can upgrade while its barracks is inactive.")
	battle.advance(timer.interval(economy) + MatchBattle.STEP, economy)
	_check(is_equal_approx(timer.elapsed, paused_progress) and ScoutFixture.combat_units(battle).is_empty(),
		"A lost-region barracks does not progress or deploy units.")

	_check(ScoutFixture.claim(scene, CPU, BEYOND), "The CPU can establish valid adjacency by paying for a claim.")
	economy.advance(40.0)
	_check(ScoutFixture.claim(scene, CPU, CONTESTED) and not timer.active and building.get_parent() == player_buildings,
		"A different faction's valid claim leaves the existing barracks inactive and with its owner.")
	var cpu_hub := scene._outposts_by_region.get(CONTESTED) as MatchBattle.Outpost
	if cpu_hub == null:
		_check(false, "The CPU claim creates a replacement outpost.")
		return
	var player_unit := _deploy_attacker(battle, economy, PLAYER, cpu_hub.position + Vector2(-1.1, 0))
	if player_unit == null:
		_check(false, "A player combat unit was produced.")
		return
	battle.advance(1.05, economy)
	_check(cpu_hub.hp == 0 and scene.owns_region(NEUTRAL, CONTESTED) and not timer.active,
		"The same attacks destroy a CPU outpost and leave the region neutral.")

	player_unit.order = MatchBattle.Order.HOLD
	player_unit.ordered_destination = player_unit.position
	energy = economy.energy(PLAYER)
	_check(ScoutFixture.claim(scene, PLAYER, CONTESTED) and timer.active
		and player_buildings.get_child_count() == 1 and player_buildings.get_child(0) == building
		and economy.barracks_count(PLAYER) == 1
		and economy.energy(PLAYER) == energy - MatchEconomy.CLAIM_COST[MatchEconomy.ENERGY],
		"The original owner pays only the claim cost and reactivates the same barracks.")
	battle.advance(timer.interval(economy) - paused_progress + MatchBattle.STEP, economy)
	_check(ScoutFixture.combat_units(battle).size() == 2, "Production resumes from the existing timer.")

	scene.restart_match()
	scene.set_process(false)
	_check(scene._battle._outposts.is_empty() and scene._outpost_views.is_empty()
		and region.get_child_count() == 2 and backup.get_child_count() == 2
		and scene.owns_region(NEUTRAL, CONTESTED) and scene.owns_region(NEUTRAL, BACKUP)
		and scene.owns_region(NEUTRAL, BEYOND)
		and scene.owns_region(PLAYER, TerritoryLayout.PLAYER_START)
		and scene.owns_region(CPU, TerritoryLayout.CPU_START)
		and scene._battle.base_hp(PLAYER) == MatchBattle.BASE_HP
		and scene._battle.base_hp(CPU) == MatchBattle.BASE_HP
		and player_buildings.get_child_count() == 0 and not selection.is_visible_in_tree(),
		"Restart clears the outposts, buildings and selection and restores both starting bases.")


func _test_obstructed_site() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	scene.map_seed = 1
	scene.region_count = 7
	root.add_child(scene)
	scene.set_process(false)
	var economy: MatchEconomy = scene.economy
	economy.advance(50.0)
	var region: MatchRegion = scene.get_region(&"region_3")
	var neighbor: MatchRegion = scene.get_region(&"region_5")
	var battle: MatchBattle = scene._battle
	var site := region.interior_point()
	_check(ScoutFixture.claim(scene, CPU, &"region_2") and ScoutFixture.claim(scene, CPU, neighbor.region_id),
		"CPU claims the regions across the border from the outpost site.")
	var barracks_point := Vector2.INF
	for offset in [Vector2(1.6, -0.1), Vector2(2.0, -0.25), Vector2(2.0, 0.25),
			Vector2(1.9, -1.1), Vector2(1.9, 1.1), Vector2(1.3, -1.4), Vector2(1.3, 1.4)]:
		var point: Vector2 = site + offset
		if scene._placement_block_reason(CPU, BARRACKS, scene._world_position(point)).is_empty():
			barracks_point = point
			break
	_check(barracks_point.is_finite() and scene.try_place_building(CPU, BARRACKS, scene._world_position(barracks_point)),
		"Fixture places a barracks across the border from the new outpost site.")
	var enemy_timer: MatchBattle.ProductionTimer = battle._timers.back()
	economy.try_spend(CPU, {MatchEconomy.FOOD: int(economy.stockpile(CPU, MatchEconomy.FOOD))})
	_check(not battle.outpost_site_clear(site), "The barracks occupies the default site.")
	_check(ScoutFixture.claim(scene, PLAYER, region.region_id), "A claim can use an alternate clear site.")
	var hub := scene._outposts_by_region.get(region.region_id) as MatchBattle.Outpost
	if hub != null:
		var view: Node3D = scene._outpost_views[region.region_id]
		_check(hub.position != site and scene.region_at_world_position(view.global_position) == region.region_id,
			"The alternate site is inside the same region.")
		economy.advance(9.0)
		enemy_timer.elapsed = economy.production_interval(CPU)
		battle.advance(9.0, scene.economy)
		_check(hub.hp < hub.max_hp, "The nearby barracks cannot shield the alternate site from attacks.")
	scene.free()


func _deploy_attacker(battle: MatchBattle, economy: MatchEconomy, side: MatchRegion.Owner,
		position: Vector2) -> MatchBattle.Unit:
	# Arrange a single normally produced unit at the start of its approach.
	var timer := battle.add_barracks(side, Vector2(0, 7))
	timer.elapsed = economy.production_interval(side)
	battle.advance(0.0, economy)
	battle.set_barracks_active(timer, false)
	for unit in ScoutFixture.combat_units(battle):
		if unit.side == side:
			unit.position = position
			return unit
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
