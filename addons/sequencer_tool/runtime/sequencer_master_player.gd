extends Node

signal playback_started()
signal playback_paused()
signal song_position_changed(previous_position: float, current_position: float)
signal track_player_registered(track_player: Node)
signal track_player_unregistered(track_player: Node)

@export var bpm: float = 120.0
@export var bars: int = 8
@export var beats_per_bar: int = 4
@export var subdivisions_per_beat: int = 4
@export var loop_enabled: bool = false

@export var internal_track_indices: Array[int] = []
@export var default_audio_bus: StringName = &"Master"

var is_playing: bool = false
var song_position: float = 0.0

var active_track_group: StringName = &""
var track_groups: Dictionary = {}
var track_group_fade_seconds: float = 1.0

var track_bus_overrides: Dictionary = {}
var _registered_track_players: Array[Node] = []

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not is_playing:
		return

	var previous_position := song_position
	song_position += _get_subdivisions_per_second() * delta

	var total_subdivisions := float(get_total_subdivisions())
	if total_subdivisions > 0.0 and song_position >= total_subdivisions:
		if loop_enabled:
			song_position = fmod(song_position, total_subdivisions)
		else:
			song_position = total_subdivisions
			_sync_registered_track_players(previous_position, song_position)
			song_position_changed.emit(previous_position, song_position)
			pause()
			return

	_sync_registered_track_players(previous_position, song_position)
	song_position_changed.emit(previous_position, song_position)

func play() -> void:
	if is_playing:
		return

	is_playing = true
	playback_started.emit()

func pause() -> void:
	if not is_playing:
		return

	is_playing = false
	playback_paused.emit()

func set_song_position(value: float) -> void:
	var previous_position := song_position
	song_position = clamp(value, 0.0, float(get_total_subdivisions()))

	_sync_registered_track_players(previous_position, song_position)
	song_position_changed.emit(previous_position, song_position)

func get_total_subdivisions() -> int:
	return max(1, bars) * max(1, beats_per_bar) * max(1, subdivisions_per_beat)

func _get_subdivisions_per_second() -> float:
	return (max(1.0, bpm) / 60.0) * float(max(1, subdivisions_per_beat))

func register_track_player(track_player: Node) -> void:
	if track_player == null:
		return

	if _registered_track_players.has(track_player):
		return

	_registered_track_players.append(track_player)
	track_player_registered.emit(track_player)

func unregister_track_player(track_player: Node) -> void:
	if track_player == null:
		return

	if not _registered_track_players.has(track_player):
		return

	_registered_track_players.erase(track_player)
	track_player_unregistered.emit(track_player)

func get_registered_track_players() -> Array[Node]:
	return _registered_track_players.duplicate()

func resolve_track_bus(track_index: int) -> StringName:
	if track_bus_overrides.has(track_index):
		return StringName(str(track_bus_overrides[track_index]))

	return default_audio_bus

func set_track_bus_override(track_index: int, bus_name: StringName) -> void:
	if track_index < 0:
		return

	track_bus_overrides[track_index] = bus_name

func clear_track_bus_override(track_index: int) -> void:
	if track_bus_overrides.has(track_index):
		track_bus_overrides.erase(track_index)

func set_active_track_group(group_name: StringName, fade_seconds: float = -1.0) -> void:
	active_track_group = group_name

	if fade_seconds >= 0.0:
		track_group_fade_seconds = fade_seconds

func _sync_registered_track_players(previous_position: float, current_position: float) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]

		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if track_player.has_method("sync_from_master"):
			track_player.sync_from_master(previous_position, current_position)
