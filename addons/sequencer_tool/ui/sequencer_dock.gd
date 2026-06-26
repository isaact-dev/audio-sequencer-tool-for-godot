@tool
extends VBoxContainer

@onready var status_label = $StatusBar/StatusLabel
@onready var loop_check_box = $StatusBar/LoopCheckBox
@onready var timeline = $HSplitContainer/TimelineBox/TimelinePanel/ScrollContainer/TimelineControl
@onready var name_edit = $HSplitContainer/SettingsHost/ClipSettings/ClipNameEdit
@onready var track_spin = $HSplitContainer/SettingsHost/ClipSettings/ClipTrackSpin
@onready var timeline_settings: VBoxContainer = $HSplitContainer/SettingsHost/TimelineSettings
@onready var clip_settings: VBoxContainer = $HSplitContainer/SettingsHost/ClipSettings
@onready var start_spin = $HSplitContainer/SettingsHost/ClipSettings/ClipStartSpin
@onready var length_spin = $HSplitContainer/SettingsHost/ClipSettings/ClipLengthSpin
@onready var volume_spin = $HSplitContainer/SettingsHost/ClipSettings/ClipVolumeSpin
@onready var settings_host = $HSplitContainer/SettingsHost
@onready var bars_slider = $HSplitContainer/SettingsHost/TimelineSettings/Bars/BarsSlider
@onready var tracks_list = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/ScrollContainer/TracksList
@onready var track_add_button = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackToolbar/TrackAddButton
@onready var track_delete_button = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackToolbar/TrackDeleteButton
@onready var track_duplicate_button = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackToolbar/TrackDuplicateButton
@onready var track_move_down_button = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackToolbar/TrackMoveDownButton
@onready var track_move_up_button = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackToolbar/TrackMoveUpButton
@onready var tracks_scroll_container = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/ScrollContainer
@onready var track_header = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackHeader
@onready var name_legend = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackHeader/NameLegend
@onready var drag_legend_spacer = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackHeader/DragLegendSpacer
@onready var mute_legend = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackHeader/MuteLegend
@onready var volume_legend = $HSplitContainer/SettingsHost/TimelineSettings/Tracks/TrackHeader/VolumeLegend
@onready var delete_clip_button = $ToolBar/ButtonDeleteClip
@onready var add_clip_button = $ToolBar/ButtonAddClip
@onready var new_sequence_dialog = $NewSequenceDialog
@onready var new_bars_spin = $NewSequenceDialog/MarginContainer/VBoxContainer/NewBarsSpin
@onready var new_beats_spin = $NewSequenceDialog/MarginContainer/VBoxContainer/NewBeatsSpin
@onready var new_subdivisions_spin = $NewSequenceDialog/MarginContainer/VBoxContainer/NewSubdivisionsSpin
@onready var open_sequence_dialog = $OpenSequenceDialog
@onready var save_sequence_dialog = $SaveSequenceDialog
@onready var bpm_slider = $HSplitContainer/SettingsHost/TimelineSettings/BPM/BPMSlider
@onready var track_delete_confirm_dialog = $TrackDeleteConfirmDialog
@onready var title_label = $title
@onready var unsaved_changes_confirm_dialog = $UnsavedChangesConfirmDialog
@onready var sequence_title_textedit = $NewSequenceDialog/MarginContainer/VBoxContainer/SequenceTitle
@onready var sequence_title_edit = $HSplitContainer/SettingsHost/TimelineSettings/TitleEdit
@onready var source_edit = $HSplitContainer/SettingsHost/ClipSettings/ClipSourceRow/ClipSourceEdit
@onready var source_pick_button = $HSplitContainer/SettingsHost/ClipSettings/ClipSourceRow/ClipSourcePickButton
@onready var pick_audio_dialog = $PickAudioDialog
@onready var playback_speed_spin = $HSplitContainer/SettingsHost/ClipSettings/ClipPlaybackSpeedSpin
@onready var audio_preview_controller = $AudioPreviewController

var editor_undo_redo: EditorUndoRedoManager = null

var current_sequence_path: String = ""

var _updating_clip_settings_ui: bool = false

var pending_track_delete_index: int = -1
var pending_audio_pick_mode: String = ""

var has_unsaved_changes: bool = false
var pending_unsaved_action: String = ""
var sequence_title: String = "Untitled Sequence"

var pick_audio_no_audio_button: Button = null

