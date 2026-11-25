extends RefCounted


static func block_reason(economy: MatchEconomy, side: MatchRegion.Owner,
		cost: Dictionary) -> String:
	return economy.build_block_reason(side, cost)


static func purchase(economy: MatchEconomy, battle: MatchBattle,
		side: MatchRegion.Owner, position: Vector2, cost: Dictionary) -> bool:
	if not economy.try_build(side, cost):
		return false
	battle.add_barracks(side, position)
	return true
