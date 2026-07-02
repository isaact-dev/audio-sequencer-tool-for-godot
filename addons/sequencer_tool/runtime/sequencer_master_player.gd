extends Node

const SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_audio_track_voice.gd")

signal playback_started()
signal playback_paused()
signal playback_finished()
signal song_position_changed(previous_position: float, current_position: float)
signal track_player_registered(track_player: Node)
signal track_player_unregistered(track_player: Node)
signal clip_started(track_index: int, clip_index: int, clip_data: Dictionary, source: Node)
signal clip_stopped(track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName, source: Node)
signal active_track_group_changed(previous_group: StringName, current_group: StringName)
signal track_group_fade_started(previous_group: StringName, current_group: StringName, fade_seconds: float)
signal track_group_fade_completed(previous_group: StringName, current_group: StringName)
signal sequence_changed(new_sequence: SequencerSequence)

@export_group("Sequence")
@export var sequence: SequencerSequence = null:
	set(value):
		if sequence == value:
			return

		sequence = value
		sequence_changed.emit(sequence)

		if is_inside_tree():
			refresh_runtime_setup()

@export_group("Playback")
@export var autoplay: bool = false
@export var loop_enabled: bool = false
@export var initial_active_track_group: StringName = &""

@export_group("Internal Tracks")
@export var internal_track_indices: Array[int] = []

@export_group("Routing")
@export var default_audio_bus: StringName = &"Master"

@export_group("Track Group Fades")
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var track_group_fade_seconds: float = 1.0
@export var fade_in_curve: Curve = null
@export var fade_out_curve: Curve = null

var bpm: float = 120.0
var bars: int = 8
var beats_per_bar: int = 4
var subdivisions_per_beat: int = 4

var is_playing: bool = false
var song_position: float = 0.0

var active_track_group: StringName = &""
var track_groups: Dictionary = {}

var track_bus_overrides: Dictionary = {}
var _missing_audio_bus_warning_keys: Dictionary = {}
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
var _internal_track_voice_fade_is_incoming: Dictionary = {}
var _track_group_fade_previous_group: StringName = &""
var _track_group_fade_current_group: StringName = &""

var _registered_track_player_fade_start_volumes: Dictionary = {}
var _registered_track_player_fade_target_volumes: Dictionary = {}
var _registered_track_player_fade_is_incoming: Dictionary = {}
var _registered_track_player_fade_enabled: Dictionary = {}

func _ready() -> void:
	set_process(true)

	if not initial_active_track_group.is_empty():
		if has_track_group(initial_active_track_group):
			active_track_group = initial_active_track_group
		else:
			push_warning("SequencerMasterPlayer: Initial track group does not exist: %s" % str(initial_active_track_group))

	_refresh_internal_track_voices()

	if autoplay:
		call_deferred("_start_autoplay")

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
			_finish_playback_at_end(previous_position)
			return


	_sync_internal_track_voices(previous_position, song_position)
	_sync_registered_track_players(previous_position, song_position)
	song_position_changed.emit(previous_position, song_position)

func _start_autoplay() -> void:
	if autoplay:
		play()

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

func _finish_playback_at_end(previous_position: float) -> void:
	if not is_playing:
		return

	is_playing = false
	_stop_internal_track_voices()
	_sync_registered_track_players(previous_position, song_position)
	song_position_changed.emit(previous_position, song_position)
	playback_finished.emit()
	playback_paused.emit()

func play_from_start(trigger_active_clip: bool = false) -> void:
	seek_song_position(0.0, trigger_active_clip)
	play()

func set_loop_enabled(value: bool) -> void:
	loop_enabled = value

func set_song_position(value: float) -> void:
	seek_song_position(value, false)

func seek_song_position(value: float, trigger_active_clip: bool = false) -> void:
	var previous_position := song_position
	song_position = clamp(value, 0.0, float(get_total_subdivisions()))

	_seek_internal_track_voices(song_position, trigger_active_clip)
	_seek_registered_track_players(song_position, trigger_active_clip)

	song_position_changed.emit(previous_position, song_position)

func set_song_position_seconds(seconds: float) -> void:
	seek_song_position_seconds(seconds, false)

func seek_song_position_seconds(seconds: float, trigger_active_clip: bool = false) -> void:
	seek_song_position(seconds_to_subdivisions(seconds), trigger_active_clip)

func set_initial_active_track_group(group_name: StringName) -> void:
	initial_active_track_group = group_name