var selected_track_index: int = -1
var dragged_track_index: int = -1
var track_row_panels: Array[PanelContainer] = []
var pending_drag_track_index: int = -1
var is_dragging_track_row: bool = false
var track_drag_start_global_position: Vector2 = Vector2.ZERO
var drag_hover_track_index: int = -1
var drag_insert_after: bool = false

const TRACK_ROW_HEIGHT := 28
const TRACK_ROW_SEPARATION := 3
const TRACK_DRAG_STRIP_WIDTH := 16
const TRACK_MUTE_WIDTH := 18
const TRACK_VOLUME_WIDTH := 34


#Lifecycle
func _ready() -> void:
	if timeline == null:
		push_error("TimelineControl not found in sequencer_dock.gd")
		return

	if editor_undo_redo != null:
		timeline.set_editor_undo_redo(editor_undo_redo)
	if audio_preview_controller != null:
		audio_preview_controller.set_timeline(timeline)

	status_label.text = timeline._build_status_text()

	delete_clip_button.disabled = true

	track_spin.min_value = 0
	track_spin.max_value = max(0, timeline.track_count - 1)
	track_spin.step = 1

	start_spin.min_value = 0.0
	start_spin.step = 0.1

	length_spin.min_value = timeline.min_clip_length
	length_spin.step = 0.1

	clip_settings.visible = false
	timeline_settings.visible = true

	loop_check_box.button_pressed = timeline.loop_enabled

	bars_slider.min_value = 1
	bars_slider.step = 1
	bars_slider.value = timeline.bars

	bpm_slider.min_value = 1
	bpm_slider.max_value = 300
	bpm_slider.step = 1
	bpm_slider.value = timeline.bpm

	_refresh_tracks_list(timeline.get_track_names())
	_clear_clip_settings_ui()
	new_bars_spin.min_value = 1
	new_bars_spin.step = 1
	new_bars_spin.rounded = true

	new_beats_spin.min_value = 1
	new_beats_spin.step = 1
	new_beats_spin.rounded = true

	new_subdivisions_spin.min_value = 1
	new_subdivisions_spin.step = 1
	new_subdivisions_spin.rounded = true

	new_sequence_dialog.get_ok_button().text = "Create"

	open_sequence_dialog.access = FileDialog.ACCESS_RESOURCES
	open_sequence_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_sequence_dialog.filters = PackedStringArray(["*.tres, *.res ; Sequencer Sequence Resource"])

	save_sequence_dialog.access = FileDialog.ACCESS_RESOURCES
	save_sequence_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_sequence_dialog.filters = PackedStringArray(["*.tres, *.res ; Sequencer Sequence Resource"])

	pick_audio_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio Files"])
	pick_audio_no_audio_button = pick_audio_dialog.add_button("No Audio", true, "NO_AUDIO")
	_refresh_save_dialog_suggested_file()
	_apply_track_header_layout()

	_update_title_text()
	_refresh_playback_locked_ui()
	unsaved_changes_confirm_dialog.add_button("Don't save",true,"DSAVE")

func set_editor_undo_redo(value: EditorUndoRedoManager) -> void:
	editor_undo_redo = value
	if timeline != null:
		timeline.set_editor_undo_redo(value)


#Clip settings UI
func _clear_clip_settings_ui() -> void:
	_updating_clip_settings_ui = true
	name_edit.text = ""
	source_edit.text = ""
	track_spin.value = track_spin.min_value
	start_spin.value = start_spin.min_value
	length_spin.value = length_spin.min_value
	volume_spin.value = 1.0
	playback_speed_spin.value = 1.0
	delete_clip_button.disabled = true
	_updating_clip_settings_ui = false

func _sync_clip_settings_ui(clip_index: int, clip_data: Dictionary) -> void:
	_updating_clip_settings_ui = true

	if clip_index < 0 or clip_data.is_empty():
		name_edit.text = ""
		source_edit.text = ""
		track_spin.value = track_spin.min_value
		start_spin.value = start_spin.min_value
		length_spin.value = length_spin.min_value
		playback_speed_spin.value = 1.0
		volume_spin.value = 1.0
	else:
		delete_clip_button.disabled = false
		var clip_length := float(clip_data.get("length", timeline.min_clip_length))
		var max_start := max(0.0, float(timeline.bars * timeline.beats_per_bar * timeline.subdivisions_per_beat) - clip_length)
		var clip_start := float(clip_data.get("start", 0.0))
		var max_length = timeline.get_clip_max_length(clip_index)
		var clip_playback_speed := float(clip_data.get("playback_speed", 1.0))
		var clip_volume := float(clip_data.get("volume", 1.0))
		var clip_name := str(clip_data.get("name", ""))
		var clip_audio_path := str(clip_data.get("audio_path", ""))

		if not name_edit.has_focus() and name_edit.text != clip_name:
			name_edit.text = clip_name
		if not source_edit.has_focus() and source_edit.text != clip_audio_path:
			source_edit.text = clip_audio_path

		var clip_track := int(clip_data.get("track", 0))

		if track_spin.value != clip_track:
			track_spin.value = clip_track

		start_spin.max_value = max_start
		if start_spin.value != clip_start:
			start_spin.value = clip_start

		length_spin.min_value = timeline.min_clip_length
		length_spin.max_value = max_length
		if length_spin.value != clip_length:
			length_spin.value = clip_length
		if playback_speed_spin.value != clip_playback_speed:
			playback_speed_spin.value = clip_playback_speed
		if volume_spin.value != clip_volume:
			volume_spin.value = clip_volume
	_updating_clip_settings_ui = false


