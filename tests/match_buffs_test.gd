extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MATCH_FIXTURE := preload("res://tests/prototype_match_fixture.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const DPS := FactionStats.UNIT_DPS
const BUILDING_HP := FactionStats.BUILDING_MAX_HP
const ENERGY := FactionStats.ENERGY
const MATERIALS := FactionStats.MATERIALS
const FOOD := FactionStats.FOOD

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_provenance()
	_test_combat_and_health(PLAYER, CPU)
	_test_combat_and_health(CPU, PLAYER)
	_test_match_lifecycle()
	if failures == 0:
		print("Faction stat stacking, provenance, combat, economy, health and lifecycle checks completed.")
	quit(1 if failures else 0)


func _test_provenance() -> void:
	var stats := FactionStats.new()
	var reversed := FactionStats.new()
	for id in [&"z", &"a"]:
		stats.set_modifier(id, PLAYER, DPS, 1.0, &"landmark", "Landmark", "Region bonus")
	for id in [&"a", &"z"]:
		reversed.set_modifier(id, PLAYER, DPS, 1.0, &"landmark", "Landmark", "Region bonus")
	var result := stats.inspect(PLAYER, DPS, 3.0)
	_check(result == reversed.inspect(PLAYER, DPS, 3.0) and result.total == 5.0
		and _ids(result) == [&"base", &"a", &"z"], "Stacking and provenance order are deterministic.")
	var entry: Dictionary = result.breakdown[1]
	_check(entry.source_type == &"landmark" and entry.source_name == "Landmark"
		and entry.owner == PLAYER and entry.stat == DPS and entry.magnitude == 1.0
		and entry.active and entry.description == "Region bonus", "Provenance includes source metadata.")
	entry.magnitude = 900.0
	result.breakdown.clear()
	_check(stats.inspect(PLAYER, DPS, 3.0) == reversed.inspect(PLAYER, DPS, 3.0),
		"Inspection returns detached data.")
	stats.set_modifier(&"a", PLAYER, DPS, 1.0, &"landmark", "Landmark", "Region bonus")
	stats.remove_source(&"z", DPS)
	_check(stats.value(PLAYER, DPS, 3.0) == 4.0 and stats.value(CPU, DPS, 3.0) == 3.0,
		"Repeated registration is idempotent and removal preserves the other source.")
	stats.set_modifier(&"a", CPU, DPS, 2.0, &"upgrade", "Training")
	_check(stats.value(PLAYER, DPS, 3.0) == 3.0 and stats.value(CPU, DPS, 3.0) == 5.0,
		"Replacing a contribution can move it to the other faction.")
	stats.set_source_active(&"a", false)
	result = stats.inspect(CPU, DPS, 3.0)
	_check(result.total == 3.0 and not result.breakdown[1].active
		and result.breakdown[1].magnitude == 0.0 and result.breakdown[1].configured_magnitude == 2.0,
		"Disabled sources remain inspectable without contributing.")
	stats.set_modifier(&"drain", CPU, BUILDING_HP, -20.0)
	result = stats.inspect(CPU, BUILDING_HP, 10.0)
	_check(result.total == 1.0 and _sum(result) == result.total, "HP floors remain attributable.")


func _test_combat_and_health(attacker: MatchRegion.Owner, defender: MatchRegion.Owner) -> void:
	var stats := FactionStats.new()
	var economy := MatchEconomy.new(stats)
	var battle := MatchBattle.new(Vector2(-10, 2), Vector2(10, 2),
		MatchBattle.DEFAULT_AGGRO_RADIUS, MatchBattle.DEFAULT_BOUNDS, stats)
	var direction := 1.0 if attacker == PLAYER else -1.0
	battle.add_barracks(attacker, Vector2(-8 * direction, -3))
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	var first := battle.get_unit(1)
	first.attack_interval = 0.5
	stats.set_modifier(&"alpha", attacker, DPS, 1.0)
	stats.set_modifier(&"beta", attacker, DPS, 1.0)
	stats.set_modifier(&"armor", defender, BUILDING_HP, 4.5)
	var outpost := battle.add_outpost(&"center", defender, Vector2(direction, 0), 12)
	stats.set_modifier(outpost.source_id, defender, ENERGY, 1.0, &"building", "Outpost")
	var attack := battle.unit_attack_stat(first)
	_check(attack.total == 4.0 and _sum(attack) == attack.total and attack.breakdown[1].magnitude == 0.5
		and battle.unit_dps_stat(first).total == 8.0, "DPS bonuses scale by attack interval.")
	_check(battle.base_hp(defender) == 80.0 and battle.base_health_stat(defender).total == 84.5
		and outpost.hp == 16.5 and outpost.health_stat().total == 16.5,
		"Existing bases keep current HP and new outposts start at their effective cap.")

	first.position = Vector2(0, 0)
	battle.advance(MatchBattle.STEP, economy)
	_check(outpost.hp == 12.5 and first.cooldown == 0.5,
		"Existing units deal the inspected per-hit damage at their attack interval.")
	stats.remove_source(&"armor")
	stats.set_modifier(&"armor", defender, BUILDING_HP, 4.5)
	_check(outpost.hp == 12.0 and outpost.max_hp == 16.5,
		"Removing a cap clamps HP and restoring the cap does not heal.")
	stats.remove_source(&"alpha")
	battle.advance(0.5, economy)
	_check(outpost.hp == 8.5, "The next hit uses the remaining source without rounding.")
	battle.advance(1.5, economy)
	_check(outpost.hp == 0.0 and battle.get_outpost(outpost.id) == null
		and economy.income_rate(defender, ENERGY) == 3.0, "Destroyed structures revoke their contributions.")
	battle.advance(2.0, economy)
	var second := battle.get_unit(2)
	_check(second != null and battle.unit_dps_stat(second).total == 4.0,
		"New production uses the same live buffs.")


func _test_match_lifecycle() -> void:
	var scene := MATCH_FIXTURE.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var economy: MatchEconomy = scene.economy
	var battle: MatchBattle = scene._battle
	var stats: FactionStats = scene.faction_stats
	var region := &"region_1"
	_check(ScoutFixture.claim(scene, PLAYER, region), "The region can be claimed through the match.")
	scene.set_region_modifier(region, ENERGY, 1.0, "Reactor")
	scene.set_region_modifier(region, MATERIALS, 1.0, "Reactor")
	stats.set_modifier(&"trade", PLAYER, ENERGY, 1.0, &"upgrade", "Trade")
	var timer := battle.add_barracks(PLAYER, Vector2(-8, -3))
	stats.set_modifier(timer.source_id, PLAYER, FOOD, 1.0, &"building", "Barracks")
	scene._refresh_hud()
	var energy_readout := scene.get_node("%Resources/energy") as Control
	_check(energy_readout.get_node("Rate").text == "+5/s"
		and energy_readout.tooltip_text == "Energy income\nPassive trickle  +3/s\nReactor  +1/s · Region 1\nTrade  +1/s\nTotal  +5/s",
		"HUD and stockpile updates use the same attributed income.")
	economy.advance(2.0)
	_check(economy.energy(PLAYER) == 10.0 and economy.energy(CPU) == 56.0
		and economy.try_spend(PLAYER, {ENERGY: 8, FOOD: 24})
		and economy.energy(PLAYER) == 2.0 and economy.stockpile(PLAYER, FOOD) == 0.0,
		"Buffed flow changes affordability and normal purchases debit stockpiles.")
	battle.set_barracks_active(timer, false)
	_check(economy.income_rate(PLAYER, FOOD) == 1.0
		and not economy.income_stat(PLAYER, FOOD).breakdown[1].active,
		"Disabling a building removes its rate from income immediately.")
	battle.set_barracks_active(timer, true)
	battle.set_barracks_active(timer, true)
	_check(economy.income_rate(PLAYER, FOOD) == 2.0, "Repeated activation never duplicates income.")

	scene._set_region_owner(region, NEUTRAL)
	_check(economy.income_rate(PLAYER, ENERGY) == 4.0 and economy.income_rate(PLAYER, MATERIALS) == 2.0
		and _ids(economy.income_stat(PLAYER, ENERGY)) == [&"base", &"trade"],
		"Neutral regions lose their effects and disappear from faction provenance.")
	scene._set_region_owner(region, CPU)
	_check(economy.income_rate(CPU, ENERGY) == 4.0 and economy.income_rate(CPU, MATERIALS) == 3.0
		and economy.income_rate(PLAYER, ENERGY) == 4.0, "The new owner receives all region effects.")
	stats.remove_source(scene.region_source_id(region))
	_check(economy.income_rate(CPU, ENERGY) == 3.0 and economy.income_rate(CPU, MATERIALS) == 2.0,
		"Removing a whole source clears every contribution.")
	stats.set_modifier(&"trade", CPU, BUILDING_HP, 5.0, &"upgrade", "Armor")
	stats.set_modifier(&"training", PLAYER, DPS, 1.5, &"upgrade", "Training")
	economy.advance(4.0)
	battle.advance(MatchEconomy.PRODUCTION_INTERVAL, economy)
	scene._select_unit(ScoutFixture.combat_units(battle)[0].id)
	scene._refresh_hud()
	var unit_stats := scene.get_node("%UnitStats") as Label
	var cpu_health := scene.get_node("%CPUHP") as Label
	_check(unit_stats.text.contains("Attack  4.5")
		and unit_stats.tooltip_text.contains("Damage per second\nBase  3\nTraining  +1.5\nTotal  4.5")
		and cpu_health.tooltip_text == "Maximum HP\nBase  80\nArmor  +5\nTotal  85",
		"Unit and base inspectors report the same attributed stats used by combat.")
	scene.restart_match()
	scene.set_process(false)
	_check(scene.faction_stats != stats and scene.economy.income_rate(PLAYER, ENERGY) == 3.0
		and scene.economy.income_rate(PLAYER, FOOD) == 1.0
		and scene._battle.base_health_stat(CPU).total == MatchBattle.BASE_HP,
		"Restart clears effects and provenance from the previous match.")
	scene.free()


func _ids(result: Dictionary) -> Array:
	return result.breakdown.map(func(entry: Dictionary) -> StringName: return entry.source_id)


func _sum(result: Dictionary) -> float:
	var total := 0.0
	for entry: Dictionary in result.breakdown:
		total += entry.magnitude
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
