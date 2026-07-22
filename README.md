# Audio Sequencer Tool for Godot

A Godot editor plugin for arranging audio clips on a musical timeline and playing authored sequences at runtime.

> **Development status:** Pre-release (`v0.1.0`)
>
> The core editor and runtime workflows are implemented, but the public API may still change before `v1.0.0`.

<img width="947" height="562" alt="image" src="https://github.com/user-attachments/assets/b5517567-e981-4025-954c-6dcc22cd362f" />

## Features

### Timeline editor

- Musical bar, beat, and subdivision-based timeline.
- Grid-assisted editing.
- Audio-backed clips with natural durations.
- Clip-start snapping with Shift-based micro-adjustment.
- Keyboard nudging and Shift-based micro-nudging.
- Single selection and multiselect.
- Clip copy, cut, paste, duplication, deletion, dragging, and right-edge resizing.
- Clips on the same track cannot overlap.
- Drag-and-drop audio files from Godot's FileSystem dock.
- Missing-audio warnings and audio-reimport length validation.
- Undo and redo support for editor operations.

### Clip properties

Each clip can store:

- Audio source path.
- Source start offset.
- Playback speed.
- Volume.
- Timeline start and length.

### Track controls

Tracks support:

- Unique names.
- Mute.
- Volume.
- Audio bus overrides.
- Adding, deleting, duplicating, renaming, and reordering.
- Drag-based reordering.
- Track-group membership.

### Track groups

- Tracks can belong to multiple groups.
- One group can be active at runtime.
- Groups can define an audio bus override.
- Editor preview can play all tracks or one selected group.
- Runtime group switching supports configurable fade duration and fade curves.
- Master-internal tracks remain controlled by the Master's internal-track allow-list.

### Editor preview

- Audio triggers when the playhead crosses a clip start.
- Playback does not automatically catch up to clips when starting in the middle.
- Explicit playhead seeking can start the active clip from the matching source offset.
- Preview respects track mute, track volume, clip volume, playback speed, source offset, track groups, and audio bus routing.
- Active preview audio follows live volume and routing changes.

### Runtime playback

The plugin provides two reusable custom runtime nodes:

- `SequencerMasterPlayer`
- `SequencerTrackPlayer`

`SequencerMasterPlayer` owns the authoritative song position, plays selected tracks internally, controls track groups, and synchronizes external TrackPlayers.

`SequencerTrackPlayer` plays one external track voice. It can live anywhere in a scene and does not need to be a child of the MasterPlayer.

Runtime features include:

- Play, pause, seek, autoplay, and looping.
- Internal multi-track playback.
- External one-track players.
- Runtime track-group switching and fades.
- Custom fade-in and fade-out curves.
- Per-TrackPlayer timing and pitch offsets.
- Random timing delay and pitch micro-variation.
- Runtime clip, playback, loop, group, fade, and TrackPlayer registration signals.
- Runtime track, clip, group, routing, and playback query helpers.

## Requirements

- Godot 4.6

The plugin has been tested with Godot 4.6. Other Godot 4.x versions may work, but they have not been tested.

## Installation

### Release ZIP

1. Download the latest release ZIP from the repository's **Releases** page.
2. Extract it into the root of your Godot project.
3. Open the project in Godot.
4. Open **Project → Project Settings → Plugins**.
5. Enable **Audio Sequencer Tool**.

### Manual installation

Copy the following directory into your Godot project:

```text
addons/sequencer_tool/
```

The final structure should be:

```text
your_project/
└─ addons/
   └─ sequencer_tool/
      ├─ plugin.cfg
      ├─ plugin.gd
      ├─ editor/
      ├─ runtime/
      └─ ui/
```

Then enable the plugin under **Project → Project Settings → Plugins**.

## Editor quick start

### Create a sequence

1. Enable the plugin.
2. Open the **Audio Sequencer** dock.
3. Press **New**.
4. Enter a title and choose the initial musical timing settings.
5. Press **Add Clip** and choose an audio file.
6. Add, rename, duplicate, or reorder tracks as needed.
7. Press **Save** and save the sequence as a `.res` or `.tres` resource.

### Add clips

Clips can be added in two ways:

- Press **Add Clip** or use **Ctrl+A**, then select an audio file.
- Drag a supported audio file from Godot's FileSystem dock onto the timeline.

New clips are placed on the track under the mouse cursor and begin at the current playhead position. Right-click the timeline to reposition the playhead before adding a clip.

The Add Clip dialog also includes a **No Audio** option for creating an empty clip.

### Edit clips

Select one clip to open its clip settings.

Available settings include:

- Name.
- Audio source.
- Source start offset.
- Playback speed.
- Volume.
- Track.
- Timeline start.
- Timeline length.

When no clips or multiple clips are selected, the dock returns to timeline settings.

### Snapping and micro-adjustment

Clip starts snap to the musical grid by default.

Hold **Shift** while dragging or nudging to temporarily use off-grid micro-adjustment.

## Shortcuts

The timeline must have keyboard focus for timeline shortcuts to work.