#Timeline settings
func _sync_timeline_settings_ui() -> void:
	if bars_slider.value != timeline.bars:
		bars_slider.value = timeline.bars

	if bpm_slider.value != timeline.bpm:
		bpm_slider.value = timeline.bpm

	if loop_check_box.button_pressed != timeline.loop_enabled:
		loop_check_box.button_pressed = timeline.loop_enabled

func _refresh_playback_locked_ui() -> void:
	var playback_locked = timeline != null and timeline.is_playing

	add_clip_button.disabled = playback_locked
	delete_clip_button.disabled = playback_locked or timeline.selected_clip_indices.is_empty()

	name_edit.editable = not playback_locked
	source_edit.editable = not playback_locked
	source_pick_button.disabled = playback_locked
	playback_speed_spin.editable = not playback_locked
	track_spin.editable = not playback_locked
	start_spin.editable = not playback_locked
	length_spin.editable = not playback_locked

	volume_spin.editable = true

	_refresh_track_toolbar_buttons()

func _update_title_text() -> void:
	title_label.text = "Audio Sequencer * - "+str(sequence_title) if has_unsaved_changes else "Audio Sequencer - "+str(sequence_title)
	if sequence_title_edit != null and not sequence_title_edit.has_focus() and sequence_title_edit.text != sequence_title:
		sequence_title_edit.text = sequence_title

func _build_suggested_sequence_file_name() -> String:
	var file_name := sequence_title.strip_edges()
	if file_name.is_empty():
		file_name = "Untitled Sequence"
	file_name = file_name.replace(" ", "_")
	file_name = file_name.replace("/", "_")
	file_name = file_name.replace("\\", "_")
	file_name = file_name.replace(":", " -")
	file_name = file_name.replace("*", "_")
	file_name = file_name.replace("?", "")
	file_name = file_name.replace("\"", "'")
	file_name = file_name.replace("<", "(")
	file_name = file_name.replace(">", ")")
	file_name = file_name.replace("|", "-")
	file_name = file_name.to_lower()
	return "%s.res" % file_name

func _refresh_save_dialog_suggested_file() -> void:
	if save_sequence_dialog == null:
		return
	save_sequence_dialog.current_file = _build_suggested_sequence_file_name()

func _mark_sequence_dirty() -> void:
	if has_unsaved_changes:
		return

	has_unsaved_changes = true
	_update_title_text()

func _mark_sequence_clean() -> void:
	has_unsaved_changes = false
	_update_title_text()

func _apply_sequence_title(value: String) -> void:
	sequence_title = value
	_mark_sequence_dirty()
	_refresh_save_dialog_suggested_file()
	_update_title_text()


#File handling
func _request_new_sequence() -> void:
	new_bars_spin.value = timeline.bars
	new_beats_spin.value = timeline.beats_per_bar
	new_subdivisions_spin.value = timeline.subdivisions_per_beat
	sequence_title_textedit.text = "New Sequence"
	new_sequence_dialog.popup_centered()

func _request_open_sequence() -> void:
	open_sequence_dialog.popup_centered_ratio()

func _save_sequence_to_path(path: String) -> void:
	if timeline == null:
		push_error("Cannot save sequence because TimelineControl is missing.")
		return

	if not timeline.has_method("create_sequence_resource"):
		push_error("TimelineControl does not support SequencerSequence resource saving.")
		return

	var resolved_path := path
	if resolved_path.get_extension().is_empty():
		resolved_path += ".res"

	var sequence_resource = timeline.create_sequence_resource(sequence_title)
	var error := ResourceSaver.save(sequence_resource, resolved_path)

	if error != OK:
		push_error("Failed to save sequence resource: %s" % resolved_path)
		return

	current_sequence_path = resolved_path
	_mark_sequence_clean()

