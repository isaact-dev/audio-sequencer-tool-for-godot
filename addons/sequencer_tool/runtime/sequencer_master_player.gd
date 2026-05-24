extends Node

const SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_audio_track_voice.gd")

signal playback_started()
signal playback_paused()
signal song_position_changed(previous_position: float, current_position: float)
signal track_player_registered(track_player: Node)
signal track_player_unregistered(track_player: Node)

@export var sequence: SequencerSequence = null

var bpm: float = 120.0
var bars: int = 8
var beats_per_bar: int = 4
var subdivisions_per_beat: int = 4

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
var _internal_track_voices: Dictionary = {}
var _internal_track_indices_signature: String = ""

func _ready() -> void:
	set_process(true)
	_refresh_internal_track_voices()

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
			_sync_internal_track_voices(previous_position, song_position)
			_sync_registered_track_players(previous_position, song_position)
			song_position_changed.emit(previous_position, song_position)
			pause()
			return

	_sync_internal_track_voices(previous_position, song_position)
	_sync_registered_track_players(previous_position, song_position)
	song_position_changed.emit(previous_position, song_position)

func play() -> void:
	if is_playing:
		return
	_refresh_internal_track_voices()
	is_playing = true
	playback_started.emit()

func pause() -> void:
	if not is_playing:
		return

	is_playing = false
	_stop_internal_track_voices()
	playback_paused.emit()

func set_song_position(value: float) -> void:
	seek_song_position(value, false)

func seek_song_position(value: float, trigger_active_clip: bool = false) -> void:
	var previous_position := song_position
	song_position = clamp(value, 0.0, float(get_total_subdivisions()))

	_seek_internal_track_voices(song_position, trigger_active_clip)
	_seek_registered_track_players(song_position, trigger_active_clip)

	song_position_changed.emit(previous_position, song_position)

func get_total_subdivisions() -> int:
	if sequence != null:
		return sequence.get_total_subdivisions()

	return max(1, bars) * max(1, beats_per_bar) * max(1, subdivisions_per_beat)

func _get_subdivisions_per_second() -> float:
	if sequence != null:
		return sequence.get_subdivisions_per_second()

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

func get_registered_track_players() -> Array:
	return _registered_track_players.duplicate()

func resolve_track_bus(track_index: int) -> StringName:
	if track_bus_overrides.has(track_index):
		return StringName(str(track_bus_overrides[track_index]))

	if sequence != null:
		return sequence.get_track_bus(track_index)

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

func _build_internal_track_indices_signature() -> String:
	var resolved_indices: Array[int] = []

	for track_index in internal_track_indices:
		if track_index < 0:
			continue
		if resolved_indices.has(track_index):
			continue
		resolved_indices.append(track_index)

	resolved_indices.sort()

	var parts: Array[String] = []
	for track_index in resolved_indices:
		parts.append(str(track_index))

	return ",".join(parts)

func _refresh_internal_track_voices() -> void:
	var new_signature := _build_internal_track_indices_signature()
	if new_signature == _internal_track_indices_signature:
		return

	_internal_track_indices_signature = new_signature

	var wanted_track_indices: Array[int] = []

	for track_index in internal_track_indices:
		if track_index < 0:
			continue
		if wanted_track_indices.has(track_index):
			continue
		wanted_track_indices.append(track_index)

	for existing_track_index in _internal_track_voices.keys():
		if wanted_track_indices.has(int(existing_track_index)):
			continue

		var existing_voice := _internal_track_voices[existing_track_index] as Node
		if existing_voice != null and is_instance_valid(existing_voice):
			if existing_voice.has_method("stop_audio"):
				existing_voice.stop_audio()
			existing_voice.queue_free()

		_internal_track_voices.erase(existing_track_index)

	for track_index in wanted_track_indices:
		var voice: Node = null

		if _internal_track_voices.has(track_index):
			voice = _internal_track_voices[track_index] as Node
		else:
			voice = SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT.new()
			voice.name = "InternalTrackVoice%d" % track_index
			add_child(voice)
			_internal_track_voices[track_index] = voice

		if voice != null and is_instance_valid(voice) and voice.has_method("configure"):
			voice.configure(
				self,
				sequence,
				track_index,
				0.0,
				0.0,
				1.0,
				&""
			)

func _seek_internal_track_voices(position: float, trigger_active_clip: bool = false) -> void:
	for track_index in _internal_track_voices.keys():
		var voice := _internal_track_voices[track_index] as Node
		if voice == null or not is_instance_valid(voice):
			_internal_track_voices.erase(track_index)
			continue

		if voice.has_method("seek_from_master"):
			voice.seek_from_master(position, trigger_active_clip)

func _sync_internal_track_voices(previous_position: float, current_position: float) -> void:
	for track_index in _internal_track_voices.keys():
		var voice := _internal_track_voices[track_index] as Node
		if voice == null or not is_instance_valid(voice):
			_internal_track_voices.erase(track_index)
			continue

		if voice.has_method("sync_from_master"):
			voice.sync_from_master(previous_position, current_position)

func _stop_internal_track_voices() -> void:
	for track_index in _internal_track_voices.keys():
		var voice := _internal_track_voices[track_index] as Node
		if voice == null or not is_instance_valid(voice):
			continue

		if voice.has_method("stop_audio"):
			voice.stop_audio()

func clear_internal_audio_stream_cache() -> void:
	for voice in _internal_track_voices.values():
		if voice == null or not is_instance_valid(voice):
			continue

		if voice.has_method("clear_audio_stream_cache"):
			voice.clear_audio_stream_cache()

func _seek_registered_track_players(position: float, trigger_active_clip: bool = false) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if track_player.has_method("seek_from_master"):
			track_player.seek_from_master(position, trigger_active_clip)
		elif track_player.has_method("sync_from_master"):
			track_player.sync_from_master(position, position)

func _sync_registered_track_players(previous_position: float, current_position: float) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]

		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if track_player.has_method("sync_from_master"):
			track_player.sync_from_master(previous_position, current_position)
