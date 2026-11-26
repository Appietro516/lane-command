class_name MatchSettings
extends RefCounted

const DifficultyProfile := preload("res://match/difficulty_profile.gd")

const DEFAULT_SEED := 17

var map: MapSettings
var cpu_difficulties: Array[int]


func _init(map_settings: MapSettings, levels: Array[int]) -> void:
	map = map_settings
	cpu_difficulties = levels.duplicate()


static func defaults() -> MatchSettings:
	var shape := MapSettings.Shape.RECTANGLE
	var count := MapSettings.DEFAULT_REGION_COUNT
	return new(MapSettings.new(shape, MapSettings.scaled_dimensions(shape, count), count, DEFAULT_SEED),
		[DifficultyProfile.DEFAULT_LEVEL])