func set_track_group_fade_seconds(value: float) -> void:
	track_group_fade_seconds = max(0.0, value)

func get_total_subdivisions() -> int:
	if sequence != null:
		return sequence.get_total_subdivisions()

	return max(1, bars) * max(1, beats_per_bar) * max(1, subdivisions_per_beat)

func _get_subdivisions_per_second() -> float:
	if sequence != null:
		return sequence.get_subdivisions_per_second()

	return (max(1.0, bpm) / 60.0) * float(max(1, subdivisions_per_beat))

func get_sequence_resource() -> Resource:
	return sequence

func get_track_count() -> int:
	if sequence != null and sequence.has_method("get_track_count"):
		return int(sequence.get_track_count())

	if sequence != null:
		return max(0, int(sequence.get("track_count")))

	return 0

func is_valid_track_index(track_index: int) -> bool:
	if sequence != null and sequence.has_method("is_valid_track_index"):
		return bool(sequence.is_valid_track_index(track_index))

	return track_index >= 0 and track_index < get_track_count()

func get_track_name(track_index: int) -> String:
	if sequence != null and sequence.has_method("get_track_name"):
		return str(sequence.get_track_name(track_index))

	if not is_valid_track_index(track_index):
		return ""

	return "Track %d" % [track_index + 1]

func get_track_index_by_name(track_name: String) -> int:
	if sequence != null and sequence.has_method("get_track_index_by_name"):
		return int(sequence.get_track_index_by_name(track_name))

	var resolved_track_name := track_name.strip_edges()
	if resolved_track_name.is_empty():
		return -1

	for track_index in range(get_track_count()):
		if get_track_name(track_index) == resolved_track_name:
			return track_index

	return -1

func get_internal_track_names() -> Array[String]:
	var result: Array[String] = []

	for track_index in internal_track_indices:
		var resolved_track_index := int(track_index)
		if not is_valid_track_index(resolved_track_index):
			continue

		result.append(get_track_name(resolved_track_index))

	return result

func set_internal_track_names(track_names: Array[String]) -> void:
	var resolved_indices: Array[int] = []

	for track_name in track_names:
		var resolved_track_index := get_track_index_by_name(track_name)
		if resolved_track_index < 0:
			continue
		if resolved_indices.has(resolved_track_index):
			continue

		resolved_indices.append(resolved_track_index)

	set_internal_track_indices(resolved_indices)

func get_song_position() -> float:
	return song_position

func get_song_position_seconds() -> float:
	return subdivisions_to_seconds(song_position)

func get_song_duration_subdivisions() -> float:
	return float(get_total_subdivisions())

func get_song_duration_seconds() -> float:
	return subdivisions_to_seconds(get_song_duration_subdivisions())

func subdivisions_to_seconds(subdivision_position: float) -> float:
	var subdivisions_per_second := _get_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0
	return max(0.0, subdivision_position) / subdivisions_per_second

func seconds_to_subdivisions(seconds: float) -> float:
	return max(0.0, seconds) * _get_subdivisions_per_second()

func register_track_player(track_player: Node) -> void:
	if track_player == null:
		return

	if _registered_track_players.has(track_player):
		return

	_registered_track_players.append(track_player)
	track_player_registered.emit(track_player)

	if track_player.has_signal("clip_started") and not track_player.clip_started.is_connected(_on_registered_track_player_clip_started):
		track_player.clip_started.connect(_on_registered_track_player_clip_started.bind(track_player))
	if track_player.has_signal("clip_stopped") and not track_player.clip_stopped.is_connected(_on_registered_track_player_clip_stopped):
		track_player.clip_stopped.connect(_on_registered_track_player_clip_stopped.bind(track_player))

	if track_player.has_method("refresh_runtime_setup"):
		track_player.refresh_runtime_setup()

func unregister_track_player(track_player: Node) -> void:
	if track_player == null:
		return

	if not _registered_track_players.has(track_player):
		return

	var started_callable := _on_registered_track_player_clip_started.bind(track_player)
	var stopped_callable := _on_registered_track_player_clip_stopped.bind(track_player)

	if track_player.has_signal("clip_started") and track_player.clip_started.is_connected(started_callable):
		track_player.clip_started.disconnect(started_callable)
	if track_player.has_signal("clip_stopped") and track_player.clip_stopped.is_connected(stopped_callable):
		track_player.clip_stopped.disconnect(stopped_callable)

	_registered_track_players.erase(track_player)
	track_player_unregistered.emit(track_player)

