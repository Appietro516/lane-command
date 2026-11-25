extends SceneTree

const MATCH_SCENE := preload("res://main.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL

# The claim chain is player start → region 1 → region 4 → CPU start for this fixture.
const FIRST_CLAIM: StringName = &"region_1"
const NEXT_CLAIM: StringName = &"region_4"
const OTHER_ADJACENT: StringName = &"region_3"
const UNCLAIMED: StringName = &"region_2"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var scene := MATCH_SCENE.instantiate()
	scene.map_seed = 17
	scene.region_count = 6
	root.add_child(scene)
	scene.set_process(false)
	_test_claim_rules(scene)
	await _test_claim_controls(scene)
	scene.free()
	if failures == 0:
		print("Match claim checks passed.")
	quit(1 if failures > 0 else 0)


func _test_claim_rules(scene: Node) -> void:
	_check_rejected(scene, PLAYER, NEXT_CLAIM, NEUTRAL, "Nonadjacent target")
	_check_rejected(scene, PLAYER, TerritoryLayout.PLAYER_START, PLAYER, "Player territory")
	_check_rejected(scene, CPU, NEXT_CLAIM, NEUTRAL, "CPU expansion")
	_check(not scene.try_claim(PLAYER, &"missing")
		and scene.economy.energy(PLAYER) == MatchEconomy.STARTING_ENERGY, "Unknown region ID")

	_check(scene.try_claim(PLAYER, FIRST_CLAIM), "An adjacent neutral region is claimable.")
	_check(scene.owns_region(PLAYER, FIRST_CLAIM)
		and scene.economy.energy(PLAYER) == MatchEconomy.STARTING_ENERGY - MatchEconomy.CLAIM_COST,
		"A successful claim transfers ownership and spends exactly the configured cost.")
	_check_rejected(scene, PLAYER, OTHER_ADJACENT, NEUTRAL, "Unaffordable adjacent target")
	scene._process(17.0)
	_check(scene.economy.energy(PLAYER) == 51.0 and scene.economy.barracks_count(PLAYER) == 0
		and scene.economy.production_interval(PLAYER) == MatchEconomy.PRODUCTION_INTERVAL
		and scene._battle.base_hp(CPU) == MatchBattle.BASE_HP,
		"A claim keeps passive income, barracks, production and CPU base HP at their normal values.")
	_check_rejected(scene, PLAYER, FIRST_CLAIM, PLAYER, "Repeat claim with sufficient energy")
	_check(scene.try_claim(PLAYER, NEXT_CLAIM) and scene.owns_region(PLAYER, NEXT_CLAIM),
		"Claimed territory opens adjacency for subsequent claims.")
	scene._process(17.0)
	_check_rejected(scene, PLAYER, TerritoryLayout.CPU_START, CPU, "Affordable adjacent enemy territory")
	scene._process(120.0)
	_check(scene._battle.is_finished(), "The CPU wins the unattended match.")
	_check_rejected(scene, PLAYER, UNCLAIMED, NEUTRAL, "Claim after the match ends")

	scene.restart_match()
	scene.set_process(false)
	_check(scene.owns_region(NEUTRAL, FIRST_CLAIM) and scene.owns_region(NEUTRAL, NEXT_CLAIM)
		and scene.owns_region(PLAYER, TerritoryLayout.PLAYER_START) and scene.owns_region(CPU, TerritoryLayout.CPU_START),
		"Restart restores the original owners after multiple claims.")


func _test_claim_controls(scene: Node) -> void:
	await process_frame
	await process_frame
	var claim := scene.get_node("%Claim") as Button
	var restart := scene.get_node("%Restart") as Button
	var selection := scene.get_node("%SelectedRegion") as Label
	var energy := scene.get_node("%Energy") as Label
	var first_region: MatchRegion = scene.get_region(FIRST_CLAIM)
	var material := first_region.geometry.material_override as StandardMaterial3D
	var camera := root.get_camera_3d()

	_check(claim.disabled and claim.text == "Claim · %d" % MatchEconomy.CLAIM_COST
		and selection.text == "Select a region", "Claim shows its price and requires a selection.")
	await _click_region(camera, scene.get_region(NEXT_CLAIM))
	_check(claim.disabled and selection.text.contains("Not adjacent"),
		"Selecting a distant neutral tile keeps Claim disabled.")
	await _click_region(camera, first_region)
	_check(not claim.disabled and selection.text.begins_with("Region 1") and material.emission_enabled
		and material.albedo_color == MatchRegion.OWNER_COLORS[NEUTRAL],
		"Clicking an adjacent neutral tile highlights it and enables Claim.")
	_click(claim.get_global_rect().get_center())
	_check(claim.disabled and selection.text.contains("Player-owned") and energy.text == "Energy 0"
		and material.albedo_color == MatchRegion.OWNER_COLORS[PLAYER],
		"Clicking Claim updates the HUD and recolors the selected tile.")
	await _click_region(camera, scene.get_region(OTHER_ADJACENT))
	_check(claim.disabled and selection.text.contains("Need more energy") and not material.emission_enabled,
		"Moving selection clears the previous highlight and shows the affordability restriction.")
	scene._process(17.0)
	_check(not claim.disabled, "Passive income re-enables Claim for the selected tile.")
	_click(Vector2(20, 140))
	await physics_frame
	await physics_frame
	_check(claim.disabled and selection.text == "Select a region", "Clicking off the map clears selection.")
	await _click_region(camera, first_region)
	_click(restart.get_global_rect().get_center())
	scene.set_process(false)
	_check(claim.disabled and selection.text == "Select a region" and energy.text == "Energy 50"
		and not material.emission_enabled and material.albedo_color == MatchRegion.OWNER_COLORS[NEUTRAL],
		"The Restart control clears selection and restores neutral color and starting energy.")


func _click_region(camera: Camera3D, region: MatchRegion) -> void:
	_click(camera.unproject_position(region.global_position))
	await physics_frame
	await physics_frame


func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)


func _check_rejected(scene: Node, side: MatchRegion.Owner, region_id: StringName,
		owner: MatchRegion.Owner, context: String) -> void:
	var player_energy: float = scene.economy.energy(PLAYER)
	var cpu_energy: float = scene.economy.energy(CPU)
	_check(not scene.try_claim(side, region_id) and scene.owns_region(owner, region_id)
		and scene.economy.energy(PLAYER) == player_energy and scene.economy.energy(CPU) == cpu_energy,
		"%s leaves ownership and energy unchanged." % context)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
