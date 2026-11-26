extends RefCounted
## Strategy tuning relative to the Match scene's Standard settings.
## Profiles affect decision-making only. Match rules own all prices and stats.

const DEFAULT_LEVEL := 3
const PROFILES := [
	{
		"label": "Relaxed",
		"description": "The CPU reacts slowly, saves less for production, and favors nearby expansion and basic troops.",
		"cadence": 2.75, "defense_delay": 2.0, "threat_threshold": 3.2,
		"food_buffer": 0.5, "investment_horizon": 1.5, "scout_reserve": 0.4,
		"counter": 0.15, "diversity": 0.3, "local_threat_weight": 0,
		"scout_delay": 1.8, "scout_travel": 1.6, "scout_connection": 0.2,
		"scout_capacity": 0.3, "scout_landmark": 0.25, "scout_production": 0.0, "scout_danger": 0.5,
		"economy_slot_reserve": 0, "opening_producers": 1,
		"enemy_production_weight": 0, "claim_options": 2, "site_samples": 8,
	},
	{
		"label": "Casual",
		"description": "The CPU builds a basic economy and mixed army, with extra time to respond to threats.",
		"cadence": 1.75, "defense_delay": 1.5, "threat_threshold": 2.0,
		"food_buffer": 0.75, "investment_horizon": 1.2, "scout_reserve": 0.7,
		"counter": 0.5, "diversity": 0.65, "local_threat_weight": 1,
		"scout_delay": 1.35, "scout_travel": 1.2, "scout_connection": 0.65,
		"scout_capacity": 0.7, "scout_landmark": 0.65, "scout_production": 0.5, "scout_danger": 0.75,
		"economy_slot_reserve": 0, "opening_producers": 1,
		"enemy_production_weight": 0, "claim_options": 3, "site_samples": 11,
	},
	{
		"label": "Standard",
		"description": "The CPU balances growth, scout claims, troop counters, and defenses.",
		"cadence": 1.0, "defense_delay": 1.0, "threat_threshold": 0.0,
		"food_buffer": 1.0, "investment_horizon": 1.0, "scout_reserve": 1.0,
		"counter": 1.0, "diversity": 1.0, "local_threat_weight": 2,
		"scout_delay": 1.0, "scout_travel": 1.0, "scout_connection": 1.0,
		"scout_capacity": 1.0, "scout_landmark": 1.0, "scout_production": 1.0, "scout_danger": 1.0,
		"economy_slot_reserve": 0, "opening_producers": 1,
		"enemy_production_weight": 0, "claim_options": 4, "site_samples": 14,
	},
	{
		"label": "Challenging",
		"description": "The CPU invests earlier, looks for safer and more useful claims, and responds faster with counters and defenses.",
		"cadence": 0.75, "defense_delay": 0.75, "threat_threshold": 0.0,
		"food_buffer": 1.15, "investment_horizon": 0.8, "scout_reserve": 1.2,
		"counter": 1.3, "diversity": 1.1, "local_threat_weight": 3,
		"scout_delay": 0.75, "scout_travel": 0.85, "scout_connection": 1.25,
		"scout_capacity": 1.25, "scout_landmark": 1.2, "scout_production": 1.5, "scout_danger": 1.3,
		"economy_slot_reserve": 1, "opening_producers": 2,
		"enemy_production_weight": 2, "claim_options": 5, "site_samples": 18,
	},
	{
		"label": "Expert",
		"description": "The CPU reacts fastest, evaluates the most scout routes and building sites, and plans counters around the troops and military buildings it can see.",
		"cadence": 0.5, "defense_delay": 0.5, "threat_threshold": 0.0,
		"food_buffer": 1.3, "investment_horizon": 0.7, "scout_reserve": 1.4,
		"counter": 1.6, "diversity": 1.15, "local_threat_weight": 4,
		"scout_delay": 0.55, "scout_travel": 0.8, "scout_connection": 1.5,
		"scout_capacity": 1.5, "scout_landmark": 1.35, "scout_production": 2.0, "scout_danger": 1.6,
		"economy_slot_reserve": 2, "opening_producers": 2,
		"enemy_production_weight": 3, "claim_options": 6, "site_samples": 22,
	},
]


static func get_profile(level: int) -> Dictionary:
	var index := level - 1 if level >= 1 and level <= PROFILES.size() else DEFAULT_LEVEL - 1
	return PROFILES[index]


static func display_name(level: int) -> String:
	return "%d · %s" % [level, get_profile(level).label]