func get_registered_track_players() -> Array:
	return _registered_track_players.duplicate()

func _set_registered_track_player_group_fade_volume(track_player: Node, value: float) -> void:
	if track_player == null or not is_instance_valid(track_player):
		return
	if track_player.has_method("set_master_group_fade_volume"):
		track_player.set_master_group_fade_volume(clamp(value, 0.0, 1.0))

func _audio_bus_exists(bus_name: StringName) -> bool:
	if bus_name.is_empty():
		return false
	return AudioServer.get_bus_index(str(bus_name)) != -1

func _get_valid_audio_bus_fallback(fallback_bus: StringName = &"Master") -> StringName:
	var resolved_fallback := StringName(str(fallback_bus).strip_edges())
	if _audio_bus_exists(resolved_fallback):
		return resolved_fallback
	if _audio_bus_exists(&"Master"):
		return &"Master"
	return resolved_fallback

func _warn_missing_audio_bus(bus_name: StringName, fallback_bus: StringName) -> void:
	if bus_name.is_empty():
		return

	var warning_key := str(bus_name)
	if _missing_audio_bus_warning_keys.has(warning_key):
		return

	_missing_audio_bus_warning_keys[warning_key] = true
	push_warning(
		"SequencerMasterPlayer: Audio bus does not exist: %s. Falling back to %s." % [
			str(bus_name),
			str(fallback_bus)
		]
	)

func _get_sequence_authored_track_bus_override(track_index: int) -> StringName:
	if sequence == null:
		return &""

	var overrides = sequence.get("track_bus_overrides")
	if not overrides is Dictionary:
		return &""

	var override_dictionary := overrides as Dictionary
	if not override_dictionary.has(track_index):
		return &""

	return StringName(str(override_dictionary[track_index]).strip_edges())

func resolve_track_bus(track_index: int) -> StringName:
	var fallback_bus := _get_valid_audio_bus_fallback(default_audio_bus)

	if track_bus_overrides.has(track_index):
		var runtime_bus := StringName(str(track_bus_overrides[track_index]).strip_edges())
		if _audio_bus_exists(runtime_bus):
			return runtime_bus
		if not runtime_bus.is_empty():
			_warn_missing_audio_bus(runtime_bus, fallback_bus)

	var authored_track_bus := _get_sequence_authored_track_bus_override(track_index)
	if not authored_track_bus.is_empty():
		if _audio_bus_exists(authored_track_bus):
			return authored_track_bus
		_warn_missing_audio_bus(authored_track_bus, fallback_bus)

	var group_bus := _get_active_track_group_bus_override()
	if not group_bus.is_empty():
		if _audio_bus_exists(group_bus):
			return group_bus
		_warn_missing_audio_bus(group_bus, fallback_bus)

	if sequence != null:
		var sequence_default_bus := StringName(str(sequence.get("default_audio_bus")).strip_edges())
		if _audio_bus_exists(sequence_default_bus):
			return sequence_default_bus
		if not sequence_default_bus.is_empty():
			_warn_missing_audio_bus(sequence_default_bus, fallback_bus)

	return fallback_bus

func set_track_bus_override(track_index: int, bus_name: StringName) -> void:
	if track_index < 0:
		return
	var resolved_bus_name := StringName(str(bus_name).strip_edges())
	if resolved_bus_name.is_empty():
		track_bus_overrides.erase(track_index)
	else:
		track_bus_overrides[track_index] = resolved_bus_name

func clear_track_bus_override(track_index: int) -> void:
	if track_bus_overrides.has(track_index):
		track_bus_overrides.erase(track_index)

func set_active_track_group(group_name: StringName, fade_seconds: float = -1.0) -> void:
	if not group_name.is_empty() and not has_track_group(group_name):
		push_warning("SequencerMasterPlayer: Track group does not exist: %s" % str(group_name))
		return
	var previous_group := active_track_group
	var group_changed := previous_group != group_name

	if not group_changed and fade_seconds < 0.0:
		return

	active_track_group = group_name

	if group_changed:
		active_track_group_changed.emit(previous_group, active_track_group)

	if fade_seconds >= 0.0:
		track_group_fade_seconds = max(0.0, fade_seconds)

	var resolved_fade_seconds := max(0.0, track_group_fade_seconds)
	if fade_seconds >= 0.0:
		resolved_fade_seconds = max(0.0, fade_seconds)

	if is_playing and resolved_fade_seconds > 0.0:
		_begin_internal_track_group_fade(resolved_fade_seconds, previous_group, active_track_group)
	else:
		_internal_track_voice_fading = false
		_track_group_fade_previous_group = &""
		_track_group_fade_current_group = &""
		refresh_runtime_setup()
		_stop_inactive_registered_track_players_for_current_group()
		_reset_registered_track_player_group_fade_volumes_for_current_group()