func _load_sequence_from_path(path: String) -> void:
	var loaded_resource := ResourceLoader.load(path)

	if loaded_resource == null:
		push_error("Failed to load sequence resource: %s" % path)
		return

	if not loaded_resource.has_method("to_dictionary"):
		push_error("Invalid sequence resource: %s" % path)
		return

	var sequence_data = loaded_resource.to_dictionary()

	timeline.load_sequence_data(sequence_data)
	sequence_title = str(sequence_data.get("title", "")).strip_edges()
	if sequence_title.is_empty():
		sequence_title = path.get_file().get_basename()

	_refresh_save_dialog_suggested_file()
	current_sequence_path = path
	_mark_sequence_clean()
	_sync_timeline_settings_ui()
	_update_title_text()


#Audio picker
func _cancel_pending_audio_pick_flow() -> void:
	pending_audio_pick_mode = ""

	if pick_audio_dialog != null and pick_audio_dialog.visible:
		pick_audio_dialog.hide()


#Track list UI
func _refresh_tracks_list(track_names: Array) -> void:
	for child in tracks_list.get_children():
		child.queue_free()

	track_row_panels.clear()

	for i in range(track_names.size()):
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_panel.custom_minimum_size.y = TRACK_ROW_HEIGHT
		row_panel.add_theme_stylebox_override("panel", _build_track_row_style(i == selected_track_index))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", TRACK_ROW_SEPARATION)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_panel.add_child(row)

		var row_name_edit := LineEdit.new()
		row_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_name_edit.custom_minimum_size = Vector2(52, 0)
		row_name_edit.text = str(track_names[i])
		row_name_edit.placeholder_text = "Track %d" % [i + 1]
		row_name_edit.editable = not timeline.is_playing
		row_name_edit.text_submitted.connect(_on_track_name_submitted.bind(i, row_name_edit))
		row_name_edit.focus_exited.connect(_on_track_name_focus_exited.bind(i, row_name_edit))
		row_name_edit.focus_entered.connect(_on_track_row_focus_entered.bind(i))

		var drag_strip := Control.new()
		drag_strip.custom_minimum_size = Vector2(TRACK_DRAG_STRIP_WIDTH, 0)
		drag_strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		drag_strip.mouse_filter = Control.MOUSE_FILTER_STOP
		drag_strip.gui_input.connect(_on_track_drag_strip_gui_input.bind(i))

		var mute_check_box := CheckBox.new()
		mute_check_box.custom_minimum_size = Vector2(TRACK_MUTE_WIDTH, 0)
		mute_check_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mute_check_box.button_pressed = timeline.get_track_muted(i)
		mute_check_box.focus_entered.connect(_on_track_row_focus_entered.bind(i))
		mute_check_box.toggled.connect(_on_track_mute_toggled.bind(i))

		var volume_edit := LineEdit.new()
		volume_edit.custom_minimum_size = Vector2(TRACK_VOLUME_WIDTH, 0)
		volume_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		volume_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		volume_edit.text = _format_track_volume_value(timeline.get_track_volume(i))
		volume_edit.focus_entered.connect(_on_track_row_focus_entered.bind(i))
		volume_edit.text_submitted.connect(_on_track_volume_edit_text_submitted.bind(i, volume_edit))
		volume_edit.focus_exited.connect(_on_track_volume_edit_focus_exited.bind(i, volume_edit))

		row.add_child(row_name_edit)
		row.add_child(drag_strip)
		row.add_child(mute_check_box)
		row.add_child(volume_edit)

		tracks_list.add_child(row_panel)
		track_row_panels.append(row_panel)

	_refresh_track_toolbar_buttons()
	_refresh_tracks_list_height()

func _refresh_tracks_list_height() -> void:
	var visible_rows := min(max(timeline.track_count, 1), 6)
	var row_height := 30
	var row_spacing := 4
	var target_height = (visible_rows * row_height) + (max(0, visible_rows - 1) * row_spacing)

	tracks_scroll_container.custom_minimum_size.y = target_height
	tracks_list.custom_minimum_size.y = 0

func _refresh_track_toolbar_buttons() -> void:
	var playback_locked = timeline != null and timeline.is_playing
	var has_selection = selected_track_index >= 0 and selected_track_index < timeline.track_count

	track_add_button.disabled = playback_locked
	track_delete_button.disabled = playback_locked or not has_selection or timeline.track_count <= 1
	track_duplicate_button.disabled = playback_locked or not has_selection
	track_move_up_button.disabled = playback_locked or not has_selection or selected_track_index <= 0
	track_move_down_button.disabled = playback_locked or not has_selection or selected_track_index >= timeline.track_count - 1

