@tool
extends Node

@export var preview_player_pool_size: int = 32

var timeline: Control = null
var previous_playhead_position: float = 0.0
var was_playing_last_frame: bool = false
var was_scrubbing_playhead_last_frame: bool = false
var _previewed_clip_indices_this_frame: Dictionary = {}
var _preview_players: Array[AudioStreamPlayer] = []
var _active_previews: Array[Dictionary] = []
var _audio_stream_cache: Dictionary = {}

const EPSILON := 0.00001
const SILENT_VOLUME_DB := -80.0

func set_timeline(value: Control) -> void:
	timeline = value

	if timeline == null:
		previous_playhead_position = 0.0
		was_playing_last_frame = false
		was_scrubbing_playhead_last_frame = false
		return

	_ensure_preview_player_pool()
	previous_playhead_position = float(timeline.playhead_position)
	was_playing_last_frame = bool(timeline.is_playing)
	was_scrubbing_playhead_last_frame = bool(timeline.is_scrubbing_playhead)

func _ensure_preview_player_pool() -> void:
	while _preview_players.size() < preview_player_pool_size:
		var player := AudioStreamPlayer.new()
		player.finished.connect(_on_preview_player_finished.bind(player))
		add_child(player)
		_preview_players.append(player)

func _get_timeline_subdivisions_per_second() -> float:
	if timeline == null:
		return 0.0

	return (float(timeline.bpm) / 60.0) * float(timeline.subdivisions_per_beat)

func _get_clip_preview_duration_seconds(clip: Dictionary) -> float:
	var subdivisions_per_second := _get_timeline_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_length := max(0.0, float(clip.get("length", 0.0)))
	return clip_length / subdivisions_per_second

func _get_clip_offset_seconds(clip: Dictionary, playhead_position: float) -> float:
	var subdivisions_per_second := _get_timeline_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_start := float(clip.get("start", 0.0))
	var offset_subdivisions := max(0.0, playhead_position - clip_start)
	var playback_speed := max(0.001, float(clip.get("playback_speed", 1.0)))

	return (offset_subdivisions / subdivisions_per_second) * playback_speed

func _get_clip_source_start_offset_seconds(clip: Dictionary) -> float:
	return max(0.0, float(clip.get("source_start_offset_seconds", 0.0)))

func _get_clip_remaining_preview_duration_seconds(clip: Dictionary, playhead_position: float) -> float:
	var subdivisions_per_second := _get_timeline_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0

	var clip_start := float(clip.get("start", 0.0))
	var clip_length := max(0.0, float(clip.get("length", 0.0)))
	var clip_end = clip_start + clip_length
	var remaining_subdivisions := max(0.0, clip_end - playhead_position)

	return remaining_subdivisions / subdivisions_per_second

func _get_available_source_duration_seconds(audio_stream: AudioStream, start_offset_seconds: float, playback_speed: float) -> float:
	if audio_stream == null:
		return 0.0

	var source_length_seconds := audio_stream.get_length()
	if source_length_seconds <= 0.0:
		return INF

	var resolved_start_offset := max(0.0, start_offset_seconds)
	if resolved_start_offset >= source_length_seconds:
		return 0.0

	var resolved_playback_speed := max(0.001, playback_speed)
	var source_remaining_seconds = source_length_seconds - resolved_start_offset

	return source_remaining_seconds / resolved_playback_speed

func _resolve_track_preview_bus(track_index: int) -> StringName:
	if timeline == null:
		return &"Master"

	var resolved_bus := &""

	if timeline.has_method("get_track_bus_override"):
		resolved_bus = timeline.get_track_bus_override(track_index)

	if resolved_bus.is_empty() and timeline.has_method("get_default_audio_bus"):
		resolved_bus = timeline.get_default_audio_bus()

	if resolved_bus.is_empty():
		resolved_bus = &"Master"

	if AudioServer.get_bus_index(String(resolved_bus)) == -1:
		return &"Master"

	return resolved_bus

func _get_preview_linear_volume(track_index: int, clip_index: int, fallback_clip_volume: float) -> float:
	if timeline == null:
		return 0.0

	if track_index < 0 or track_index >= timeline.track_count:
		return 0.0

	if timeline.get_track_muted(track_index):
		return 0.0

	var clip_volume := fallback_clip_volume
	if clip_index >= 0 and clip_index < timeline.clips.size():
		var clip = timeline.clips[clip_index]
		clip_volume = max(0.0, float(clip.get("volume", fallback_clip_volume)))

	var track_volume := max(0.0, float(timeline.get_track_volume(track_index)))
	return track_volume * max(0.0, clip_volume)

