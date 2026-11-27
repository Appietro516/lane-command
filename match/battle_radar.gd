class_name BattleRadar
extends RefCounted
## Radar snapshots are value records with no ability to resolve live unit positions.

const WATCHTOWER := &"watchtower"
const RADAR := &"radar_station"
const COUNTERINTELLIGENCE := &"counterintelligence_station"
const PULSE_INTERVAL := 8.0
const CONTACT_LIFETIME := 11.0
const DECOY_LIFETIME := 24.0
const DECOY_COOLDOWN := 36.0
const MAX_DECOYS := 2
const DECOY_COMPOSITION := {&"infantry": 3, &"heavy": 1, &"ranged": 2}

class Contact:
	var key: String
	var side: MatchRegion.Owner
	var point: Vector2
	var recorded_at: float
	var composition: Dictionary
	var _decoy := false

	func _init(id: String, faction: MatchRegion.Owner, location: Vector2, time: float, types: Dictionary) -> void:
		key = id
		side = faction
		point = location
		recorded_at = time
		composition = types

var pulse_interval := PULSE_INTERVAL
var _next_pulse: Dictionary = {}
var _ready: Dictionary = {}
var _contacts: Dictionary = {}
var _decoys: Dictionary[int, Contact] = {}
var _active_radars: Dictionary[int, int] = {}
var pulse_count := 0
var _discovered: Dictionary = {}
var _next_verification := 0.0


func contacts_for(side: MatchRegion.Owner) -> Array:
	return _contacts.get(side, [])


func can_deploy(side: MatchRegion.Owner, station: int, now: float) -> bool:
	if now + 0.00001 < _ready.get(station, 0.0):
		return false
	var active := 0
	for decoy in _decoys.values():
		if decoy.side == side and now - decoy.recorded_at < DECOY_LIFETIME:
			active += 1
	return active < MAX_DECOYS


func deploy(side: MatchRegion.Owner, station: int, point: Vector2, now: float) -> bool:
	if not can_deploy(side, station, now):
		return false
	var decoy := Contact.new("d%d/%d" % [station, roundi(now / MatchBattle.STEP)], side, point, now, DECOY_COMPOSITION)
	decoy._decoy = true
	_decoys[station] = decoy
	_ready[station] = now + DECOY_COOLDOWN
	return true


func register_radar(id: int, side: MatchRegion.Owner) -> void:
	_active_radars[id] = side


func disable_radar(id: int) -> void:
	var owner: int = _active_radars.get(id, -1)
	_active_radars.erase(id)
	if owner >= 0 and not _active_radars.values().has(owner):
		_next_pulse.erase(owner)


func remove_station(id: int) -> void:
	disable_radar(id)
	_erase_decoy(id)
	_ready.erase(id)


func _erase_decoy(id: int) -> void:
	if _decoys.has(id):
		_discovered.erase(_decoys[id].key)
		_decoys.erase(id)


func advance(battle: MatchBattle, units: Array[MatchBattle.Unit], now: float) -> void:
	if _active_radars.is_empty() and _contacts.is_empty() and _decoys.is_empty():
		return
	var due := {}
	for owner: MatchRegion.Owner in _active_radars.values():
		if not _next_pulse.has(owner):
			_next_pulse[owner] = now + pulse_interval
		elif now + 0.00001 >= _next_pulse[owner]:
			due[owner] = true
	for id in _decoys.keys():
		if now - _decoys[id].recorded_at >= DECOY_LIFETIME:
			_erase_decoy(id)
	var verify := now >= _next_verification
	if verify:
		_next_verification = now + BattleVisibility.UPDATE_INTERVAL
	for side in _contacts.keys():
		if not _contacts[side].is_empty() and now - _contacts[side][0].recorded_at >= CONTACT_LIFETIME:
			_contacts.erase(side)
		elif verify:
			var seen := _contacts[side] as Array
			for index in range(seen.size() - 1, -1, -1):
				var contact: Contact = seen[index]
				if not contact._decoy or not battle.can_see(side, contact.point):
					continue
				_discovered.get_or_add(contact.key, {})[side] = true
				seen.remove_at(index)
			if seen.is_empty():
				_contacts.erase(side)
	if due.is_empty():
		return

	var batch: Array[Contact] = []
	for unit in units:
		if unit.hp > 0.0 and battle.is_side_active(unit.side):
			batch.append(Contact.new("u%d" % unit.id, unit.side, unit.position, now, {unit.type_id: 1}))
	for decoy in _decoys.values():
		var snapshot := Contact.new(decoy.key, decoy.side, decoy.point, now, decoy.composition)
		snapshot._decoy = true
		batch.append(snapshot)
	for side: MatchRegion.Owner in due:
		var snapshot: Array[Contact] = []
		for contact in batch:
			if contact.side != side and (not contact._decoy or (not _discovered.get(contact.key, {}).has(side)
					and not battle.can_see(side, contact.point))):
				snapshot.append(contact)
		if not snapshot.is_empty():
			_contacts[side] = snapshot
		else:
			_contacts.erase(side)
		_next_pulse[side] = now + pulse_interval
		pulse_count += 1
