extends SceneTree
## Run with Godot's Compatibility renderer and --disable-vsync for frame intervals.

const MatchScene := preload("res://main.tscn")
const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const EVENTS := ["wall", "chain", "mortar", "nest", "military", "resource", "outpost", "units"]
const INTERVAL := 32
const WARMUP := 24

var _scene: Node3D
var _battle: MatchBattle
var _victims: Array[Array] = []
var _frames: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var regions := int(args[0]) if args.size() > 0 else 24
	var dense := args.has("dense")
	var interval := 8 if args.has("quick") else INTERVAL
	var warmup := 8 if args.has("quick") else WARMUP
	var seed_value := 17
	root.size = Vector2i(640, 400)
	if args.has("quick"):
		root.content_scale_size = root.size
	_scene = MatchScene.instantiate()
	_scene.region_count = regions
	_scene.map_seed = seed_value
	if regions > 24:
		_scene.map_width = 100.0
		_scene.map_height = 64.0
	root.add_child(_scene)
	_scene.set_process(false)
	_scene._time_until_cpu_decision = INF
	_scene.claim_completed.disconnect(_scene._discover_on_claim)
	_battle = _scene._battle
	_populate(dense)
	print(JSON.stringify({"regions": _scene._layout.cells.size(), "dense": dense, "seed": seed_value,
		"units": _battle.active_units().size(), "fortifications": _scene._fortifications.size(),
		"obstacles": _battle.navigation._obstacles.size(), "renderer": RenderingServer.get_video_adapter_name(),
		"godot": Engine.get_version_info().string}))

	var previous := Time.get_ticks_usec()
	for frame in range(warmup + interval * EVENTS.size()):
		var event := ""
		if frame >= warmup and (frame - warmup) % interval == 0:
			var index := (frame - warmup) / interval
			event = EVENTS[index]
			# Set lethal HP just before a normal fixed step. Cleanup, movement
			# replans, scene callbacks, HUD and rendering use the real match.
			for victim in _victims[index]:
				victim.hp = 0.0
		var start := Time.get_ticks_usec()
		_scene._process(MatchBattle.STEP)
		var update_us := Time.get_ticks_usec() - start
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var drawn := Time.get_ticks_usec()
		if frame >= warmup - 3:
			_frames.append({"frame": frame - warmup, "event": event, "update_us": update_us,
				"render_tail_us": drawn - start - update_us, "frame_us": drawn - previous})
		previous = drawn
		await process_frame

	for frame in _frames:
		print(JSON.stringify(frame))
	quit()


func _populate(dense: bool) -> void:
	var positions: Array[Vector2] = [Vector2(0, -4), Vector2(0, -3), Vector2(0, -2),
		Vector2(0, -1), Vector2(5, -5), Vector2(5, 5), Vector2(-6, 7), Vector2(6, 7)]
	var kinds: Array[StringName] = [Rules.WALL, Rules.WALL, Rules.WALL, Rules.WALL,
		Rules.MORTAR, Rules.NEST, &"training_range", &"generator"]
	var objects: Array[MatchBattle.Fortification] = []
	for i in kinds.size():
		objects.append(_structure(kinds[i], positions[i], PI * 0.5 if i < 4 else 0.0))

	# This mutually touching chain remains across the ordered movement lanes.
	for y in range(0, 5):
		_structure(Rules.WALL, Vector2(0, y), PI * 0.5)
	if dense:
		for x in range(-24, 25, 4):
			for y in [-13, -9, 10, 14]:
				_structure(Rules.WALL, Vector2(x, y), 0.0)

	var claim_cell: TerritoryLayout.Cell
	for cell: TerritoryLayout.Cell in _scene._layout.cells:
		var is_neutral: bool = _scene.get_region(cell.id).region_owner == MatchRegion.Owner.NEUTRAL
		if is_neutral and cell.site.x > 10.0 and absf(cell.site.y) < 7.0:
			claim_cell = cell
			break
	_scene._complete_claim(PLAYER, claim_cell.id, -1, claim_cell.site)
	_structure(Rules.WALL, claim_cell.site + Vector2(1.7, 0), 0.0, [claim_cell.id])

	for i in (27 if dense else 6):
		var unit := _battle.spawn_unit(PLAYER, Vector2(-7.0 - i * 0.07, 0.6 + (i % 6) * 0.46),
			Catalog.COMBAT_TYPES[i % 3])
		_battle.issue_move(unit.id, Vector2(11.0, unit.position.y))
	var dead_units: Array[MatchBattle.Unit] = []
	for i in (108 if dense else 9):
		var position := Vector2(-12.0 + (i % 19) * 1.2, -6.0 - (i / 19) * 0.45)
		var unit := _battle.spawn_unit(PLAYER, position, Catalog.COMBAT_TYPES[i % 3])
		if unit != null:
			unit.stance = MatchBattle.Stance.IDLE
			dead_units.append(unit)

	_victims = [[objects[0]], [objects[1], objects[2], objects[3]], [objects[4]], [objects[5]],
		[objects[6]], [objects[7]], [_scene._outposts_by_region[claim_cell.id]], dead_units]


func _structure(kind: StringName, point: Vector2, angle: float,
		regions: Array[StringName] = []) -> MatchBattle.Fortification:
	var profile: Dictionary = Rules.PROFILES.get(kind, _scene.BUILDINGS[kind])
	var structure := _battle.add_producer(kind, profile, PLAYER, point) if profile.has("unit_type") \
		else _battle.add_structure(kind, profile, PLAYER, point, angle)
	var covered: Array[StringName] = [_scene._layout.region_at(point)]
	_scene._add_structure_view(structure, regions, covered)
	for resource in profile.get("income", {}):
		_scene.faction_stats.set_modifier(structure.source_id, PLAYER, resource, profile.income[resource],
			&"building", profile.label)
	return structure
