extends SceneTree

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const Rules := preload("res://match/fortification_rules.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const STEP := MatchBattle.STEP

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_gunfire()
	_test_overlapping_fire()
	_test_wall_navigation()
	root.size = Vector2i(1280, 800)
	var scene := MATCH_FIXTURE.instantiate()
	scene.map_seed = 17
	scene.unit_aggro_radius = 0.9
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	await process_frame
	await _test_catalog_and_drag(scene)
	_test_claim_and_restart(scene)
	await _test_match_gunfire(scene)
	scene.free()
	if _failures == 0:
		print("Fortification combat, wall navigation, placement UI, ownership and restart checks passed.")
	quit(1 if _failures > 0 else 0)


func _test_gunfire() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(Vector2(-12, 0), Vector2(12, 0), 0.1)
	var nest := battle.add_fortification(Rules.NEST, PLAYER, Vector2.ZERO)
	var near := _unit(battle, 1, CPU, Vector2(0, 2))
	var far := _unit(battle, 2, CPU, Vector2(0, 2.5))
	_unit(battle, 3, PLAYER, Vector2(0, -1.5))
	battle.advance(STEP, economy)
	_check(near.hp == MatchBattle.UNIT_HP - nest.profile.damage and far.hp == MatchBattle.UNIT_HP,
		"Machine gun fire hits only the nearest eligible enemy.")
	battle.advance(nest.profile.interval - STEP, economy)
	_check(near.hp == MatchBattle.UNIT_HP - nest.profile.damage, "The nest waits for its configured cooldown.")
	battle.advance(STEP, economy)
	_check(near.hp == MatchBattle.UNIT_HP - 2 * nest.profile.damage, "The nest fires again at its rapid cadence.")

	battle = MatchBattle.new(Vector2(-12, 0), Vector2(12, 0), 0.1)
	var mortar := battle.add_fortification(Rules.MORTAR, CPU, Vector2.ZERO)
	near = _unit(battle, 1, PLAYER, Vector2(0, 5.0))
	far = _unit(battle, 2, PLAYER, Vector2(0.9, 5.3))
	var outside := _unit(battle, 3, PLAYER, Vector2(-1.6, 5.3))
	var friendly := _unit(battle, 4, CPU, Vector2(0, 5.2))
	battle.advance(STEP, economy)
	var hit_hp: float = MatchBattle.UNIT_HP - mortar.profile.damage
	_check(near.hp == hit_hp and far.hp == hit_hp and outside.hp == MatchBattle.UNIT_HP
		and friendly.hp == MatchBattle.UNIT_HP, "CPU mortar splash from beyond nest range hits only enemies in radius.")
	battle.advance(mortar.profile.interval - STEP, economy)
	_check(near.hp == hit_hp and far.hp == hit_hp, "Mortar cadence is slower than the nest cadence.")
	battle.advance(STEP, economy)
	_check(near.hp == hit_hp - mortar.profile.damage and far.hp == near.hp,
		"Mortars repeat splash damage at their configured cadence.")


func _test_overlapping_fire() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(Vector2(-12, 0), Vector2(12, 0), 0.1)
	var first := battle.add_fortification(Rules.NEST, CPU, Vector2(0, -1))
	var second := battle.add_fortification(Rules.NEST, CPU, Vector2(0, 1))
	var near := _unit(battle, 1, PLAYER, Vector2(2, 0))
	var far := _unit(battle, 2, PLAYER, Vector2(3, 0))
	near.hp = first.profile.damage
	battle.advance(STEP, economy)
	_check(battle.get_unit(near.id) == null and far.hp == MatchBattle.UNIT_HP - second.profile.damage,
		"Two ready CPU nests retarget within the same step after a lethal shot.")

	battle = MatchBattle.new(Vector2(-12, 0), Vector2(12, 0), 0.1)
	var nest := battle.add_fortification(Rules.NEST, PLAYER, Vector2.ZERO)
	battle.add_fortification(Rules.WALL, PLAYER, Vector2(2, 0), PI * 0.5)
	var blocked := _unit(battle, 1, CPU, Vector2(3, 0))
	var clear := _unit(battle, 2, CPU, Vector2(0, 4))
	battle.advance(STEP, economy)
	_check(blocked.hp == MatchBattle.UNIT_HP and clear.hp == MatchBattle.UNIT_HP - nest.profile.damage,
		"A nest skips the nearer enemy behind a wall and fires along the clear line.")

	for order in [[1, 2], [2, 1]]:
		battle = MatchBattle.new(Vector2(-12, 0), Vector2(12, 0), 0.1)
		nest = battle.add_fortification(Rules.NEST, PLAYER, Vector2.ZERO)
		for id: int in order:
			_unit(battle, id, CPU, Vector2(2, 1 if id == 1 else -1))
		battle.advance(STEP, economy)
		_check(battle.get_unit(1).hp == MatchBattle.UNIT_HP - nest.profile.damage
			and battle.get_unit(2).hp == MatchBattle.UNIT_HP,
			"Equidistant enemies resolve to the same target regardless of registration order.")


func _test_wall_navigation() -> void:
	var economy := MatchEconomy.new()
	var battle := MatchBattle.new(Vector2(-12, 0), Vector2(12, 0))
	var a := Vector2(-2, 0)
	var b := Vector2(2, 0)
	var wall := battle.add_fortification(Rules.WALL, CPU, Vector2.ZERO, PI * 0.25)
	var adjacent := battle.add_fortification(Rules.WALL, CPU, Vector2.from_angle(PI * 0.25), PI * 0.25)
	_check(not battle.navigation.line_clear(a, b) and battle.navigation.path(a, b).size() > 1,
		"A rotated wall blocks direct passage but allows a route around it.")
	var seam := adjacent.position * 0.5
	var normal := adjacent.position.normalized().orthogonal()
	_check(not battle.navigation.line_clear(seam - normal, seam + normal),
		"Adjacent wall segments block movement at their shared seam.")
	battle = MatchBattle.new(Vector2(-8, 0), Vector2(8, 0), 0.1, Rect2(-10, -0.5, 20, 1))
	wall = battle.add_fortification(Rules.WALL, CPU, Vector2.ZERO, PI * 0.5)
	var unit := _unit(battle, 1, PLAYER, a)
	_check(battle.navigation.path(a, b).is_empty() and battle.issue_move(unit.id, b),
		"An order behind an impassable hostile wall is accepted when the unit can breach it.")
	battle.advance(0.5, economy)
	_check(wall.hp == wall.max_hp - MatchBattle.ATTACK_DAMAGE and unit.target == wall.id,
		"A blocked unit approaches and damages the hostile wall segment.")
	battle.advance(8.0, economy)
	_check(battle.get_fortification(wall.id) == null and battle.navigation.line_clear(a, b)
		and unit.position == b, "Destroying a wall opens the route and the original move order resumes.")


func _test_catalog_and_drag(scene: Node) -> void:
	var build := scene.get_node("%Build") as Button
	var menu := scene.get_node("%BuildMenu") as Control
	var status := scene.get_node("%PlacementStatus") as Label
	var wall: Button = scene._build_options[Rules.WALL]
	var mortar: Button = scene._build_options[Rules.MORTAR]
	var camera := root.get_camera_3d() as StrategyCamera
	var battle: MatchBattle = scene._battle
	var initial := _stock(scene.economy)
	scene._select_region(TerritoryLayout.PLAYER_START)
	_click(build.get_global_rect().get_center())
	await process_frame
	await process_frame
	_check(menu.visible and not wall.disabled and not mortar.disabled, "Build exposes the four catalog options.")
	_click(mortar.get_global_rect().get_center())
	_check(scene._placement_id == Rules.MORTAR and scene._pending_pick == Vector2.INF
		and _stock(scene.economy) == initial and scene._selected_region_id == TerritoryLayout.PLAYER_START,
		"An affordable tile opens placement without a world click or purchase.")
	var mortar_point := Vector3(-10, 0, -2)
	var mortar_pointer := camera.unproject_position(mortar_point)
	scene._update_placement_preview(mortar_pointer)
	_check(scene._range_ring.visible and scene._splash_ring.visible and status.text.contains("Splash radius"),
		"Mortar placement displays range and splash guides.")
	_click(mortar_pointer)
	scene._physics_process(0)
	_check(battle._fortifications.size() == 1 and scene._placement_id == &"",
		"The mortar places through the normal catalog flow.")
	_click(build.get_global_rect().get_center())
	await process_frame
	_check(wall.is_visible_in_tree() and not wall.disabled and mortar.disabled,
		"The minimum-cost wall stays available while an unaffordable mortar is disabled.")
	var before := _stock(scene.economy)
	_click(mortar.get_global_rect().get_center())
	_check(menu.visible and scene._placement_id == &"" and _stock(scene.economy) == before
		and scene._selected_region_id == TerritoryLayout.PLAYER_START,
		"A disabled tile consumes input and leaves placement, resources and map selection alone.")
	_click(wall.get_global_rect().get_center())
	var start := Vector3(-13, 0, -4)
	var too_long := Vector3(-13, 0, -0.5)
	_mouse(camera.unproject_position(start), MOUSE_BUTTON_LEFT, true)
	scene._update_placement_preview(camera.unproject_position(too_long))
	_check(status.text.contains("3 units") and status.text.contains("9 Energy + 6 Materials")
		and status.text.contains("Need more") and scene._preview_material.albedo_color == scene.INVALID_PREVIEW,
		"The unaffordable preview shows rounded length, price and invalid state.")
	_mouse(camera.unproject_position(too_long), MOUSE_BUTTON_LEFT, false)
	_check(battle._fortifications.size() == 1 and _stock(scene.economy) == before,
		"Releasing an unaffordable wall creates no segments and charges no resources.")
	_check(not scene.try_place_wall(PLAYER, start, start + Vector3(0, 0, 0.9))
		and _stock(scene.economy) == before, "A sub-minimum wall does not charge.")
	_mouse(camera.unproject_position(start), MOUSE_BUTTON_LEFT, true)
	_mouse(scene.get_node("%CancelPlacement").get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false)
	await process_frame
	_check(scene._wall_start == Vector2.INF and battle._fortifications.size() == 1,
		"Releasing over the placement HUD aborts the drag without building.")
	# Pan between press and release so both endpoints must use their own camera transform.
	_mouse(camera.unproject_position(start), MOUSE_BUTTON_LEFT, true)
	camera.position += Vector3(1.5, 0, -0.8)
	camera.size *= 0.85
	var end := start + Vector3(0, 0, 1.9)
	scene._update_placement_preview(camera.unproject_position(end))
	_check(status.text.contains("1 unit ·") and status.text.contains("3 Energy + 2 Materials")
		and scene._preview_material.albedo_color == scene.VALID_PREVIEW, "A valid drag shows its exact rounded price.")
	_mouse(camera.unproject_position(end), MOUSE_BUTTON_LEFT, false)
	_check(battle._fortifications.size() == 2 and _stock(scene.economy) == before - Vector3(3, 2, 0),
		"A valid drag under a moved and zoomed camera builds one segment for one payment.")
	if battle._fortifications.size() == 2:
		var first: MatchBattle.Fortification = battle._fortifications.values().back()
		_check(first.position.distance_to(Vector2(start.x, start.z + 0.5)) < 0.001,
			"The drag preserves the map-space start captured before the camera changed.")

	_click(build.get_global_rect().get_center())
	await process_frame
	_check(not build.disabled and menu.visible and wall.disabled, "Build remains open when every tile is unaffordable.")
	for option: Button in scene._build_options.values():
		_check(option.visible and option.disabled, "Every unaffordable tile remains visible.")
	var before_income := _stock(scene.economy)
	scene.economy.advance(35.0)
	scene._refresh_hud()
	_check(not wall.disabled and not mortar.disabled and scene.economy.energy(PLAYER) > before_income.x,
		"Tiles automatically re-enable when stockpiles recover.")
	_click(wall.get_global_rect().get_center())
	_mouse(camera.unproject_position(Vector3(-13, 0, -2.0)), MOUSE_BUTTON_LEFT, true)
	_mouse(camera.unproject_position(Vector3(-13, 0, 0.4)), MOUSE_BUTTON_LEFT, false)
	_check(battle._fortifications.size() == 4, "A second drag builds two separately registered segments.")
	var player_unit := _unit(battle, 101, PLAYER, Vector2(-11, -0.5))
	scene._spawn_unit(player_unit)
	scene._select_unit(player_unit.id)
	scene._begin_placement(Rules.WALL)
	_mouse(camera.unproject_position(end), MOUSE_BUTTON_RIGHT, true)
	_check(scene._placement_id == &"" and scene.selected_unit() == player_unit
		and player_unit.order == MatchBattle.Order.HOLD, "Right-click cancels and restores selection without an order.")
	_check(not scene.try_place_building(PLAYER, &"barracks", start + Vector3(0, 0, 0.5)),
		"A new barracks cannot cover a wall with its spawn exits.")


func _test_claim_and_restart(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene.economy.advance(20.0)
	var battle: MatchBattle = scene._battle
	var contested := &"region_1"
	var region: MatchRegion = scene.get_region(contested)
	var point := region.global_position + Vector3(-2.6, 0, 0)
	var start := region.global_position + Vector3(0, 0, -2.2)
	var end := start + Vector3.RIGHT * 2.4
	var before := _stock(scene.economy)
	_check(not scene.try_place_building(PLAYER, Rules.NEST, point)
		and not scene.try_place_wall(PLAYER, start, end)
		and _stock(scene.economy) == before, "Neutral territory rejects both guns and wall segments.")
	scene._set_region_owner(TerritoryLayout.CPU_START, PLAYER)
	_check(not scene.try_place_wall(PLAYER, Vector3(-9, 0, -2), Vector3(9, 0, -2))
		and _stock(scene.economy) == before, "Friendly endpoints cannot authorize a crossing through neutral territory.")
	scene._set_region_owner(TerritoryLayout.CPU_START, CPU)
	scene.outpost_hp = MatchBattle.ATTACK_DAMAGE
	_check(scene.try_claim(PLAYER, contested), "The player can claim the test region.")
	scene.economy.advance(40.0)
	_check(scene.try_place_building(PLAYER, Rules.NEST, point)
		and scene.try_place_wall(PLAYER, start, end), "A claimed region accepts guns and walls.")
	var defenses: Array[MatchBattle.Fortification] = []
	for placed in scene._fortifications.values():
		if placed.regions.has(contested):
			defenses.append(placed.defense)
	_check(defenses.size() == 3, "A nest and the two independently destructible wall segments are registered.")
	if defenses.size() != 3:
		return

	var hub: MatchBattle.Outpost = scene._outposts_by_region[contested]
	var raider := _unit(battle, 102, CPU, hub.position + Vector2(1.20, 0))
	scene._spawn_unit(raider)
	battle.advance(STEP, scene.economy)
	_check(scene.owns_region(MatchRegion.Owner.NEUTRAL, contested)
		and not defenses[0].active and not defenses[1].active and not defenses[2].active,
		"Combat loss of the outpost deactivates every fortification in that region.")
	var nest := defenses[0]
	raider.position = nest.position + Vector2(0, 1.1)
	raider.ordered_destination = raider.position
	var raider_hp := raider.hp
	raider.cooldown = 0.0
	scene._process(STEP)
	_check(raider.hp == raider_hp and nest.hp < nest.max_hp,
		"The inactive nest holds fire but stays targetable by the enemy.")
	_check(scene.try_claim(PLAYER, contested) and nest.active and defenses[1].active and defenses[2].active,
		"The original owner's reclaim reactivates retained defenses.")
	scene._process(STEP)
	_check(raider.hp == raider_hp - nest.profile.damage and scene._shot_effects.get_child_count() == 1,
		"The reclaimed gun resumes firing with a single shot.")
	var view: Node3D = scene._fortifications[nest.id].view
	nest.hp = MatchBattle.ATTACK_DAMAGE
	raider.cooldown = 0.0
	battle.advance(STEP, scene.economy)
	_check(not view.is_inside_tree() and battle.get_fortification(nest.id) == null
		and defenses[1].hp == defenses[1].max_hp, "Enemy damage removes only the destroyed fortification.")
	scene._begin_placement(Rules.WALL)
	scene.restart_match()
	_check(scene._fortifications.is_empty() and scene._battle._fortifications.is_empty()
		and scene.get_node("Buildings/Player").get_child_count() == 0 and scene._preview == null
		and scene._shot_effects.get_child_count() == 0
		and scene._battle.navigation.is_passable(nest.position)
		and _stock(scene.economy) == _stock(MatchEconomy.new()),
		"Headless restart clears defenses, previews, navigation obstacles and payments.")


func _test_match_gunfire(scene: Node) -> void:
	var regions := scene.get_node("Regions") as Node3D
	regions.scale = Vector3.ONE * 1.1
	regions.rotate_y(0.15)
	scene.restart_match()
	scene.set_process(false)
	scene.economy.advance(30.0)
	var nest_point: Vector3 = scene._world_position(Vector2(-10, -1.7))
	var mortar_point: Vector3 = scene._world_position(Vector2(-7.7, 0.7))
	if not scene.try_place_building(PLAYER, Rules.NEST, nest_point) \
			or not scene.try_place_building(PLAYER, Rules.MORTAR, mortar_point):
		_check(false, "Both weapons can be purchased and placed in the seed-17 match.")
		return

	var battle: MatchBattle = scene._battle
	var nest: MatchBattle.Fortification = scene._fortifications.values()[0].defense
	var mortar: MatchBattle.Fortification = scene._fortifications.values()[1].defense
	_check(battle.get_fortification(nest.id) == nest and battle.get_fortification(mortar.id) == mortar
		and nest.active and mortar.active and nest.side == PLAYER and mortar.side == PLAYER,
		"Both new player weapons are active in the battle registry.")

	scene._select_fortification(nest.id)
	var camera := root.get_camera_3d() as StrategyCamera
	camera.position += Vector3(1.5, 0, -0.8)
	camera.size *= 0.85
	_check(scene._range_ring.visible
		and scene._map_position(scene._range_ring.to_global(Vector3.RIGHT)).is_equal_approx(
			nest.position + Vector2.RIGHT * float(nest.profile.range)),
		"The selected nest's outer range edge matches combat after the camera pans and zooms.")
	var nester := _scene_unit(scene, 101, CPU, nest.position + Vector2(0, -4.6))
	scene._select_fortification(MatchBattle.NO_TARGET)
	# Exercise only the nest against the infantry until the mortar assertions.
	battle.set_fortification_active(mortar, false)
	scene._process(STEP)
	_check(nester.hp == MatchBattle.UNIT_HP, "The nest holds fire outside its displayed range.")
	nester.order = MatchBattle.Order.MOVE
	nester.ordered_destination = nest.position + Vector2(0, -4.4)
	scene._process(7 * STEP)
	var nest_hit_hp := MatchBattle.UNIT_HP - float(nest.profile.damage)
	_check(nester.hp == nest_hit_hp and scene._selected_fortification == MatchBattle.NO_TARGET,
		"Moving CPU infantry loses HP upon entering the unselected nest's displayed range.")
	scene._select_unit(nester.id)
	var hp_text: String = scene.get_node("%UnitStats").text
	var elapsed := battle.elapsed_time()
	paused = true
	scene.set_process(true)
	await process_frame
	await process_frame
	scene.set_process(false)
	paused = false
	_check(battle.elapsed_time() == elapsed and nester.hp == nest_hit_hp, "Pausing stops defensive damage.")
	scene._process(float(nest.profile.interval))
	_check(nester.hp == nest_hit_hp - nest.profile.damage and scene.get_node("%UnitStats").text != hp_text,
		"The nest repeats damage at its cadence and the enemy HP readout updates.")
	nester.order = MatchBattle.Order.MOVE
	nester.ordered_destination = nest.position + Vector2(0, -4.7)
	var replacement := _scene_unit(scene, 102, CPU, nest.position + Vector2(4.0, 0))
	scene._process(float(nest.profile.interval))
	_check(nester.hp == nest_hit_hp - nest.profile.damage and replacement.hp == nest_hit_hp,
		"The nest switches targets when the original enemy retreats out of range.")

	scene._select_unit(MatchBattle.NO_TARGET)
	scene._select_fortification(mortar.id)
	_check(scene._range_ring.visible and scene._splash_ring.visible
		and scene._map_position(scene._range_ring.to_global(Vector3.RIGHT)).is_equal_approx(
			mortar.position + Vector2.RIGHT * float(mortar.profile.range))
		and scene._map_position(scene._splash_ring.to_global(Vector3.RIGHT)).is_equal_approx(
			mortar.position + Vector2.RIGHT * float(mortar.profile.splash)),
		"The mortar displays the combat range and splash radii.")
	scene._select_fortification(MatchBattle.NO_TARGET)
	battle.set_fortification_active(nest, false)
	battle.set_fortification_active(mortar, true)
	var impact := _scene_unit(scene, 103, CPU, mortar.position + Vector2(6.8, 0))
	var splash := _scene_unit(scene, 104, CPU, mortar.position + Vector2(6.8, 0.8))
	var outside := _scene_unit(scene, 105, CPU, mortar.position + Vector2(7.2, 0))
	var friendly := _scene_unit(scene, 106, PLAYER, mortar.position + Vector2(5.7, 0))
	# Move the earlier nest target clear of mortar range.
	replacement.position = Vector2(0, -4)
	replacement.ordered_destination = replacement.position
	scene._process(STEP)
	var mortar_hit_hp := MatchBattle.UNIT_HP - float(mortar.profile.damage)
	_check(impact.hp == mortar_hit_hp and splash.hp == mortar_hit_hp
		and outside.hp == MatchBattle.UNIT_HP and friendly.hp == MatchBattle.UNIT_HP,
		"An unselected player mortar splashes multiple enemies within range and spares allies and out-of-range infantry.")


func _scene_unit(scene: Node, id: int, side: MatchRegion.Owner, position: Vector2) -> MatchBattle.Unit:
	var unit := _unit(scene._battle, id, side, position)
	scene._battle.unit_produced.emit(unit)
	return unit


func _unit(battle: MatchBattle, id: int, side: MatchRegion.Owner, position: Vector2) -> MatchBattle.Unit:
	var unit := MatchBattle.Unit.new(id, side, position)
	unit.order = MatchBattle.Order.HOLD
	unit.ordered_destination = position
	battle._units[id] = unit
	return unit


func _stock(economy: MatchEconomy) -> Vector3:
	return Vector3(economy.energy(PLAYER), economy.stockpile(PLAYER, MatchEconomy.MATERIALS),
		economy.stockpile(PLAYER, MatchEconomy.FOOD))


func _click(position: Vector2) -> void:
	_mouse(position, MOUSE_BUTTON_LEFT, true)
	_mouse(position, MOUSE_BUTTON_LEFT, false)


func _mouse(position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
