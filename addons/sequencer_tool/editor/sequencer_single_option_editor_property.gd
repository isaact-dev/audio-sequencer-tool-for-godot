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

func _get_current_property_value() -> Variant:
	var edited_object := get_edited_object()
	if edited_object == null or property_name.is_empty():
		return null

	return edited_object.get(property_name)

func _get_sequence_for_track_options() -> Resource:
	var edited_object := get_edited_object()
	if edited_object == null:
		return null

	var direct_sequence = edited_object.get("sequence")
	if direct_sequence is Resource:
		return direct_sequence

	if edited_object is Node:
		var node := edited_object as Node
		var master_path = edited_object.get("master_path")

		if master_path is NodePath and not (master_path as NodePath).is_empty():
			var master_node := node.get_node_or_null(master_path)
			if master_node != null:
				var master_sequence = master_node.get("sequence")
				if master_sequence is Resource:
					return master_sequence

	var master = edited_object.get("master")
	if master is Node:
		var master_sequence = (master as Node).get("sequence")
		if master_sequence is Resource:
			return master_sequence

	return null

func _clear_value_for_sequence_change() -> void:
	if property_name.is_empty():
		return
	match option_kind:
		&"track_group":
			emit_changed(property_name, &"")
		&"sequence_track":
			emit_changed(property_name, 0)

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
		&"sequence_track":
			var sequence := _get_sequence_for_track_options()
			if sequence == null:
				return "sequence_track:null"

			var parts: Array[String] = []
			parts.append("sequence:%s" % str(sequence.get_instance_id()))
			parts.append("track_count:%d" % int(sequence.get("track_count")))

			var track_names = sequence.get("track_names")
			if track_names is Array:
				for track_name in track_names:
					parts.append(str(track_name))

			return "|".join(parts)
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

	var current_value = _get_current_property_value()
	_rebuild_options(current_value)

func _rebuild_options(current_value: Variant) -> void:
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
		&"sequence_track":
			_add_sequence_track_options()

	if _option_values.is_empty():
		_option_button.add_item("No options")
		_option_values.append(current_value)

	var selected_index := 0
	for i in range(_option_values.size()):
		if _option_values[i] == current_value:
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

func _add_sequence_track_options() -> void:
	var edited_object := get_edited_object()
	if edited_object == null:
		return

	var sequence = _get_sequence_for_track_options()
	if sequence == null:
		_option_button.add_item("Assign master with sequence first")
		_option_values.append(0)
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

		_option_button.add_item(track_label)
		_option_values.append(track_index)

func _on_option_selected(index: int) -> void:
	if _is_updating:
		return
	if property_name.is_empty():
		return
	if index < 0 or index >= _option_values.size():
		return

	emit_changed(property_name, _option_values[index])
