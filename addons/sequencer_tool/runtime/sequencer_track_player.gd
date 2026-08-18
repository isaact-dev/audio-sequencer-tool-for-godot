extends Node

const SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_audio_track_voice.gd")

signal master_connected(master: Node)
signal master_disconnected(master: Node)
signal master_position_synced(previous_position: float, current_position: float)
signal clip_started(track_index: int, clip_index: int, clip_data: Dictionary)
signal clip_stopped(track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName)

@export_group("Master Sync")
@export var master_path: NodePath

@export_group("Track Voice")
@export_range(0, 128, 1, "or_greater") var track_index: int = 0
@export_range(0.0, 3.0, 0.01, "or_greater") var volume: float = 1.0
@export var audio_bus_override: StringName = &""

@export_group("Offsets")
@export_range(-64.0, 64.0, 0.01, "or_less", "or_greater") var timing_offset_subdivisions: float = 0.0
@export_range(-48.0, 48.0, 0.01, "or_less", "or_greater") var pitch_offset_semitones: float = 0.0

@export_group("Random Timing Variation")
@export_range(0.0, 2.0, 0.001, "or_greater", "suffix:s") var random_timing_delay_min_seconds: float = 0.0
@export_range(0.0, 2.0, 0.001, "or_greater", "suffix:s") var random_timing_delay_max_seconds: float = 0.0

@export_group("Random Pitch Variation")
@export_range(-2.0, 2.0, 0.01, "or_less", "or_greater", "suffix:st") var random_pitch_offset_min_semitones: float = 0.0
@export_range(-2.0, 2.0, 0.01, "or_less", "or_greater", "suffix:st") var random_pitch_offset_max_semitones: float = 0.0

var master_group_fade_volume: float = 1.0
var fade_progress: float = 1.0
var external_fade_volume: float = 1.0
var _external_fade_direction: int = 1

var master: Node = null
var _voice: Node = null

func _ready() -> void:
	_ensure_voice()

	if not master_path.is_empty():
		set_master_path(master_path)

	_update_external_fade_volume()

func set_master_path(value: NodePath) -> bool:
	master_path = value

	if not is_inside_tree():
		return false

	if master_path.is_empty():
		disconnect_from_master()
		return true

	var resolved_master := get_node_or_null(master_path)
	if resolved_master == null:
		disconnect_from_master()
		return false

	connect_to_master(resolved_master)
	return true

func connect_to_master_path(value: NodePath) -> bool:
	return set_master_path(value)

func set_master(value: Node) -> bool:
	if value == null:
		disconnect_from_master()
		master_path = NodePath()
		return true

	connect_to_master(value)

	if is_inside_tree() and value.is_inside_tree():
		master_path = get_path_to(value)

	return true

func _ensure_voice() -> void:
	if _voice != null and is_instance_valid(_voice):
		return

	_voice = SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT.new()
	_voice.name = "SequencerAudioTrackVoice"
	add_child(_voice)
	if _voice.has_signal("clip_started") and not _voice.clip_started.is_connected(_on_voice_clip_started):
		_voice.clip_started.connect(_on_voice_clip_started)
	if _voice.has_signal("clip_stopped") and not _voice.clip_stopped.is_connected(_on_voice_clip_stopped):
		_voice.clip_stopped.connect(_on_voice_clip_stopped)
	_refresh_voice_configuration()

func _refresh_voice_configuration() -> void:
	if _voice == null or not is_instance_valid(_voice):
		return

	_voice.configure(
		master,
		_get_sequence(),
		track_index,
		timing_offset_subdivisions,
		pitch_offset_semitones,
		get_effective_volume(),
		audio_bus_override,
		random_timing_delay_min_seconds,
		random_timing_delay_max_seconds,
		random_pitch_offset_min_semitones,
		random_pitch_offset_max_semitones
	)

func refresh_runtime_setup() -> void:
	_ensure_voice()
	_refresh_voice_configuration()

func handle_master_sequence_changed(_new_sequence: Resource) -> void:
	stop_audio()
	refresh_runtime_setup()

func set_track_index(value: int) -> void:
	track_index = max(0, value)
	refresh_runtime_setup()

func set_track_name(track_name: String) -> bool:
	var sequence_resource := _get_sequence()
	if sequence_resource == null:
		return false

	if not sequence_resource.has_method("get_track_index_by_name"):
		return false

	var resolved_track_index := int(sequence_resource.get_track_index_by_name(track_name))
	if resolved_track_index < 0:
		return false

	set_track_index(resolved_track_index)
	return true

func set_timing_offset(value: float) -> void:
	timing_offset_subdivisions = value
	refresh_runtime_setup()

func set_pitch_offset(value: float) -> void:
	pitch_offset_semitones = value
	refresh_runtime_setup()

func set_random_timing_delay_range(min_seconds: float, max_seconds: float) -> void:
	random_timing_delay_min_seconds = max(0.0, min_seconds)
	random_timing_delay_max_seconds = max(random_timing_delay_min_seconds, max_seconds)
	refresh_runtime_setup()