func _linear_volume_to_preview_db(linear_volume: float) -> float:
	if linear_volume <= EPSILON:
		return SILENT_VOLUME_DB

	return linear_to_db(linear_volume)

func _acquire_preview_player(track_index: int) -> AudioStreamPlayer:
	_ensure_preview_player_pool()

	for player in _preview_players:
		if not _is_preview_player_active(player):
			player.bus = _resolve_track_preview_bus(track_index)
			return player

	if _active_previews.is_empty():
		return null

	var oldest_preview_index := 0
	var oldest_end_time := float(_active_previews[0].get("end_time", 0.0))

	for i in range(1, _active_previews.size()):
		var preview_end_time := float(_active_previews[i].get("end_time", 0.0))
		if preview_end_time < oldest_end_time:
			oldest_end_time = preview_end_time
			oldest_preview_index = i

	var stolen_player := _active_previews[oldest_preview_index].get("player") as AudioStreamPlayer
	_release_preview_player(stolen_player)

	if stolen_player != null:
		stolen_player.bus = _resolve_track_preview_bus(track_index)

	return stolen_player

func _is_preview_player_active(player: AudioStreamPlayer) -> bool:
	for preview in _active_previews:
		if preview.get("player") == player:
			return true
	return false

func _release_preview_player(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return

	player.stop()
	player.stream = null

	for i in range(_active_previews.size() - 1, -1, -1):
		if _active_previews[i].get("player") == player:
			_active_previews.remove_at(i)

func stop_all_audio() -> void:
	for preview in _active_previews:
		var player := preview.get("player") as AudioStreamPlayer
		if player == null or not is_instance_valid(player):
			continue

		player.stop()
		player.stream = null

	_active_previews.clear()

	for player in _preview_players:
		if player == null or not is_instance_valid(player):
			continue

		player.stop()
		player.stream = null

func _update_active_previews() -> void:
	var now_seconds := Time.get_ticks_usec() / 1000000.0

	for i in range(_active_previews.size() - 1, -1, -1):
		var preview := _active_previews[i]
		var player := preview.get("player") as AudioStreamPlayer
		var end_time := float(preview.get("end_time", 0.0))
		var track_index := int(preview.get("track_index", -1))
		var clip_index := int(preview.get("clip_index", -1))
		var clip_volume := float(preview.get("clip_volume", 1.0))

		if player == null or not is_instance_valid(player):
			_active_previews.remove_at(i)
			continue

		if now_seconds >= end_time:
			_release_preview_player(player)
			continue

		if track_index < 0 or track_index >= timeline.track_count:
			_release_preview_player(player)
			continue

		if timeline.get_track_muted(track_index):
			_release_preview_player(player)
			continue

		player.bus = _resolve_track_preview_bus(track_index)
		var final_volume := _get_preview_linear_volume(track_index, clip_index, clip_volume)
		player.volume_db = _linear_volume_to_preview_db(final_volume)


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

func clear_audio_stream_cache() -> void:
	_audio_stream_cache.clear()

func _process(_delta: float) -> void:
	if timeline == null:
		return

	var is_playing_now := bool(timeline.is_playing)
	var is_scrubbing_now := bool(timeline.is_scrubbing_playhead)
	var current_playhead_position := float(timeline.playhead_position)

	_previewed_clip_indices_this_frame.clear()
	_update_active_previews()

	if not is_playing_now:
		if was_playing_last_frame:
			stop_all_audio()

		if is_scrubbing_now:
			was_scrubbing_playhead_last_frame = true
			was_playing_last_frame = false
			return

		previous_playhead_position = current_playhead_position
		was_playing_last_frame = false
		was_scrubbing_playhead_last_frame = false
		return

	if was_scrubbing_playhead_last_frame:
		stop_all_audio()
		_trigger_clips_at_playhead_position(current_playhead_position)
		previous_playhead_position = current_playhead_position
		was_playing_last_frame = true
		was_scrubbing_playhead_last_frame = false
		return

	if _did_playhead_jump(previous_playhead_position, current_playhead_position):
		stop_all_audio()
		_trigger_clips_at_playhead_position(current_playhead_position)
		previous_playhead_position = current_playhead_position
		was_playing_last_frame = true
		return

	_trigger_crossed_clip_starts(previous_playhead_position, current_playhead_position)

	previous_playhead_position = current_playhead_position
	was_playing_last_frame = true
	was_scrubbing_playhead_last_frame = false

func _trigger_crossed_clip_starts(previous_position: float, current_position: float) -> void:
	var total_subdivisions := float(
		timeline.bars * timeline.beats_per_bar * timeline.subdivisions_per_beat
	)

	var include_start := previous_position <= EPSILON

	if current_position >= previous_position:
		_trigger_clip_starts_in_range(previous_position, current_position, include_start)
	else:
		_trigger_clip_starts_in_range(previous_position, total_subdivisions)
		_trigger_clip_starts_in_range(0.0, current_position, true)

func _is_normal_loop_wrap(previous_position: float, current_position: float) -> bool:
	if timeline == null:
		return false
	if not bool(timeline.loop_enabled):
		return false

	var total_subdivisions := float(
		timeline.bars * timeline.beats_per_bar * timeline.subdivisions_per_beat
	)
	if total_subdivisions <= 0.0:
		return false

	return (
		current_position < previous_position
		and previous_position >= total_subdivisions - 2.0
		and current_position <= 2.0
	)

func _did_playhead_jump(previous_position: float, current_position: float) -> bool:
	if timeline == null:
		return false
	if _is_normal_loop_wrap(previous_position, current_position):
		return false

	var max_expected_step := 1.5 # in subdivisions, safe margin
	return abs(current_position - previous_position) > max_expected_step

func _trigger_clip_starts_in_range(start_position: float, end_position: float, include_start: bool = false) -> void:
	for clip_index in range(timeline.clips.size()):
		var clip = timeline.clips[clip_index]
		var clip_start := float(clip.get("start", -1.0))

		if include_start:
			if clip_start < start_position - EPSILON or clip_start > end_position + EPSILON:
				continue
		else:
			if clip_start <= start_position + EPSILON or clip_start > end_position + EPSILON:
				continue

		if _previewed_clip_indices_this_frame.has(clip_index):
			continue

		_previewed_clip_indices_this_frame[clip_index] = true
		_preview_clip(clip_index, clip)

func _trigger_clips_at_playhead_position(position: float) -> void:
	if timeline == null:
		return

	for clip_index in range(timeline.clips.size()):
		var clip = timeline.clips[clip_index]
		var clip_start := float(clip.get("start", -1.0))
		var clip_length := float(clip.get("length", 0.0))

		if clip_length <= 0.0:
			continue

		var clip_end := clip_start + clip_length

		if position < clip_start or position >= clip_end:
			continue

		if _previewed_clip_indices_this_frame.has(clip_index):
			continue

		var offset_seconds := _get_clip_offset_seconds(clip, position)
		var remaining_duration_seconds := _get_clip_remaining_preview_duration_seconds(clip, position)

		if remaining_duration_seconds <= 0.0:
			continue

		_previewed_clip_indices_this_frame[clip_index] = true
		_preview_clip(clip_index, clip, offset_seconds, remaining_duration_seconds)

func _preview_clip(clip_index: int, clip: Dictionary, start_offset_seconds: float = 0.0, preview_duration_seconds: float = -1.0) -> void:
	var audio_path := str(clip.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		return

	var audio_stream := _get_cached_audio_stream(audio_path)
	if audio_stream == null:
		return

	var track_index := int(clip.get("track", -1))
	if track_index < 0 or track_index >= timeline.track_count:
		return

	if timeline.get_track_muted(track_index):
		return

	var clip_volume := max(0.0, float(clip.get("volume", 1.0)))
	var final_volume := _get_preview_linear_volume(track_index, clip_index, clip_volume)

	var playback_speed := max(0.001, float(clip.get("playback_speed", 1.0)))
	var resolved_start_offset_seconds = _get_clip_source_start_offset_seconds(clip) + max(0.0, start_offset_seconds)

	var resolved_preview_duration_seconds := preview_duration_seconds
	if resolved_preview_duration_seconds < 0.0:
		resolved_preview_duration_seconds = _get_clip_preview_duration_seconds(clip)

	var available_source_duration_seconds := _get_available_source_duration_seconds(
		audio_stream,
		resolved_start_offset_seconds,
		playback_speed
	)

	resolved_preview_duration_seconds = min(
		resolved_preview_duration_seconds,
		available_source_duration_seconds
	)

	if resolved_preview_duration_seconds <= 0.0:
		return

	var player := _acquire_preview_player(track_index)

	if player == null:
		return

	player.stream = audio_stream
	player.pitch_scale = playback_speed
	player.volume_db = _linear_volume_to_preview_db(final_volume)
	player.play(resolved_start_offset_seconds)

	_active_previews.append({
		"player": player,
		"end_time": (Time.get_ticks_usec() / 1000000.0) + resolved_preview_duration_seconds,
		"track_index": track_index,
		"clip_index": clip_index,
		"clip_volume": clip_volume
	})

func _on_preview_player_finished(player: AudioStreamPlayer) -> void:
	_release_preview_player(player)
