@tool
extends EditorInspectorPlugin

const SEQUENCER_MASTER_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_master_player.gd")
const SINGLE_OPTION_EDITOR := preload("res://addons/sequencer_tool/editor/sequencer_single_option_editor_property.gd")
const MULTI_OPTION_EDITOR := preload("res://addons/sequencer_tool/editor/sequencer_multi_option_editor_property.gd")


func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	if not object is Node:
		return false
	return (object as Node).get_script() == SEQUENCER_MASTER_PLAYER_SCRIPT


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	hint_type: PropertyHint,
	hint_string: String,
	usage_flags: int,
	wide: bool
) -> bool:
	match name:
		"default_audio_bus":
			var editor = SINGLE_OPTION_EDITOR.new()
			editor.setup(&"default_audio_bus", &"audio_bus", false)
			add_property_editor(name, editor, false, "Default Audio Bus")
			return true

		"initial_active_track_group":
			var editor = SINGLE_OPTION_EDITOR.new()
			editor.setup(&"initial_active_track_group", &"track_group", true, "None")
			add_property_editor(name, editor, false, "Initial Active Group")
			return true

		"internal_track_indices":
			var editor = MULTI_OPTION_EDITOR.new()
			editor.setup(&"internal_track_indices", &"sequence_tracks")
			add_property_editor(name, editor, false, "Internal Tracks")
			return true

	return false
