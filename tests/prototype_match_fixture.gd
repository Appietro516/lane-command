extends "res://match/match.gd"
## Retains the original coordinates for focused gameplay cases with authored click
## positions, structures, and claim chains. Production map tests cover generated camps.

const SIZE := Vector2(30.0, 18.0)


class PrototypeLayout extends TerritoryLayout:
	func _generate_sites(count: int) -> PackedVector2Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = active_seed
		var sites := PackedVector2Array([Vector2(-10.2, 0.0)])
		var anchors := [
			Vector2(-3.0, -4.5), Vector2(3.0, 4.5), Vector2(-3.0, 4.5),
			Vector2(3.0, -4.5), Vector2.ZERO,
		]
		for i in range(count - 2):
			sites.append(anchors[i] + Vector2(rng.randf_range(-1.4, 1.4),
				rng.randf_range(-1.6, 1.6)))
		sites.append(Vector2(10.2, 0.0))
		return sites


static func instantiate() -> Node:
	return load("res://tests/prototype_match_fixture.tscn").instantiate()


func _create_layout() -> TerritoryLayout:
	return PrototypeLayout.new(map_seed, region_count, SIZE)
