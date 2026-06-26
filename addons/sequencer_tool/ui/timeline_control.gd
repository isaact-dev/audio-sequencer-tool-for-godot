@tool
extends Control

const SEQUENCER_SEQUENCE_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_sequence.gd")

signal status_text_changed(text: String)
signal selected_clip_changed(clip_index: int, clip_data: Dictionary)
signal tracks_changed(track_names: Array)
signal sequence_changed()
signal add_clip_requested()
signal playback_state_changed(is_playing: bool)

@export var bars: int = 8
@export var beats_per_bar: int = 4
@export var subdivisions_per_beat: int = 4
@export var track_count: int = 4
@export var lane_height: float = 48.0
@export var pixels_per_subdivision: float = 24.0
@export var header_height: float = 32.0
@export var clip_vertical_padding: float = 6.0
@export var clip_horizontal_padding: float = 2.0
@export var snap_enabled: bool = true
@export var keyboard_nudge_amount: float = 1.0
@export var keyboard_micro_nudge_amount: float = 0.1
@export var auto_scroll_edge_threshold: float = 48.0
@export var auto_scroll_speed: float = 16.0
@export var visible_scroll_margin: float = 24.0
@export var min_clip_length: float = 0.85
@export var resize_handle_width: float = 10.0
@export var track_label_width: float = 70.0
@export var blocked_action_flash_duration: float = 0.18
@export var bpm: float = 120.0
@export var playhead_follow_margin: float = 48.0

var background_color := Color(0.10, 0.10, 0.12)
var header_color := Color(0.16, 0.16, 0.20)
var header_separator_color := Color(0.0, 0.0, 0.0, 0.45)

var lane_color_a := Color(0.14, 0.14, 0.16)
var lane_color_b := Color(0.12, 0.12, 0.14)
var muted_lane_overlay_color := Color(0.0, 0.0, 0.0, 0.325)
var muted_clip_overlay_color := Color(0.0, 0.0, 0.0, 0.455)
var muted_track_text_color := Color(0.58, 0.58, 0.62)

var subdivision_line_color := Color(0.20, 0.20, 0.24)
var beat_line_color := Color(0.32, 0.32, 0.38)
var bar_line_color := Color(0.55, 0.55, 0.65)

var bar_number_color := Color(0.92, 0.92, 0.96)
var clip_text_color := Color(1.0, 1.0, 1.0)
var clip_outline_color := Color(0.0, 0.0, 0.0, 0.45)

var clip_waveform_color := Color(1.0, 1.0, 1.0, 0.102)
var clip_waveform_step: float = 4.0
var clip_waveform_vertical_padding: float = 8.0

var track_color_palette: Array[Color] = [
	Color(0.30, 0.40, 0.62),
	Color(0.42, 0.34, 0.60),
	Color(0.58, 0.38, 0.24),
	Color(0.26, 0.46, 0.58),
	Color(0.50, 0.32, 0.52),
	Color(0.56, 0.42, 0.28)
]

var blocked_action_flash_time: float = 0.0
var blocked_action_flash_fill_color := Color(0.749, 0.18, 0.18, 0.039)
var blocked_action_flash_outline_color := Color(0.949, 0.302, 0.302, 0.486)
var clips: Array[Dictionary] = []

var track_names: Array[String] = []
var track_mutes: Array[bool] = []
var track_volumes: Array[float] = []
var track_colors: Array[Color] = []
var default_audio_bus: StringName = &"Master"
var track_bus_overrides: Dictionary = {}
var track_effect_chains: Dictionary = {}
var track_groups: Dictionary = {}

var selected_clip_outline_color := Color(1.0, 0.9, 0.35, 1.0)
var selected_clip_overlay_color := Color(1.0, 1.0, 1.0, 0.08)
var hovered_clip_outline_color := Color(1.0, 1.0, 1.0, 0.38)
var hovered_clip_overlay_color := Color(1.0, 1.0, 1.0, 0.05)

var playhead_line_color := Color(1.0, 0.9, 0.35, 1.0)
var playhead_line_width: float = 2.0
var is_playing: bool = false
var playhead_position: float = 0.0
var is_scrubbing_playhead: bool = false
var was_playing_before_scrub: bool = false

var selected_clip_index: int = -1
var selected_clip_indices: Array[int] = []
var hovered_clip_index: int = -1
var hovered_resize_clip_index: int = -1

var loop_enabled: bool = false

var is_dragging_clip: bool = false
var dragged_clip_index: int = -1
var drag_grab_offset: float = 0.0
var temporary_snap_override_active: bool = false
var drag_start_mouse_position: Vector2 = Vector2.ZERO

var is_resizing_clip: bool = false
var resized_clip_index: int = -1
var resize_grab_offset: float = 0.0
var resize_start_mouse_position: Vector2 = Vector2.ZERO

var resize_handle_color := Color(1.0, 1.0, 1.0, 0.18)
var active_resize_handle_color := Color(1.0, 0.9, 0.35, 0.95)

var drag_original_clip_index: int = -1
var drag_original_clip_data: Dictionary = {}
var drag_original_selected_clips: Dictionary = {}

var resize_original_clip_index: int = -1
var resize_original_clip_data: Dictionary = {}

var editor_undo_redo: EditorUndoRedoManager = null
var action_feedback_text: String = ""

var pending_clip_insertion_context: Dictionary = {}

var clip_clipboard: Array[Dictionary] = []


#Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)

	_ensure_track_names_size()
	_update_timeline_size()
	call_deferred("_emit_status_text")
	call_deferred("_emit_selected_clip_changed")
	call_deferred("_emit_tracks_changed")
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func set_editor_undo_redo(value: EditorUndoRedoManager) -> void:
	editor_undo_redo = value


#Signal handlers
func _emit_sequence_changed() -> void:
	sequence_changed.emit()

func _emit_status_text() -> void:
	status_text_changed.emit(_build_status_text())
	_clear_action_feedback()

func _emit_tracks_changed() -> void:
	tracks_changed.emit(get_track_names())

func _emit_selected_clip_changed() -> void:
	if selected_clip_indices.size() == 1:
		selected_clip_changed.emit(selected_clip_index, _get_selected_clip_data())
	else:
		selected_clip_changed.emit(-1, {})

func _build_status_text() -> String:
	var snap_text := "On" if _is_snap_active() else "Off"
	var base_text := ""
	if selected_clip_indices.size() > 1:
		base_text = "Selected: %d clips | Snap: %s" % [
			selected_clip_indices.size(),
			snap_text
		]
	elif selected_clip_index < 0 or selected_clip_index >= clips.size():
		base_text = "Selected: None | Start: - | Length: - | Snap: %s" % snap_text
	else:
		var clip := clips[selected_clip_index]

		if not clip.has("name") or not clip.has("start") or not clip.has("length"):
			base_text = "Selected: Invalid | Start: - | Length: - | Snap: %s" % snap_text
		else:
			var clip_name := str(clip["name"])
			var start: float = clip["start"]
			var length: float = clip["length"]
			var track: int = clip["track"]

			base_text = "Selected: %s | Start: %.2f | Length: %.2f | Track: %d | Snap: %s" % [
				clip_name,
				start,
				length,
				track,
				snap_text
			]

	if not action_feedback_text.is_empty():
		base_text += " | %s" % action_feedback_text

	return base_text

func _show_blocked_action_feedback(message: String) -> void:
	_set_action_feedback(message)
	blocked_action_flash_time = blocked_action_flash_duration
	queue_redraw()

func _set_action_feedback(message: String) -> void:
	action_feedback_text = message
	_emit_status_text()

func _clear_action_feedback() -> void:
	if action_feedback_text.is_empty():
		return

	action_feedback_text = ""


#Timeline geometry
func _get_total_subdivisions() -> int:
	return bars * beats_per_bar * subdivisions_per_beat

func _get_total_width() -> float:
	return track_label_width + (_get_total_subdivisions() * pixels_per_subdivision)

func _get_total_height() -> float:
	return header_height + (track_count * lane_height)

func _get_bar_width() -> float:
	return beats_per_bar * subdivisions_per_beat * pixels_per_subdivision

func _get_subdivisions_per_second() -> float:
	return (bpm / 60.0) * float(subdivisions_per_beat)

func _update_timeline_size() -> void:
	custom_minimum_size = Vector2(_get_total_width(), _get_total_height())

func _timeline_to_x(position: float) -> float:
	return track_label_width + (position * pixels_per_subdivision)

func _x_to_timeline(x: float) -> float:
	return max(0.0, (x - track_label_width) / pixels_per_subdivision)

func _y_to_track_index(y: float) -> int:
	var local_y := y - header_height

	if local_y < 0.0:
		return 0

	var track_index := int(floor(local_y / lane_height))
	return clamp(track_index, 0, track_count - 1)

func _track_to_y(track_index: int) -> float:
	return header_height + (track_index * lane_height)

func _is_mouse_over_timeline_lanes(position: Vector2) -> bool:
	return (
		position.x >= track_label_width
		and position.x <= size.x
		and position.y >= header_height
		and position.y <= size.y
	)

func _is_in_timeline_header(position: Vector2) -> bool:
	return position.y >= 0.0 and position.y <= header_height and position.x >= track_label_width

func _snap_timeline_position(position: float) -> float:
	if not _is_snap_active():
		return position

	return round(position)

func _is_snap_active() -> bool:
	return snap_enabled != temporary_snap_override_active


#Track data helpers
func _create_default_track_name(track_index: int) -> String:
	return "Track %d" % [track_index + 1]

func _ensure_track_names_size() -> void:
	while track_names.size() < track_count:
		track_names.append(_create_default_track_name(track_names.size()))
	while track_names.size() > track_count:
		track_names.remove_at(track_names.size() - 1)

	while track_mutes.size() < track_count:
		track_mutes.append(false)
	while track_mutes.size() > track_count:
		track_mutes.remove_at(track_mutes.size() - 1)

	while track_volumes.size() < track_count:
		track_volumes.append(1.0)
	while track_volumes.size() > track_count:
		track_volumes.remove_at(track_volumes.size() - 1)

	while track_colors.size() > track_count:
		track_colors.remove_at(track_colors.size() - 1)

func get_track_names() -> Array[String]:
	return track_names.duplicate()

func get_track_muted(track_index: int) -> bool:
	if track_index < 0 or track_index >= track_mutes.size():
		return false
	return track_mutes[track_index]

func get_track_volume(track_index: int) -> float:
	if track_index < 0 or track_index >= track_volumes.size():
		return 1.0
	return track_volumes[track_index]

func _get_track_color(track_index: int) -> Color:
	if track_color_palette.is_empty():
		return Color(0.0, 1.0, 0.0, 1.0)

	return track_color_palette[track_index % track_color_palette.size()]

func set_track_count(value: int) -> void:
	track_count = max(1, value)
	_ensure_track_names_size()

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("track"):
			continue
		clip["track"] = clamp(int(clip["track"]), 0, track_count - 1)
		clips[i] = clip

	_update_timeline_size()
	_emit_status_text()
	_emit_selected_clip_changed()
	_emit_tracks_changed()
	queue_redraw()

func _set_track_muted_internal(track_index: int, value: bool) -> void:
	if track_index < 0 or track_index >= track_count:
		return
	if track_index >= track_mutes.size():
		return
	if track_mutes[track_index] == value:
		return

	track_mutes[track_index] = value

func set_track_muted(track_index: int, value: bool) -> void:
	_commit_track_state_change("Set Track Mute", func() -> void:
		_set_track_muted_internal(track_index, value)
	)

