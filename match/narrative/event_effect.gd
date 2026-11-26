class_name NarrativeEffect
extends Resource
## A declarative operation. An empty option effect list represents no change.

enum Operation { GRANT, SPEND, MODIFIER }

@export var operation := Operation.GRANT
## Resource ID for grants/spends, or FactionStats key for a modifier.
@export var key: StringName
@export_range(1, 1000000000) var amount := 1
@export var modifier_name := ""
@export var magnitude := 1.0
## Zero keeps the source until match end. Positive durations use simulation seconds.
@export var duration := 0.0


func is_valid() -> bool:
	match operation:
		Operation.GRANT, Operation.SPEND:
			return MatchEconomy.RESOURCES.has(key) and amount > 0 and amount <= 1000000000
		Operation.MODIFIER:
			return FactionStats.STAT_DEFINITIONS.has(key) and not modifier_name.strip_edges().is_empty() \
				and is_finite(magnitude) and not is_zero_approx(magnitude) \
				and is_finite(duration) and duration >= 0.0
	return false


func preview() -> String:
	match operation:
		Operation.GRANT:
			return "Gain %s" % MatchEconomy.cost_text({key: amount})
		Operation.MODIFIER:
			var stat_label := String(key).capitalize()
			if key == FactionStats.UNIT_DPS:
				stat_label = "Unit DPS"
			if MatchEconomy.RESOURCES.has(key):
				stat_label = "%s income/s" % MatchEconomy.RESOURCES[key].label
			var lifetime := "%s s" % str(duration) if duration > 0.0 else "rest of match"
			return "%s (%s%s %s, %s)" % [
				modifier_name, "+" if magnitude > 0.0 else "", str(magnitude), stat_label, lifetime,
			]
	return ""
