@tool
extends EditorPlugin
const SEQUENCER_MASTER_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_master_player.gd")
const SEQUENCER_TRACK_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_track_player.gd")

var dock
var dock_ui

func _enable_plugin():
	print("Godot Audio Sequencer Tool enabled")

func _disable_plugin():
	print("Godot Audio Sequencer Tool disabled")

func _get_editor_icon(icon_name: StringName) -> Texture2D:
	var base_control := get_editor_interface().get_base_control()
	var icon := base_control.get_theme_icon(icon_name, "EditorIcons")

	if icon != null:
		return icon

	return base_control.get_theme_icon("Node", "EditorIcons")

func _make_recolored_editor_icon(icon_name: StringName, color: Color) -> Texture2D:
	var source_icon := _get_editor_icon(icon_name)
	if source_icon == null:
		return null

	var image := source_icon.get_image()
	if image == null:
		return source_icon

	image.convert(Image.FORMAT_RGBA8)

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue

			image.set_pixel(x, y, Color(color.r, color.g, color.b, pixel.a * color.a))

	return ImageTexture.create_from_image(image)

func _enter_tree():
	dock_ui = preload("res://addons/sequencer_tool/ui/sequencer_dock.tscn").instantiate()

	dock = EditorDock.new()
	dock.add_child(dock_ui)

	dock.title = "Audio Sequencer"
	dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL

	dock_ui.set_editor_undo_redo(get_undo_redo())

	add_dock(dock)
	var master_player_icon := _make_recolored_editor_icon("AudioStreamPlayer", Color(1.0, 0.78, 0.22, 1.0))
	var track_player_icon := _make_recolored_editor_icon("AudioStreamPlayer", Color(1.0, 0.651, 0.306, 1.0))

	add_custom_type(
		"SequencerMasterPlayer",
		"Node",
		SEQUENCER_MASTER_PLAYER_SCRIPT,
		master_player_icon
	)

	add_custom_type(
		"SequencerTrackPlayer",
		"Node",
		SEQUENCER_TRACK_PLAYER_SCRIPT,
		track_player_icon
	)

func _exit_tree():
	remove_dock(dock)
	dock.free()
	dock = null
	dock_ui = null
	remove_custom_type("SequencerTrackPlayer")
	remove_custom_type("SequencerMasterPlayer")