func _set_track_volume_internal(track_index: int, value: float) -> void:
	if track_index < 0 or track_index >= track_count:
		return
	if track_index >= track_volumes.size():
		return

	var resolved_value := max(0.0, value)
	if is_equal_approx(track_volumes[track_index], resolved_value):
		return

	track_volumes[track_index] = resolved_value

func set_track_volume(track_index: int, value: float) -> void:
	_commit_track_state_change("Set Track Volume", func() -> void:
		_set_track_volume_internal(track_index, value)
	)

func get_default_audio_bus() -> StringName:
	return default_audio_bus

func set_default_audio_bus(value: StringName) -> void:
	if default_audio_bus == value:
		return

	default_audio_bus = value
	_emit_sequence_changed()

func get_track_bus_override(track_index: int) -> StringName:
	if track_bus_overrides.has(track_index):
		return StringName(str(track_bus_overrides[track_index]))

	return &""

func set_track_bus_override(track_index: int, bus_name: StringName) -> void:
	if track_index < 0 or track_index >= track_count:
		return

	if bus_name.is_empty():
		if track_bus_overrides.has(track_index):
			track_bus_overrides.erase(track_index)
			_emit_sequence_changed()
		return

	if StringName(str(track_bus_overrides.get(track_index, &""))) == bus_name:
		return

	track_bus_overrides[track_index] = bus_name
	_emit_sequence_changed()

func get_track_groups() -> Dictionary:
	return track_groups.duplicate(true)

func set_track_groups(value: Dictionary) -> void:
	track_groups = value.duplicate(true)
	_emit_sequence_changed()

func _build_track_state_snapshot() -> Dictionary:
	var clips_snapshot: Array[Dictionary] = []
	for clip in clips:
		clips_snapshot.append(clip.duplicate(true))

	return {
		"track_count": track_count,
		"track_names": track_names.duplicate(),
		"track_mutes": track_mutes.duplicate(),
		"track_volumes": track_volumes.duplicate(),
		"clips": clips_snapshot
	}

func _apply_track_state_snapshot(state: Dictionary) -> void:
	track_count = max(1, int(state.get("track_count", track_count)))

	track_names.clear()
	for track_name in state.get("track_names", []):
		track_names.append(str(track_name))

	track_mutes.clear()
	for muted in state.get("track_mutes", []):
		track_mutes.append(bool(muted))

	track_volumes.clear()
	for volume in state.get("track_volumes", []):
		track_volumes.append(max(0.0, float(volume)))

	_ensure_track_names_size()

	clips.clear()
	for clip_data in state.get("clips", []):
		if clip_data is Dictionary:
			clips.append((clip_data as Dictionary).duplicate(true))

	selected_clip_indices = selected_clip_indices.filter(func(index: int) -> bool:
		return index >= 0 and index < clips.size()
	)

	if selected_clip_indices.is_empty():
		selected_clip_index = -1
	elif not selected_clip_indices.has(selected_clip_index):
		selected_clip_index = selected_clip_indices.back()

	hovered_clip_index = -1
	hovered_resize_clip_index = -1
	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0
	drag_start_mouse_position = Vector2.ZERO
	drag_original_clip_index = -1
	drag_original_clip_data = {}
	drag_original_selected_clips.clear()
	is_resizing_clip = false
	resized_clip_index = -1
	resize_grab_offset = 0.0
	resize_start_mouse_position = Vector2.ZERO
	resize_original_clip_index = -1
	resize_original_clip_data = {}
	_update_cursor_shape()

	_update_timeline_size()
	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	_emit_tracks_changed()
	queue_redraw()

func _commit_track_state_change(action_name: String, mutator: Callable) -> void:
	var before_state := _build_track_state_snapshot()

	mutator.call()

	var after_state := _build_track_state_snapshot()
	if before_state == after_state:
		return

	if editor_undo_redo == null:
		_apply_track_state_snapshot(after_state)
		return

	_apply_track_state_snapshot(before_state)

	editor_undo_redo.create_action(action_name)
	editor_undo_redo.add_do_method(self, "_apply_track_state_snapshot", after_state)
	editor_undo_redo.add_undo_method(self, "_apply_track_state_snapshot", before_state)
	editor_undo_redo.commit_action()

func set_bars(value: int) -> void:
	var new_bars := max(1, value)
	if new_bars == bars:
		return

	var new_total_subdivisions := float(new_bars * beats_per_bar * subdivisions_per_beat)
	var furthest_clip_end := _get_furthest_clip_end()
	if new_total_subdivisions < furthest_clip_end:
		_show_blocked_action_feedback("Can't reduce bars below the last clip end.")
		return

	if editor_undo_redo == null:
		_apply_bars_value(new_bars)
		return

	var previous_bars := bars

	editor_undo_redo.create_action("Change Bars")
	editor_undo_redo.add_do_method(self, "_apply_bars_value", new_bars)
	editor_undo_redo.add_undo_method(self, "_apply_bars_value", previous_bars)
	editor_undo_redo.commit_action()

func _apply_bars_value(value: int) -> void:
	bars = max(1, value)
	_update_timeline_size()
	_emit_status_text()
	_emit_selected_clip_changed()
	_emit_sequence_changed()
	queue_redraw()


#Clip geometry, constraints and placement helpers
func _get_clip_rect(clip: Dictionary) -> Rect2:
	var track_index: int = clip["track"]
	var start: float = clip["start"]
	var length: float = clip["length"]

	var x := _timeline_to_x(start) + clip_horizontal_padding
	var y := _track_to_y(track_index) + clip_vertical_padding
	var width := (length * pixels_per_subdivision) - (clip_horizontal_padding/2)
	var height := lane_height - (clip_vertical_padding * 2.0)

	return Rect2(x, y, width, height)

func _get_clip_index_at_position(position: Vector2) -> int:
	for i in range(clips.size() - 1, -1, -1):
		var clip := clips[i]

		if not clip.has("track") or not clip.has("start") or not clip.has("length"):
			continue

		var track_index: int = clip["track"]
		var length: float = clip["length"]

		if track_index < 0 or track_index >= track_count:
			continue

		if length <= 0.0:
			continue

		var rect := _get_clip_rect(clip)

		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue

		if rect.has_point(position):
			return i

	return -1

func _get_clip_end(clip: Dictionary) -> float:
	return float(clip["start"]) + float(clip["length"])

func _clip_has_audio_source(clip: Dictionary) -> bool:
	return not str(clip.get("audio_path", "")).strip_edges().is_empty()

func _get_furthest_clip_end() -> float:
	var furthest_end := 0.0

	for clip in clips:
		if not clip.has("start") or not clip.has("length"):
			continue

		furthest_end = max(furthest_end, _get_clip_end(clip))

	return furthest_end

func _get_track_clips_sorted(track_index: int, exclude_clip_index: int = -1, exclude_clip_indices: Array[int] = []) -> Array:
	var clips_on_track: Array[Dictionary] = []

	for i in range(clips.size()):
		if i == exclude_clip_index:
			continue

		if exclude_clip_indices.has(i):
			continue

		var clip := clips[i]
		if not clip.has("track") or not clip.has("start") or not clip.has("length"):
			continue

		if int(clip["track"]) != track_index:
			continue

		clips_on_track.append({
			"index": i,
			"start": float(clip["start"]),
			"end": _get_clip_end(clip)
		})

	clips_on_track.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["start"]) < float(b["start"])
	)

	return clips_on_track

func _get_clip_start_limits(track_index: int, exclude_clip_index: int, clip_length: float, desired_start: float, exclude_clip_indices: Array[int] = []) -> Dictionary:
	var total_subdivisions := float(_get_total_subdivisions())
	var min_start := 0.0
	var next_start := total_subdivisions

	for other in _get_track_clips_sorted(track_index, exclude_clip_index, exclude_clip_indices):
		var other_start := float(other["start"])
		var other_end := float(other["end"])

		if other_end <= desired_start:
			min_start = max(min_start, other_end)
		elif other_start >= desired_start:
			next_start = min(next_start, other_start)
			break
		else:
			min_start = max(min_start, other_end)

	var max_start := next_start - clip_length
	var has_room := max_start >= min_start

	return {
		"min_start": min_start,
		"max_start": max_start,
		"has_room": has_room
	}

func _get_max_clip_length_without_overlap(track_index: int, exclude_clip_index: int, clip_start: float) -> float:
	var total_subdivisions := float(_get_total_subdivisions())
	var next_start := total_subdivisions

	for other in _get_track_clips_sorted(track_index, exclude_clip_index):
		var other_start := float(other["start"])

		if other_start >= clip_start:
			next_start = other_start
			break

	return max(min_clip_length, next_start - clip_start)

