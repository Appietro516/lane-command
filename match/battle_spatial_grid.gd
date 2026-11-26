class_name BattleSpatialGrid
extends RefCounted
## Stores IDs so indexed units can update position without retaining each other.

const CELL_SIZE := 4.0
var count := 0
var _cells: Dictionary[Vector3i, Array] = {}


static func cell_at(position: Vector2) -> Vector2i:
	return Vector2i((position / CELL_SIZE).floor())


func insert(id: int, cell: Vector2i, group: int) -> void:
	var key := Vector3i(cell.x, cell.y, group)
	var bucket: Array = _cells.get_or_add(key, [])
	bucket.append(id)
	count += 1


func erase(id: int, cell: Vector2i, group: int) -> void:
	var key := Vector3i(cell.x, cell.y, group)
	var bucket: Array = _cells[key]
	bucket.erase(id)
	count -= 1
	if bucket.is_empty():
		_cells.erase(key)


func append_ids(center: Vector2i, reach: int, group: int, result: Array[int]) -> void:
	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			var key := Vector3i(x, y, group)
			if _cells.has(key):
				result.append_array(_cells[key])