func _apply_track_header_layout() -> void:
	track_header.add_theme_constant_override("separation", TRACK_ROW_SEPARATION)

	name_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	drag_legend_spacer.custom_minimum_size = Vector2(TRACK_DRAG_STRIP_WIDTH, 0)
	drag_legend_spacer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	mute_legend.custom_minimum_size = Vector2(TRACK_MUTE_WIDTH, 0)
	mute_legend.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mute_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	volume_legend.custom_minimum_size = Vector2(TRACK_VOLUME_WIDTH, 0)
	volume_legend.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	volume_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _set_selected_track_index(value: int) -> void:
	if value < 0 or value >= timeline.track_count:
		selected_track_index = -1
	else:
		selected_track_index = value
	_refresh_track_row_selection_styles()
	_refresh_track_toolbar_buttons()

func _build_track_row_style(selected: bool, drag_target: bool = false, insert_after: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3

	if selected:
		style.bg_color = Color(0.24, 0.28, 0.36)
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)

	if drag_target:
		style.border_color = Color(0.82, 0.88, 1.0)
		if insert_after:
			style.border_width_bottom = 2
		else:
			style.border_width_top = 2

	return style

func _refresh_track_row_selection_styles() -> void:
	for i in range(track_row_panels.size()):
		var row_panel := track_row_panels[i]
		if row_panel == null or not is_instance_valid(row_panel):
			continue

		var is_selected := i == selected_track_index
		var is_drag_target := is_dragging_track_row and i == drag_hover_track_index

		row_panel.add_theme_stylebox_override(
			"panel",
			_build_track_row_style(is_selected, is_drag_target, drag_insert_after)
		)

func _node_or_descendant_has_focused_line_edit(node: Node) -> bool:
	if node is LineEdit and (node as LineEdit).has_focus():
		return true

	for child in node.get_children():
		if _node_or_descendant_has_focused_line_edit(child):
			return true

	return false


#Track row drag helpers
func _get_track_row_index_at_global_position(global_position: Vector2) -> int:
	for i in range(track_row_panels.size()):
		var row_panel := track_row_panels[i]
		if row_panel == null or not is_instance_valid(row_panel):
			continue
		if row_panel.get_global_rect().has_point(global_position):
			return i
	return -1

func _resolve_final_track_drop_index(source_index: int) -> int:
	if drag_hover_track_index < 0 or drag_hover_track_index >= timeline.track_count:
		return -1

	var target_index := drag_hover_track_index
	if drag_insert_after:
		target_index += 1

	if target_index > source_index:
		target_index -= 1

	target_index = clamp(target_index, 0, timeline.track_count - 1)
	return target_index

func _cancel_track_drag_state() -> void:
	pending_drag_track_index = -1
	dragged_track_index = -1
	drag_hover_track_index = -1
	drag_insert_after = false
	is_dragging_track_row = false
	_refresh_track_row_selection_styles()