func _get_clip_max_length_from_audio(clip: Dictionary) -> float:
	var audio_path := str(clip.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		return INF

	var audio_stream := load(audio_path) as AudioStream
	if audio_stream == null:
		return INF

	var audio_length_seconds := audio_stream.get_length()
	if audio_length_seconds <= 0.0:
		return INF
	var source_start_offset_seconds := max(0.0, float(clip.get("source_start_offset_seconds", 0.0)))
	var remaining_audio_seconds := max(0.0, audio_length_seconds - source_start_offset_seconds)
	if remaining_audio_seconds <= 0.0:
		return min_clip_length
	var playback_speed := max(0.001, float(clip.get("playback_speed", 1.0)))
	return max(min_clip_length, (remaining_audio_seconds * _get_subdivisions_per_second()) / playback_speed)

func _get_effective_max_clip_length(clip_index: int, clip: Dictionary) -> float:
	if not clip.has("track") or not clip.has("start"):
		return min_clip_length

	var overlap_max := _get_max_clip_length_without_overlap(
		int(clip["track"]),
		clip_index,
		float(clip["start"])
	)
	var audio_max := _get_clip_max_length_from_audio(clip)

	return max(min_clip_length, min(overlap_max, audio_max))

func get_clip_max_length(clip_index: int) -> float:
	if clip_index < 0 or clip_index >= clips.size():
		return min_clip_length

	return _get_effective_max_clip_length(clip_index, clips[clip_index])

func _clamp_all_clip_lengths_for_current_tempo() -> bool:
	var changed := false

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("length"):
			continue

		var current_length := float(clip.get("length", min_clip_length))
		var max_length := _get_effective_max_clip_length(i, clip)
		var clamped_length := clamp(current_length, min_clip_length, max_length)

		if is_equal_approx(current_length, clamped_length):
			continue

		clip["length"] = clamped_length
		clips[i] = clip
		changed = true

	return changed

func _find_available_start(track_index: int, clip_length: float, preferred_start: float, exclude_clip_index: int = -1) -> float:
	var total_subdivisions := float(_get_total_subdivisions())
	var max_start := max(0.0, total_subdivisions - clip_length)
	var candidate_start := clamp(preferred_start, 0.0, max_start)

	for other in _get_track_clips_sorted(track_index, exclude_clip_index):
		var other_start := float(other["start"])
		var other_end := float(other["end"])

		if candidate_start + clip_length <= other_start:
			return candidate_start

		if candidate_start < other_end:
			candidate_start = other_end

		if candidate_start > max_start:
			return -1.0

	return candidate_start

func _can_place_clip_at(track_index: int, exclude_clip_index: int, clip_length: float, start_position: float) -> bool:
	var limits := _get_clip_start_limits(track_index, exclude_clip_index, clip_length, start_position)

	if not bool(limits["has_room"]):
		return false

	var resolved_start := clamp(
		start_position,
		float(limits["min_start"]),
		float(limits["max_start"])
	)

	return is_equal_approx(resolved_start, start_position)

func _is_supported_audio_path(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return extension == "wav" or extension == "ogg" or extension == "mp3"

func _extract_audio_paths_from_drop_data(data: Variant) -> Array[String]:
	var audio_paths: Array[String] = []

	if data is Dictionary:
		var data_dictionary := data as Dictionary

		if str(data_dictionary.get("type", "")) == "files":
			var files := data_dictionary.get("files", [])
			if files is PackedStringArray:
				for file_path in files:
					var resolved_path := str(file_path)
					if _is_supported_audio_path(resolved_path):
						audio_paths.append(resolved_path)
			elif files is Array:
				for file_path in files:
					var resolved_path := str(file_path)
					if _is_supported_audio_path(resolved_path):
						audio_paths.append(resolved_path)

		elif data_dictionary.has("files"):
			var dictionary_files := data_dictionary.get("files", [])
			if dictionary_files is Array:
				for file_path in dictionary_files:
					var resolved_path := str(file_path)
					if _is_supported_audio_path(resolved_path):
						audio_paths.append(resolved_path)

	elif data is PackedStringArray:
		for file_path in data:
			var resolved_path := str(file_path)
			if _is_supported_audio_path(resolved_path):
				audio_paths.append(resolved_path)

	elif data is Array:
		for file_path in data:
			var resolved_path := str(file_path)
			if _is_supported_audio_path(resolved_path):
				audio_paths.append(resolved_path)

	return audio_paths


#Sequence serialization
func get_sequence_data() -> Dictionary:
	var serialized_clips: Array[Dictionary] = []

	for clip in clips:
		var serialized_clip: Dictionary = {
			"track": int(clip.get("track", 0)),
			"start": float(clip.get("start", 0.0)),
			"length": float(clip.get("length", min_clip_length)),
			"name": str(clip.get("name", "Clip")),
			"audio_path": str(clip.get("audio_path", "")),
			"source_start_offset_seconds": max(0.0, float(clip.get("source_start_offset_seconds", 0.0))),
			"playback_speed": float(clip.get("playback_speed", 1.0)),
			"volume": float(clip.get("volume", 1.0))
		}

		serialized_clips.append(serialized_clip)

	return {
		"bars": bars,
		"beats_per_bar": beats_per_bar,
		"subdivisions_per_beat": subdivisions_per_beat,
		"bpm": bpm,
		"track_count": track_count,
		"track_names": track_names.duplicate(),
		"track_mutes": track_mutes.duplicate(),
		"track_volumes": track_volumes.duplicate(),
		"default_audio_bus": str(default_audio_bus),
		"track_bus_overrides": track_bus_overrides.duplicate(true),
		"track_effect_chains": track_effect_chains.duplicate(true),
		"track_groups": track_groups.duplicate(true),
		"clips": serialized_clips
	}

func create_sequence_resource(sequence_title: String = "") -> Resource:
	var sequence_resource := SEQUENCER_SEQUENCE_SCRIPT.new()
	var sequence_data := get_sequence_data()

	var resolved_title := sequence_title.strip_edges()
	if resolved_title.is_empty():
		resolved_title = "Untitled Sequence"

	sequence_data["title"] = resolved_title
	sequence_data["format_version"] = 1
	sequence_resource.load_from_dictionary(sequence_data)

	return sequence_resource

func load_sequence_data(data: Dictionary) -> void:
	bars = max(1, int(data.get("bars", bars)))
	beats_per_bar = max(1, int(data.get("beats_per_bar", beats_per_bar)))
	subdivisions_per_beat = max(1, int(data.get("subdivisions_per_beat", subdivisions_per_beat)))
	bpm = max(1.0, float(data.get("bpm", bpm)))
	track_count = max(1, int(data.get("track_count", track_count)))

	track_names.clear()

	var loaded_track_names = data.get("track_names", [])
	if loaded_track_names is Array:
		for track_name in loaded_track_names:
			track_names.append(str(track_name))

	track_mutes.clear()
	var loaded_track_mutes = data.get("track_mutes", [])
	if loaded_track_mutes is Array:
		for muted in loaded_track_mutes:
			track_mutes.append(bool(muted))

	track_volumes.clear()
	var loaded_track_volumes = data.get("track_volumes", [])
	if loaded_track_volumes is Array:
		for volume in loaded_track_volumes:
			track_volumes.append(max(0.0, float(volume)))
	_ensure_track_names_size()
	default_audio_bus = StringName(str(data.get("default_audio_bus", default_audio_bus)))

	var loaded_track_bus_overrides = data.get("track_bus_overrides", {})
	track_bus_overrides = loaded_track_bus_overrides.duplicate(true) if loaded_track_bus_overrides is Dictionary else {}

	var loaded_track_effect_chains = data.get("track_effect_chains", {})
	track_effect_chains = loaded_track_effect_chains.duplicate(true) if loaded_track_effect_chains is Dictionary else {}

	var loaded_track_groups = data.get("track_groups", {})
	track_groups = loaded_track_groups.duplicate(true) if loaded_track_groups is Dictionary else {}

	clips.clear()

	var loaded_clips = data.get("clips", [])
	if loaded_clips is Array:
		for loaded_clip in loaded_clips:
			if not loaded_clip is Dictionary:
				continue

			var clip_track := clamp(int(loaded_clip.get("track", 0)), 0, track_count - 1)
			var clip_start := max(0.0, float(loaded_clip.get("start", 0.0)))
			var clip_length := max(min_clip_length, float(loaded_clip.get("length", min_clip_length)))
			var clip_playback_speed := max(0.001, float(loaded_clip.get("playback_speed", 1.0)))
			var clip_volume := max(0.0, float(loaded_clip.get("volume", 1.0)))
			var clip_source_start_offset_seconds := max(0.0, float(loaded_clip.get("source_start_offset_seconds", 0.0)))

			var clip: Dictionary = {
				"track": clip_track,
				"start": clip_start,
				"length": clip_length,
				"name": str(loaded_clip.get("name", "Clip")),
				"audio_path": str(loaded_clip.get("audio_path", "")),
				"source_start_offset_seconds": clip_source_start_offset_seconds,
				"playback_speed": clip_playback_speed,
				"volume": clip_volume
			}
			var max_length := min(max(min_clip_length, float(_get_total_subdivisions()) - clip_start),_get_clip_max_length_from_audio(clip))
			clip["length"] = clamp(clip_length, min_clip_length, max_length)
			clips.append(clip)

	_reset_selection_and_interaction_state()
	_update_timeline_size()

	_set_playing(false)
	playhead_position = 0.0

	_emit_status_text()
	_emit_selected_clip_changed()
	_emit_tracks_changed()
	queue_redraw()

func create_new_sequence(new_bars: int, new_beats_per_bar: int, new_subdivisions_per_beat: int) -> void:
	load_sequence_data({
		"bars": max(1, new_bars),
		"beats_per_bar": max(1, new_beats_per_bar),
		"subdivisions_per_beat": max(1, new_subdivisions_per_beat),
		"bpm": bpm,
		"track_count": track_count,
		"track_names": [],
		"track_mutes": [],
		"track_volumes": [],
		"default_audio_bus": "Master",
		"track_bus_overrides": {},
		"track_effect_chains": {},
		"track_groups": {},
		"clips": []
	})


#Selection helpers
func _reset_selection_and_interaction_state() -> void:
	selected_clip_indices.clear()
	selected_clip_index = -1
	hovered_clip_index = -1
	hovered_resize_clip_index = -1

	drag_original_selected_clips.clear()

	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0
	drag_start_mouse_position = Vector2.ZERO
	drag_original_clip_index = -1
	drag_original_clip_data = {}

	is_resizing_clip = false
	resized_clip_index = -1
	resize_grab_offset = 0.0
	resize_start_mouse_position = Vector2.ZERO
	resize_original_clip_index = -1
	resize_original_clip_data = {}
	_update_cursor_shape()

func _cancel_active_edit_interaction_state() -> void:
	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0
	drag_start_mouse_position = Vector2.ZERO
	drag_original_clip_index = -1
	drag_original_clip_data = {}
	drag_original_selected_clips.clear()

	is_resizing_clip = false
	resized_clip_index = -1
	resize_grab_offset = 0.0
	resize_start_mouse_position = Vector2.ZERO
	resize_original_clip_index = -1
	resize_original_clip_data = {}

	temporary_snap_override_active = false
	hovered_resize_clip_index = -1
	hovered_clip_index = -1

	_update_cursor_shape()
	queue_redraw()

func _clear_selection() -> void:
	selected_clip_indices.clear()
	selected_clip_index = -1
	_update_cursor_shape()

func _set_single_selection(clip_index: int) -> void:
	selected_clip_indices = [clip_index]
	selected_clip_index = clip_index
	_update_cursor_shape()

func _toggle_selection(clip_index: int) -> void:
	if selected_clip_indices.has(clip_index):
		selected_clip_indices.erase(clip_index)
	else:
		selected_clip_indices.append(clip_index)

	if selected_clip_indices.is_empty():
		selected_clip_index = -1
	else:
		selected_clip_index = selected_clip_indices.back()
	_update_cursor_shape()

func _set_selected_clip_indices(indices: Array[int]) -> void:
	selected_clip_indices.clear()

	for clip_index in indices:
		if clip_index >= 0 and clip_index < clips.size():
			selected_clip_indices.append(clip_index)

	if selected_clip_indices.is_empty():
		selected_clip_index = -1
	else:
		selected_clip_index = selected_clip_indices.back()

	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _get_selected_clip_data() -> Dictionary:
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return {}

	return clips[selected_clip_index].duplicate(true)

func clear_selected_clip() -> void:
	if selected_clip_index == -1:
		return

	selected_clip_index = -1
	selected_clip_indices.clear()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()


#Playback
func set_playhead_position(value: float) -> void:
	playhead_position = clamp(value, 0.0, float(_get_total_subdivisions()))
	queue_redraw()

func set_loop_enabled(value: bool) -> void:
	loop_enabled = value
	_emit_status_text()
	queue_redraw()

func _update_playhead_from_mouse_x(mouse_x: float) -> void:
	set_playhead_position(_x_to_timeline(mouse_x))

func _begin_playhead_scrub(mouse_x: float) -> void:
	is_scrubbing_playhead = true
	was_playing_before_scrub = is_playing
	_set_playing(false)
	_update_playhead_from_mouse_x(mouse_x)

func _end_playhead_scrub() -> void:
	if not is_scrubbing_playhead:
		return

	is_scrubbing_playhead = false

	if was_playing_before_scrub:
		_set_playing(true)

	was_playing_before_scrub = false
	queue_redraw()

func _ensure_playhead_visible_during_playback() -> void:
	var playhead_x := _timeline_to_x(playhead_position)

	var playhead_rect := Rect2(
		playhead_x - 1.0,
		0.0,
		2.0,
		size.y
	)

	_ensure_rect_visible_horizontally(playhead_rect, playhead_follow_margin)

func _is_editing_blocked_by_playback(show_feedback: bool = false) -> bool:
	if not is_playing:
		return false

	if show_feedback:
		_show_blocked_action_feedback("Pause playback before editing.")

	return true

func _set_playing(value: bool) -> void:
	if is_playing == value:
		return
	if value:
		_cancel_active_edit_interaction_state()
	is_playing = value
	playback_state_changed.emit(is_playing)
	queue_redraw()

func play() -> void:
	_set_playing(true)

func pause() -> void:
	_set_playing(false)

func _build_bpm_state_snapshot() -> Dictionary:
	var clips_snapshot: Array[Dictionary] = []

	for clip in clips:
		clips_snapshot.append(clip.duplicate(true))

	return {
		"bpm": bpm,
		"clips": clips_snapshot
	}

func _apply_bpm_state_snapshot(state: Dictionary) -> void:
	bpm = max(1.0, float(state.get("bpm", bpm)))

	clips.clear()
	for clip_data in state.get("clips", []):
		if clip_data is Dictionary:
			clips.append((clip_data as Dictionary).duplicate(true))

	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _set_bpm_internal(value: float) -> void:
	var new_bpm := max(1.0, value)
	if is_equal_approx(bpm, new_bpm):
		return

	bpm = new_bpm
	var clips_changed := _clamp_all_clip_lengths_for_current_tempo()

	_emit_sequence_changed()
	_emit_status_text()

	if clips_changed:
		_emit_selected_clip_changed()

	queue_redraw()

func set_bpm(value: float) -> void:
	var before_state := _build_bpm_state_snapshot()

	_set_bpm_internal(value)

	var after_state := _build_bpm_state_snapshot()
	if before_state == after_state:
		return

	if editor_undo_redo == null:
		_apply_bpm_state_snapshot(after_state)
		return

	_apply_bpm_state_snapshot(before_state)

	editor_undo_redo.create_action("Change BPM")
	editor_undo_redo.add_do_method(self, "_apply_bpm_state_snapshot", after_state)
	editor_undo_redo.add_undo_method(self, "_apply_bpm_state_snapshot", before_state)
	editor_undo_redo.commit_action()


#Input/process
func _gui_input(event: InputEvent) -> void:
	_update_temporary_snap_override_from_event(event)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
				delete_selected_clip()
				accept_event()
				return
			if key_event.ctrl_pressed and key_event.keycode == KEY_C:
				copy_selected_clips()
				accept_event()
				return
			if key_event.ctrl_pressed and key_event.keycode == KEY_X:
				cut_selected_clips()
				accept_event()
				return
			if key_event.ctrl_pressed and key_event.keycode == KEY_V:
				paste_clipboard()
				accept_event()
				return
			if key_event.ctrl_pressed and key_event.keycode == KEY_D:
				duplicate_selected_clip()
				accept_event()
				return
			if key_event.ctrl_pressed and key_event.keycode == KEY_A:
				if _is_editing_blocked_by_playback(true):
					accept_event()
					return
				add_clip_requested.emit()
				accept_event()
				return
			if key_event.keycode == KEY_SPACE:
				if is_playing:
					pause()
				else:
					play()
				accept_event()
				return
		if key_event.pressed:
			if key_event.keycode == KEY_LEFT:
				if key_event.shift_pressed:
					_nudge_selected_clip(-keyboard_micro_nudge_amount, false)
				else:
					_nudge_selected_clip(-keyboard_nudge_amount, true)
				accept_event()
				return
			if key_event.keycode == KEY_RIGHT:
				if key_event.shift_pressed:
					_nudge_selected_clip(keyboard_micro_nudge_amount, false)
				else:
					_nudge_selected_clip(keyboard_nudge_amount, true)
				accept_event()
				return

	if event is InputEventMouseMotion:
		var mouse_motion_event := event as InputEventMouseMotion

		if is_scrubbing_playhead:
			_update_playhead_from_mouse_x(mouse_motion_event.position.x)
			accept_event()
			return

		if not is_dragging_clip and not is_resizing_clip:
			_update_hovered_resize_handle(mouse_motion_event.position)
			_update_hovered_clip(mouse_motion_event.position)

		return

	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if not mouse_button_event.pressed:
			if is_scrubbing_playhead:
				_end_playhead_scrub()
				accept_event()
				return
			if is_dragging_clip:
				_end_clip_drag()
				accept_event()
				return
			if is_resizing_clip:
				_end_clip_resize()
				accept_event()
				return
		if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button_event.pressed:
				grab_focus()

				if _is_in_timeline_header(mouse_button_event.position):
					_begin_playhead_scrub(mouse_button_event.position.x)
					accept_event()
					return

				var clicked_resize_clip_index := _get_resize_handle_clip_index_at_position(mouse_button_event.position)

				if clicked_resize_clip_index != -1:
					_set_single_selection(clicked_resize_clip_index)
					_emit_selected_clip_changed()
					_begin_clip_resize(clicked_resize_clip_index, mouse_button_event.position)
					return

				var clicked_clip_index := _get_clip_index_at_position(mouse_button_event.position)

				if clicked_clip_index == -1:
					_clear_selection()
					_update_hovered_resize_handle(mouse_button_event.position)
					_update_hovered_clip(mouse_button_event.position)
					_update_cursor_shape()
					_emit_status_text()
					_emit_selected_clip_changed()
					queue_redraw()
					accept_event()
					return

				if mouse_button_event.shift_pressed:
					_toggle_selection(clicked_clip_index)
					_update_hovered_resize_handle(mouse_button_event.position)
					_update_hovered_clip(mouse_button_event.position)
					_update_cursor_shape()
					_emit_status_text()
					_emit_selected_clip_changed()
					queue_redraw()
					accept_event()
					return

				if not selected_clip_indices.has(clicked_clip_index):
					_set_single_selection(clicked_clip_index)

				_emit_status_text()
				_emit_selected_clip_changed()
				_begin_clip_drag(clicked_clip_index, mouse_button_event.position)
				accept_event()
				return

			else:
				if is_scrubbing_playhead:
					_end_playhead_scrub()
					accept_event()
					return

				if is_resizing_clip:
					_end_clip_resize()
				else:
					_end_clip_drag()

				_update_hovered_resize_handle(mouse_button_event.position)
				_update_hovered_clip(mouse_button_event.position)
		if mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button_event.pressed:
				grab_focus()

				if _is_in_timeline_header(mouse_button_event.position) or _is_mouse_over_timeline_lanes(mouse_button_event.position):
					_begin_playhead_scrub(mouse_button_event.position.x)
					accept_event()
					return
			else:
				if is_scrubbing_playhead:
					_end_playhead_scrub()
					accept_event()
					return

func _process(delta: float) -> void:
	if blocked_action_flash_time > 0.0:
		blocked_action_flash_time = max(0.0, blocked_action_flash_time - delta)
		queue_redraw()

	if is_playing and not is_scrubbing_playhead:
		playhead_position += _get_subdivisions_per_second() * delta

		if playhead_position >= float(_get_total_subdivisions()):
			playhead_position = 0.0

			if not loop_enabled:
				_set_playing(false)

		_ensure_playhead_visible_during_playback()
		queue_redraw()

	if not is_dragging_clip and not is_resizing_clip:
		return

	temporary_snap_override_active = Input.is_key_pressed(KEY_SHIFT)

	var mouse_position := get_local_mouse_position()
	_auto_scroll_during_drag(mouse_position, delta)
	mouse_position = get_local_mouse_position()

	if is_resizing_clip:
		_update_clip_resize(mouse_position)
	elif is_dragging_clip:
		_update_clip_drag(mouse_position)

func _update_temporary_snap_override_from_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion_event := event as InputEventMouseMotion
		temporary_snap_override_active = mouse_motion_event.shift_pressed
	elif event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		temporary_snap_override_active = mouse_button_event.shift_pressed
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		temporary_snap_override_active = key_event.shift_pressed


#Drag and resize
func _update_cursor_shape() -> void:
	if is_resizing_clip or hovered_resize_clip_index != -1:
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif is_dragging_clip:
		mouse_default_cursor_shape = Control.CURSOR_MOVE
	elif hovered_clip_index != -1 and selected_clip_indices.has(hovered_clip_index):
		mouse_default_cursor_shape = Control.CURSOR_MOVE
	elif hovered_clip_index != -1:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _begin_clip_drag(clip_index: int, mouse_position: Vector2) -> void:
	if _is_editing_blocked_by_playback():
		return

	if not selected_clip_indices.has(clip_index):
		return

	if clip_index < 0 or clip_index >= clips.size():
		return
	drag_start_mouse_position = mouse_position
	var clip := clips[clip_index]

	if not clip.has("start"):
		return

	drag_original_clip_index = clip_index
	drag_original_clip_data = clip.duplicate(true)

	drag_original_selected_clips.clear()
	for i in selected_clip_indices:
		if i >= 0 and i < clips.size():
			drag_original_selected_clips[i] = clips[i].duplicate(true)

	var clip_start: float = clip["start"]
	var mouse_timeline_position := _x_to_timeline(mouse_position.x)

	is_dragging_clip = true
	dragged_clip_index = clip_index
	drag_grab_offset = mouse_timeline_position - clip_start

	selected_clip_index = clip_index
	hovered_clip_index = -1
	_update_cursor_shape()
	queue_redraw()

func _update_clip_drag(mouse_position: Vector2) -> void:
	if not is_dragging_clip or is_resizing_clip:
		return

	if dragged_clip_index < 0 or dragged_clip_index >= clips.size():
		return

	if mouse_position.distance_to(drag_start_mouse_position) < 4.0:
		return

	if selected_clip_indices.size() > 1:
		var primary_index := selected_clip_index
		if not drag_original_selected_clips.has(primary_index):
			return

		var primary_original = drag_original_selected_clips[primary_index]
		var primary_start: float = primary_original["start"]

		var mouse_timeline_position := _x_to_timeline(mouse_position.x)
		var desired_primary_start := mouse_timeline_position - drag_grab_offset
		desired_primary_start = _snap_timeline_position(desired_primary_start)

		var delta := desired_primary_start - primary_start
		if is_equal_approx(delta, 0.0):
			return
		for clip_index in selected_clip_indices:
			if not drag_original_selected_clips.has(clip_index):
				return

			var original = drag_original_selected_clips[clip_index]
			var track := int(original["track"])
			var start := float(original["start"])
			var length := float(original["length"])

			var desired_start := start + delta

			var limits := _get_clip_start_limits(
				track,
				clip_index,
				length,
				desired_start,
				selected_clip_indices
			)

			if not bool(limits["has_room"]):
				return

			var resolved := clamp(
				desired_start,
				float(limits["min_start"]),
				float(limits["max_start"])
			)

			if not is_equal_approx(resolved, desired_start):
				return
		for clip_index in selected_clip_indices:
			var original = drag_original_selected_clips[clip_index]
			var clip = original.duplicate(true)
			clip["start"] = float(original["start"]) + delta
			clips[clip_index] = clip

		_emit_status_text()
		_emit_selected_clip_changed()
		queue_redraw()
		return

	var clip := clips[dragged_clip_index]

	if not clip.has("start") or not clip.has("length") or not clip.has("track"):
		return

	var length: float = clip["length"]
	var mouse_timeline_position := _x_to_timeline(mouse_position.x)
	var desired_start := mouse_timeline_position - drag_grab_offset
	desired_start = _snap_timeline_position(desired_start)

	var target_track := _y_to_track_index(mouse_position.y)
	var target_limits := _get_clip_start_limits(target_track, dragged_clip_index, length, desired_start)

	var new_track := int(clip["track"])
	var new_start := float(clip["start"])

	if bool(target_limits["has_room"]):
		new_track = target_track
		new_start = clamp(desired_start, float(target_limits["min_start"]), float(target_limits["max_start"]))
	else:
		var current_limits := _get_clip_start_limits(int(clip["track"]), dragged_clip_index, length, desired_start)
		if bool(current_limits["has_room"]):
			new_start = clamp(desired_start, float(current_limits["min_start"]), float(current_limits["max_start"]))

	clip["track"] = new_track
	clip["start"] = new_start

	clips[dragged_clip_index] = clip

	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _end_clip_drag() -> void:
	if not is_dragging_clip:
		return
	var handled_multiselect_drag := false
	if drag_original_selected_clips.size() > 1:
		var before := {}
		var after := {}

		for clip_index in drag_original_selected_clips.keys():
			before[clip_index] = drag_original_selected_clips[clip_index].duplicate(true)
			after[clip_index] = clips[clip_index].duplicate(true)

		if editor_undo_redo != null:
			var dragged_selection := selected_clip_indices.duplicate()

			editor_undo_redo.create_action("Move Clips")
			for clip_index in before.keys():
				editor_undo_redo.add_do_method(self, "_set_clip_data", clip_index, after[clip_index])
				editor_undo_redo.add_undo_method(self, "_set_clip_data", clip_index, before[clip_index])

			editor_undo_redo.add_do_method(self, "_set_selected_clip_indices", dragged_selection)
			editor_undo_redo.add_undo_method(self, "_set_selected_clip_indices", dragged_selection)
			editor_undo_redo.commit_action()
		handled_multiselect_drag = true
		drag_original_selected_clips.clear()


	var should_register_undo := false
	var final_clip_index := drag_original_clip_index
	var before_clip: Dictionary = {}
	var after_clip: Dictionary = {}

	if not handled_multiselect_drag and drag_original_clip_index >= 0 and drag_original_clip_index < clips.size() and not drag_original_clip_data.is_empty():
		var current_clip := clips[drag_original_clip_index]

		var original_start := float(drag_original_clip_data.get("start", 0.0))
		var current_start := float(current_clip.get("start", 0.0))
		var original_track := int(drag_original_clip_data.get("track", 0))
		var current_track := int(current_clip.get("track", 0))

		if original_start != current_start or original_track != current_track:
			should_register_undo = true
			before_clip = drag_original_clip_data.duplicate(true)
			after_clip = current_clip.duplicate(true)

	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0
	drag_start_mouse_position = Vector2.ZERO
	temporary_snap_override_active = false

	if should_register_undo and editor_undo_redo != null:
		editor_undo_redo.create_action("Move Clip")
		editor_undo_redo.add_do_method(self, "_set_clip_data", final_clip_index, after_clip)
		editor_undo_redo.add_undo_method(self, "_set_clip_data", final_clip_index, before_clip)
		editor_undo_redo.commit_action()

	drag_original_clip_index = -1
	drag_original_clip_data = {}

	_update_cursor_shape()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _get_resize_handle_rect(clip: Dictionary) -> Rect2:
	var clip_rect := _get_clip_rect(clip)
	var handle_width := min(resize_handle_width, clip_rect.size.x)

	return Rect2(
		clip_rect.end.x - handle_width,
		clip_rect.position.y,
		handle_width,
		clip_rect.size.y
	)

func _get_resize_handle_clip_index_at_position(position: Vector2) -> int:
	for i in range(clips.size() - 1, -1, -1):
		var clip := clips[i]

		if not clip.has("track") or not clip.has("start") or not clip.has("length"):
			continue

		var track_index: int = clip["track"]
		var length: float = clip["length"]

		if track_index < 0 or track_index >= track_count:
			continue

		if length <= 0.0:
			continue

		var handle_rect := _get_resize_handle_rect(clip)

		if handle_rect.size.x <= 1.0 or handle_rect.size.y <= 1.0:
			continue

		if handle_rect.has_point(position):
			return i

	return -1

func _update_hovered_resize_handle(position: Vector2) -> void:
	var new_hovered_resize_clip_index := _get_resize_handle_clip_index_at_position(position)

	if new_hovered_resize_clip_index == hovered_resize_clip_index:
		return

	hovered_resize_clip_index = new_hovered_resize_clip_index
	_update_cursor_shape()
	queue_redraw()

func _begin_clip_resize(clip_index: int, mouse_position: Vector2) -> void:
	if _is_editing_blocked_by_playback():
		return

	if clip_index < 0 or clip_index >= clips.size():
		return
	resize_start_mouse_position = mouse_position
	var clip := clips[clip_index]

	if not clip.has("start") or not clip.has("length"):
		return
	resize_original_clip_index = clip_index
	resize_original_clip_data = clip.duplicate(true)

	var clip_start: float = clip["start"]
	var clip_length: float = clip["length"]
	var clip_end := clip_start + clip_length
	var mouse_timeline_position := _x_to_timeline(mouse_position.x)

	is_resizing_clip = true
	resized_clip_index = clip_index
	resize_grab_offset = mouse_timeline_position - clip_end

	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0

	_set_single_selection(clip_index)
	hovered_clip_index = -1
	hovered_resize_clip_index = clip_index
	_update_cursor_shape()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _update_clip_resize(mouse_position: Vector2) -> void:
	if not is_resizing_clip:
		return

	if resized_clip_index < 0 or resized_clip_index >= clips.size():
		return

	if mouse_position.distance_to(resize_start_mouse_position) < 4.0:
		return

	var clip := clips[resized_clip_index]

	if not clip.has("start") or not clip.has("length"):
		return

	var start: float = clip["start"]
	var track_index: int = clip["track"]
	var mouse_timeline_position := _x_to_timeline(mouse_position.x)
	var new_end := mouse_timeline_position - resize_grab_offset
	new_end = _snap_timeline_position(new_end)

	var min_end := start + min_clip_length
	var max_length := _get_effective_max_clip_length(resized_clip_index, clip)
	var max_end := start + max_length

	new_end = clamp(new_end, min_end, max_end)
	var new_length := new_end - start

	clip["length"] = new_length
	clips[resized_clip_index] = clip

	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _end_clip_resize() -> void:
	if not is_resizing_clip:
		return

	var should_register_undo := false
	var final_clip_index := resize_original_clip_index
	var before_clip: Dictionary = {}
	var after_clip: Dictionary = {}

	if resize_original_clip_index >= 0 and resize_original_clip_index < clips.size() and not resize_original_clip_data.is_empty():
		var current_clip := clips[resize_original_clip_index]
		if resize_original_clip_data != current_clip:
			should_register_undo = true
			before_clip = resize_original_clip_data.duplicate(true)
			after_clip = current_clip.duplicate(true)

	is_resizing_clip = false
	resized_clip_index = -1
	resize_grab_offset = 0.0
	resize_start_mouse_position = Vector2.ZERO
	temporary_snap_override_active = false
	if should_register_undo and editor_undo_redo != null:
		editor_undo_redo.create_action("Resize Clip")
		editor_undo_redo.add_do_method(self, "_set_clip_data", final_clip_index, after_clip)
		editor_undo_redo.add_undo_method(self, "_set_clip_data", final_clip_index, before_clip)
		editor_undo_redo.commit_action()

	resize_original_clip_index = -1
	resize_original_clip_data = {}

	_update_cursor_shape()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()


#Clip creation/editing
func prepare_next_clip_insertion_context() -> void:
	var mouse_position := get_local_mouse_position()
	var mouse_over_timeline := _is_mouse_over_timeline_lanes(mouse_position)

	pending_clip_insertion_context = {
		"selected_clip_index": selected_clip_index,
		"playhead_position": playhead_position,
		"mouse_over_timeline": mouse_over_timeline,
		"mouse_track": _y_to_track_index(mouse_position.y) if mouse_over_timeline else 0
	}

func _build_new_clip_defaults(audio_path: String) -> Dictionary:
	var clip_name := "New Clip"
	var clip_length := max(4.0, min_clip_length)

	if not audio_path.strip_edges().is_empty():
		clip_name = audio_path.get_file().get_basename()

		var audio_stream := load(audio_path) as AudioStream
		if audio_stream != null:
			var audio_length_seconds := audio_stream.get_length()
			if audio_length_seconds > 0.0:
				clip_length = max(audio_length_seconds * _get_subdivisions_per_second(), min_clip_length)

	if clip_name.strip_edges().is_empty():
		clip_name = "New Clip"

	return {
		"name": clip_name,
		"length": clip_length
	}

func _build_clip_data_at_position(audio_path: String, track_index: int, desired_start: float) -> Dictionary:
	if _is_editing_blocked_by_playback(true):
		return {}

	var defaults := _build_new_clip_defaults(audio_path)
	var clip_length := min(float(defaults["length"]), float(_get_total_subdivisions()))
	var clip_name := str(defaults["name"])

	if clip_length <= 0.0:
		return {}

	var resolved_track := clamp(track_index, 0, track_count - 1)
	var resolved_start := _snap_timeline_position(desired_start)

	if not _can_place_clip_at(resolved_track, -1, clip_length, resolved_start):
		resolved_start = _find_available_start(resolved_track, clip_length, resolved_start)
		if resolved_start < 0.0:
			return {}

	return {
		"track": resolved_track,
		"start": resolved_start,
		"length": clip_length,
		"name": clip_name,
		"audio_path": audio_path,
		"source_start_offset_seconds": 0.0,
		"playback_speed": 1.0,
		"volume": 1.0
	}

func add_clip_at_position(audio_path: String, track_index: int, desired_start: float) -> int:
	var new_clip := _build_clip_data_at_position(audio_path, track_index, desired_start)
	if new_clip.is_empty():
		return -1

	var insert_index := clips.size()

	if editor_undo_redo == null:
		_insert_clip_at(insert_index, new_clip)
		_ensure_clip_visible(insert_index)
		return insert_index

	editor_undo_redo.create_action("Add Clip")
	editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_index, new_clip)
	editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_index)
	editor_undo_redo.commit_action()
	_ensure_clip_visible(insert_index)

	return insert_index

