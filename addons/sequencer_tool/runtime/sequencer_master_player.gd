extends Node

const SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_audio_track_voice.gd")

signal playback_started()
signal playback_paused()
signal song_position_changed(previous_position: float, current_position: float)
signal track_player_registered(track_player: Node)
signal track_player_unregistered(track_player: Node)

@export var sequence: SequencerSequence = null
@export var fade_curve: Curve = null

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

var _internal_track_voice_volumes: Dictionary = {}
var _internal_track_voice_enabled: Dictionary = {}
var _internal_track_voice_fade_start_volumes: Dictionary = {}
var _internal_track_voice_fade_target_volumes: Dictionary = {}
var _internal_track_voice_fade_elapsed: float = 0.0
var _internal_track_voice_fade_duration: float = 0.0
var _internal_track_voice_fading: bool = false

func _ready() -> void:
	set_process(true)
	_refresh_internal_track_voices()

func _process(delta: float) -> void:
	if not is_playing:
		return

	_update_internal_track_voice_fade(delta)

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

	if track_player.has_method("refresh_runtime_setup"):
			track_player.refresh_runtime_setup()

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
	if active_track_group == group_name and fade_seconds < 0.0:
		return

	active_track_group = group_name

	if fade_seconds >= 0.0:
		track_group_fade_seconds = fade_seconds

	var resolved_fade_seconds := track_group_fade_seconds
	if fade_seconds >= 0.0:
		resolved_fade_seconds = fade_seconds

	if is_playing and resolved_fade_seconds > 0.0:
		_begin_internal_track_group_fade(resolved_fade_seconds)
	else:
		_internal_track_voice_fading = false
		refresh_runtime_setup()

func get_active_internal_track_indices() -> Array[int]:
	var group_track_indices := _get_active_track_group_track_indices()
	if not group_track_indices.is_empty():
		return group_track_indices

	return _sanitize_track_indices(internal_track_indices)

func _sanitize_track_indices(values: Array) -> Array[int]:
	var result: Array[int] = []

	for value in values:
		var track_index := int(value)
		if track_index < 0:
			continue
		if result.has(track_index):
			continue
		result.append(track_index)

	return result

func _get_active_track_groups() -> Dictionary:
	if not track_groups.is_empty():
		return track_groups

	if sequence != null:
		var sequence_track_groups = sequence.get("track_groups")
		if sequence_track_groups is Dictionary:
			return sequence_track_groups as Dictionary

	return {}

func _get_active_track_group_track_indices() -> Array[int]:
	if active_track_group.is_empty():
		return []

	var groups := _get_active_track_groups()
	if not groups.has(active_track_group):
		return []

	var group_data = groups[active_track_group]

	if group_data is Array:
		return _sanitize_track_indices(group_data as Array)

	if group_data is Dictionary:
		var group_dictionary := group_data as Dictionary
		if group_dictionary.has("track_indices"):
			var track_indices = group_dictionary["track_indices"]
			if track_indices is Array:
				return _sanitize_track_indices(track_indices as Array)

	return []

func refresh_runtime_setup() -> void:
	_internal_track_indices_signature = "__force_refresh__"
	_refresh_internal_track_voices()
	_refresh_registered_track_player_setups()


func set_sequence_resource(value: SequencerSequence) -> void:
	if sequence == value:
		return

	sequence = value
	refresh_runtime_setup()


func set_internal_track_indices(value: Array[int]) -> void:
	internal_track_indices = value.duplicate()
	refresh_runtime_setup()

func _build_internal_track_indices_signature() -> String:
	var resolved_indices := get_active_internal_track_indices()
	resolved_indices.sort()

	var parts: Array[String] = []
	for track_index in resolved_indices:
		parts.append(str(track_index))

	return "%s:%s" % [
		str(active_track_group),
		",".join(parts)
	]

func _configure_internal_track_voice_volume(track_index: int, voice_volume: float) -> void:
	if not _internal_track_voices.has(track_index):
		return

	var voice := _internal_track_voices[track_index] as Node
	if voice == null or not is_instance_valid(voice):
		return

	var resolved_volume := max(0.0, voice_volume)
	_internal_track_voice_volumes[track_index] = resolved_volume

	if voice.has_method("configure"):
		voice.configure(
			self,
			sequence,
			track_index,
			0.0,
			0.0,
			resolved_volume,
			&""
		)

func _ensure_internal_track_voice(track_index: int, voice_volume: float = 1.0) -> Node:
	if _internal_track_voices.has(track_index):
		var existing_voice := _internal_track_voices[track_index] as Node
		if existing_voice != null and is_instance_valid(existing_voice):
			_configure_internal_track_voice_volume(track_index, voice_volume)
			return existing_voice

	var voice := SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT.new()
	voice.name = "InternalTrackVoice%d" % track_index
	add_child(voice)

	_internal_track_voices[track_index] = voice
	_internal_track_voice_enabled[track_index] = true
	_configure_internal_track_voice_volume(track_index, voice_volume)

	return voice

func _refresh_internal_track_voices() -> void:
	var new_signature := _build_internal_track_indices_signature()
	if new_signature == _internal_track_indices_signature:
		return

	_internal_track_indices_signature = new_signature
	var wanted_track_indices := get_active_internal_track_indices()

	for existing_track_index in _internal_track_voices.keys():
		if wanted_track_indices.has(int(existing_track_index)):
			continue

		var existing_voice := _internal_track_voices[existing_track_index] as Node
		if existing_voice != null and is_instance_valid(existing_voice):
			if existing_voice.has_method("stop_audio"):
				existing_voice.stop_audio()
			existing_voice.queue_free()

		_internal_track_voices.erase(existing_track_index)
		_internal_track_voice_volumes.erase(existing_track_index)
		_internal_track_voice_enabled.erase(existing_track_index)

		for track_index in wanted_track_indices:
				_internal_track_voice_enabled[track_index] = true
				_ensure_internal_track_voice(track_index, 1.0)

