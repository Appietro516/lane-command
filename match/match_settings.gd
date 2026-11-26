class_name MatchSettings
extends RefCounted

const DifficultyProfile := preload("res://match/difficulty_profile.gd")

enum MapSize { SMALL, MEDIUM, LARGE }

const SIZE_PRESETS := {
	MapSize.SMALL: {
		"label": "Small", "rectangle": Vector2(40, 24), "square": 32.0, "triangle": 40.0,
	},
	MapSize.MEDIUM: {
		"label": "Medium", "rectangle": MapSettings.DEFAULT_SIZE, "square": 48.0, "triangle": 60.0,
	},
	MapSize.LARGE: {
		"label": "Large", "rectangle": Vector2(90, 54), "square": 72.0, "triangle": 90.0,
	},
}
const DEFAULT_SEED := 17

var map: MapSettings
var map_size: MapSize
var cpu_difficulties: Array[int]


func _init(map_settings: MapSettings, preset: MapSize, levels: Array[int]) -> void:
	map = map_settings
	map_size = preset
	cpu_difficulties = levels.duplicate()


static func defaults() -> MatchSettings:
	return new(MapSettings.new(MapSettings.Shape.RECTANGLE, MapSettings.DEFAULT_SIZE,
		MapSettings.DEFAULT_REGION_COUNT, DEFAULT_SEED), MapSize.MEDIUM, [DifficultyProfile.DEFAULT_LEVEL])


static func preset_dimensions(preset: MapSize, shape: MapSettings.Shape) -> Vector2:
	var dimensions: Dictionary = SIZE_PRESETS[preset]
	match shape:
		MapSettings.Shape.SQUARE:
			return Vector2.ONE * dimensions.square
		MapSettings.Shape.TRIANGLE:
			return Vector2(dimensions.triangle, dimensions.triangle * sqrt(3.0) / 2.0)
		_:
			return dimensions.rectangle