func set_random_pitch_offset_range(min_semitones: float, max_semitones: float) -> void:
	random_pitch_offset_min_semitones = min(min_semitones, max_semitones)
	random_pitch_offset_max_semitones = max(min_semitones, max_semitones)
	refresh_runtime_setup()

func set_voice_volume(value: float) -> void:
	volume = max(0.0, value)
	_apply_effective_volume_to_voice()

func set_master_group_fade_volume(value: float) -> void:
	master_group_fade_volume = clamp(value, 0.0, 1.0)
	_apply_effective_volume_to_voice()

func set_audio_bus_override(value: StringName) -> void:
	audio_bus_override = value
	refresh_runtime_setup()

func _get_sequence() -> Resource:
	if master == null or not is_instance_valid(master):
		return null

	var sequence_value = master.get("sequence")
	if sequence_value is Resource:
		return sequence_value as Resource

	return null

func _get_master_song_position() -> float:
	if master == null or not is_instance_valid(master):
		return 0.0

	if master.has_method("get_song_position"):
		return float(master.get_song_position())

	var value = master.get("song_position")
	if value == null:
		return 0.0

	return max(0.0, float(value))

func _resolve_external_fade_volume(progress: float, direction: int) -> float:
	var resolved_progress := clamp(progress, 0.0, 1.0)

	if master == null or not is_instance_valid(master):
		return resolved_progress

	if direction < 0 and master.has_method("sample_fade_out_progress"):
		return clamp(
			float(master.sample_fade_out_progress(resolved_progress)),
			0.0,
			1.0
		)

	if direction >= 0 and master.has_method("sample_fade_in_progress"):
		return clamp(
			float(master.sample_fade_in_progress(resolved_progress)),
			0.0,
			1.0
		)

	return resolved_progress

func _update_external_fade_volume() -> void:
	external_fade_volume = _resolve_external_fade_volume(
		fade_progress,
		_external_fade_direction
	)

	_apply_effective_volume_to_voice()

func _apply_effective_volume_to_voice() -> void:
	if _voice == null or not is_instance_valid(_voice):
		return

	if _voice.has_method("set_voice_volume"):
		_voice.set_voice_volume(get_effective_volume())

func set_fade_progress(value: float) -> void:
	var resolved_progress := clamp(value, 0.0, 1.0)

	if resolved_progress > fade_progress:
		_external_fade_direction = 1
	elif resolved_progress < fade_progress:
		_external_fade_direction = -1

	fade_progress = resolved_progress
	_update_external_fade_volume()

func get_fade_progress() -> float:
	return clamp(fade_progress, 0.0, 1.0)

func get_external_fade_volume() -> float:
	return clamp(external_fade_volume, 0.0, 1.0)

func sync_to_current_master_position(trigger_active_clip: bool = false) -> bool:
	if master == null or not is_instance_valid(master):
		return false

	_ensure_voice()
	_refresh_voice_configuration()

	var current_position := _get_master_song_position()
	seek_from_master(current_position, trigger_active_clip)

	return true

func is_connected_to_master() -> bool:
	return master != null and is_instance_valid(master)

func get_master() -> Node:
	if is_connected_to_master():
		return master

	return null

func get_sequence_resource() -> Resource:
	return _get_sequence()

func is_track_index_available() -> bool:
	var sequence_resource := _get_sequence()
	if sequence_resource == null:
		return false

	if sequence_resource.has_method("is_valid_track_index"):
		return bool(sequence_resource.is_valid_track_index(track_index))

	var sequence_track_count := int(sequence_resource.get("track_count"))
	return track_index >= 0 and track_index < sequence_track_count

func get_track_name() -> String:
	var sequence_resource := _get_sequence()
	if sequence_resource == null:
		return ""

	if sequence_resource.has_method("get_track_name"):
		return str(sequence_resource.get_track_name(track_index))

	if not is_track_index_available():
		return ""

	return "Track %d" % [track_index + 1]

func is_track_muted() -> bool:
	var sequence_resource := _get_sequence()
	if sequence_resource == null:
		return false

	if sequence_resource.has_method("get_track_muted"):
		return bool(sequence_resource.get_track_muted(track_index))

	return false

func get_track_volume() -> float:
	var sequence_resource := _get_sequence()
	if sequence_resource == null:
		return 1.0

	if sequence_resource.has_method("get_track_volume"):
		return max(0.0, float(sequence_resource.get_track_volume(track_index)))

	return 1.0

func get_resolved_audio_bus() -> StringName:
	return resolve_audio_bus()

func get_track_state() -> Dictionary:
	return {
		"track_index": track_index,
		"name": get_track_name(),
		"track_available": is_track_index_available(),
		"muted": is_track_muted(),
		"volume": get_track_volume(),
		"voice_volume": volume,
		"master_group_fade_volume": get_master_group_fade_volume(),
		"fade_progress": get_fade_progress(),
		"external_fade_volume": get_external_fade_volume(),
		"effective_voice_volume": get_effective_volume(),
		"audio_bus_override": audio_bus_override,
		"resolved_bus": get_resolved_audio_bus(),
		"active_in_master_group": is_active_in_master_group(),
		"playing_clip": is_playing_clip(),
		"active_clip_index": get_active_clip_index()
	}