func add_clip(audio_path: String = "") -> void:
	if _is_editing_blocked_by_playback(true):
		return

	var defaults := _build_new_clip_defaults(audio_path)
	var default_length := float(defaults["length"])
	var clip_name := str(defaults["name"])

	var total_subdivisions := float(_get_total_subdivisions())

	if total_subdivisions <= 0.0:
		return

	default_length = min(default_length, total_subdivisions)

	var insertion_context := pending_clip_insertion_context
	pending_clip_insertion_context = {}

	var new_track := 0
	var desired_start := _snap_timeline_position(float(insertion_context.get("playhead_position", playhead_position)))

	var context_selected_clip_index := int(insertion_context.get("selected_clip_index", selected_clip_index))
	if context_selected_clip_index >= 0 and context_selected_clip_index < clips.size():
		var selected_clip := clips[context_selected_clip_index]
		if selected_clip.has("track") and selected_clip.has("start") and selected_clip.has("length"):
			new_track = int(selected_clip["track"])
			desired_start = _snap_timeline_position(float(selected_clip["start"]) + float(selected_clip["length"]))
	elif bool(insertion_context.get("mouse_over_timeline", false)):
		new_track = clamp(int(insertion_context.get("mouse_track", 0)), 0, track_count - 1)

	var new_clip := _build_clip_data_at_position(audio_path, new_track, desired_start)
	if new_clip.is_empty():
		_show_blocked_action_feedback("No room to add a clip on this track.")
		return

	var insert_index := clips.size()

	if editor_undo_redo == null:
		_insert_clip_at(insert_index, new_clip)
		_ensure_clip_visible(insert_index)
		return

	editor_undo_redo.create_action("Add Clip")
	editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_index, new_clip)
	editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_index)
	editor_undo_redo.commit_action()
	_ensure_clip_visible(insert_index)