func _on_track_drag_strip_gui_input(event: InputEvent, track_index: int) -> void:
	if timeline != null and timeline.is_playing:
		_cancel_track_drag_state()
		return
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton

		if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_button_event.pressed:
			_set_selected_track_index(track_index)
			pending_drag_track_index = track_index
			dragged_track_index = -1
			drag_hover_track_index = -1
			drag_insert_after = false
			is_dragging_track_row = false
			track_drag_start_global_position = mouse_button_event.global_position
			return

		if not is_dragging_track_row:
			pending_drag_track_index = -1
			dragged_track_index = -1
			drag_hover_track_index = -1
			drag_insert_after = false
			_refresh_track_row_selection_styles()
			return

		var source_index := dragged_track_index
		var final_target_index := _resolve_final_track_drop_index(source_index)

		pending_drag_track_index = -1
		dragged_track_index = -1
		drag_hover_track_index = -1
		drag_insert_after = false
		is_dragging_track_row = false

		if final_target_index != -1 and final_target_index != source_index:
			timeline.move_track(source_index, final_target_index)
			selected_track_index = final_target_index

		_refresh_track_row_selection_styles()
		_refresh_track_toolbar_buttons()
		return

	if event is InputEventMouseMotion:
		var mouse_motion_event := event as InputEventMouseMotion

		if pending_drag_track_index == -1:
			return
		if (mouse_motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return

		if not is_dragging_track_row:
			if mouse_motion_event.global_position.distance_to(track_drag_start_global_position) < 6.0:
				return

			is_dragging_track_row = true
			dragged_track_index = pending_drag_track_index
			drag_hover_track_index = pending_drag_track_index
			drag_insert_after = false

		var hovered_index := _get_track_row_index_at_global_position(mouse_motion_event.global_position)
		if hovered_index == -1:
			return

		var hovered_panel := track_row_panels[hovered_index]
		if hovered_panel == null or not is_instance_valid(hovered_panel):
			return

		var rect := hovered_panel.get_global_rect()
		var insert_after := mouse_motion_event.global_position.y >= (rect.position.y + rect.size.y * 0.5)

		if drag_hover_track_index != hovered_index or drag_insert_after != insert_after:
			drag_hover_track_index = hovered_index
			drag_insert_after = insert_after
			_refresh_track_row_selection_styles()


#Track edit helpers
func _format_track_volume_value(value: float) -> String:
	var text := "%.2f" % value
	return text

func _parse_track_volume_value(text: String) -> float:
	var parsed = text.strip_edges().replace(",", ".")
	if parsed.is_empty():
		return 1.0

	if not parsed.is_valid_float():
		return 1.0

	return clamp(float(parsed), 0.0, 3.0)

func _commit_track_volume_after_focus_change(track_index: int, line_edit: LineEdit) -> void:
	if line_edit == null or not is_instance_valid(line_edit):
		return

	var value := _parse_track_volume_value(line_edit.text)
	timeline.set_track_volume(track_index, value)
	line_edit.text = _format_track_volume_value(value)

func _commit_track_name_after_focus_change(track_index: int, line_edit: LineEdit) -> void:
	if line_edit == null or not is_instance_valid(line_edit):
		return
	timeline.rename_track(track_index, line_edit.text)

func _on_track_name_submitted(_text: String, track_index: int, line_edit: LineEdit) -> void:
	timeline.rename_track(track_index, line_edit.text)
	line_edit.release_focus()

func _on_track_name_focus_exited(track_index: int, line_edit: LineEdit) -> void:
	call_deferred("_commit_track_name_after_focus_change", track_index, line_edit)

func _on_track_volume_edit_text_submitted(_text: String, track_index: int, line_edit: LineEdit) -> void:
	var value := _parse_track_volume_value(line_edit.text)
	timeline.set_track_volume(track_index, value)
	line_edit.text = _format_track_volume_value(value)
	line_edit.release_focus()

func _on_track_volume_edit_focus_exited(track_index: int, line_edit: LineEdit) -> void:
	call_deferred("_commit_track_volume_after_focus_change", track_index, line_edit)


#Toolbar buttons
func _on_button_add_clip_pressed() -> void:
	if timeline != null and timeline.is_playing:
		if timeline.has_method("_is_editing_blocked_by_playback"):
			timeline._is_editing_blocked_by_playback(true)
		return
	timeline.prepare_next_clip_insertion_context()
	pending_audio_pick_mode = "add_clip"
	pick_audio_dialog.popup_centered_ratio()

func _on_button_delete_clip_pressed() -> void:
	timeline.delete_selected_clip()

func _on_button_new_pressed() -> void:
	if has_unsaved_changes:
		pending_unsaved_action = "new"
		unsaved_changes_confirm_dialog.popup_centered()
		return

	_request_new_sequence()

func _on_button_open_pressed() -> void:
	if has_unsaved_changes:
		pending_unsaved_action = "open"
		unsaved_changes_confirm_dialog.popup_centered()
		return

	_request_open_sequence()

func _on_button_save_pressed() -> void:
	if current_sequence_path.is_empty():
		_refresh_save_dialog_suggested_file()
		save_sequence_dialog.popup_centered_ratio()
		return
	_save_sequence_to_path(current_sequence_path)

func _on_button_save_as_pressed() -> void:
	_refresh_save_dialog_suggested_file()
	save_sequence_dialog.popup_centered_ratio()

func _on_button_play_pressed() -> void:
	timeline.play()

func _on_button_pause_pressed() -> void:
	timeline.pause()


#Timeline settings handlers
func _on_bars_slider_value_changed(value: float) -> void:
	var requested_bars := int(value)
	timeline.set_bars(requested_bars)

	if int(bars_slider.value) != timeline.bars:
		bars_slider.value = timeline.bars

func _on_bpm_slider_value_changed(value):
	timeline.set_bpm(value)

func _on_loop_check_box_toggled(toggled_on: bool) -> void:
	timeline.set_loop_enabled(toggled_on)

func _on_title_edit_text_submitted(new_text) -> void:
	sequence_title_edit.release_focus()

func _on_title_edit_focus_exited() -> void:
	var new_title = sequence_title_edit.text.strip_edges()
	if new_title.is_empty():
		new_title = "Untitled Sequence"

	if new_title == sequence_title:
		_update_title_text()
		return

	if editor_undo_redo == null:
		_apply_sequence_title(new_title)
		return

	var previous_title := sequence_title

	editor_undo_redo.create_action("Rename Sequence")
	editor_undo_redo.add_do_method(self, "_apply_sequence_title", new_title)
	editor_undo_redo.add_undo_method(self, "_apply_sequence_title", previous_title)
	editor_undo_redo.commit_action()


#Clip settings handlers
func _on_clip_name_edit_text_submitted(new_text: String) -> void:
	if _updating_clip_settings_ui:
		return

	timeline.set_selected_clip_name(new_text)
	name_edit.release_focus()

func _on_clip_name_edit_focus_exited() -> void:
	if _updating_clip_settings_ui:
		return

	timeline.set_selected_clip_name(name_edit.text)

func _on_clip_track_spin_value_changed(value: float) -> void:
	if _updating_clip_settings_ui:
		return
	timeline.set_selected_clip_track(int(value))

func _on_clip_start_spin_value_changed(value: float) -> void:
	if _updating_clip_settings_ui:
		return
	timeline.set_selected_clip_start(value)

func _on_clip_length_spin_value_changed(value: float) -> void:
	if _updating_clip_settings_ui:
		return
	timeline.set_selected_clip_length(value)

func _on_clip_close_button_pressed() -> void:
	timeline.clear_selected_clip()

func _on_clip_source_edit_text_submitted(new_text: String) -> void:
	if _updating_clip_settings_ui:
		return

	timeline.set_selected_clip_audio_path(new_text)
	source_edit.release_focus()

func _on_clip_source_edit_focus_exited() -> void:
	if _updating_clip_settings_ui:
		return

	timeline.set_selected_clip_audio_path(source_edit.text)

func _on_clip_source_pick_button_pressed() -> void:
	if timeline != null and timeline.is_playing:
		if timeline.has_method("_is_editing_blocked_by_playback"):
			timeline._is_editing_blocked_by_playback(true)
		return

	if timeline.selected_clip_index < 0:
		return

	pending_audio_pick_mode = "set_selected_clip_source"
	pick_audio_dialog.popup_centered_ratio()

func _on_clip_playback_speed_spin_value_changed(value: float) -> void:
	if _updating_clip_settings_ui:
		return
	timeline.set_selected_clip_playback_speed(value)

func _on_clip_volume_spin_value_changed(value: float) -> void:
	if _updating_clip_settings_ui:
		return
	timeline.set_selected_clip_volume(value)


#Track toolbar handlers
func _on_track_add_button_pressed() -> void:
	timeline.add_track()

func _on_track_delete_button_pressed() -> void:
	if selected_track_index < 0:
		return
	_on_track_delete_pressed(selected_track_index)

func _on_track_duplicate_button_pressed() -> void:
	if selected_track_index < 0:
		return
	timeline.duplicate_track(selected_track_index)
	_set_selected_track_index(min(selected_track_index + 1, timeline.track_count - 1))

func _on_track_move_up_button_pressed() -> void:
	if selected_track_index < 1:
		return
	timeline.move_track(selected_track_index, selected_track_index - 1)
	_set_selected_track_index(selected_track_index - 1)

func _on_track_move_down_button_pressed() -> void:
	if selected_track_index < 0 or selected_track_index >= timeline.track_count - 1:
		return
	timeline.move_track(selected_track_index, selected_track_index + 1)
	_set_selected_track_index(selected_track_index + 1)

func _on_track_delete_pressed(track_index: int) -> void:
	pending_track_delete_index = track_index
	track_delete_confirm_dialog.popup_centered()

func _on_track_move_up_pressed(track_index: int) -> void:
	timeline.move_track(track_index, track_index - 1)

func _on_track_move_down_pressed(track_index: int) -> void:
	timeline.move_track(track_index, track_index + 1)

func _on_track_mute_toggled(toggled_on: bool, track_index: int) -> void:
	timeline.set_track_muted(track_index, toggled_on)

func _on_track_row_focus_entered(track_index: int) -> void:
	_set_selected_track_index(track_index)


#Dialog handlers
func _on_new_sequence_dialog_confirmed() -> void:
	timeline.create_new_sequence(
		int(new_bars_spin.value),
		int(new_beats_spin.value),
		int(new_subdivisions_spin.value)
	)
	sequence_title = sequence_title_textedit.text.strip_edges()
	if sequence_title.is_empty():
		sequence_title = "Untitled Sequence"
	current_sequence_path = ""
	_refresh_save_dialog_suggested_file()
	_sync_timeline_settings_ui()
	_mark_sequence_clean()
	_update_title_text()

func _on_open_sequence_dialog_file_selected(path: String) -> void:
	_load_sequence_from_path(path)
	_update_title_text()

func _on_save_sequence_dialog_file_selected(path: String) -> void:
	_save_sequence_to_path(path)
	_update_title_text()
	if not pending_unsaved_action.is_empty():
		match pending_unsaved_action:
			"new":
				_request_new_sequence()
			"open":
				_request_open_sequence()

		pending_unsaved_action = ""

func _on_track_delete_confirm_dialog_confirmed() -> void:
	if pending_track_delete_index < 0:
		return

	timeline.remove_track(pending_track_delete_index)
	pending_track_delete_index = -1

func _on_track_delete_confirm_dialog_canceled() -> void:
	pending_track_delete_index = -1

func _on_unsaved_changes_confirm_dialog_confirmed() -> void:
	if current_sequence_path.is_empty():
		_refresh_save_dialog_suggested_file()
		save_sequence_dialog.popup_centered_ratio()
		return

	_save_sequence_to_path(current_sequence_path)

	match pending_unsaved_action:
		"new":
			_request_new_sequence()
		"open":
			_request_open_sequence()

	pending_unsaved_action = ""

func _on_unsaved_changes_confirm_dialog_custom_action(action: StringName) -> void:
	if action != "DSAVE":
		return
	unsaved_changes_confirm_dialog.hide()
	match pending_unsaved_action:
		"new":
			_request_new_sequence()
		"open":
			_request_open_sequence()

	pending_unsaved_action = ""

func _on_pick_audio_dialog_file_selected(path: String) -> void:
	match pending_audio_pick_mode:
		"add_clip":
			timeline.add_clip(path)

		"set_selected_clip_source":
			timeline.set_selected_clip_audio_path(path)

	pending_audio_pick_mode = ""

func _on_pick_audio_dialog_custom_action(action: StringName) -> void:
	if action != "NO_AUDIO":
		return

	pick_audio_dialog.hide()

	match pending_audio_pick_mode:
		"add_clip":
			timeline.add_clip()

		"set_selected_clip_source":
			timeline.set_selected_clip_audio_path("")

	pending_audio_pick_mode = ""

func _on_pick_audio_dialog_canceled() -> void:
	pending_audio_pick_mode = ""


#Timeline signal handlers
func _on_timeline_control_tracks_changed(track_names: Array) -> void:
	track_spin.max_value = max(0, timeline.track_count - 1)

	if selected_track_index >= timeline.track_count:
		selected_track_index = timeline.track_count - 1
	if timeline.track_count <= 0:
		selected_track_index = -1

	for child in tracks_list.get_children():
		if _node_or_descendant_has_focused_line_edit(child):
			_refresh_track_toolbar_buttons()
			_refresh_tracks_list_height()
			_refresh_track_row_selection_styles()
			return

	_refresh_tracks_list(track_names)
	_refresh_track_toolbar_buttons()

func _on_timeline_control_status_text_changed(text: String) -> void:
	status_label.text = text

func _on_timeline_control_selected_clip_changed(clip_index: int, clip_data: Dictionary) -> void:
	var single_clip_selected = timeline != null and timeline.selected_clip_indices.size() == 1

	if not single_clip_selected or clip_index < 0 or clip_data.is_empty():
		_clear_clip_settings_ui()
		delete_clip_button.disabled = timeline == null or timeline.selected_clip_indices.is_empty()
		timeline_settings.visible = true
		clip_settings.visible = false
		_refresh_playback_locked_ui()
		return

	_sync_clip_settings_ui(clip_index, clip_data)
	timeline_settings.visible = false
	clip_settings.visible = true
	_refresh_playback_locked_ui()

func _on_timeline_control_sequence_changed() -> void:
	_mark_sequence_dirty()
	_sync_timeline_settings_ui()

func _on_timeline_control_add_clip_requested() -> void:
	_on_button_add_clip_pressed()

func _on_timeline_control_playback_state_changed(is_playing_now: bool) -> void:
	if is_playing_now:
		_cancel_track_drag_state()
		_cancel_pending_audio_pick_flow()

	_refresh_playback_locked_ui()
	_refresh_tracks_list(timeline.get_track_names())
