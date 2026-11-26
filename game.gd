extends Node

const MatchScene := preload("res://main.tscn")
const SetupScene := preload("res://match/match_setup.tscn")

var _settings := MatchSettings.defaults()
var _setup: MatchSetup
var _match: Node3D


func _ready() -> void:
	_show_setup()


func _show_setup() -> void:
	if _match != null:
		remove_child(_match)
		_match.queue_free()
		_match = null
	_setup = SetupScene.instantiate()
	_setup.settings = _settings
	_setup.start_requested.connect(_start_match, CONNECT_DEFERRED)
	add_child(_setup)


func _start_match(settings: MatchSettings, layout: TerritoryLayout) -> void:
	if _setup == null:
		return
	remove_child(_setup)
	_setup.queue_free()
	_setup = null
	_settings = settings
	_match = MatchScene.instantiate()
	_match.configure_match(settings, layout)
	_match.return_to_setup_requested.connect(_show_setup, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	add_child(_match)