func get_active_internal_track_indices() -> Array[int]:
	var allowed_track_indices := _sanitize_track_indices(internal_track_indices)
	var group_track_indices := _get_active_track_group_track_indices()

	if group_track_indices.is_empty():
		return allowed_track_indices

	var result: Array[int] = []
	for track_index in allowed_track_indices:
		if group_track_indices.has(track_index):
			result.append(track_index)

	return result

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
	return get_track_group_track_indices(active_track_group)

func _is_track_active_in_current_group(track_index: int) -> bool:
	if active_track_group.is_empty():
		return true

	var active_track_indices := _get_active_track_group_track_indices()
	return active_track_indices.has(track_index)

func get_active_track_group() -> StringName:
	return active_track_group

func get_active_track_group_bus_override() -> StringName:
	return _get_active_track_group_bus_override()

func clear_active_track_group(fade_seconds: float = -1.0) -> void:
	set_active_track_group(&"", fade_seconds)

func has_track_group(group_name: StringName) -> bool:
	if group_name.is_empty():
		return true

	var groups := _get_active_track_groups()
	return groups.has(group_name)

func get_track_group_names() -> Array[StringName]:
	var result: Array[StringName] = []
	var groups := _get_active_track_groups()

	for group_name in groups.keys():
		result.append(StringName(str(group_name)))

	result.sort()
	return result

func get_track_group_track_indices(group_name: StringName) -> Array[int]:
	if group_name.is_empty():
		return []

	var groups := _get_active_track_groups()
	if not groups.has(group_name):
		return []

	var group_data = groups[group_name]

	if group_data is Array:
		return _sanitize_track_indices(group_data as Array)

	if group_data is Dictionary:
		var group_dictionary := group_data as Dictionary
		if group_dictionary.has("track_indices"):
			var track_indices = group_dictionary["track_indices"]
			if track_indices is Array:
				return _sanitize_track_indices(track_indices as Array)

	return []

func _get_registered_track_player_track_index(track_player: Node) -> int:
	if track_player == null or not is_instance_valid(track_player):
		return -1

	var value = track_player.get("track_index")
	if value == null:
		return -1

	return int(value)

func get_clip_count() -> int:
	if sequence != null and sequence.has_method("get_clip_count"):
		return int(sequence.get_clip_count())

	if sequence != null:
		var sequence_clips = sequence.get("clips")
		if sequence_clips is Array:
			return (sequence_clips as Array).size()

	return 0

func is_valid_clip_index(clip_index: int) -> bool:
	if sequence != null and sequence.has_method("is_valid_clip_index"):
		return bool(sequence.is_valid_clip_index(clip_index))

	return clip_index >= 0 and clip_index < get_clip_count()

func get_clip_data(clip_index: int) -> Dictionary:
	if sequence != null and sequence.has_method("get_clip_data"):
		return sequence.get_clip_data(clip_index)

	if sequence == null:
		return {}

	var sequence_clips = sequence.get("clips")
	if not sequence_clips is Array:
		return {}

	var clips_array := sequence_clips as Array
	if clip_index < 0 or clip_index >= clips_array.size():
		return {}

	var clip = clips_array[clip_index]
	if clip is Dictionary:
		return (clip as Dictionary).duplicate(true)

	return {}

func get_track_clip_indices(track_index: int) -> Array:
	if sequence != null and sequence.has_method("get_track_clip_indices"):
		return sequence.get_track_clip_indices(track_index)

	var result: Array[int] = []

	if sequence == null:
		return result

	var sequence_clips = sequence.get("clips")
	if not sequence_clips is Array:
		return result

	var clips_array := sequence_clips as Array
	for clip_index in range(clips_array.size()):
		var clip = clips_array[clip_index]
		if not clip is Dictionary:
			continue
		if int((clip as Dictionary).get("track", -1)) != track_index:
			continue
		result.append(clip_index)

	return result

