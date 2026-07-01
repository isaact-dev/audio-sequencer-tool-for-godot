extends Node

var master: Node = null
var sequence: Resource = null
var track_index: int = 0
var timing_offset_subdivisions: float = 0.0
var pitch_offset_semitones: float = 0.0
var volume: float = 1.0
var audio_bus_override: StringName = &""

var random_timing_delay_min_seconds: float = 0.0
var random_timing_delay_max_seconds: float = 0.0
var _pending_clip_triggers: Array[Dictionary] = []

var random_pitch_offset_min_semitones: float = 0.0
var random_pitch_offset_max_semitones: float = 0.0

var _audio_player: AudioStreamPlayer = null
var _audio_stream_cache: Dictionary = {}
var _active_clip_index: int = -1
var _active_clip_end_time: float = 0.0
var _active_clip_data: Dictionary = {}
var _last_triggered_clip_index: int = -1
var _last_triggered_frame: int = -1

const EPSILON := 0.00001
const SILENT_VOLUME_DB := -80.0

signal clip_started(track_index: int, clip_index: int, clip_data: Dictionary)
signal clip_stopped(track_index: int, clip_index: int, clip_data: Dictionary, reason: StringName)

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	_update_pending_clip_triggers(delta)
	_update_active_audio()

	if _pending_clip_triggers.is_empty() and _active_clip_index < 0:
		set_process(false)

func configure(
	owner_master: Node,
	owner_sequence: Resource,
	voice_track_index: int,
	voice_timing_offset_subdivisions: float = 0.0,
	voice_pitch_offset_semitones: float = 0.0,
	voice_volume: float = 1.0,
	voice_audio_bus_override: StringName = &"",
	voice_random_timing_delay_min_seconds: float = 0.0,
	voice_random_timing_delay_max_seconds: float = 0.0,
	voice_random_pitch_offset_min_semitones: float = 0.0,
	voice_random_pitch_offset_max_semitones: float = 0.0
) -> void:
	master = owner_master
	sequence = owner_sequence
	track_index = voice_track_index
	timing_offset_subdivisions = voice_timing_offset_subdivisions
	pitch_offset_semitones = voice_pitch_offset_semitones
	volume = voice_volume
	audio_bus_override = voice_audio_bus_override
	random_timing_delay_min_seconds = max(0.0, voice_random_timing_delay_min_seconds)
	random_timing_delay_max_seconds = max(random_timing_delay_min_seconds, voice_random_timing_delay_max_seconds)
	random_pitch_offset_min_semitones = min(
		voice_random_pitch_offset_min_semitones,
		voice_random_pitch_offset_max_semitones
	)
	random_pitch_offset_max_semitones = max(
		voice_random_pitch_offset_min_semitones,
		voice_random_pitch_offset_max_semitones
	)

func sync_from_master(previous_position: float, current_position: float) -> void:
	var local_previous_position := previous_position + timing_offset_subdivisions
	var local_current_position := current_position + timing_offset_subdivisions

	_trigger_crossed_clip_starts(local_previous_position, local_current_position)
	_update_active_audio()

func seek_from_master(position: float, trigger_active_clip: bool = false) -> void:
	var local_position := position + timing_offset_subdivisions

	stop_audio(&"seek")

	if trigger_active_clip:
		_trigger_clip_at_position(local_position)

func stop_audio(reason: StringName = &"stopped") -> void:
	var stopped_clip_index := _active_clip_index
	var stopped_clip_data := _active_clip_data.duplicate(true)

	_active_clip_index = -1
	_active_clip_end_time = 0.0
	_active_clip_data = {}
	_pending_clip_triggers.clear()
	set_process(false)

	if _audio_player != null and is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.stream = null

	if stopped_clip_index >= 0:
		clip_stopped.emit(track_index, stopped_clip_index, stopped_clip_data, reason)

func release_audio_player() -> void:
	stop_audio()

	if _audio_player == null or not is_instance_valid(_audio_player):
		return

	_audio_player.queue_free()
	_audio_player = null