func _seek_internal_track_voices(position: float, trigger_active_clip: bool = false) -> void:
	for track_index in _internal_track_voices.keys():
		var voice := _internal_track_voices[track_index] as Node
		if voice == null or not is_instance_valid(voice):
			_internal_track_voices.erase(track_index)
			continue

		if voice.has_method("seek_from_master"):
			voice.seek_from_master(position, trigger_active_clip)

func _sample_track_group_fade_curve(t: float) -> float:
	var resolved_t := clamp(t, 0.0, 1.0)

	if fade_curve == null:
		return resolved_t

	var point_count := fade_curve.get_point_count()
	if point_count <= 0:
		return resolved_t

	if point_count == 1:
		return clamp(fade_curve.get_point_position(0).y, 0.0, 1.0)

	var points: Array[Vector2] = []
	for i in range(point_count):
		points.append(fade_curve.get_point_position(i))

	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x
	)

	if resolved_t <= points[0].x:
		return clamp(points[0].y, 0.0, 1.0)

	for i in range(1, points.size()):
		var previous_point := points[i - 1]
		var next_point := points[i]

		if resolved_t > next_point.x:
			continue

		var segment_length := next_point.x - previous_point.x
		if segment_length <= 0.00001:
			return clamp(next_point.y, 0.0, 1.0)

		var segment_t := clamp((resolved_t - previous_point.x) / segment_length, 0.0, 1.0)
		return clamp(lerp(previous_point.y, next_point.y, segment_t), 0.0, 1.0)

	return clamp(points.back().y, 0.0, 1.0)

func _begin_internal_track_group_fade(fade_seconds: float) -> void:
	var wanted_track_indices := get_active_internal_track_indices()
	var all_track_indices: Array[int] = []

	for existing_track_index in _internal_track_voices.keys():
		var resolved_track_index := int(existing_track_index)
		if not all_track_indices.has(resolved_track_index):
			all_track_indices.append(resolved_track_index)

	for track_index in wanted_track_indices:
		if not all_track_indices.has(track_index):
			all_track_indices.append(track_index)

	_internal_track_voice_fade_start_volumes.clear()
	_internal_track_voice_fade_target_volumes.clear()

	for track_index in all_track_indices:
		var is_incoming := wanted_track_indices.has(track_index)
		var current_volume := float(_internal_track_voice_volumes.get(track_index, 0.0))

		if is_incoming:
			if not _internal_track_voices.has(track_index):
				current_volume = 0.0
				_ensure_internal_track_voice(track_index, current_volume)

			_internal_track_voice_enabled[track_index] = true
			_internal_track_voice_fade_start_volumes[track_index] = current_volume
			_internal_track_voice_fade_target_volumes[track_index] = 1.0
			_configure_internal_track_voice_volume(track_index, current_volume)
		else:
			_internal_track_voice_enabled[track_index] = false
			_internal_track_voice_fade_start_volumes[track_index] = current_volume
			_internal_track_voice_fade_target_volumes[track_index] = 0.0
			_configure_internal_track_voice_volume(track_index, current_volume)

	_internal_track_voice_fade_elapsed = 0.0
	_internal_track_voice_fade_duration = max(0.001, fade_seconds)
	_internal_track_voice_fading = true

func _update_internal_track_voice_fade(delta: float) -> void:
	if not _internal_track_voice_fading:
		return

	_internal_track_voice_fade_elapsed += delta

	var raw_t := clamp(_internal_track_voice_fade_elapsed / _internal_track_voice_fade_duration, 0.0, 1.0)
	var curve_t := _sample_track_group_fade_curve(raw_t)

	for track_index in _internal_track_voice_fade_target_volumes.keys():
		var start_volume := float(_internal_track_voice_fade_start_volumes.get(track_index, 0.0))
		var target_volume := float(_internal_track_voice_fade_target_volumes.get(track_index, 0.0))
		var resolved_volume := lerp(start_volume, target_volume, curve_t)

		_configure_internal_track_voice_volume(int(track_index), resolved_volume)

	if raw_t < 1.0:
		return

	_internal_track_voice_fading = false
	_internal_track_voice_fade_start_volumes.clear()
	_internal_track_voice_fade_target_volumes.clear()
	_internal_track_voice_fade_elapsed = 0.0
	_internal_track_voice_fade_duration = 0.0

	_internal_track_indices_signature = "__force_refresh__"
	_refresh_internal_track_voices()

func _sync_internal_track_voices(previous_position: float, current_position: float) -> void:
	for track_index in _internal_track_voices.keys():
		var voice := _internal_track_voices[track_index] as Node
		if voice == null or not is_instance_valid(voice):
			_internal_track_voices.erase(track_index)
			continue
		if not bool(_internal_track_voice_enabled.get(track_index, true)):
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

func _refresh_registered_track_player_setups() -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if track_player.has_method("refresh_runtime_setup"):
			track_player.refresh_runtime_setup()

func _sync_registered_track_players(previous_position: float, current_position: float) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]

		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if track_player.has_method("sync_from_master"):
			track_player.sync_from_master(previous_position, current_position)
