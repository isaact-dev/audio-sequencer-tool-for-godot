@tool
extends Resource
class_name SequencerSequence

const FORMAT_VERSION := 1

@export_storage var format_version: int = FORMAT_VERSION
@export_storage var title: String = "Untitled Sequence"

@export_storage var bars: int = 8
@export_storage var beats_per_bar: int = 4
@export_storage var subdivisions_per_beat: int = 4
@export_storage var bpm: float = 120.0

@export_storage var track_count: int = 4
@export_storage var track_names: Array[String] = []
@export_storage var track_mutes: Array[bool] = []
@export_storage var track_volumes: Array[float] = []

@export_storage var default_audio_bus: StringName = &"Master"
@export_storage var track_bus_overrides: Dictionary = {}
@export_storage var track_effect_chains: Dictionary = {}

@export_storage var track_groups: Dictionary = {}
@export_storage var clips: Array[Dictionary] = []

func get_total_subdivisions() -> int:
	return max(1, bars) * max(1, beats_per_bar) * max(1, subdivisions_per_beat)

func get_subdivisions_per_second() -> float:
	return (max(1.0, bpm) / 60.0) * float(max(1, subdivisions_per_beat))

func get_duration_seconds() -> float:
	var subdivisions_per_second := get_subdivisions_per_second()
	if subdivisions_per_second <= 0.0:
		return 0.0
	return float(get_total_subdivisions()) / subdivisions_per_second

func get_track_muted(track_index: int) -> bool:
	if track_index < 0 or track_index >= track_mutes.size():
		return false

	return track_mutes[track_index]

func get_track_volume(track_index: int) -> float:
	if track_index < 0 or track_index >= track_volumes.size():
		return 1.0

	return max(0.0, track_volumes[track_index])

func get_track_bus(track_index: int) -> StringName:
	if track_bus_overrides.has(track_index):
		var bus_name := StringName(str(track_bus_overrides[track_index]).strip_edges())
		if not bus_name.is_empty():
			return bus_name
	return default_audio_bus

func get_track_clips(track_index: int) -> Array:
	var result: Array[Dictionary] = []
	for clip_index in range(clips.size()):
		var clip := clips[clip_index]
		if int(clip.get("track", -1)) != track_index:
			continue
		var duplicated_clip := clip.duplicate(true)
		duplicated_clip["_sequence_clip_index"] = clip_index
		result.append(duplicated_clip)
	return result

func _get_sequence_clip_index(fallback_clip_index: int, clip: Dictionary) -> int:
	return int(clip.get("_sequence_clip_index", fallback_clip_index))

func load_from_dictionary(data: Dictionary) -> void:
	format_version = int(data.get("format_version", data.get("version", FORMAT_VERSION)))
	title = str(data.get("title", title)).strip_edges()
	if title.is_empty():
		title = "Untitled Sequence"

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

	_ensure_track_arrays_size()

	default_audio_bus = StringName(str(data.get("default_audio_bus", default_audio_bus)))
	track_bus_overrides = data.get("track_bus_overrides", {}).duplicate(true)
	track_effect_chains = data.get("track_effect_chains", {}).duplicate(true)
	track_groups = data.get("track_groups", {}).duplicate(true)

	clips.clear()
	var loaded_clips = data.get("clips", [])
	if loaded_clips is Array:
		for loaded_clip in loaded_clips:
			if not loaded_clip is Dictionary:
				continue

			var clip_track := clamp(int(loaded_clip.get("track", 0)), 0, track_count - 1)
			var clip_start := max(0.0, float(loaded_clip.get("start", 0.0)))
			var clip_length := max(0.0, float(loaded_clip.get("length", 0.0)))

			clips.append({
				"track": clip_track,
				"start": clip_start,
				"length": clip_length,
				"name": str(loaded_clip.get("name", "Clip")),
				"audio_path": str(loaded_clip.get("audio_path", "")),
				"source_start_offset_seconds": max(0.0, float(loaded_clip.get("source_start_offset_seconds", 0.0))),
				"playback_speed": max(0.001, float(loaded_clip.get("playback_speed", 1.0))),
				"volume": max(0.0, float(loaded_clip.get("volume", 1.0)))
			})

func to_dictionary() -> Dictionary:
	var serialized_clips: Array[Dictionary] = []

	for clip in clips:
		serialized_clips.append(clip.duplicate(true))

	return {
		"format_version": FORMAT_VERSION,
		"title": title,
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

func _ensure_track_arrays_size() -> void:
	while track_names.size() < track_count:
		track_names.append("Track %d" % [track_names.size() + 1])

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
