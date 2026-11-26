class_name NarrativeOption
extends Resource

@export var id: StringName
@export var label := ""
@export_multiline var description := ""
@export var effects: Array[NarrativeEffect] = []
## CPU utility for effects beyond resource stock and income, in units of starting stock.
@export var cpu_tactical_value := 0.0


func costs() -> Dictionary:
	var cost := {}
	for effect in effects:
		if effect.operation == NarrativeEffect.Operation.SPEND:
			cost[effect.key] = cost.get(effect.key, 0) + effect.amount
	return cost


func preview() -> String:
	var lines := PackedStringArray()
	if not description.strip_edges().is_empty():
		lines.append(description)
	var cost := costs()
	if not cost.is_empty():
		lines.append("Spend %s" % MatchEconomy.cost_text(cost))
	for effect in effects:
		if effect.operation != NarrativeEffect.Operation.SPEND:
			lines.append(effect.preview())
	if effects.is_empty():
		lines.append("No gameplay changes")
	return "\n".join(lines)
