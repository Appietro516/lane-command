extends RefCounted


static func purchase(economy: MatchEconomy, battle: MatchBattle,
		side: MatchRegion.Owner, position: Vector2, cost: Dictionary) -> MatchBattle.ProductionTimer:
	if not economy.try_build(side, cost):
		return null
	return battle.add_barracks(side, position)