func is_active_in_master_group() -> bool:
	if master == null or not is_instance_valid(master):
		return true

	if master.has_method("is_track_active_in_current_group"):
		return bool(master.is_track_active_in_current_group(track_index))

	return true

func get_master_group_fade_volume() -> float:
	return clamp(master_group_fade_volume, 0.0, 1.0)

func _exit_tree() -> void:
	disconnect_from_master()

	if _voice != null and is_instance_valid(_voice):
		if _voice.has_method("release_audio_player"):
			_voice.release_audio_player()

func connect_to_master(value: Node) -> void:
	if master == value:
		return

	disconnect_from_master()
	master = value

	if master == null:
		_refresh_voice_configuration()
		return

	if master.has_signal("playback_paused"):
		master.playback_paused.connect(_on_master_playback_paused)

	if master.has_method("register_track_player"):
		master.register_track_player(self)

	if master.has_signal("sequence_changed"):
		master.sequence_changed.connect(_on_master_sequence_changed)

	_update_external_fade_volume()
	_refresh_voice_configuration()
	sync_to_current_master_position(false)
	master_connected.emit(master)

func disconnect_from_master() -> void:
	if master == null:
		return

	var previous_master := master
	master = null

	if is_instance_valid(previous_master):
		if previous_master.has_signal("playback_paused") and previous_master.playback_paused.is_connected(_on_master_playback_paused):
			previous_master.playback_paused.disconnect(_on_master_playback_paused)

		if previous_master.has_method("unregister_track_player"):
			previous_master.unregister_track_player(self)

		if previous_master.has_signal("sequence_changed") and previous_master.sequence_changed.is_connected(_on_master_sequence_changed):
			previous_master.sequence_changed.disconnect(_on_master_sequence_changed)

	if _voice != null and _voice.has_method("stop_audio"):
		_voice.stop_audio()

	master_group_fade_volume = 1.0
	_refresh_voice_configuration()
	master_disconnected.emit(previous_master)

func sync_from_master(previous_position: float, current_position: float) -> void:
	if _voice != null and _voice.has_method("sync_from_master"):
		_voice.sync_from_master(previous_position, current_position)

	var local_previous_position := previous_position + timing_offset_subdivisions
	var local_current_position := current_position + timing_offset_subdivisions
	master_position_synced.emit(local_previous_position, local_current_position)

func seek_from_master(position: float, trigger_active_clip: bool = false) -> void:
	if _voice != null and _voice.has_method("seek_from_master"):
		_voice.seek_from_master(position, trigger_active_clip)

	var local_position := position + timing_offset_subdivisions
	master_position_synced.emit(local_position, local_position)

func get_pitch_scale_multiplier() -> float:
	return pow(2.0, pitch_offset_semitones / 12.0)

func get_effective_volume() -> float:
	return (
		max(0.0, volume)
		* clamp(master_group_fade_volume, 0.0, 1.0)
		* clamp(external_fade_volume, 0.0, 1.0)
	)

func resolve_audio_bus() -> StringName:
	if not audio_bus_override.is_empty():
		return audio_bus_override

	if master != null and master.has_method("resolve_track_bus"):
		return master.resolve_track_bus(track_index)

	return &"Master"

func stop_audio() -> void:
	if _voice != null and _voice.has_method("stop_audio"):
		_voice.stop_audio()

func clear_audio_stream_cache() -> void:
	if _voice != null and _voice.has_method("clear_audio_stream_cache"):
		_voice.clear_audio_stream_cache()

func is_playing_clip() -> bool:
	if _voice != null and _voice.has_method("is_playing_clip"):
		return bool(_voice.is_playing_clip())

	return false

func get_active_clip_index() -> int:
	if _voice != null and _voice.has_method("get_active_clip_index"):
		return int(_voice.get_active_clip_index())

	return -1

func get_active_clip_data() -> Dictionary:
	if _voice != null and _voice.has_method("get_active_clip_data"):
		return _voice.get_active_clip_data()

	return {}

func get_active_clip_remaining_seconds() -> float:
	if _voice != null and _voice.has_method("get_active_clip_remaining_seconds"):
		return float(_voice.get_active_clip_remaining_seconds())

	return 0.0

func _on_voice_clip_started(event_track_index: int, clip_index: int, clip_data: Dictionary) -> void:
	clip_started.emit(event_track_index, clip_index, clip_data)

func _on_voice_clip_stopped(event_track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName) -> void:
	clip_stopped.emit(event_track_index, clip_index, clip_data, reason)

func _on_master_playback_paused() -> void:
	if _voice != null and _voice.has_method("stop_audio"):
		_voice.stop_audio(&"paused")

func _on_master_sequence_changed(new_sequence: Resource) -> void:
	handle_master_sequence_changed(new_sequence)
