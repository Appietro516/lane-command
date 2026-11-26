class_name NarrativeEvent
extends Resource

@export var id: StringName
@export var trigger: StringName
@export var title := ""
@export_multiline var text := ""
@export var illustration: Texture2D
@export_range(0, 1000000) var weight := 1

@export_group("Eligibility")
## Neutral allows either active faction.
@export var eligible_side := MatchRegion.Owner.NEUTRAL
## An empty list allows any region, including a context without a region.
@export var eligible_regions: Array[StringName] = []
## All named facts must be supplied by the trigger producer.
@export var required_facts: Array[StringName] = []
@export var minimum_stock: Dictionary[StringName, int] = {}

@export_group("Decision")
@export var options: Array[NarrativeOption] = []


func validation_error() -> String:
	if id.is_empty() or trigger.is_empty() or title.strip_edges().is_empty() \
			or text.strip_edges().is_empty() or weight < 0 or weight > 1000000:
		return "Invalid ID, trigger, text, or weight"
	if eligible_side not in MatchRegion.Owner.values() \
			or &"" in eligible_regions or &"" in required_facts:
		return "Invalid eligibility context"
	for key in minimum_stock:
		if not MatchEconomy.RESOURCES.has(key) or minimum_stock[key] < 0:
			return "Invalid minimum stock"
	if options.size() < 2 or options.size() > 3:
		return "A decision needs two or three options"
	var ids: Array[StringName] = []
	var has_free_option := false
	for option in options:
		if option == null or option.id.is_empty() or option.id in ids \
				or option.label.strip_edges().is_empty() or not is_finite(option.cpu_tactical_value):
			return "Invalid or duplicate option"
		ids.append(option.id)
		for effect in option.effects:
			if effect == null or not effect.is_valid():
				return "Invalid effect on option %s" % option.id
		has_free_option = has_free_option or option.costs().is_empty()
	# Earlier decisions can spend resources while this decision waits in the queue.
	return "" if has_free_option else "A decision needs an option with no spending"


func is_eligible(origin: StringName, side: MatchRegion.Owner, region: StringName,
		facts: Array[StringName], economy: MatchEconomy) -> bool:
	if trigger != origin or weight == 0:
		return false
	if eligible_side != MatchRegion.Owner.NEUTRAL and eligible_side != side:
		return false
	if not eligible_regions.is_empty() and region not in eligible_regions:
		return false
	for fact in required_facts:
		if fact not in facts:
			return false
	return economy.cost_block_reason(side, minimum_stock).is_empty()
