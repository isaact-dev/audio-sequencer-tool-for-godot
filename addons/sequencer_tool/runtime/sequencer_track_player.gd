extends Node

signal master_connected(master: Node)
signal master_disconnected(master: Node)
signal master_position_synced(previous_position: float, current_position: float)

@export var master_path: NodePath
@export var track_index: int = 0
@export var timing_offset_subdivisions: float = 0.0
@export var pitch_offset_semitones: float = 0.0
@export var volume: float = 1.0
@export var audio_bus_override: StringName = &""

var master: Node = null

func _ready() -> void:
	if not master_path.is_empty():
		var resolved_master := get_node_or_null(master_path)
		if resolved_master != null:
			connect_to_master(resolved_master)

func _exit_tree() -> void:
	disconnect_from_master()

func connect_to_master(value: Node) -> void:
	if master == value:
		return

	disconnect_from_master()

	master = value

	if master == null:
		return

	if master.has_method("register_track_player"):
		master.register_track_player(self)

func disconnect_from_master() -> void:
	if master == null:
		return

	var previous_master := master
	master = null

	if is_instance_valid(previous_master):
		if previous_master.has_method("unregister_track_player"):
			previous_master.unregister_track_player(self)

	master_disconnected.emit(previous_master)

func sync_from_master(previous_position: float, current_position: float) -> void:
	var local_previous_position := previous_position + timing_offset_subdivisions
	var local_current_position := current_position + timing_offset_subdivisions

	master_position_synced.emit(local_previous_position, local_current_position)

func get_pitch_scale_multiplier() -> float:
	return pow(2.0, pitch_offset_semitones / 12.0)

func get_effective_volume() -> float:
	return max(0.0, volume)

func resolve_audio_bus() -> StringName:
	if not audio_bus_override.is_empty():
		return audio_bus_override

	if master != null and master.has_method("resolve_track_bus"):
		return master.resolve_track_bus(track_index)

	return &"Master"
