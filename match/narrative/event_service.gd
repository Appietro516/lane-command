class_name NarrativeEvents
extends RefCounted
## One instance per match. The producer supplies a stable, unique occurrence ID.

signal queue_changed

enum Status { PENDING, RESOLVED }

class Decision:
	var definition: NarrativeEvent
	var origin: StringName
	var region: StringName
	var side: MatchRegion.Owner
	var status := Status.PENDING
	var selected_option: StringName


var _seed: int
var _economy: MatchEconomy
var _events: Array[NarrativeEvent] = []
var _decisions: Dictionary[StringName, Decision] = {}
var _player_queue: Array[StringName] = []
var _expirations: Dictionary[StringName, float] = {}
var _time := 0.0
var _active := true
var _applying := false


func _init(match_seed: int, economy: MatchEconomy, catalog: NarrativeCatalog) -> void:
	_seed = match_seed
	_economy = economy
	if catalog == null:
		return
	var errors := catalog.validation_errors()
	if not errors.is_empty():
		push_error("Invalid narrative catalog: %s" % "; ".join(errors))
		return
	# Snapshot the catalog and sort by ID so editor ordering cannot affect selection.
	var snapshot := catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as NarrativeCatalog
	_events = snapshot.events
	_events.sort_custom(func(a: NarrativeEvent, b: NarrativeEvent) -> bool: return a.id < b.id)


## Returns whether the ID refers to the requested occurrence. An existing ID never rerolls.
func submit(id: StringName, origin: StringName, side: MatchRegion.Owner,
		region := &"", facts: Array[StringName] = []) -> bool:
	if not _active or id.is_empty() or side not in [MatchRegion.Owner.PLAYER, MatchRegion.Owner.CPU]:
		return false
	var existing := _decisions.get(id) as Decision
	if existing != null:
		return existing.origin == origin and existing.region == region and existing.side == side
	var candidates: Array[NarrativeEvent] = []
	var total := 0
	for event in _events:
		if event.is_eligible(origin, side, region, facts, _economy):
			candidates.append(event)
			total += event.weight
	if candidates.is_empty():
		return false
	var rng := _rng(id, "event")
	var roll := rng.randi_range(1, total)
	for event in candidates:
		roll -= event.weight
		if roll <= 0:
			var decision := Decision.new()
			decision.definition = event
			decision.origin = origin
			decision.region = region
			decision.side = side
			_decisions[id] = decision
			if side == MatchRegion.Owner.PLAYER:
				_player_queue.append(id)
				if not _applying:
					queue_changed.emit()
			return true
	return false


func pending_player_id() -> StringName:
	return &"" if _player_queue.is_empty() else _player_queue[0]


func instance(id: StringName) -> Dictionary:
	var decision := _decisions.get(id) as Decision
	if decision == null:
		return {}
	return {
		"id": id, "event_id": decision.definition.id, "origin": decision.origin,
		"region": decision.region, "side": decision.side, "status": decision.status,
		"selected_option": decision.selected_option,
	}


func player_dialogue() -> Dictionary:
	var id := pending_player_id()
	if id.is_empty():
		return {}
	var decision := _decisions[id]
	var options: Array[Dictionary] = []
	for option in decision.definition.options:
		options.append({
			"id": option.id, "label": option.label, "preview": option.preview(),
			"blocked": _economy.cost_block_reason(decision.side, option.costs()),
		})
	return {
		"id": id, "title": decision.definition.title, "text": decision.definition.text,
		"illustration": decision.definition.illustration, "options": options,
	}


func resolve_player(id: StringName, option_id: StringName) -> bool:
	if id.is_empty() or id != pending_player_id():
		return false
	for option in _decisions[id].definition.options:
		if option.id == option_id:
			return _resolve(id, option)
	return false


## A caller may supply a CPU choice or use the shared scarcity-based policy.
func resolve_cpu(id: StringName, option_id := &"") -> bool:
	var decision := _decisions.get(id) as Decision
	if decision == null or decision.side != MatchRegion.Owner.CPU or decision.status != Status.PENDING:
		return false
	var best: Array[NarrativeOption] = []
	var best_score := -INF
	for option in decision.definition.options:
		if not option_id.is_empty():
			if option.id == option_id:
				return _resolve(id, option)
			continue
		if not _economy.cost_block_reason(decision.side, option.costs()).is_empty():
			continue
		var score := _cpu_score(decision.side, option)
		if score > best_score:
			best_score = score
			best.clear()
		if score == best_score:
			best.append(option)
	if best.is_empty():
		return false
	best.sort_custom(func(a: NarrativeOption, b: NarrativeOption) -> bool: return a.id < b.id)
	return _resolve(id, best[_rng(id, "cpu choice").randi_range(0, best.size() - 1)])


func _cpu_score(side: MatchRegion.Owner, option: NarrativeOption) -> float:
	const INCOME_HORIZON := 20.0
	var score := option.cpu_tactical_value
	for effect in option.effects:
		if not MatchEconomy.RESOURCES.has(effect.key):
			continue
		var stock: float = MatchEconomy.RESOURCES[effect.key].starting_stock
		var available := _economy.stockpile(side, effect.key)
		var net := float(effect.amount)
		match effect.operation:
			NarrativeEffect.Operation.SPEND:
				net = -net
			NarrativeEffect.Operation.MODIFIER:
				var duration := minf(effect.duration, INCOME_HORIZON) if effect.duration > 0.0 else INCOME_HORIZON
				net = 0.75 * effect.magnitude * duration
		score += net / (stock + available)
	return score


func advance_time(simulation_time: float) -> void:
	_time = simulation_time
	for source_id in _expirations.keys():
		if _time + 1e-9 >= _expirations[source_id]:
			_expirations.erase(source_id)
			_economy.stats.remove_source(source_id)


func close() -> void:
	_active = false
	_player_queue.clear()
	for id in _decisions.keys():
		if _decisions[id].status == Status.PENDING:
			_decisions.erase(id)
	queue_changed.emit()


func _resolve(id: StringName, option: NarrativeOption) -> bool:
	if not _active or _applying:
		return false
	var decision := _decisions[id]
	if decision.status != Status.PENDING or not _economy.try_spend(decision.side, option.costs()):
		return false
	# Record the decision before publishing any modifier signals.
	_applying = true
	decision.status = Status.RESOLVED
	decision.selected_option = option.id
	for index in option.effects.size():
		var effect := option.effects[index]
		match effect.operation:
			NarrativeEffect.Operation.GRANT:
				_economy.grant_resource(decision.side, effect.key, effect.amount)
			NarrativeEffect.Operation.MODIFIER:
				var source_id := StringName("narrative/%s/%d" % [id, index])
				_economy.stats.set_modifier(source_id, decision.side, effect.key,
					effect.magnitude, &"narrative", effect.modifier_name, option.description,
					true, 0, decision.region)
				if effect.duration > 0.0:
					_expirations[source_id] = _time + effect.duration
	if decision.side == MatchRegion.Owner.PLAYER and not _player_queue.is_empty():
		_player_queue.pop_front()
	_applying = false
	queue_changed.emit()
	return true


func _rng(id: StringName, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var digest := ("%d/narrative/%s/%s" % [_seed, purpose, id]).sha256_buffer()
	rng.seed = digest.decode_s64(0)
	return rng
