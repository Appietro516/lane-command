extends RefCounted

const TRIGGER := &"survey"
const TAKE := &"take_supplies"
const INVEST := &"repair_relay"
const LEAVE := &"leave"
const PLAYER := MatchRegion.Owner.PLAYER


static func catalog() -> NarrativeCatalog:
	var event := NarrativeEvent.new()
	event.id = &"supply_manifest"
	event.trigger = TRIGGER
	event.weight = 3
	event.title = "The Supply Manifest"
	event.text = "A field crew has uncovered a sealed supply depot. Its reserve crates are intact, and spare parts could bring the old relay back online."
	var take := _option(TAKE, "Open the reserve crates", "")
	take.effects.append(_stock(NarrativeEffect.Operation.GRANT, MatchEconomy.MATERIALS, 12))
	var invest := _option(INVEST, "Restore the field relay", "")
	invest.effects.append(_stock(NarrativeEffect.Operation.SPEND, MatchEconomy.ENERGY, 30))
	invest.effects.append(_stock(NarrativeEffect.Operation.SPEND, MatchEconomy.ENERGY, 10))
	var modifier := NarrativeEffect.new()
	modifier.operation = NarrativeEffect.Operation.MODIFIER
	modifier.key = MatchEconomy.ENERGY
	modifier.modifier_name = "Field relay"
	modifier.magnitude = 2.0
	modifier.duration = 2.0
	invest.effects.append(modifier)
	var leave := _option(LEAVE, "Leave the depot sealed", "")
	event.options.assign([take, invest, leave])
	var result := NarrativeCatalog.new()
	result.events.append(event)
	return result


static func _option(id: StringName, label: String, description: String) -> NarrativeOption:
	var option := NarrativeOption.new()
	option.id = id
	option.label = label
	option.description = description
	return option


static func _stock(operation: NarrativeEffect.Operation, key: StringName, amount: int) -> NarrativeEffect:
	var effect := NarrativeEffect.new()
	effect.operation = operation
	effect.key = key
	effect.amount = amount
	return effect