- **Space** — Play or pause the sequence.
- **Ctrl+A** — Open the Add Clip audio picker.
- **Delete** or **Backspace** — Delete the selected clip or clips.
- **Ctrl+C** — Copy the selected clip or clips.
- **Ctrl+X** — Cut the selected clip or clips.
- **Ctrl+V** — Paste copied clips.
- **Ctrl+D** — Duplicate the selected clip or clips.
- **Left Arrow** — Nudge the selected clip or clips left using the normal grid-aligned nudge.
- **Right Arrow** — Nudge the selected clip or clips right using the normal grid-aligned nudge.
- **Shift+Left Arrow** — Micro-nudge the selected clip or clips left.
- **Shift+Right Arrow** — Micro-nudge the selected clip or clips right.
- **Hold Shift while dragging** — Temporarily disable snapping for off-grid micro-adjustment.

Structural editing shortcuts, including Add Clip, delete, paste, duplicate, and nudging, are blocked while playback is running.

## Audio routing and effects

The sequencer routes audio through Godot's existing audio buses.

Routing is resolved in this order:

1. Runtime MasterPlayer track override.
2. Authored track bus override.
3. Active track-group bus override.
4. Sequence default bus.
5. Master or player fallback bus.

Track-specific routing takes priority over group routing.

Audio effects are configured in Godot's **Audio Bus editor**. The sequencer does not author, duplicate, install, or store effect chains.

To apply an effect to a sequencer track:

1. Create or select an audio bus in Godot's Audio Bus editor.
2. Add and configure the desired effects on that bus.
3. Select a track in the Audio Sequencer dock.
4. Assign the bus using the track's **Bus** option.

If an authored bus is renamed or deleted, the sequencer displays it as missing and playback falls back through the remaining routing priorities.

## Runtime quick start

### MasterPlayer setup

1. Add a `SequencerMasterPlayer` node to a scene.
2. Assign a saved `SequencerSequence` resource.
3. Choose the tracks that the MasterPlayer should play internally.
4. Enable autoplay if desired, or call `play()` from a script.

Example:

```gdscript
@onready var master = $SequencerMasterPlayer

func _ready() -> void:
	master.play()
```

The Master's internal track selection is an allow-list.

When no active group is selected, the MasterPlayer internally plays the selected internal tracks.

When a group is active, it internally plays only tracks that are included in both:

- the internal-track allow-list
- the active group's track membership

### External TrackPlayer setup

Use a `SequencerTrackPlayer` when a track voice should live on another scene object, such as a singer, instrument, or positional audio source.

1. Add a `SequencerTrackPlayer` to the scene object.
2. Assign its `master_path`.
3. Select one sequence track.
4. Configure volume, bus override, timing offset, pitch offset, or random variation as needed.

Example:

```gdscript
@onready var master = $"../MainAudio/SequencerMasterPlayer"
@onready var track_player = $SequencerTrackPlayer

func _ready() -> void:
	track_player.set_master(master)
	track_player.set_track_name("Lead Vocal")
```

A TrackPlayer represents one logical track voice. Use multiple TrackPlayers for stacked or doubled playback.

### Seeking

Normal playback and explicit seeking are handled separately.

```gdscript
master.seek_song_position(32.0)
```

By default, a seek stops active audio without starting a clip in the middle.

To explicitly start the clip under the new playhead position:

```gdscript
master.seek_song_position(32.0, true)
```

Second-based helpers are also available:

```gdscript
master.seek_song_position_seconds(12.5)
```

### Track groups

Switch the active group with:

```gdscript
master.set_active_track_group(&"Chorus")
```

Pass a fade duration for a one-off transition:

```gdscript
master.set_active_track_group(&"Chorus", 2.0)
```

Clear the active group with:

```gdscript
master.clear_active_track_group()
```

## Mute versus volume

Mute and volume intentionally behave differently.

### Mute

Mute is a hard playback gate:

- Muted tracks do not trigger new clip starts.
- Muting a track stops its active audio.
- Unmuting does not start a clip from the middle.
- Playback resumes when the playhead crosses a future clip start.

### Volume

Volume is a mix control:

- A track or clip at volume `0` can still trigger and continue running silently.
- Raising its volume later reveals the already-running audio.
- Use volume rather than mute for fade-in behavior.

## Saved resources

Sequences are saved as native Godot resources:

```text
.res
.tres
```

The recommended format is `.res`.

Sequence resources are intended to be authored through the Audio Sequencer dock rather than by manually editing their internal arrays in the normal Inspector.

## Documentation

The essential editor and runtime setup instructions are included in this README. More detailed guides and examples are planned for future releases.

## Reporting issues

When reporting a bug, include:

- Godot version.
- Plugin version or commit.
- Operating system.
- Steps to reproduce.
- Expected behavior.
- Actual behavior.
- Error messages or relevant editor output.
- A minimal reproduction project when possible.

Report issues at: https://github.com/isaact-dev/audio-sequencer-tool-for-godot/issues

## Trademark notice

Audio Sequencer Tool for Godot is an independent community project and is not affiliated with or endorsed by the Godot Foundation.

Godot is a trademark of the Godot Foundation.

## License

Godot Audio Sequencer Tool is available under the MIT License.
See [LICENSE](LICENSE).
