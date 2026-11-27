extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
const Catalog := preload("res://match/unit_catalog.gd")
var _failures := 0
var _winner := MatchRegion.Owner.NEUTRAL


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bounds := Rect2(-30, -18, 60, 36)
	var battle := MatchBattle.new(Vector2(-20, 0), Vector2(20, 0), 4.0, bounds)
	battle.enable_visibility(bounds)
	var economy := MatchEconomy.new(battle.stats)
	var point := Vector2(6, 0)
	battle.objectives.add_camp(point, true)
	battle.objectives.add_camp(Vector2(-5, 11), false)
	battle.objectives.boon_collected.connect(func(side: MatchRegion.Owner, _id: int, _cycle: int) -> void:
		_winner = side)
	battle.objectives.advance(battle, economy, 0.0)
	var stronghold := battle.objectives.camps[0]
	var minor := battle.objectives.camps[1]
	var guardian := battle.get_unit(stronghold.guard_id)
	var scout := battle.spawn_unit(P, Vector2(3.4, 0), Catalog.RANGED)
	_check(battle.can_see(P, point) and not battle.can_see(C, point), "camp sight is faction-specific")
	_check(guardian.hp > battle.get_unit(minor.guard_id).hp * 2.0, "stronghold is significantly stronger")
	guardian.hp = 1.0
	_check(battle.order_attack(P, scout.id, guardian.id), "visible guardian can be attacked")
	battle.advance(0.5, economy)
	_check(stronghold.guard_id == MatchBattle.NO_TARGET and stronghold.drop_until > 0.0
		and _winner == MatchRegion.Owner.NEUTRAL, "defeat drops boon without rewarding killer")
	var rival := battle.spawn_unit(C, point + Vector2(0.3, 0))
	scout.position = point + Vector2(0.7, 0)
	battle.advance(0.25, economy)
	_check(_winner == C and battle.objectives.pickups == 1 and stronghold.drop_until == 0.0, "closest faction wins contested pickup once")
	var now := battle.elapsed_time()
	_check(battle.objectives.has_boon(C, NeutralObjectives.Reward.SIEGE, now) and
		battle.structure_damage_multiplier(rival, MatchBattle.BASE_TARGET) >
		battle.structure_damage_multiplier(scout, MatchBattle.BASE_TARGET), "siege boon improves hub damage")
	_check(not battle.objectives.has_boon(C, NeutralObjectives.Reward.SIEGE, now + 76.0), "siege boon expires")
	battle.objectives.advance(battle, economy, stronghold.respawns_at + 0.5)
	_check(stronghold.guard_id != MatchBattle.NO_TARGET and stronghold.cycle == 2, "guard respawns")
	battle.get_unit(minor.guard_id).hp = 0
	battle.advance(MatchBattle.STEP, economy)
	_check(minor.drop_until > battle.elapsed_time(), "minor camp also drops a reward")
	battle.objectives.advance(battle, economy, minor.drop_until + 0.1)
	_check(battle.objectives.pickups == 1, "unclaimed boon expires")
	print("Jungle test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