func clear_audio_stream_cache() -> void:
	_audio_stream_cache.clear()

func get_pitch_scale_multiplier() -> float:
	return pow(2.0, pitch_offset_semitones / 12.0)

func _get_random_pitch_offset_semitones() -> float:
	if is_equal_approx(random_pitch_offset_min_semitones, random_pitch_offset_max_semitones):
		return random_pitch_offset_min_semitones

	return randf_range(random_pitch_offset_min_semitones, random_pitch_offset_max_semitones)

func _get_random_pitch_scale_multiplier() -> float:
	return pow(2.0, _get_random_pitch_offset_semitones() / 12.0)

func get_effective_volume() -> float:
	return max(0.0, volume)

func resolve_audio_bus() -> StringName:
	if not audio_bus_override.is_empty():
		return audio_bus_override

	if master != null and master.has_method("resolve_track_bus"):
		return master.resolve_track_bus(track_index)

	return &"Master"

func _ensure_audio_player() -> void:
	if _audio_player != null and is_instance_valid(_audio_player):
		return

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_player_finished)

func _get_total_subdivisions() -> float:
	if sequence != null and sequence.has_method("get_total_subdivisions"):
		return float(sequence.get_total_subdivisions())

	if master != null and master.has_method("get_total_subdivisions"):
		return float(master.get_total_subdivisions())

	return 0.0

func _get_subdivisions_per_second() -> float:
	if sequence != null and sequence.has_method("get_subdivisions_per_second"):
		return float(sequence.get_subdivisions_per_second())

	return 0.0

func _get_track_clips() -> Array:
	if sequence == null or not sequence.has_method("get_track_clips"):
		return []

	return sequence.get_track_clips(track_index)

func _get_sequence_clip_index(fallback_clip_index: int, clip: Dictionary) -> int:
	return int(clip.get("_sequence_clip_index", fallback_clip_index))

func _is_track_muted() -> bool:
	if sequence == null or not sequence.has_method("get_track_muted"):
		return false

	return bool(sequence.get_track_muted(track_index))

func _get_track_volume() -> float:
	if sequence == null or not sequence.has_method("get_track_volume"):
		return 1.0

	return max(0.0, float(sequence.get_track_volume(track_index)))

func _get_cached_audio_stream(audio_path: String) -> AudioStream:
	var resolved_path := audio_path.strip_edges()
	if resolved_path.is_empty():
		return null

	if _audio_stream_cache.has(resolved_path):
		var cached_stream := _audio_stream_cache[resolved_path] as AudioStream
		if cached_stream != null:
			return cached_stream
		_audio_stream_cache.erase(resolved_path)

	var loaded_stream := load(resolved_path) as AudioStream
	if loaded_stream == null:
		return null

	_audio_stream_cache[resolved_path] = loaded_stream
	return loaded_stream

func _linear_volume_to_db(linear_volume: float) -> float:
	if linear_volume <= EPSILON:
		return SILENT_VOLUME_DB

	return linear_to_db(linear_volume)

func _get_clip_duration_seconds(clip: Dictionary) -> float:
	var subdivisions_per_second := _get_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_length := max(0.0, float(clip.get("length", 0.0)))
	return clip_length / subdivisions_per_second

func _get_clip_offset_seconds(clip: Dictionary, playhead_position: float, playback_pitch_scale: float) -> float:
	var subdivisions_per_second := _get_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_start := float(clip.get("start", 0.0))
	var offset_subdivisions := max(0.0, playhead_position - clip_start)
	return (offset_subdivisions / subdivisions_per_second) * max(0.001, playback_pitch_scale)

func _get_clip_source_start_offset_seconds(clip: Dictionary) -> float:
	return max(0.0, float(clip.get("source_start_offset_seconds", 0.0)))

func _get_clip_remaining_duration_seconds(clip: Dictionary, playhead_position: float) -> float:
	var subdivisions_per_second := _get_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_start := float(clip.get("start", 0.0))
	var clip_length := max(0.0, float(clip.get("length", 0.0)))
	var clip_end = clip_start + clip_length
	var remaining_subdivisions := max(0.0, clip_end - playhead_position)

	return remaining_subdivisions / subdivisions_per_second