func get_clip_name(clip_index: int) -> String:
	if sequence != null and sequence.has_method("get_clip_name"):
		return str(sequence.get_clip_name(clip_index))

	var clip := get_clip_data(clip_index)
	if clip.is_empty():
		return ""

	return str(clip.get("name", "Clip"))

func get_clip_track_index(clip_index: int) -> int:
	if sequence != null and sequence.has_method("get_clip_track_index"):
		return int(sequence.get_clip_track_index(clip_index))

	var clip := get_clip_data(clip_index)
	if clip.is_empty():
		return -1

	return int(clip.get("track", -1))

func get_clip_start(clip_index: int) -> float:
	if sequence != null and sequence.has_method("get_clip_start"):
		return float(sequence.get_clip_start(clip_index))

	var clip := get_clip_data(clip_index)
	if clip.is_empty():
		return 0.0

	return max(0.0, float(clip.get("start", 0.0)))

func get_clip_length(clip_index: int) -> float:
	if sequence != null and sequence.has_method("get_clip_length"):
		return float(sequence.get_clip_length(clip_index))

	var clip := get_clip_data(clip_index)
	if clip.is_empty():
		return 0.0

	return max(0.0, float(clip.get("length", 0.0)))

func get_clip_end(clip_index: int) -> float:
	if sequence != null and sequence.has_method("get_clip_end"):
		return float(sequence.get_clip_end(clip_index))

	return get_clip_start(clip_index) + get_clip_length(clip_index)

func _is_registered_track_player_active_in_current_group(track_player: Node) -> bool:
	var track_index := _get_registered_track_player_track_index(track_player)
	return _is_track_active_in_current_group(track_index)

func _stop_inactive_registered_track_players_for_current_group() -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		var track_index := _get_registered_track_player_track_index(track_player)
		if _is_track_active_in_current_group(track_index):
			continue

		if track_player.has_method("stop_audio"):
			track_player.stop_audio()

func _reset_registered_track_player_group_fade_volumes_for_current_group() -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		if _is_registered_track_player_active_in_current_group(track_player):
			_set_registered_track_player_group_fade_volume(track_player, 1.0)
		else:
			_set_registered_track_player_group_fade_volume(track_player, 0.0)

func _get_active_track_group_bus_override() -> StringName:
	if active_track_group.is_empty():
		return &""

	var groups := _get_active_track_groups()
	if not groups.has(active_track_group):
		return &""

	var group_data = groups[active_track_group]
	if not group_data is Dictionary:
		return &""

	return StringName(str((group_data as Dictionary).get("bus_override", "")).strip_edges())

func get_track_group_bus_override(group_name: StringName) -> StringName:
	if group_name.is_empty():
		return &""

	if sequence != null and sequence.has_method("get_track_group_bus_override"):
		return sequence.get_track_group_bus_override(group_name)

	var groups := _get_active_track_groups()
	if not groups.has(group_name):
		return &""

	var group_data = groups[group_name]
	if not group_data is Dictionary:
		return &""

	return StringName(str((group_data as Dictionary).get("bus_override", "")).strip_edges())

func refresh_runtime_setup() -> void:
	_internal_track_indices_signature = "__force_refresh__"
	_refresh_internal_track_voices()
	_refresh_registered_track_player_setups()

func set_sequence_resource(value: SequencerSequence) -> void:
	sequence = value

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
	voice.clip_started.connect(_on_internal_track_voice_clip_started.bind(voice))
	voice.clip_stopped.connect(_on_internal_track_voice_clip_stopped.bind(voice))

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
			if existing_voice.has_method("release_audio_player"):
				existing_voice.release_audio_player()
			elif existing_voice.has_method("stop_audio"):
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

func _sample_normalized_curve(curve: Curve, t: float, fallback_value: float) -> float:
	var resolved_t := clamp(t, 0.0, 1.0)

	if curve == null:
		return clamp(fallback_value, 0.0, 1.0)

	return clamp(curve.sample_baked(resolved_t), 0.0, 1.0)

