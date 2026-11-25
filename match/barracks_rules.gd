extends RefCounted


static func block_reason(economy: MatchEconomy, side: MatchRegion.Owner) -> String:
	if economy.can_build(side):
		return ""
	if economy.barracks_count(side) >= MatchEconomy.BARRACKS_CAPACITY:
		return "Barracks limit reached"
	return "Need more energy"


static func purchase(economy: MatchEconomy, battle: MatchBattle,
		side: MatchRegion.Owner, position: Vector2) -> bool:
	if not economy.try_build(side):
		return false
	battle.add_barracks(side, position)
	return true
