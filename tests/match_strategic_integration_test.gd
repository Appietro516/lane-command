extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
const Catalog := preload("res://match/unit_catalog.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layout := TerritoryLayout.new(131, 7, Vector2(60, 36), 1, 1, 4, MapSettings.Shape.CIRCLE)
	var scene: Node = load("res://main.tscn").instantiate()
	scene.configure_match(MatchSettings.new(layout.settings, [1, 2, 3, 5]), layout)
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	_check(battle._bases.size() == 5 and scene._intelligence.size() == 5, "five factions have separate intelligence")
	_check(scene._intelligence[P].starts.size() == 5 and scene._strength.ranked().size() == 5, "five public starts and strengths")
	var scouts := battle.active_units().filter(func(unit: MatchBattle.Unit) -> bool:
		return unit.type_id == Catalog.SCOUT)
	_check(scouts.size() == 10, "the neutral roster leaves each faction two scouts")

	var pos: Vector2 = battle._bases[P]
	var site := pos.lerp(Vector2.ZERO, 0.45)
	var producer := battle.add_barracks(P, site)
	var rally := site + Vector2(0, -3.2)
	_check(battle.set_producer_rally(P, producer.id, rally), "producer accepts a rally point")
	var interval := producer.interval(scene.economy)
	scene.economy.grant_resource(P, MatchEconomy.ENERGY, 80)
	scene.economy.grant_resource(P, MatchEconomy.FOOD, 40)
	_check(battle.upgrade_producer(P, producer.id, scene.economy)
		and producer.interval(scene.economy) < interval, "per-building production upgrade still shortens its cycle")
	battle.advance(producer.interval(scene.economy), scene.economy)
	var recruit: MatchBattle.Unit
	for unit in battle.active_units():
		if unit.side == P and unit.type_id == Catalog.INFANTRY:
			recruit = unit
	_check(recruit != null and recruit.stance == MatchBattle.Stance.IDLE, "rallied production keeps the Idle default")
	if recruit != null:
		battle.advance(MatchBattle.STEP, scene.economy)
		_check(recruit.order == MatchBattle.Order.MOVE and recruit.following_rally, "recruit follows rally before Idle")

	for side in battle._bases:
		if side != P:
			battle._base_health[side].hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(battle.outcome() == MatchBattle.Outcome.VICTORY and battle.is_finished(), "all four CPU defeats give victory")
	scene.restart_match()
	_check(scene._battle != battle and scene._battle.outcome() == MatchBattle.Outcome.IN_PROGRESS
		and scene._battle.base_hp(C) == MatchBattle.BASE_HP, "restart restores a clean five-faction match")
	scene.queue_free()
	print("Strategic integration test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
