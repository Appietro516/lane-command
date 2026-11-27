extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bounds := Rect2(-30, -18, 60, 36)
	var battle := MatchBattle.new(Vector2(-20, 0), Vector2(20, 0), 4.0, bounds)
	battle.enable_visibility(bounds)
	var profile := {"hp": 25, "size": Vector2.ONE}
	var radar := battle.add_structure(BattleRadar.RADAR, profile, P, Vector2(-18, -4))
	var station := battle.add_structure(BattleRadar.COUNTERINTELLIGENCE, profile, C, Vector2(18, 4))
	var enemy := battle.spawn_unit(C, Vector2(14, 5))
	var bait := Vector2(8, -8)
	var failures := 0
	failures += _check(battle.deploy_decoy(C, station.id, bait), "deploy decoy")
	failures += _check(not battle.deploy_decoy(C, station.id, bait), "decoy cooldown")
	battle.radar.advance(battle, battle.active_units(), 0.0)
	battle.radar.advance(battle, battle.active_units(), 7.9)
	failures += _check(battle.radar.contacts_for(P).is_empty(), "no tracking before first pulse")
	battle.radar.advance(battle, battle.active_units(), 8.0)
	var contacts := battle.radar.contacts_for(P)
	failures += _check(contacts.size() == 2, "one live snapshot and one spoofed contact")
	var original := enemy.position
	enemy.position = Vector2(13, 6)
	battle.radar.advance(battle, battle.active_units(), 9.0)
	failures += _check(not contacts.is_empty() and contacts[0].point == original, "contact remains at its recorded position")
	failures += _check(not battle.can_see(P, original), "radar grants no direct sight")
	var tower_profile := {"hp": 25, "size": Vector2.ONE, "vision": 11.0}
	var tower := battle.add_structure(BattleRadar.WATCHTOWER, tower_profile, P, bait)
	battle.radar.advance(battle, battle.active_units(), 10.0)
	failures += _check(battle.radar.contacts_for(P).size() == 1 and battle.can_see(P, bait), "direct sight verifies decoy")
	battle.set_fortification_active(tower, false)
	battle.set_fortification_active(radar, false)
	battle.radar.advance(battle, battle.active_units(), 24.0)
	failures += _check(battle.radar.contacts_for(P).is_empty() and battle.radar.pulse_count == 1, "station loss stops future pulses")
	print("Recon test failures: %d" % failures)
	quit(int(failures > 0))


func _check(condition: bool, message: String) -> int:
	if not condition:
		push_error(message)
	return int(not condition)
