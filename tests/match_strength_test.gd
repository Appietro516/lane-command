extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(is_equal_approx(FactionStrength.score(1, 0, 0, 0), 350.0)
		and is_equal_approx(FactionStrength.score(0, 1, 0, 0), 300.0)
		and is_equal_approx(FactionStrength.score(0, 0, 1, 1), 350.0), "category weights")
	var strength := FactionStrength.new()
	var economy := MatchEconomy.new()
	strength.scores[P] = 240.0
	strength.scores[C] = 600.0
	strength._update_trends(0.0)
	var energy := economy.energy(P)
	_check(not strength.award(economy, P, &"region/test", 35.0), "sustained gap required")
	_check(strength.award(economy, P, &"region/test", 36.0, true) and economy.energy(P) == energy + 30.0,
		"landmark bounty pays three-resource grant")
	_check(not strength.award(economy, P, &"camp/test", 90.0), "cooldown")
	_check(not strength.award(economy, P, &"region/test", 200.0), "once per objective")
	for index in 6:
		strength.award(economy, P, StringName("camp/%d" % index), 200.0 + index * 91.0)
	_check(strength.awarded == FactionStrength.BOUNTY_LIMIT, "per-match bounty cap")
	_check(not strength.award(economy, C, &"region/test", 999.0), "leader receives no comeback bounty")

	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	_check(not scene._score_list.visible and scene._score_list.get_child_count() == 2, "score panel initially collapsed")
	var button: Button = scene._score_panel.get_child(0).get_child(0)
	button.button_pressed = true
	_check(scene._score_list.visible and scene._score_list.get_child(0).text.begins_with("1. "), "scores can be expanded")
	scene.restart_match()
	_check(scene._strength.awarded == 0 and scene._strength.ranked().size() == 2, "restart clears bounties")
	scene.queue_free()
	print("Strength test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