func duplicate_selected_clip() -> void:
	if _is_editing_blocked_by_playback(true):
		return
	var source_indices: Array[int] = []
	for clip_index in selected_clip_indices:
		if clip_index >= 0 and clip_index < clips.size():
			source_indices.append(clip_index)

	source_indices.sort()

	if source_indices.size() > 1:
		var group_min_start := INF
		var group_max_end := -INF
		var duplicated_clips: Array[Dictionary] = []

		for clip_index in source_indices:
			var source_clip := clips[clip_index]

			if not source_clip.has("track") or not source_clip.has("start") or not source_clip.has("length"):
				_show_blocked_action_feedback("Selected clip is invalid for duplication.")
				return

			var source_start := float(source_clip["start"])
			var source_length := float(source_clip["length"])
			var source_end := source_start + source_length

			group_min_start = min(group_min_start, source_start)
			group_max_end = max(group_max_end, source_end)

		var duplicated_group_start = max(_snap_timeline_position(group_max_end), group_max_end)
		var group_delta = duplicated_group_start - group_min_start
		var group_fit_found := false

		for _attempt in range(128):
			var next_group_delta = group_delta
			var group_can_fit := true

			for clip_index in source_indices:
				var source_clip := clips[clip_index]
				var duplicate_track := int(source_clip["track"])
				var duplicate_length := float(source_clip["length"])
				var preferred_start = float(source_clip["start"]) + group_delta
				var available_start := _find_available_start(duplicate_track, duplicate_length, preferred_start)

				if available_start < 0.0:
					_show_blocked_action_feedback("No room to duplicate this selection.")
					return

				if not is_equal_approx(available_start, preferred_start):
					group_can_fit = false

				next_group_delta = max(next_group_delta, available_start - float(source_clip["start"]))

			if group_can_fit:
				group_fit_found = true
				break

			if is_equal_approx(next_group_delta, group_delta):
				break

			group_delta = next_group_delta

		if not group_fit_found:
			_show_blocked_action_feedback("No room to duplicate this selection.")
			return

		for clip_index in source_indices:
			var source_clip := clips[clip_index]
			var duplicated_clip := source_clip.duplicate(true)
			duplicated_clip["start"] = float(source_clip["start"]) + group_delta
			duplicated_clip["name"] = "%s Copy" % str(source_clip.get("name", "Clip"))
			duplicated_clips.append(duplicated_clip)
		var insert_start_index := clips.size()
		var new_selection: Array[int] = []

		for i in range(duplicated_clips.size()):
			new_selection.append(insert_start_index + i)

		if editor_undo_redo == null:
			for i in range(duplicated_clips.size()):
				_insert_clip_at(insert_start_index + i, duplicated_clips[i])

			_set_selected_clip_indices(new_selection)
			_ensure_clip_visible(new_selection.back())
			return

		editor_undo_redo.create_action("Duplicate Clips")

		for i in range(duplicated_clips.size()):
			editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_start_index + i, duplicated_clips[i])

		for i in range(duplicated_clips.size() - 1, -1, -1):
			editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_start_index + i)

		editor_undo_redo.add_do_method(self, "_set_selected_clip_indices", new_selection)
		editor_undo_redo.commit_action()

		_ensure_clip_visible(new_selection.back())
		return

	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		_show_blocked_action_feedback("No clip selected to duplicate.")
		return

	var source_clip := clips[selected_clip_index]
	if not source_clip.has("track") or not source_clip.has("start") or not source_clip.has("length"):
		_show_blocked_action_feedback("Selected clip is invalid for duplication.")
		return


	var duplicated_clip := source_clip.duplicate(true)
	var source_start := float(source_clip["start"])
	var source_length := float(source_clip["length"])
	var desired_start := max(_snap_timeline_position(source_start + source_length), source_start + source_length)
	var duplicate_track := int(source_clip["track"])
	var duplicated_start := desired_start

	if not _can_place_clip_at(duplicate_track, -1, source_length, desired_start):
		duplicated_start = _find_available_start(duplicate_track, source_length, desired_start)

		if duplicated_start < 0.0:
			_show_blocked_action_feedback("No room to duplicate this clip on its track.")
			return

	duplicated_clip["start"] = duplicated_start
	duplicated_clip["name"] = "%s Copy" % str(source_clip.get("name", "Clip"))

	var insert_index := selected_clip_index + 1

	if editor_undo_redo == null:
		_insert_clip_at(insert_index, duplicated_clip)
		_ensure_clip_visible(selected_clip_index)
		return

	editor_undo_redo.create_action("Duplicate Clip")
	editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_index, duplicated_clip)
	editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_index)
	editor_undo_redo.commit_action()
	_ensure_clip_visible(selected_clip_index)

