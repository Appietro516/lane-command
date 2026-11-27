extends SceneTree

const FIXTURE := preload("res://tests/prototype_match_fixture.tscn")
const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const Stance := MatchBattle.Stance
const Order := MatchBattle.Order

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var scene := FIXTURE.instantiate()
	# Exercise formation and rally timing on routes with no neutral encounters.
	scene.neutral_objectives_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	var battle: MatchBattle = scene._battle
	var first := battle.spawn_unit(PLAYER, Vector2(-4, 0), Catalog.INFANTRY, null, Stance.IDLE)
	var second := battle.spawn_unit(PLAYER, Vector2(-2, 0), Catalog.HEAVY, null, Stance.IDLE)
	var third := battle.spawn_unit(PLAYER, Vector2(3, 0), Catalog.RANGED, null, Stance.IDLE)
	var enemy := battle.spawn_unit(CPU, Vector2(-3, 0), Catalog.RANGED, null, Stance.IDLE)
	await process_frame
	var camera := root.get_camera_3d()
	var a := camera.unproject_position(scene._unit_views[first.id].global_position)
	var b := camera.unproject_position(scene._unit_views[second.id].global_position)
	var c := camera.unproject_position(scene._unit_views[third.id].global_position)
	_drag(scene, Rect2(a.min(b), (a - b).abs()).grow(10))
	_check(scene._selected_units.size() == 2 and not scene._selected_units.has(enemy.id),
		"Right drag selects only friendly units and displays the rectangle.")
	_check("Heavy × 1" in scene._unit_intent.text and "Infantry × 1" in scene._unit_intent.text
		and "38 / 38" in scene._unit_stats.text, "Mixed groups show counts and aggregate HP.")
	_drag(scene, Rect2(c - Vector2.ONE * 9, Vector2.ONE * 18), true)
	_check(scene._selected_units.size() == 3, "Shift adds to the command group.")
	_drag(scene, Rect2(b - Vector2.ONE * 9, Vector2.ONE * 18), true, true)
	_check(scene._selected_units.size() == 2 and not scene._selected_units.has(second.id),
		"Ctrl subtracts even when Shift is also held.")
	var stance: OptionButton = scene._stance_picker
	stance.item_selected.emit(stance.get_item_index(Stance.SEEK_STRONGEST))
	_check(first.stance == Stance.SEEK_STRONGEST and third.stance == Stance.SEEK_STRONGEST,
		"The inspector applies a group stance.")
	stance.item_selected.emit(stance.get_item_index(Stance.IDLE))
	# The enemy already served the mixed-selection check. Keep the movement fixture outside weapon range.
	enemy.position = Vector2(8, 5)
	var resume: CheckBox = scene.get_node("%ResumeStance")
	_check(resume.button_pressed, "Move resumes stance by default.")
	var goal := camera.unproject_position(scene._world_position(Vector2(-1, 3.6)))
	_mouse(goal, true)
	_mouse(goal, false)
	_check(first.order == Order.AUTONOMOUS and battle._queued_orders.size() == 2,
		"Right-click queues one formation command without synchronous route searches.")
	battle.advance(MatchBattle.STEP, scene.economy)
	var formation := [first.ordered_destination, third.ordered_destination]
	_check(first.order == Order.MOVE and third.order == Order.MOVE and formation[0] != formation[1],
		"Units start moving to distinct formation positions before resuming stance.")
	battle.advance(6.5, scene.economy)
	_check(first.order == Order.AUTONOMOUS and third.order == Order.AUTONOMOUS
		and first.position == formation[0] and third.position == formation[1],
		"Both units resume their idle stance only after reaching their formation slots.")
	resume.button_pressed = false
	first.hp = 0
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.selected_unit() == third and not resume.button_pressed,
		"Destruction removes the casualty and preserves the explicit resume preference.")
	_test_rally(scene, battle)
	scene.free()
	if failures == 0:
		print("Group selection, movement, stance preferences and producer rally checks passed.")
	quit(int(failures > 0))


func _test_rally(scene: Node, battle: MatchBattle) -> void:
	var producer := battle.add_barracks(PLAYER, Vector2(-11.0, -3.8))
	var target := Vector2(7, -4)
	_check(battle.set_producer_stance(PLAYER, producer.id, Stance.IDLE)
		and battle.set_producer_rally(PLAYER, producer.id, target)
		and not battle.set_producer_rally(CPU, producer.id, Vector2.ZERO)
		and not battle.set_producer_rally(PLAYER, producer.id, Vector2(100, 100)),
		"An owned producer can rally across borders and rejects enemy edits and invalid targets.")
	producer.elapsed = producer.interval(scene.economy)
	battle.advance(MatchBattle.STEP, scene.economy)
	var recruit := battle.active_units().back() as MatchBattle.Unit
	_check(recruit.order == Order.MOVE and recruit.ordered_destination == target,
		"The new unit starts moving toward the producer rally point.")
	_check(battle.set_producer_rally(PLAYER, producer.id, Vector2.INF)
		and recruit.ordered_destination == target, "Clearing the rally leaves the published order intact.")
	battle.set_fortification_active(producer, false)
	battle.advance(18.0, scene.economy)
	_check(recruit.position == target and recruit.order == Order.AUTONOMOUS and recruit.stance == Stance.IDLE,
		"The rally recruit enters the producer's configured stance on arrival.")


func _drag(scene: Node, rectangle: Rect2, shift := false, ctrl := false) -> void:
	_mouse(rectangle.position, true, shift, ctrl)
	var motion := InputEventMouseMotion.new()
	motion.position = rectangle.end
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion, true)
	_check(scene._selection_box.visible, "The rectangle is visible during a right drag.")
	_mouse(rectangle.end, false, shift, ctrl)
	_check(not scene._selection_box.visible, "Releasing closes the selection rectangle.")


func _mouse(point: Vector2, pressed: bool, shift := false, ctrl := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