func _get_available_source_duration_seconds(audio_stream: AudioStream, start_offset_seconds: float, playback_pitch_scale: float) -> float:
	if audio_stream == null:
		return 0.0

	var source_length_seconds := audio_stream.get_length()
	if source_length_seconds <= 0.0:
		return INF

	var resolved_start_offset := max(0.0, start_offset_seconds)
	if resolved_start_offset >= source_length_seconds:
		return 0.0

	var source_remaining_seconds = source_length_seconds - resolved_start_offset
	return source_remaining_seconds / max(0.001, playback_pitch_scale)

func _get_clip_final_volume(clip: Dictionary) -> float:
	var clip_volume := max(0.0, float(clip.get("volume", 1.0)))
	return _get_track_volume() * clip_volume * get_effective_volume()

func _trigger_crossed_clip_starts(previous_position: float, current_position: float) -> void:
	if _is_track_muted():
		stop_audio()
		return

	var total_subdivisions := _get_total_subdivisions()
	if total_subdivisions <= 0.0:
		return

	if current_position >= previous_position:
		_trigger_clip_starts_in_range(previous_position, current_position, previous_position <= EPSILON)
	else:
		_trigger_clip_starts_in_range(previous_position, total_subdivisions, false)
		_trigger_clip_starts_in_range(0.0, current_position, true)

func _trigger_clip_at_position(position: float) -> void:
	if _is_track_muted():
		stop_audio()
		return

	var clips := _get_track_clips()

	for clip_index in range(clips.size()):
		var clip = clips[clip_index]
		if not clip is Dictionary:
			continue

		var clip_start := float(clip.get("start", -1.0))
		var clip_length := float(clip.get("length", 0.0))
		if clip_length <= 0.0:
			continue

		var clip_end := clip_start + clip_length
		if position < clip_start or position >= clip_end:
			continue

		var clip_playback_speed := max(0.001, float(clip.get("playback_speed", 1.0)))
		var playback_pitch_scale = clip_playback_speed * get_pitch_scale_multiplier()
		var offset_seconds := _get_clip_offset_seconds(clip, position, playback_pitch_scale)
		var remaining_duration_seconds := _get_clip_remaining_duration_seconds(clip, position)

		if remaining_duration_seconds <= 0.0:
			continue

		_queue_or_play_clip(_get_sequence_clip_index(clip_index, clip), clip, offset_seconds, remaining_duration_seconds)
		return

func _trigger_clip_starts_in_range(start_position: float, end_position: float, include_start: bool = false) -> void:
	var clips := _get_track_clips()

	for clip_index in range(clips.size()):
		var clip = clips[clip_index]
		if not clip is Dictionary:
			continue

		var clip_start := float(clip.get("start", -1.0))

		if include_start:
			if clip_start < start_position - EPSILON or clip_start > end_position + EPSILON:
				continue
		else:
			if clip_start <= start_position + EPSILON or clip_start > end_position + EPSILON:
				continue

		var sequence_clip_index := _get_sequence_clip_index(clip_index, clip)
		var process_frame := Engine.get_process_frames()
		if _last_triggered_clip_index == sequence_clip_index and _last_triggered_frame == process_frame:
			continue

		_last_triggered_clip_index = sequence_clip_index
		_last_triggered_frame = process_frame
		_queue_or_play_clip(sequence_clip_index, clip)

func _get_random_timing_delay_seconds() -> float:
	if random_timing_delay_max_seconds <= EPSILON:
		return 0.0

	var min_delay := max(0.0, random_timing_delay_min_seconds)
	var max_delay := max(min_delay, random_timing_delay_max_seconds)

	if is_equal_approx(min_delay, max_delay):
		return min_delay

	return randf_range(min_delay, max_delay)

