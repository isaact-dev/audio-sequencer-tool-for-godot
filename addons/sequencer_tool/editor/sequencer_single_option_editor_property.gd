@tool
extends EditorProperty

var property_name: StringName = &""
var option_kind: StringName = &""
var include_empty_option: bool = false
var empty_option_label: String = "None"

var _option_button := OptionButton.new()
var _option_values: Array = []
var _is_updating: bool = false
var _last_options_signature: String = ""
var _last_sequence_instance_id: int = -2

func _init() -> void:
	add_child(_option_button)
	add_focusable(_option_button)
	_option_button.item_selected.connect(_on_option_selected)

	set_process(true)

func _process(_delta: float) -> void:
	if option_kind == &"track_group":
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
	if option_kind != &"track_group":
		return

	emit_changed(property_name, &"")


func _build_options_signature() -> String:
	var edited_object := get_edited_object()
	if edited_object == null:
		return ""

	match option_kind:
		&"audio_bus":
			var parts: Array[String] = []
			for bus_index in range(AudioServer.get_bus_count()):
				parts.append(AudioServer.get_bus_name(bus_index))
			return "audio_bus:%s" % ",".join(parts)

		&"track_group":
			var groups: Dictionary = {}

			var object_groups = edited_object.get("track_groups")
			if object_groups is Dictionary and not (object_groups as Dictionary).is_empty():
				groups = object_groups as Dictionary
			else:
				var sequence = edited_object.get("sequence")
				if sequence != null:
					var sequence_groups = sequence.get("track_groups")
					if sequence_groups is Dictionary:
						groups = sequence_groups as Dictionary

			var group_names: Array[String] = []
			for group_name in groups.keys():
				group_names.append(str(group_name))
			group_names.sort()

			var sequence_instance_id := _get_sequence_instance_id()

			return "track_group:%d:%s" % [
				sequence_instance_id,
				",".join(group_names)
			]

	return ""

func setup(target_property_name: StringName, target_option_kind: StringName, allow_empty: bool = false, empty_label: String = "None") -> void:
	property_name = target_property_name
	option_kind = target_option_kind
	include_empty_option = allow_empty
	empty_option_label = empty_label
	_update_property()

func _update_property() -> void:
	if property_name.is_empty():
		return

	var edited_object := get_edited_object()
	if edited_object == null:
		return

	var current_value := StringName(str(edited_object.get(property_name)))
	_rebuild_options(current_value)

func _rebuild_options(current_value: StringName) -> void:
	_is_updating = true
	_option_button.clear()
	_option_values.clear()

	if include_empty_option:
		_option_button.add_item(empty_option_label)
		_option_values.append(&"")

	match option_kind:
		&"audio_bus":
			_add_audio_bus_options()
		&"track_group":
			_add_track_group_options()

	if not current_value.is_empty() and not _option_values.has(current_value):
		_option_button.add_item(str(current_value))
		_option_values.append(current_value)

	var selected_index := 0
	for i in range(_option_values.size()):
		if StringName(str(_option_values[i])) == current_value:
			selected_index = i
			break

	if _option_button.item_count > 0:
		_option_button.select(selected_index)
	_last_options_signature = _build_options_signature()
	_last_sequence_instance_id = _get_sequence_instance_id()
	_is_updating = false

func _add_audio_bus_options() -> void:
	for bus_index in range(AudioServer.get_bus_count()):
		var bus_name := StringName(AudioServer.get_bus_name(bus_index))
		_option_button.add_item(str(bus_name))
		_option_values.append(bus_name)

	if _option_values.is_empty():
		_option_button.add_item("Master")
		_option_values.append(&"Master")

func _add_track_group_options() -> void:
	var edited_object := get_edited_object()
	if edited_object == null:
		return

	var group_names: Array[String] = []
	var groups: Dictionary = {}

	var object_groups = edited_object.get("track_groups")
	if object_groups is Dictionary and not (object_groups as Dictionary).is_empty():
		groups = object_groups as Dictionary
	else:
		var sequence = edited_object.get("sequence")
		if sequence != null:
			var sequence_groups = sequence.get("track_groups")
			if sequence_groups is Dictionary:
				groups = sequence_groups as Dictionary

	for group_name_value in groups.keys():
		group_names.append(str(group_name_value))

	group_names.sort()

	for group_name in group_names:
		var group_value := StringName(group_name)
		_option_button.add_item(group_name)
		_option_values.append(group_value)

func _on_option_selected(index: int) -> void:
	if _is_updating:
		return
	if property_name.is_empty():
		return
	if index < 0 or index >= _option_values.size():
		return

	emit_changed(property_name, _option_values[index])