func copy_selected_clips() -> void:
	var source_indices: Array[int] = []

	for clip_index in selected_clip_indices:
		if clip_index >= 0 and clip_index < clips.size():
			source_indices.append(clip_index)

	source_indices.sort()
	clip_clipboard.clear()

	for clip_index in source_indices:
		clip_clipboard.append(clips[clip_index].duplicate(true))

	if clip_clipboard.is_empty():
		_show_blocked_action_feedback("No clips selected to copy.")
		return

	_set_action_feedback("Copied %d clip(s)." % clip_clipboard.size())

func cut_selected_clips() -> void:
	copy_selected_clips()

	if clip_clipboard.is_empty():
		return

	delete_selected_clip()

func paste_clipboard() -> void:
	if _is_editing_blocked_by_playback(true):
		return

	if clip_clipboard.is_empty():
		_show_blocked_action_feedback("Clipboard is empty.")
		return

	var clipboard_min_start := INF
	var clipboard_min_track := track_count
	var clipboard_max_track := -1
	var pasted_clips: Array[Dictionary] = []

	for clip in clip_clipboard:
		if not clip.has("track") or not clip.has("start") or not clip.has("length"):
			_show_blocked_action_feedback("Clipboard data is invalid.")
			return

		clipboard_min_start = min(clipboard_min_start, float(clip["start"]))
		var clip_track := int(clip["track"])
		clipboard_min_track = min(clipboard_min_track, clip_track)
		clipboard_max_track = max(clipboard_max_track, clip_track)
	var clipboard_track_count := (clipboard_max_track - clipboard_min_track) + 1
	if clipboard_track_count > track_count:
		_show_blocked_action_feedback("Not enough tracks to paste this selection.")
		return

	var target_top_track := clipboard_min_track
	var mouse_position := get_local_mouse_position()

	if _is_mouse_over_timeline_lanes(mouse_position):
		target_top_track = _y_to_track_index(mouse_position.y)

	var max_top_track := track_count - clipboard_track_count
	target_top_track = clamp(target_top_track, 0, max_top_track)

	var track_offset := target_top_track - clipboard_min_track

	var target_group_start := max(_snap_timeline_position(playhead_position), playhead_position)
	var group_delta = target_group_start - clipboard_min_start
	var group_fit_found := false

	for _attempt in range(128):
		var next_group_delta = group_delta
		var group_can_fit := true

		for clip in clip_clipboard:
			var duplicate_track := int(clip["track"]) + track_offset
			var duplicate_length := float(clip["length"])
			var preferred_start = float(clip["start"]) + group_delta
			var available_start := _find_available_start(duplicate_track, duplicate_length, preferred_start)

			if available_start < 0.0:
				_show_blocked_action_feedback("No room to paste this selection.")
				return

			if not is_equal_approx(available_start, preferred_start):
				group_can_fit = false

			next_group_delta = max(next_group_delta, available_start - float(clip["start"]))

		if group_can_fit:
			group_fit_found = true
			break

		if is_equal_approx(next_group_delta, group_delta):
			break

		group_delta = next_group_delta

	if not group_fit_found:
		_show_blocked_action_feedback("No room to paste this selection.")
		return

	for clip in clip_clipboard:
		var pasted_clip := clip.duplicate(true)
		pasted_clip["start"] = float(clip["start"]) + group_delta
		pasted_clip["track"] = int(clip["track"]) + track_offset
		pasted_clips.append(pasted_clip)

	var insert_start_index := clips.size()
	var new_selection: Array[int] = []

	for i in range(pasted_clips.size()):
		new_selection.append(insert_start_index + i)

	if editor_undo_redo == null:
		for i in range(pasted_clips.size()):
			_insert_clip_at(insert_start_index + i, pasted_clips[i])

		_set_selected_clip_indices(new_selection)
		_ensure_clip_visible(new_selection.back())
		return

	editor_undo_redo.create_action("Paste Clips")

	for i in range(pasted_clips.size()):
		editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_start_index + i, pasted_clips[i])

	for i in range(pasted_clips.size() - 1, -1, -1):
		editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_start_index + i)

	editor_undo_redo.add_do_method(self, "_set_selected_clip_indices", new_selection)
	editor_undo_redo.commit_action()

	_ensure_clip_visible(new_selection.back())

func delete_selected_clip() -> void:
	if _is_editing_blocked_by_playback(true):
		return

	var clip_indices: Array[int] = []
	for clip_index in selected_clip_indices:
		if clip_index >= 0 and clip_index < clips.size():
			clip_indices.append(clip_index)

	if clip_indices.is_empty():
		return

	clip_indices.sort()

	if editor_undo_redo == null:
		for i in range(clip_indices.size() - 1, -1, -1):
			_remove_clip_at(clip_indices[i])
		return

	editor_undo_redo.create_action("Delete Clips" if clip_indices.size() > 1 else "Delete Clip")
	for i in range(clip_indices.size() - 1, -1, -1):
		var clip_index := clip_indices[i]
		var clip_data := clips[clip_index].duplicate(true)
		editor_undo_redo.add_do_method(self, "_remove_clip_at", clip_index)
		editor_undo_redo.add_undo_method(self, "_insert_clip_at", clip_index, clip_data)
	editor_undo_redo.commit_action()

func _nudge_selected_clip(amount: float, use_snap: bool) -> void:
	if _is_editing_blocked_by_playback(true):
		return

	var clip_indices: Array[int] = []
	for clip_index in selected_clip_indices:
		if clip_index >= 0 and clip_index < clips.size():
			clip_indices.append(clip_index)

	if clip_indices.is_empty():
		return

	if selected_clip_index < 0 or not clip_indices.has(selected_clip_index):
		selected_clip_index = clip_indices.back()

	if clip_indices.size() > 1:
		var primary_clip := clips[selected_clip_index]
		if not primary_clip.has("start"):
			return

		var resolved_delta := amount
		if use_snap:
			var primary_start: float = primary_clip["start"]
			var resolved_primary_start := round(primary_start + amount)
			resolved_delta = resolved_primary_start - primary_start

		if is_equal_approx(resolved_delta, 0.0):
			_show_blocked_action_feedback("No room to nudge selection.")
			return

		for clip_index in clip_indices:
			var clip := clips[clip_index]
			if not clip.has("start") or not clip.has("length") or not clip.has("track"):
				return

			var track_index: int = clip["track"]
			var start: float = clip["start"]
			var length: float = clip["length"]
			var desired_start := start + resolved_delta

			var limits := _get_clip_start_limits(
				track_index,
				clip_index,
				length,
				desired_start,
				clip_indices
			)

			if not bool(limits["has_room"]):
				_show_blocked_action_feedback("No room to nudge selection.")
				return

			var resolved_start := clamp(
				desired_start,
				float(limits["min_start"]),
				float(limits["max_start"])
			)

			if not is_equal_approx(resolved_start, desired_start):
				_show_blocked_action_feedback("No room to nudge selection.")
				return

		var before_clips := {}
		for clip_index in clip_indices:
			before_clips[clip_index] = clips[clip_index].duplicate(true)

		for clip_index in clip_indices:
			var clip := clips[clip_index]
			clip["start"] = float(clip["start"]) + resolved_delta
			clips[clip_index] = clip

		var after_clips := {}
		for clip_index in clip_indices:
			after_clips[clip_index] = clips[clip_index].duplicate(true)

		_emit_sequence_changed()
		_emit_status_text()
		_emit_selected_clip_changed()
		queue_redraw()

		if editor_undo_redo != null:
			editor_undo_redo.create_action("Nudge Clips")
			for clip_index in clip_indices:
				editor_undo_redo.add_do_method(self, "_set_clip_data", clip_index, after_clips[clip_index])
				editor_undo_redo.add_undo_method(self, "_set_clip_data", clip_index, before_clips[clip_index])
			editor_undo_redo.add_do_method(self, "_set_selected_clip_indices", clip_indices)
			editor_undo_redo.add_undo_method(self, "_set_selected_clip_indices", clip_indices)
			editor_undo_redo.commit_action()

		return

	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index]
	if not clip.has("start") or not clip.has("length") or not clip.has("track"):
		return

	var track_index: int = clip["track"]
	var start: float = clip["start"]
	var length: float = clip["length"]
	var desired_start := start + amount

	if use_snap:
		desired_start = round(desired_start)

	var limits := _get_clip_start_limits(
		track_index,
		selected_clip_index,
		length,
		desired_start
	)

	if not bool(limits["has_room"]):
		_show_blocked_action_feedback("No room to nudge clip.")
		return

	var new_start := clamp(
		desired_start,
		float(limits["min_start"]),
		float(limits["max_start"])
	)

	if is_equal_approx(new_start, start):
		_show_blocked_action_feedback("No room to nudge clip.")
		return

	var before_clip := clip.duplicate(true)
	clip["start"] = new_start
	clips[selected_clip_index] = clip
	var after_clip := clip.duplicate(true)

	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

	if editor_undo_redo != null:
		editor_undo_redo.create_action("Nudge Clip")
		editor_undo_redo.add_do_method(self, "_set_clip_data", selected_clip_index, after_clip)
		editor_undo_redo.add_undo_method(self, "_set_clip_data", selected_clip_index, before_clip)
		editor_undo_redo.commit_action()

