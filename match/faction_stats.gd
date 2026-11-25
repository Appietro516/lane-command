class_name FactionStats
extends RefCounted
## Flat modifiers keyed by stat and stable source ID. One source may contribute to several stats.

signal stat_changed(stat: StringName)

const UNIT_DPS := &"unit_dps"
const BUILDING_MAX_HP := &"building_max_hp"
const ENERGY := &"energy"
const MATERIALS := &"materials"
const FOOD := &"food"
const BASELINE := &"base"
const LIMIT := &"_minimum"
const BASELINE_TYPE := &"baseline"
const STAT_DEFINITIONS := {
	UNIT_DPS: {"minimum": 0.0},
	BUILDING_MAX_HP: {"minimum": 1.0},
	ENERGY: {},
	MATERIALS: {},
	FOOD: {},
}

var _sources: Dictionary[StringName, Dictionary] = {}
var _computed: Dictionary[StringName, Dictionary] = {}


func set_modifier(source_id: StringName, owner: MatchRegion.Owner, stat: StringName,
		magnitude: float, source_type := &"buff", source_name := "", description := "",
		active := true, building_id := 0, region_id := &"") -> bool:
	if not STAT_DEFINITIONS.has(stat) or source_id.is_empty() or source_id in [BASELINE, LIMIT] \
			or owner not in MatchRegion.Owner.values() or not is_finite(magnitude):
		return false
	var contribution := _contribution(source_id, source_type,
		str(source_id) if source_name.is_empty() else source_name, owner, stat, magnitude, active)
	contribution["description"] = description
	if building_id != 0:
		contribution["building_id"] = building_id
	if not region_id.is_empty():
		contribution["region_id"] = region_id
	var sources := _sources.get_or_add(stat, {}) as Dictionary
	if sources.get(source_id) != contribution:
		sources[source_id] = contribution
		_invalidate_all([stat])
	return true


## An empty stat applies to every contribution from this source.
func remove_source(source_id: StringName, stat := &"") -> void:
	var changed: Array[StringName] = []
	for key in _sources:
		if (stat.is_empty() or key == stat) and _sources[key].erase(source_id):
			changed.append(key)
	_invalidate_all(changed)


func set_source_owner(source_id: StringName, owner: MatchRegion.Owner) -> void:
	if owner in MatchRegion.Owner.values():
		_update_source(source_id, &"owner", owner)


func set_source_active(source_id: StringName, active: bool) -> void:
	_update_source(source_id, &"active", active)


func value(owner: MatchRegion.Owner, stat: StringName, base_value: float) -> float:
	return _compute(owner, stat, base_value).total


## Baseline first, then source IDs in lexical order, then any stat limit adjustment.
## Disabled contributions have zero magnitude and keep their configured value.
func inspect(owner: MatchRegion.Owner, stat: StringName, base_value: float) -> Dictionary:
	return _compute(owner, stat, base_value).duplicate(true)


func _compute(owner: MatchRegion.Owner, stat: StringName, base_value: float) -> Dictionary:
	var cache := _computed.get_or_add(stat, {}) as Dictionary
	var owner_cache := cache.get_or_add(owner, {}) as Dictionary
	if owner_cache.has(base_value):
		return owner_cache[base_value]

	var breakdown: Array[Dictionary] = [
		_contribution(BASELINE, BASELINE_TYPE, "Base", owner, stat, base_value, true),
	]
	var total := base_value
	var sources: Dictionary = _sources.get(stat, {})
	var ids := PackedStringArray(sources.keys())
	ids.sort()
	for source_id in ids:
		var source: Dictionary = sources[StringName(source_id)]
		if source.owner != owner or owner == MatchRegion.Owner.NEUTRAL:
			continue
		var entry := source.duplicate()
		entry["configured_magnitude"] = source.magnitude
		if not entry.active:
			entry.magnitude = 0.0
		total += entry.magnitude
		breakdown.append(entry)

	var definition: Dictionary = STAT_DEFINITIONS.get(stat, {})
	var minimum: float = definition.get("minimum", -INF)
	if total < minimum:
		breakdown.append(_contribution(LIMIT, &"rule", "Minimum", owner, stat, minimum - total, true))
		total = minimum

	var result := {"total": total, "breakdown": breakdown}
	owner_cache[base_value] = result
	return result


func _update_source(source_id: StringName, field: StringName, value_to_set: Variant) -> void:
	var changed: Array[StringName] = []
	for stat in _sources:
		var source: Dictionary = _sources[stat].get(source_id, {})
		if not source.is_empty() and source[field] != value_to_set:
			source[field] = value_to_set
			changed.append(stat)
	_invalidate_all(changed)


func _invalidate_all(changed: Array[StringName]) -> void:
	var ordered := PackedStringArray(changed)
	ordered.sort()
	for stat: StringName in ordered:
		_computed.erase(stat)
	for stat: StringName in ordered:
		stat_changed.emit(stat)


func _contribution(source_id: StringName, source_type: StringName, source_name: String,
		owner: MatchRegion.Owner, stat: StringName, magnitude: float, active: bool) -> Dictionary:
	return {
		"source_id": source_id, "source_type": source_type, "source_name": source_name,
		"owner": owner, "stat": stat, "magnitude": magnitude, "active": active,
	}
