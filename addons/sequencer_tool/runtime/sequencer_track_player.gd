extends Node

const SEQUENCER_AUDIO_TRACK_VOICE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_audio_track_voice.gd")

signal master_connected(master: Node)
signal master_disconnected(master: Node)
signal master_position_synced(previous_position: float, current_position: float)
signal clip_started(track_index: int, clip_index: int, clip_data: Dictionary)
signal clip_stopped(track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName)

@export var master_path: NodePath
@export var track_index: int = 0
@export var timing_offset_subdivisions: float = 0.0
@export var pitch_offset_semitones: float = 0.0
@export var volume: float = 1.0
@export var audio_bus_override: StringName = &""

var master: Node = null
var _voice: Node = null

func _ready() -> void:
	_ensure_voice()

	if not master_path.is_empty():
		var resolved_master := get_node_or_null(master_path)
		if resolved_master != null:
			connect_to_master(resolved_master)

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
		volume,
		audio_bus_override
	)

func refresh_runtime_setup() -> void:
	_ensure_voice()
	_refresh_voice_configuration()

func set_track_index(value: int) -> void:
	track_index = max(0, value)
	refresh_runtime_setup()

func set_timing_offset(value: float) -> void:
	timing_offset_subdivisions = value
	refresh_runtime_setup()

func set_pitch_offset(value: float) -> void:
	pitch_offset_semitones = value
	refresh_runtime_setup()

func set_voice_volume(value: float) -> void:
	volume = max(0.0, value)
	refresh_runtime_setup()

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

	_refresh_voice_configuration()
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

	if _voice != null and _voice.has_method("stop_audio"):
		_voice.stop_audio()

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
	return max(0.0, volume)

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

func _on_voice_clip_started(event_track_index: int, clip_index: int, clip_data: Dictionary) -> void:
	clip_started.emit(event_track_index, clip_index, clip_data)

func _on_voice_clip_stopped(event_track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName) -> void:
	clip_stopped.emit(event_track_index, clip_index, clip_data, reason)

func _on_master_playback_paused() -> void:
	if _voice != null and _voice.has_method("stop_audio"):
		_voice.stop_audio(&"paused")