func _begin_internal_track_group_fade(fade_seconds: float, previous_group: StringName, current_group: StringName) -> void:
	_track_group_fade_previous_group = previous_group
	_track_group_fade_current_group = current_group
	track_group_fade_started.emit(previous_group, current_group, fade_seconds)
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
	_internal_track_voice_fade_is_incoming.clear()
	_registered_track_player_fade_start_volumes.clear()
	_registered_track_player_fade_target_volumes.clear()
	_registered_track_player_fade_is_incoming.clear()
	_registered_track_player_fade_enabled.clear()

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
			_internal_track_voice_fade_is_incoming[track_index] = true
			_configure_internal_track_voice_volume(track_index, current_volume)
		else:
			_internal_track_voice_enabled[track_index] = false
			_internal_track_voice_fade_start_volumes[track_index] = current_volume
			_internal_track_voice_fade_target_volumes[track_index] = 0.0
			_internal_track_voice_fade_is_incoming[track_index] = false
			_configure_internal_track_voice_volume(track_index, current_volume)

	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		var is_incoming := _is_registered_track_player_active_in_current_group(track_player)
		var current_volume := 1.0
		if _registered_track_player_fade_target_volumes.has(track_player):
			current_volume = float(_registered_track_player_fade_target_volumes.get(track_player, 1.0))

		if is_incoming:
			_registered_track_player_fade_start_volumes[track_player] = 0.0
			_registered_track_player_fade_target_volumes[track_player] = 1.0
			_registered_track_player_fade_is_incoming[track_player] = true
			_registered_track_player_fade_enabled[track_player] = true
			_set_registered_track_player_group_fade_volume(track_player, 0.0)
		else:
			_registered_track_player_fade_start_volumes[track_player] = current_volume
			_registered_track_player_fade_target_volumes[track_player] = 0.0
			_registered_track_player_fade_is_incoming[track_player] = false
			_registered_track_player_fade_enabled[track_player] = true
			_set_registered_track_player_group_fade_volume(track_player, current_volume)

	_internal_track_voice_fade_elapsed = 0.0
	_internal_track_voice_fade_duration = max(0.001, fade_seconds)
	_internal_track_voice_fading = true

func _update_internal_track_voice_fade(delta: float) -> void:
	if not _internal_track_voice_fading:
		return

	_internal_track_voice_fade_elapsed += delta

	var raw_t := clamp(_internal_track_voice_fade_elapsed / _internal_track_voice_fade_duration, 0.0, 1.0)

	for track_index in _internal_track_voice_fade_target_volumes.keys():
		var start_volume := float(_internal_track_voice_fade_start_volumes.get(track_index, 0.0))
		var target_volume := float(_internal_track_voice_fade_target_volumes.get(track_index, 0.0))
		var is_incoming := bool(_internal_track_voice_fade_is_incoming.get(track_index, true))
		var resolved_volume := 0.0

		if is_incoming:
			var fade_in_amount := _sample_normalized_curve(fade_in_curve, raw_t, raw_t)
			resolved_volume = lerp(start_volume, target_volume, fade_in_amount)
		else:
			var fade_out_volume := _sample_normalized_curve(fade_out_curve, raw_t, 1.0 - raw_t)
			resolved_volume = start_volume * fade_out_volume

		_configure_internal_track_voice_volume(int(track_index), resolved_volume)

	for track_player in _registered_track_player_fade_target_volumes.keys():
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_player_fade_start_volumes.erase(track_player)
			_registered_track_player_fade_target_volumes.erase(track_player)
			_registered_track_player_fade_is_incoming.erase(track_player)
			_registered_track_player_fade_enabled.erase(track_player)
			continue

		var start_volume := float(_registered_track_player_fade_start_volumes.get(track_player, 0.0))
		var target_volume := float(_registered_track_player_fade_target_volumes.get(track_player, 0.0))
		var is_incoming := bool(_registered_track_player_fade_is_incoming.get(track_player, true))
		var resolved_volume := 0.0

		if is_incoming:
			var fade_in_amount := _sample_normalized_curve(fade_in_curve, raw_t, raw_t)
			resolved_volume = lerp(start_volume, target_volume, fade_in_amount)
		else:
			var fade_out_volume := _sample_normalized_curve(fade_out_curve, raw_t, 1.0 - raw_t)
			resolved_volume = start_volume * fade_out_volume
		_set_registered_track_player_group_fade_volume(track_player, resolved_volume)

	if raw_t < 1.0:
		return
	var completed_previous_group := _track_group_fade_previous_group
	var completed_current_group := _track_group_fade_current_group
	_internal_track_voice_fading = false
	_internal_track_voice_fade_start_volumes.clear()
	_internal_track_voice_fade_target_volumes.clear()
	_internal_track_voice_fade_is_incoming.clear()
	_internal_track_voice_fade_elapsed = 0.0
	_internal_track_voice_fade_duration = 0.0

	_internal_track_indices_signature = "__force_refresh__"
	_refresh_internal_track_voices()

	for track_player in _registered_track_player_fade_target_volumes.keys():
		if track_player == null or not is_instance_valid(track_player):
			continue

		var is_incoming := bool(_registered_track_player_fade_is_incoming.get(track_player, true))
		if is_incoming:
			_set_registered_track_player_group_fade_volume(track_player, 1.0)
		else:
			_set_registered_track_player_group_fade_volume(track_player, 0.0)
			if track_player.has_method("stop_audio"):
				track_player.stop_audio()

	_registered_track_player_fade_start_volumes.clear()
	_registered_track_player_fade_target_volumes.clear()
	_registered_track_player_fade_is_incoming.clear()
	_registered_track_player_fade_enabled.clear()

	track_group_fade_completed.emit(completed_previous_group, completed_current_group)

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

