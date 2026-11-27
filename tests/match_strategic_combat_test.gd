extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
const Catalog := preload("res://match/unit_catalog.gd")
const Rules := preload("res://match/fortification_rules.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bounds := Rect2(-30, -18, 60, 36)
	var battle := MatchBattle.new(Vector2(-20, 0), Vector2(20, 0), 4.0, bounds)
	battle.enable_visibility(bounds)
	var economy := MatchEconomy.new(battle.stats)
	var infantry := battle.spawn_unit(P, Vector2.ZERO)
	var heavy := battle.spawn_unit(P, Vector2(0, 2), Catalog.HEAVY)
	var raider := battle.spawn_unit(C, Vector2(13, 0), Catalog.RAIDER)
	_check(infantry.stance == MatchBattle.Stance.IDLE and infantry.definition.speed == 1.584, "idle and slower")
	_check(not battle.order_attack(P, infantry.id, raider.id), "no blind targeting")
	battle.advance(0.5, economy)
	_check(infantry.position == Vector2.ZERO, "idle units do not seek")
	raider.position = Vector2(0.75, 0)
	_check(battle.order_attack(P, heavy.id, raider.id), "sighted targets accept attack orders")
	battle.advance(MatchBattle.STEP, economy)
	_check(raider.hp < raider.definition.hp and infantry.hp < infantry.definition.hp, "idle units return fire")
	var rb: Dictionary = Catalog.DEFINITIONS[Catalog.RAIDER]
	var ib: Dictionary = Catalog.DEFINITIONS[Catalog.INFANTRY]
	var hb: Dictionary = Catalog.DEFINITIONS[Catalog.HEAVY]
	var ranged: Dictionary = Catalog.DEFINITIONS[Catalog.RANGED]
	_check(Catalog.damage_multiplier(rb, ib) > 2.0 and Catalog.damage_multiplier(hb, rb) > 1.5
		and Catalog.damage_multiplier(ranged, rb) > 2.0, "class counters are data driven")
	_check(Catalog.damage_multiplier(Rules.PROFILES[Rules.ANTI_TANK], hb) > 4.0, "anti-tank hard counter")
	_check(battle.structure_damage_multiplier(infantry, MatchBattle.BASE_TARGET) < 0.5
		and battle.structure_damage_multiplier(heavy, MatchBattle.BASE_TARGET) > 1.5, "fortified hubs favor siege")
	var envoy := battle.spawn_unit(C, Vector2(-16, 0), Catalog.HEAVY)
	battle.advance(MatchBattle.STEP, economy)
	_check(envoy.hp < envoy.definition.hp and battle.base_hp(P) == 420, "starting base fires")
	var outpost := battle.add_outpost(&"probe", P, Vector2(-4, -6), MatchBattle.DEFAULT_OUTPOST_HP)
	envoy.position = Vector2(-1, -6)
	battle.advance(MatchBattle.STEP, economy)
	_check(envoy.hp <= envoy.definition.hp - 8.5 and outpost.max_hp == 40, "outpost fires")
	print("Strategic combat test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
