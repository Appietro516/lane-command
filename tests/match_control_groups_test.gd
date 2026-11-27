extends SceneTree

const P := MatchBattle.PLAYER
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var units := battle.visible_units(P)
	var first: MatchBattle.Unit
	var second: MatchBattle.Unit
	for unit in units:
		if unit.side != P:
			continue
		if first == null:
			first = unit
		else:
			second = unit
			break
	scene._select_unit(first.id)
	_check(scene._control_group_shortcut(_key(KEY_1, true)), "Ctrl+1 assigns")
	scene._select_unit(second.id)
	scene._control_group_shortcut(_key(KEY_1, false, true))
	_check(scene._control_groups[0].size() == 2, "Shift+1 extends membership")
	scene._control_group_shortcut(_key(KEY_1))
	scene._control_group_shortcut(_key(KEY_1))
	_check(scene._selected_units.size() == 2 and scene._group_buttons[0].button_pressed, "recall and highlight")
	var camera := scene.get_node("Camera") as StrategyCamera
	_check(camera._target_focus.is_equal_approx((first.position + second.position) * 0.5), "double tap centers group")
	scene._select_unit(second.id)
	scene._control_group_shortcut(_key(KEY_2, true))
	_check(scene._control_groups[0].size() == 1 and scene._control_groups[1].has(second.id), "reassignment replaces membership")
	second.hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene._control_groups[1].is_empty(), "death removes group member")
	var field := LineEdit.new()
	scene.get_node("HUD").add_child(field)
	field.grab_focus()
	_check(not scene._control_group_shortcut(_key(KEY_1)), "typing leaves groups alone")
	field.release_focus()
	scene.restart_match()
	_check(scene._control_groups[0].is_empty(), "restart clears groups")
	scene.queue_free()
	print("Control group test failures: %d" % _failures)
	quit(int(_failures > 0))


func _key(key: Key, control := false, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key
	event.ctrl_pressed = control
	event.shift_pressed = shift
	return event


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