func set_selected_clip_name(value: String) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	clip["name"] = value
	_commit_selected_clip_change("Rename Clip", clip)

func set_selected_clip_track(value: int) -> void:
	if _is_editing_blocked_by_playback(true):
		return

	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	var target_track := clamp(value, 0, track_count - 1)
	var start: float = clip["start"]
	var length: float = clip["length"]
	var limits := _get_clip_start_limits(target_track, selected_clip_index, length, start)

	if not bool(limits["has_room"]):
		return

	clip["track"] = target_track
	clip["start"] = clamp(start, float(limits["min_start"]), float(limits["max_start"]))
	_commit_selected_clip_change("Change Clip Track", clip)

func set_selected_clip_start(value: float) -> void:
	if _is_editing_blocked_by_playback(true):
		return

	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)

	if not clip.has("length"):
		return

	var length: float = clip["length"]
	var track_index: int = clip["track"]
	var limits := _get_clip_start_limits(track_index, selected_clip_index, length, value)

	if not bool(limits["has_room"]):
		return

	clip["start"] = clamp(value, float(limits["min_start"]), float(limits["max_start"]))
	_commit_selected_clip_change("Change Clip Start", clip)

func set_selected_clip_length(value: float) -> void:
	if _is_editing_blocked_by_playback(true):
		return

	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)

	if not clip.has("start"):
		return

	var start: float = clip["start"]
	var track_index: int = clip["track"]
	var max_length := _get_effective_max_clip_length(selected_clip_index, clip)
	clip["length"] = clamp(value, min_clip_length, max_length)
	_commit_selected_clip_change("Change Clip Length", clip)

func set_selected_clip_audio_path(value: String) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	clip["audio_path"] = value.strip_edges()
	clip["length"] = clamp(
		float(clip.get("length", min_clip_length)),
		min_clip_length,
		_get_effective_max_clip_length(selected_clip_index, clip)
	)

	_commit_selected_clip_change("Set Clip Audio Source", clip)

func set_selected_clip_playback_speed(value: float) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	clip["playback_speed"] = max(0.001, value)
	clip["length"] = clamp(
		float(clip.get("length", min_clip_length)),
		min_clip_length,
		_get_effective_max_clip_length(selected_clip_index, clip)
	)

	_commit_selected_clip_change("Set Clip Playback Speed", clip)

func set_selected_clip_volume(value: float) -> void:
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	clip["volume"] = max(0.0, value)
	_commit_selected_clip_change("Set Clip Volume", clip)

func set_selected_clip_source_start_offset_seconds(value: float) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip := clips[selected_clip_index].duplicate(true)
	clip["source_start_offset_seconds"] = max(0.0, value)
	clip["length"] = clamp(
		float(clip.get("length", min_clip_length)),
		min_clip_length,
		_get_effective_max_clip_length(selected_clip_index, clip)
	)

	_commit_selected_clip_change("Set Clip Source Start Offset", clip)

func _commit_selected_clip_change(action_name: String, updated_clip: Dictionary) -> void:
	if selected_clip_index < 0 or selected_clip_index >= clips.size():
		return

	var clip_index := selected_clip_index
	var before_clip := clips[clip_index].duplicate(true)
	var after_clip := updated_clip.duplicate(true)

	if before_clip == after_clip:
		return

	if editor_undo_redo == null:
		_set_clip_data(clip_index, after_clip)
		return

	editor_undo_redo.create_action(action_name)
	editor_undo_redo.add_do_method(self, "_set_clip_data", clip_index, after_clip)
	editor_undo_redo.add_undo_method(self, "_set_clip_data", clip_index, before_clip)
	editor_undo_redo.commit_action()

func _set_clip_data(clip_index: int, clip_data: Dictionary) -> void:
	if clip_index < 0 or clip_index >= clips.size():
		return

	clips[clip_index] = clip_data.duplicate(true)
	selected_clip_index = clip_index
	selected_clip_indices = [selected_clip_index]
	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _insert_clip_at(clip_index: int, clip_data: Dictionary) -> void:
	clip_index = clamp(clip_index, 0, clips.size())
	clips.insert(clip_index, clip_data.duplicate(true))
	selected_clip_index = clip_index
	selected_clip_indices = [selected_clip_index]
	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()

func _remove_clip_at(clip_index: int) -> void:
	if clip_index < 0 or clip_index >= clips.size():
		return

	clips.remove_at(clip_index)
	selected_clip_indices.clear()
	selected_clip_index = -1
	hovered_clip_index = -1
	hovered_resize_clip_index = -1
	is_dragging_clip = false
	dragged_clip_index = -1
	drag_grab_offset = 0.0
	drag_start_mouse_position = Vector2.ZERO
	drag_original_clip_index = -1
	drag_original_clip_data = {}
	is_resizing_clip = false
	resized_clip_index = -1
	resize_grab_offset = 0.0
	resize_start_mouse_position = Vector2.ZERO
	resize_original_clip_index = -1
	resize_original_clip_data = {}

	_emit_sequence_changed()
	_emit_status_text()
	_emit_selected_clip_changed()
	queue_redraw()


#Track commands
func _add_track_internal() -> void:
	track_count += 1
	track_names.append(_create_default_track_name(track_count - 1))
	track_mutes.append(false)
	track_volumes.append(1.0)

func add_track() -> void:
	if _is_editing_blocked_by_playback(true):
		return

	_commit_track_state_change("Add Track", func() -> void:
		_add_track_internal()
	)

func _remove_track_internal(track_index: int) -> void:
	if track_count <= 1:
		return
	if track_index < 0 or track_index >= track_count:
		return

	var clip_indices_to_remove: Array[int] = []

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("track"):
			continue

		var clip_track := int(clip["track"])
		if clip_track == track_index:
			clip_indices_to_remove.append(i)

	for i in range(clip_indices_to_remove.size() - 1, -1, -1):
		clips.remove_at(clip_indices_to_remove[i])

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("track"):
			continue

		var clip_track := int(clip["track"])
		if clip_track > track_index:
			clip["track"] = clip_track - 1
			clips[i] = clip

	track_names.remove_at(track_index)
	track_mutes.remove_at(track_index)
	track_volumes.remove_at(track_index)
	track_count -= 1

func remove_track(track_index: int) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	_commit_track_state_change("Delete Track", func() -> void:
		_remove_track_internal(track_index)
	)

func _rename_track_internal(track_index: int, value: String) -> void:
	if track_index < 0 or track_index >= track_names.size():
		return

	var resolved_name := value.strip_edges()
	if track_names[track_index] == resolved_name:
		return

	track_names[track_index] = resolved_name

func rename_track(track_index: int, value: String) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	_commit_track_state_change("Rename Track", func() -> void:
		_rename_track_internal(track_index, value)
	)

