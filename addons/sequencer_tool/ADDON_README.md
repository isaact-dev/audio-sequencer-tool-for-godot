# Godot Audio Sequencer Tool

A reusable Godot editor plugin for arranging audio clips on a musical timeline and playing saved sequences at runtime.

## Installation

Copy this folder into the target Godot project so the final path is:

```text
addons/sequencer_tool/
```

Then:

1. Open the project in Godot.
2. Open **Project → Project Settings → Plugins**.
3. Enable **Audio Sequencer Tool**.
4. Open the **Audio Sequencer** dock.

## Quick start

1. Press **New** in the Audio Sequencer dock.
2. Configure the sequence timing.
3. Add tracks and audio clips.
4. Use the track settings to configure mute, volume, and audio bus routing.
5. Save the sequence as a `.res` or `.tres` resource.
6. Add a `SequencerMasterPlayer` to a runtime scene.
7. Assign the saved sequence and select its internal tracks.
8. Call `play()` or enable autoplay.

Use `SequencerTrackPlayer` for external one-track voices attached to other scene objects.

## Audio effects

Audio effects are configured through Godot's Audio Bus editor.

The sequencer routes audio through:

1. Runtime MasterPlayer track override.
2. Authored track bus override.
3. Active track-group bus override.
4. Sequence default bus.
5. Master or player fallback bus.

## Important playback behavior

- Clips trigger when the playhead crosses their start.
- Normal playback does not catch up to clips when starting in the middle.
- Explicit seeking can optionally start the active clip from the correct source offset.
- Mute is a hard trigger gate.
- Volume `0` allows audio to continue running silently.
- Unmuting a track does not start a clip from the middle.

## License

This addon is available under the MIT License.

See [LICENSE](LICENSE) in this folder.
