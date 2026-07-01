@tool
extends EditorInspectorPlugin

const SEQUENCER_TRACK_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_track_player.gd")
const SINGLE_OPTION_EDITOR := preload("res://addons/sequencer_tool/editor/sequencer_single_option_editor_property.gd")


func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	if not object is Node:
		return false
	return (object as Node).get_script() == SEQUENCER_TRACK_PLAYER_SCRIPT


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
		"track_index":
			var editor = SINGLE_OPTION_EDITOR.new()
			editor.setup(&"track_index", &"sequence_track", false)
			add_property_editor(name, editor, false, "Track")
			return true

		"audio_bus_override":
			var editor = SINGLE_OPTION_EDITOR.new()
			editor.setup(&"audio_bus_override", &"audio_bus", true, "Use Master / Track Routing")
			add_property_editor(name, editor, false, "Bus Override")
			return true

	return false