func _move_track_internal(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= track_count:
		return
	if to_index < 0 or to_index >= track_count:
		return
	if from_index == to_index:
		return

	var moved_name := track_names[from_index]
	track_names.remove_at(from_index)
	track_names.insert(to_index, moved_name)

	var moved_mute := track_mutes[from_index]
	track_mutes.remove_at(from_index)
	track_mutes.insert(to_index, moved_mute)

	var moved_volume := track_volumes[from_index]
	track_volumes.remove_at(from_index)
	track_volumes.insert(to_index, moved_volume)

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("track"):
			continue

		var clip_track := int(clip["track"])
		if clip_track == from_index:
			clip["track"] = to_index
		elif from_index < to_index and clip_track > from_index and clip_track <= to_index:
			clip["track"] = clip_track - 1
		elif from_index > to_index and clip_track >= to_index and clip_track < from_index:
			clip["track"] = clip_track + 1

		clips[i] = clip

func move_track(from_index: int, to_index: int) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	_commit_track_state_change("Move Track", func() -> void:
		_move_track_internal(from_index, to_index)
	)

func _duplicate_track_internal(track_index: int) -> void:
	if track_index < 0 or track_index >= track_count:
		return

	var source_name := track_names[track_index]
	var duplicated_name := "%s Copy" % source_name
	var duplicated_mute := false
	var duplicated_volume := 1.0

	if track_index < track_mutes.size():
		duplicated_mute = track_mutes[track_index]
	if track_index < track_volumes.size():
		duplicated_volume = track_volumes[track_index]

	var insert_index := track_index + 1

	track_count += 1
	track_names.insert(insert_index, duplicated_name)
	track_mutes.insert(insert_index, duplicated_mute)
	track_volumes.insert(insert_index, duplicated_volume)

	var duplicated_clips: Array[Dictionary] = []

	for i in range(clips.size()):
		var clip := clips[i]
		if not clip.has("track"):
			continue

		var clip_track := int(clip["track"])
		if clip_track > track_index:
			clip["track"] = clip_track + 1
			clips[i] = clip
		elif clip_track == track_index:
			var duplicated_clip := clip.duplicate(true)
			duplicated_clip["track"] = insert_index
			duplicated_clips.append(duplicated_clip)

	for duplicated_clip in duplicated_clips:
		clips.append(duplicated_clip)

func duplicate_track(track_index: int) -> void:
	if _is_editing_blocked_by_playback(true):
		return
	_commit_track_state_change("Duplicate Track", func() -> void:
		_duplicate_track_internal(track_index)
	)


#Scroll helpers
func _get_scroll_container() -> ScrollContainer:
	var parent_node := get_parent()

	if parent_node is ScrollContainer:
		return parent_node as ScrollContainer

	return null

func _get_max_horizontal_scroll(scroll_container: ScrollContainer) -> float:
	return max(0.0, _get_total_width() - scroll_container.size.x)

func _set_horizontal_scroll(value: float) -> void:
	var scroll_container := _get_scroll_container()

	if scroll_container == null:
		return

	var max_scroll := _get_max_horizontal_scroll(scroll_container)
	scroll_container.scroll_horizontal = int(clamp(value, 0.0, max_scroll))

func _ensure_rect_visible_horizontally(rect: Rect2, margin: float = 0.0) -> void:
	var scroll_container := _get_scroll_container()

	if scroll_container == null:
		return

	var visible_left := float(scroll_container.scroll_horizontal)
	var visible_right := visible_left + scroll_container.size.x

	var target_scroll := visible_left

	if rect.position.x - margin < visible_left:
		target_scroll = rect.position.x - margin
	elif rect.end.x + margin > visible_right:
		target_scroll = rect.end.x + margin - scroll_container.size.x

	_set_horizontal_scroll(target_scroll)

func _ensure_clip_visible(clip_index: int) -> void:
	if clip_index < 0 or clip_index >= clips.size():
		return

	var clip := clips[clip_index]
	if not clip.has("track") or not clip.has("start") or not clip.has("length"):
		return

	var rect := _get_clip_rect(clip)
	_ensure_rect_visible_horizontally(rect, visible_scroll_margin)

func _auto_scroll_during_drag(mouse_position: Vector2, delta: float) -> void:
	var scroll_container := _get_scroll_container()

	if scroll_container == null:
		return

	var visible_left := float(scroll_container.scroll_horizontal)
	var visible_right := visible_left + scroll_container.size.x

	var scroll_direction := 0.0
	var strength := 0.0

	if mouse_position.x < visible_left + auto_scroll_edge_threshold:
		var distance_to_edge := (visible_left + auto_scroll_edge_threshold) - mouse_position.x
		strength = clamp(distance_to_edge / auto_scroll_edge_threshold, 0.0, 1.0)
		scroll_direction = -1.0
	elif mouse_position.x > visible_right - auto_scroll_edge_threshold:
		var distance_to_edge := mouse_position.x - (visible_right - auto_scroll_edge_threshold)
		strength = clamp(distance_to_edge / auto_scroll_edge_threshold, 0.0, 1.0)
		scroll_direction = 1.0

	if scroll_direction == 0.0:
		return

	var scroll_amount := auto_scroll_speed * 60.0 * delta
	scroll_amount *= lerp(0.35, 1.0, strength)

	_set_horizontal_scroll(visible_left + (scroll_amount * scroll_direction))


#Drop handling
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _is_editing_blocked_by_playback():
		return false
	if not _is_mouse_over_timeline_lanes(at_position):
		return false
	return not _extract_audio_paths_from_drop_data(data).is_empty()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var audio_paths := _extract_audio_paths_from_drop_data(data)
	if audio_paths.is_empty():
		return

	var target_track := _y_to_track_index(at_position.y)
	var next_start := _snap_timeline_position(_x_to_timeline(at_position.x))
	var dropped_clips: Array[Dictionary] = []

	for audio_path in audio_paths:
		var new_clip := _build_clip_data_at_position(audio_path, target_track, next_start)
		if new_clip.is_empty():
			continue

		dropped_clips.append(new_clip)
		next_start = _snap_timeline_position(float(new_clip["start"]) + float(new_clip["length"]))

	if dropped_clips.is_empty():
		_show_blocked_action_feedback("No room to add dropped audio on this track.")
		return

	var insert_start_index := clips.size()
	var new_selection: Array[int] = []
	for i in range(dropped_clips.size()):
		new_selection.append(insert_start_index + i)

	if editor_undo_redo == null:
		for i in range(dropped_clips.size()):
			_insert_clip_at(insert_start_index + i, dropped_clips[i])
		_set_selected_clip_indices(new_selection)
		_ensure_clip_visible(new_selection.back())
		return

	editor_undo_redo.create_action("Drop Audio Clips" if dropped_clips.size() > 1 else "Drop Audio Clip")
	for i in range(dropped_clips.size()):
		editor_undo_redo.add_do_method(self, "_insert_clip_at", insert_start_index + i, dropped_clips[i])
	for i in range(dropped_clips.size() - 1, -1, -1):
		editor_undo_redo.add_undo_method(self, "_remove_clip_at", insert_start_index + i)
	editor_undo_redo.add_do_method(self, "_set_selected_clip_indices", new_selection)
	editor_undo_redo.add_undo_method(self, "_clear_selection")
	editor_undo_redo.commit_action()
	_ensure_clip_visible(new_selection.back())


#Drawing
func _draw() -> void:
	_draw_background()
	_draw_header()
	_draw_track_lanes()
	_draw_track_names()
	_draw_vertical_grid()
	_draw_clips()
	_draw_bar_numbers()
	_draw_blocked_action_feedback()
	_draw_playhead()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)

func _draw_header() -> void:
	draw_rect(Rect2(0, 0, size.x, header_height), header_color, true)

	draw_line(
		Vector2(0, header_height),
		Vector2(size.x, header_height),
		header_separator_color,
		1.0
	)
	draw_line(
		Vector2(track_label_width, 0),
		Vector2(track_label_width, size.y),
		header_separator_color,
		1.0
	)

func _draw_track_lanes() -> void:
	for track_index in range(track_count):
		var y := _track_to_y(track_index)
		var color := lane_color_a if track_index % 2 == 0 else lane_color_b
		draw_rect(Rect2(0, y, size.x, lane_height), color, true)

		if get_track_muted(track_index):
			draw_rect(Rect2(0, y, size.x, lane_height), muted_lane_overlay_color, true)

		draw_line(
			Vector2(0, y + lane_height),
			Vector2(size.x, y + lane_height),
			Color(0.0, 0.0, 0.0, 0.35),
			1.0
		)

func _draw_vertical_grid() -> void:
	var total_subdivisions := _get_total_subdivisions()

	for i in range(total_subdivisions + 1):
		var x := track_label_width + (i * pixels_per_subdivision)
		var color := subdivision_line_color
		var width := 1.0

		if i % (beats_per_bar * subdivisions_per_beat) == 0:
			color = bar_line_color
			width = 2.0
		elif i % subdivisions_per_beat == 0:
			color = beat_line_color

		draw_line(
			Vector2(x, 0),
			Vector2(x, size.y),
			color,
			width
		)

func _draw_bar_numbers() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var bar_width := _get_bar_width()

	for bar_index in range(bars):
		var bar_number := str(bar_index + 1)
		var x := track_label_width + (bar_index * bar_width) + 6.0
		var y := header_height * 0.7

		draw_string(
			font,
			Vector2(x, y),
			bar_number,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			bar_number_color
		)

func _draw_track_names() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() - 2.0

	for track_index in range(track_count):
		var y := _track_to_y(track_index)
		var track_name := "Track %d" % [track_index + 1]
		if track_index < track_names.size():
			track_name = track_names[track_index]

		var track_text_color := bar_number_color
		if get_track_muted(track_index):
			track_text_color = muted_track_text_color

		var text_position := Vector2(
			8.0,
			y + (lane_height * 0.62)
		)

		draw_string(
			font,
			text_position,
			track_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			track_label_width - 16.0,
			font_size,
			track_text_color
		)

func _draw_blocked_action_feedback() -> void:
	if blocked_action_flash_time <= 0.0:
		return

	var strength := blocked_action_flash_time / blocked_action_flash_duration

	var fill_color := blocked_action_flash_fill_color
	fill_color.a *= strength

	var outline_color := blocked_action_flash_outline_color
	outline_color.a *= strength

	draw_rect(Rect2(Vector2.ZERO, size), fill_color, true)
	draw_rect(Rect2(Vector2.ZERO, size), outline_color, false, 2.0)

func _draw_playhead() -> void:
	var x := _timeline_to_x(playhead_position)

	draw_line(
		Vector2(x, 0),
		Vector2(x, size.y),
		playhead_line_color,
		playhead_line_width
	)

func _draw_clip_waveform(rect: Rect2, clip: Dictionary) -> void:
	if rect.size.x <= 8.0 or rect.size.y <= 8.0:
		return

	var audio_path := str(clip.get("audio_path", "")).strip_edges()
	if audio_path.is_empty():
		return

	var left := rect.position.x + 6.0
	var right := rect.end.x - 6.0
	var top := rect.position.y + clip_waveform_vertical_padding
	var bottom := rect.end.y - clip_waveform_vertical_padding

	if right <= left or bottom <= top:
		return

	var width := right - left
	var height := bottom - top
	var center_y := top + (height * 0.5)
	var bar_count := max(1, int(floor(width / clip_waveform_step)))
	var seed := abs(audio_path.hash())
	var phase_a := float(seed % 97) / 97.0 * TAU
	var phase_b := float(seed % 53) / 53.0 * TAU
	var phase_c := float(seed % 31) / 31.0 * TAU

	for i in range(bar_count + 1):
		var t := float(i) / float(bar_count)
		var wave_a := abs(sin((t * TAU * 5.0) + phase_a))
		var wave_b := abs(sin((t * TAU * 13.0) + phase_b))
		var wave_c := abs(sin((t * TAU * 29.0) + phase_c))
		var amplitude := clamp((wave_a * 0.55) + (wave_b * 0.30) + (wave_c * 0.15), 0.0, 1.0)
		var half_height := lerp(height * 0.08, height * 0.5, amplitude)
		var x := left + (float(i) * clip_waveform_step)

		draw_line(
			Vector2(x, center_y - half_height),
			Vector2(x, center_y + half_height),
			clip_waveform_color,
			2.0
		)

func _draw_clips() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()

	for i in range(clips.size()):
		var clip := clips[i]

		if not clip.has("track") or not clip.has("start") or not clip.has("length"):
			continue

		var track_index: int = clip["track"]
		var length: float = clip["length"]

		if track_index < 0 or track_index >= track_count:
			continue

		if length <= 0.0:
			continue

		var rect := _get_clip_rect(clip)

		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue

		var color: Color = _get_track_color(track_index)
		draw_rect(rect, color, true)

		if _clip_has_audio_source(clip):
			_draw_clip_waveform(rect, clip)

		if get_track_muted(track_index):
			draw_rect(rect, muted_clip_overlay_color, true)

		if selected_clip_indices.has(i):
			draw_rect(rect, selected_clip_overlay_color, true)
			draw_rect(rect, selected_clip_outline_color, false, 2.0)
		elif i == hovered_clip_index:
			draw_rect(rect, hovered_clip_overlay_color, true)
			draw_rect(rect, hovered_clip_outline_color, false, 2.0)
		else:
			draw_rect(rect, clip_outline_color, false, 1.0)

		if i == selected_clip_index or i == hovered_resize_clip_index or i == resized_clip_index:
			var handle_rect := _get_resize_handle_rect(clip)
			var handle_color := active_resize_handle_color if i == resized_clip_index or i == hovered_resize_clip_index else resize_handle_color
			draw_rect(handle_rect, handle_color, true)

		if clip.has("name"):
			var clip_name: String = str(clip["name"])
			var text_position := Vector2(
				rect.position.x + 6.0,
				rect.position.y + (rect.size.y * 0.62)
			)

			draw_string(
				font,
				text_position,
				clip_name,
				HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 10.0,
				font_size,
				clip_text_color
			)

func _update_hovered_clip(position: Vector2) -> void:
	var new_hovered_clip_index := _get_clip_index_at_position(position)

	if new_hovered_clip_index == hovered_clip_index:
		return

	hovered_clip_index = new_hovered_clip_index
	_update_cursor_shape()
	queue_redraw()

func _on_timeline_panel_mouse_exited():
	if is_dragging_clip or is_resizing_clip:
		return

	if hovered_clip_index != -1 or hovered_resize_clip_index != -1:
		hovered_clip_index = -1
		hovered_resize_clip_index = -1
		_update_cursor_shape()
		queue_redraw()
