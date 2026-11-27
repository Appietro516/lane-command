extends SceneTree

const P := MatchBattle.PLAYER
const C := MatchBattle.CPU
const ENERGY := MatchEconomy.ENERGY
const ScoutExpeditions := preload("res://match/scout_expeditions.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var signatures := {}
	var neutral: Array[MatchRegion] = []
	for region: MatchRegion in scene._regions_by_id.values():
		signatures[region.region_id] = region.specialty
		if region.region_owner == MatchRegion.Owner.NEUTRAL:
			neutral.append(region)
		else:
			_check(region.specialty == RegionSpecialty.Kind.STANDARD, "starting regions are ordinary")
	_check(signatures.size() == 7 and scene._landmarks.size() >= 3, "standard opening has seven regions and several landmarks")
	_check(RegionSpecialty.income_factor(RegionSpecialty.Kind.FERTILE, &"farm") == 1.35
		and RegionSpecialty.income_factor(RegionSpecialty.Kind.FERTILE, &"mine") == 1.0, "local resource bonus is specific")
	_check(RegionSpecialty.defense_factor(RegionSpecialty.Kind.DEFENSIBLE) == 1.2, "defense bonus")
	_check(MatchEconomy.producer_efficiency(2) == 1.0 and MatchEconomy.producer_efficiency(5) < 0.8
		and MatchEconomy.producer_efficiency(90) == 0.55, "diminishing returns have a floor")
	var claims: ScoutExpeditions = scene._expeditions
	_check(claims.claim_price(P)[ENERGY] == 50 and claims.claim_price(C)[ENERGY] == 50, "starting price")
	neutral[0].region_owner = P
	neutral[1].region_owner = P
	_check(claims.claim_price(P)[ENERGY] == 72 and claims.claim_price(C)[ENERGY] == 50, "player price scales independently")
	neutral[1].ruined = true
	_check(claims.claim_price(P)[ENERGY] == 60, "ruin reduces held region count")
	scene.restart_match()
	for region: MatchRegion in scene._regions_by_id.values():
		_check(signatures[region.region_id] == region.specialty, "restart preserves seeded traits")
	scene.queue_free()
	print("Region test failures: %d" % _failures)
	quit(int(_failures > 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
