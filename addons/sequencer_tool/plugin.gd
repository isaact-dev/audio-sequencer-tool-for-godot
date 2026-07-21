@tool
extends EditorPlugin
const SEQUENCER_MASTER_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_master_player.gd")
const SEQUENCER_TRACK_PLAYER_SCRIPT := preload("res://addons/sequencer_tool/runtime/sequencer_track_player.gd")
const SEQUENCER_MASTER_PLAYER_INSPECTOR_PLUGIN_SCRIPT := preload("res://addons/sequencer_tool/editor/sequencer_master_player_inspector_plugin.gd")
const SEQUENCER_TRACK_PLAYER_INSPECTOR_PLUGIN_SCRIPT := preload("res://addons/sequencer_tool/editor/sequencer_track_player_inspector_plugin.gd")

var dock
var dock_ui
var editor_file_system: EditorFileSystem = null
var master_player_inspector_plugin: EditorInspectorPlugin = null
var track_player_inspector_plugin: EditorInspectorPlugin = null
var editor_selection: EditorSelection = null

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
	editor_selection = get_editor_interface().get_selection()
	if (
		editor_selection != null
		and not editor_selection.selection_changed.is_connected(
			_on_editor_selection_changed
		)
	):
		editor_selection.selection_changed.connect(
			_on_editor_selection_changed
		)
	editor_file_system = get_editor_interface().get_resource_filesystem()
	if editor_file_system != null and not editor_file_system.filesystem_changed.is_connected(_on_editor_filesystem_changed):
		editor_file_system.filesystem_changed.connect(_on_editor_filesystem_changed)
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

	master_player_inspector_plugin = SEQUENCER_MASTER_PLAYER_INSPECTOR_PLUGIN_SCRIPT.new()
	track_player_inspector_plugin = SEQUENCER_TRACK_PLAYER_INSPECTOR_PLUGIN_SCRIPT.new()
	add_inspector_plugin(track_player_inspector_plugin)
	add_inspector_plugin(master_player_inspector_plugin)

func _exit_tree():
	if (
		editor_selection != null
		and editor_selection.selection_changed.is_connected(
			_on_editor_selection_changed
		)
	):
		editor_selection.selection_changed.disconnect(
			_on_editor_selection_changed
		)

	editor_selection = null
	remove_custom_type("SequencerTrackPlayer")
	remove_custom_type("SequencerMasterPlayer")
	if editor_file_system != null and editor_file_system.filesystem_changed.is_connected(_on_editor_filesystem_changed):
		editor_file_system.filesystem_changed.disconnect(_on_editor_filesystem_changed)
	editor_file_system = null
	if master_player_inspector_plugin != null:
		remove_inspector_plugin(master_player_inspector_plugin)
		master_player_inspector_plugin = null
	if track_player_inspector_plugin != null:
		remove_inspector_plugin(track_player_inspector_plugin)
		track_player_inspector_plugin = null
	if dock != null:
		remove_dock(dock)
		dock.free()

	dock = null
	dock_ui = null

func _get_sequence_from_master_node(master_node: Node) -> Resource:
	if master_node == null:
		return null

	if master_node.get_script() != SEQUENCER_MASTER_PLAYER_SCRIPT:
		return null

	var sequence = master_node.get("sequence")
	if sequence is Resource:
		return sequence as Resource

	return null

func _get_sequence_from_track_player_node(track_player: Node) -> Resource:
	if track_player == null:
		return null

	if track_player.get_script() != SEQUENCER_TRACK_PLAYER_SCRIPT:
		return null

	var master_path = track_player.get("master_path")
	if master_path is NodePath and not (master_path as NodePath).is_empty():
		var master_node := track_player.get_node_or_null(
			master_path as NodePath
		)
		var path_sequence := _get_sequence_from_master_node(master_node)
		if path_sequence != null:
			return path_sequence

	var connected_master = track_player.get("master")
	if connected_master is Node:
		return _get_sequence_from_master_node(connected_master as Node)

	return null

func _get_sequence_from_selected_node(selected_node: Node) -> Resource:
	if selected_node == null:
		return null

	if selected_node.get_script() == SEQUENCER_MASTER_PLAYER_SCRIPT:
		return _get_sequence_from_master_node(selected_node)

	if selected_node.get_script() == SEQUENCER_TRACK_PLAYER_SCRIPT:
		return _get_sequence_from_track_player_node(selected_node)

	return null

func _on_editor_selection_changed() -> void:
	if editor_selection == null:
		return

	if dock == null or dock_ui == null:
		return

	var selected_nodes := editor_selection.get_selected_nodes()
	if selected_nodes.size() != 1:
		return

	var selected_node := selected_nodes[0] as Node
	if selected_node == null:
		return

	var sequence_resource := _get_sequence_from_selected_node(
		selected_node
	)
	if sequence_resource == null:
		return

	if not dock_ui.has_method("open_sequence_resource"):
		return

	dock_ui.open_sequence_resource(sequence_resource)
	dock.make_visible()

func _on_editor_filesystem_changed() -> void:
	if dock_ui != null and dock_ui.has_method("revalidate_audio_clip_lengths_after_file_change"):
		dock_ui.revalidate_audio_clip_lengths_after_file_change()
