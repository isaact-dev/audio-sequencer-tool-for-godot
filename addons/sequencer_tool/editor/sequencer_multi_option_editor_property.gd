@tool
extends EditorProperty

var property_name: StringName = &""
var option_kind: StringName = &""

var _menu_button := MenuButton.new()
var _option_values: Array[int] = []
var _option_labels: Array[String] = []
var _is_updating: bool = false
var _last_options_signature: String = ""
var _last_sequence_instance_id: int = -2

func _init() -> void:
	add_child(_menu_button)
	add_focusable(_menu_button)

	var popup := _menu_button.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.id_pressed.connect(_on_popup_id_pressed)

	set_process(true)

func _process(_delta: float) -> void:
	var sequence_instance_id := _get_sequence_instance_id()
	if sequence_instance_id != _last_sequence_instance_id:
		_last_sequence_instance_id = sequence_instance_id
		_clear_value_for_sequence_change()
		_update_property()
		return

	var signature := _build_options_signature()
	if signature == _last_options_signature:
		return

	_last_options_signature = signature
	_update_property()


func _get_sequence_instance_id() -> int:
	var edited_object := get_edited_object()
	if edited_object == null:
		return -1

	var sequence = edited_object.get("sequence")
	if sequence == null:
		return -1

	return sequence.get_instance_id()


func _clear_value_for_sequence_change() -> void:
	if property_name.is_empty():
		return

	emit_changed(property_name, [])


func _build_options_signature() -> String:
	var edited_object := get_edited_object()
	if edited_object == null:
		return ""

	match option_kind:
		&"sequence_tracks":
			var sequence = edited_object.get("sequence")
			if sequence == null:
				return "sequence:null"

			var parts: Array[String] = []
			parts.append("sequence:%s" % str(sequence.get_instance_id()))
			parts.append("track_count:%d" % int(sequence.get("track_count")))

			var track_names = sequence.get("track_names")
			if track_names is Array:
				for track_name in track_names:
					parts.append(str(track_name))

			return "|".join(parts)

	return ""

func setup(target_property_name: StringName, target_option_kind: StringName) -> void:
	property_name = target_property_name
	option_kind = target_option_kind
	_update_property()

func _update_property() -> void:
	if property_name.is_empty():
		return

	var edited_object := get_edited_object()
	if edited_object == null:
		return

	_rebuild_options()

func _rebuild_options() -> void:
	_is_updating = true

	_option_values.clear()
	_option_labels.clear()

	match option_kind:
		&"sequence_tracks":
			_build_sequence_track_options()

	var popup := _menu_button.get_popup()
	popup.clear()

	var selected_indices := _get_selected_indices()

	for i in range(_option_values.size()):
		var track_index := _option_values[i]
		var label := _option_labels[i]
		popup.add_check_item(label, track_index)
		popup.set_item_checked(popup.get_item_index(track_index), selected_indices.has(track_index))

	_refresh_button_text(selected_indices)

	_menu_button.disabled = _option_values.is_empty()
	_last_options_signature = _build_options_signature()
	_last_sequence_instance_id = _get_sequence_instance_id()
	_is_updating = false

func _build_sequence_track_options() -> void:
	var edited_object := get_edited_object()
	if edited_object == null:
		return

	var sequence = edited_object.get("sequence")
	if sequence == null:
		return

	var track_count := int(sequence.get("track_count"))
	var track_names: Array = []

	var sequence_track_names = sequence.get("track_names")
	if sequence_track_names is Array:
		track_names = sequence_track_names

	for track_index in range(track_count):
		var track_label := "Track %d" % [track_index + 1]
		if track_index < track_names.size():
			track_label = str(track_names[track_index])

		_option_values.append(track_index)
		_option_labels.append(track_label)

func _get_selected_indices() -> Array:
	var result: Array[int] = []

	var edited_object := get_edited_object()
	if edited_object == null:
		return result

	var raw_value = edited_object.get(property_name)
	if raw_value is Array:
		for value in raw_value:
			var track_index := int(value)
			if not result.has(track_index):
				result.append(track_index)

	result.sort()
	return result

func _on_popup_id_pressed(option_id: int) -> void:
	if _is_updating:
		return

	var selected_indices := _get_selected_indices()

	if selected_indices.has(option_id):
		selected_indices.erase(option_id)
	else:
		selected_indices.append(option_id)

	selected_indices.sort()

	emit_changed(property_name, selected_indices)
	_rebuild_options()

func _refresh_button_text(selected_indices: Array[int]) -> void:
	if _option_values.is_empty():
		_menu_button.text = "Assign a sequence first"
		return

	if selected_indices.is_empty():
		_menu_button.text = "No tracks"
		return

	var selected_labels: Array[String] = []

	for i in range(_option_values.size()):
		var track_index := _option_values[i]
		if selected_indices.has(track_index):
			selected_labels.append(_option_labels[i])

	if selected_labels.size() <= 2:
		_menu_button.text = ", ".join(selected_labels)
	else:
		_menu_button.text = "%d tracks" % selected_labels.size()
