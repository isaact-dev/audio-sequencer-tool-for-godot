@tool
extends Node

var timeline: TimelineControl = null
var previous_playhead_position: float = 0.0
var was_playing_last_frame: bool = false
var _previewed_clip_indices_this_frame: Dictionary = {}

const CLIP_START_TRIGGER_EPSILON := 0.00001

func set_timeline(value: TimelineControl) -> void:
	timeline = value

	if timeline == null:
		previous_playhead_position = 0.0
		was_playing_last_frame = false
		return

	previous_playhead_position = float(timeline.playhead_position)
	was_playing_last_frame = bool(timeline.is_playing)

func _process(_delta: float) -> void:
	if timeline == null:
		return

	var is_playing_now := bool(timeline.is_playing)
	var current_playhead_position := float(timeline.playhead_position)

	_previewed_clip_indices_this_frame.clear()

	if not is_playing_now:
		previous_playhead_position = current_playhead_position
		was_playing_last_frame = false
		return

		previous_playhead_position = current_playhead_position
		was_playing_last_frame = true
		return

	_trigger_crossed_clip_starts(previous_playhead_position, current_playhead_position)

	previous_playhead_position = current_playhead_position
	was_playing_last_frame = true

func _trigger_crossed_clip_starts(previous_position: float, current_position: float) -> void:
	var total_subdivisions := float(
		timeline.bars * timeline.beats_per_bar * timeline.subdivisions_per_beat
	)

	if current_position >= previous_position:
		_trigger_clip_starts_in_range(previous_position, current_position)
	else:
		_trigger_clip_starts_in_range(previous_position, total_subdivisions)

func _trigger_clip_starts_in_range(start_position: float, end_position: float, include_start: bool = false) -> void:
	for clip_index in range(timeline.clips.size()):
		var clip := timeline.clips[clip_index]
		var clip_start := float(clip.get("start", -1.0))
		var trigger_position := clip_start + CLIP_START_TRIGGER_EPSILON

		if include_start:
			if trigger_position < start_position or trigger_position > end_position:
				continue
		else:
			if trigger_position <= start_position or trigger_position > end_position:
				continue

		if _previewed_clip_indices_this_frame.has(clip_index):
			continue

		_previewed_clip_indices_this_frame[clip_index] = true
		_preview_clip(clip)

func _preview_clip(clip: Dictionary) -> void:
	var audio_path := str(clip.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		return

	var audio_stream := load(audio_path) as AudioStream
	if audio_stream == null:
		return

	var track_index := int(clip.get("track", -1))
	if track_index < 0 or track_index >= timeline.track_count:
		return

	if timeline.get_track_muted(track_index):
		return

	var track_volume := max(0.0, float(timeline.get_track_volume(track_index)))
	var clip_volume := max(0.0, float(clip.get("volume", 1.0)))
	var final_volume = track_volume * clip_volume

	if final_volume <= 0.0:
		return

	var player := AudioStreamPlayer.new()
	player.stream = audio_stream
	player.pitch_scale = max(0.001, float(clip.get("playback_speed", 1.0)))
	player.volume_db = linear_to_db(max(0.0001, final_volume))
	player.finished.connect(_on_preview_player_finished.bind(player))

	add_child(player)
	player.play()

func _on_preview_player_finished(player: AudioStreamPlayer) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