func _queue_or_play_clip(
	clip_index: int,
	clip: Dictionary,
	start_offset_seconds: float = 0.0,
	preview_duration_seconds: float = -1.0
) -> void:
	var delay_seconds := _get_random_timing_delay_seconds()

	if delay_seconds <= EPSILON:
		_play_clip(clip_index, clip, start_offset_seconds, preview_duration_seconds)
		return

	_pending_clip_triggers.append({
		"remaining_seconds": delay_seconds,
		"clip_index": clip_index,
		"clip": clip.duplicate(true),
		"start_offset_seconds": start_offset_seconds,
		"preview_duration_seconds": preview_duration_seconds
	})

	set_process(true)

func _update_pending_clip_triggers(delta: float) -> void:
	if _pending_clip_triggers.is_empty():
		return

	for i in range(_pending_clip_triggers.size() - 1, -1, -1):
		var pending := _pending_clip_triggers[i]
		var remaining_seconds := float(pending.get("remaining_seconds", 0.0)) - delta

		if remaining_seconds > 0.0:
			pending["remaining_seconds"] = remaining_seconds
			_pending_clip_triggers[i] = pending
			continue

		_pending_clip_triggers.remove_at(i)

		if _is_track_muted():
			continue

		_play_clip(
			int(pending.get("clip_index", -1)),
			pending.get("clip", {}),
			float(pending.get("start_offset_seconds", 0.0)),
			float(pending.get("preview_duration_seconds", -1.0))
		)

func _play_clip(
	clip_index: int,
	clip: Dictionary,
	start_offset_seconds: float = 0.0,
	preview_duration_seconds: float = -1.0
) -> void:
	var audio_path := str(clip.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		return

	var audio_stream := _get_cached_audio_stream(audio_path)
	if audio_stream == null:
		return

	if _is_track_muted():
		stop_audio(&"muted")
		return

	_ensure_audio_player()

	var clip_playback_speed := max(0.001, float(clip.get("playback_speed", 1.0)))
	var random_pitch_multiplier := 1.0
	if start_offset_seconds <= EPSILON:
		random_pitch_multiplier = _get_random_pitch_scale_multiplier()

	var playback_pitch_scale = clip_playback_speed * get_pitch_scale_multiplier() * random_pitch_multiplier
	var resolved_start_offset_seconds = _get_clip_source_start_offset_seconds(clip) + max(0.0, start_offset_seconds)

	var resolved_duration_seconds := preview_duration_seconds
	if resolved_duration_seconds < 0.0:
		resolved_duration_seconds = _get_clip_duration_seconds(clip)

	var source_duration_seconds := _get_available_source_duration_seconds(
		audio_stream,
		resolved_start_offset_seconds,
		playback_pitch_scale
	)
	resolved_duration_seconds = min(resolved_duration_seconds, source_duration_seconds)

	if resolved_duration_seconds <= 0.0:
		return

	_audio_player.stop()
	_audio_player.stream = audio_stream
	_audio_player.bus = resolve_audio_bus()
	_audio_player.pitch_scale = playback_pitch_scale
	_audio_player.volume_db = _linear_volume_to_db(_get_clip_final_volume(clip))
	_audio_player.play(resolved_start_offset_seconds)

	_active_clip_index = clip_index
	_active_clip_data = clip.duplicate(true)
	_active_clip_end_time = (Time.get_ticks_usec() / 1000000.0) + resolved_duration_seconds
	set_process(true)
	clip_started.emit(track_index, clip_index, _active_clip_data.duplicate(true))

func _update_active_audio() -> void:
	if _active_clip_index < 0:
		return

	if _audio_player == null or not is_instance_valid(_audio_player):
		stop_audio(&"invalid_player")
		return
	if _is_track_muted():
		stop_audio(&"muted")
		return

	var now_seconds := Time.get_ticks_usec() / 1000000.0
	if now_seconds >= _active_clip_end_time:
		stop_audio(&"finished")
		return

	_audio_player.bus = resolve_audio_bus()
	_audio_player.volume_db = _linear_volume_to_db(_get_clip_final_volume(_active_clip_data))

func _on_audio_player_finished() -> void:
	stop_audio(&"finished")