func is_internal_track_playing_clip(track_index: int) -> bool:
	if not _internal_track_voices.has(track_index):
		return false

	var voice := _internal_track_voices[track_index] as Node
	if voice == null or not is_instance_valid(voice):
		return false

	if voice.has_method("is_playing_clip"):
		return bool(voice.is_playing_clip())

	return false

func get_internal_track_active_clip_index(track_index: int) -> int:
	if not _internal_track_voices.has(track_index):
		return -1

	var voice := _internal_track_voices[track_index] as Node
	if voice == null or not is_instance_valid(voice):
		return -1

	if voice.has_method("get_active_clip_index"):
		return int(voice.get_active_clip_index())

	return -1

func get_internal_track_active_clip_data(track_index: int) -> Dictionary:
	if not _internal_track_voices.has(track_index):
		return {}

	var voice := _internal_track_voices[track_index] as Node
	if voice == null or not is_instance_valid(voice):
		return {}

	if voice.has_method("get_active_clip_data"):
		return voice.get_active_clip_data()

	return {}

func get_internal_track_active_clip_remaining_seconds(track_index: int) -> float:
	if not _internal_track_voices.has(track_index):
		return 0.0

	var voice := _internal_track_voices[track_index] as Node
	if voice == null or not is_instance_valid(voice):
		return 0.0

	if voice.has_method("get_active_clip_remaining_seconds"):
		return float(voice.get_active_clip_remaining_seconds())

	return 0.0

func _seek_registered_track_players(position: float, trigger_active_clip: bool = false) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		var track_index := _get_registered_track_player_track_index(track_player)
		if not _is_track_active_in_current_group(track_index):
			if track_player.has_method("stop_audio"):
				track_player.stop_audio()
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

func _on_internal_track_voice_clip_started(event_track_index: int, clip_index: int, clip_data: Dictionary, source_voice: Node) -> void:
	clip_started.emit(event_track_index, clip_index, clip_data, source_voice)

func _on_internal_track_voice_clip_stopped(event_track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName, source_voice: Node) -> void:
	clip_stopped.emit(event_track_index, clip_index, clip_data, reason, source_voice)

func _on_registered_track_player_clip_started(event_track_index: int, clip_index: int, clip_data: Dictionary, source_track_player: Node) -> void:
	clip_started.emit(event_track_index, clip_index, clip_data, source_track_player)

func _on_registered_track_player_clip_stopped(event_track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName, source_track_player: Node) -> void:
	clip_stopped.emit(event_track_index, clip_index, clip_data, reason, source_track_player)

func _sync_registered_track_players(previous_position: float, current_position: float) -> void:
	for i in range(_registered_track_players.size() - 1, -1, -1):
		var track_player := _registered_track_players[i]
		if track_player == null or not is_instance_valid(track_player):
			_registered_track_players.remove_at(i)
			continue

		var track_index := _get_registered_track_player_track_index(track_player)
		if not _is_track_active_in_current_group(track_index):
			if _internal_track_voice_fading and _registered_track_player_fade_enabled.has(track_player):
				if track_player.has_method("sync_from_master"):
					track_player.sync_from_master(previous_position, current_position)
				continue

			if track_player.has_method("stop_audio"):
				track_player.stop_audio()
			continue

		if track_player.has_method("sync_from_master"):
			track_player.sync_from_master(previous_position, current_position)
