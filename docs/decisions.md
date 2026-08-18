# Design Decisions

This file tracks design decisions for the Godot Audio Sequencer Tool.

---
## 2026-03-18 — Initial focus on UI

### Decision

The focus of the initial development will be on creating the UI.

### Reasoning

This tool is primarily an editor-facing workflow tool, so usability and interface structure are central to the project.
By building the UI first, it is easier to test if the logic and systems work correctly and if the tool is intuitive to use.

A visible interface also makes progress easier to evaluate and helps guide later implementation decisions.

## 2026-03-20 — Clip timing behavior

### Decision

Clips should not be treated as strictly grid-sized blocks.

### Reasoning

Clips will almost never line up with the music timeline. 
The start of a clip should initially snap on the timeline but should also be able to be moved without snapping for micro-adjustments.

The timeline should therefore support:
- musically aligned starting positions
- natural clip durations
- small timing offsets when needed

### Consequences

The fake clip system using dictionaries created on 2026-03-20 should be updated to allow clips that are not the exact length of musical intervals.

## 2026-03-20 — Centralize clip rectangle creation in a helper function

### Decision

Clip rectangle creation should be centralized in a helper function.

### Reasoning

Creating a helper function for centralizing clip rectangle creation to simplify future features such as:
- selection
- hover
- dragging
- resizing

All systems that depend on clip geometry will use the same calculation source

## 2026-03-20 — Clicking clips should prioritize selecting the top clip

### Decision

When detecting which clip was clicked, the clip array should be checked in reverse order so that the clip drawn last is prioritized.

### Reasoning

This matches the visual layers of the timeline. The clip that appears on top should be the one that gets selected.
Even if overlapping clips are not intended in the final version, this rule provides behavior for temporary overlaps, test data, or future edge cases.


## 2026-03-21 — Hover state should be tracked separately from selection state

### Decision

Hover state should be tracked separately from selection state so the timeline can distinguish between the currently selected clip and the clip currently under the cursor.
This way a clip can be selected whilst another is hovered over.

## 2026-03-21 — Clip dragging should preserve the mouse’s relative grab offset inside the clip

### Decision

Clip dragging should preserve the mouse’s relative grab offset inside the clip so the clip does not jump when dragging begins.
This is done by adding drag state variables.

## 2026-03-21 — Initially focus on horizontal dragging

### Decision

By focusing on horizontal dragging first, a lot of complications are avoided. 
It is important that the snapping and micro-adjustments in the horizontal direction are as user friendly as possible.
Track switching will be implemented later.

## 2026-03-26 — Dragging should use snap by default but allow a temporary snap override / adjustments should be possible with arrow keys

### Decision
Dragging should use snap by default but allow a temporary snap override so users can make quick off-grid micro-adjustments without changing the global snap setting.
This should be done by using the shift key as a hold hotkey.
Adjustments shoud also be able to be made using the arrow keys.
Microadjustments should also be able to be made with the arrow keys while holding shift.

For this to work, focus should be assigned to the correct control node to override default arrow key behaviour in the editor.

## 2026-03-26 — Initial UI status signals should be emitted after scene startup is complete

### Decision
Initial UI status signals should be emitted after scene startup is complete so parent dock elements are fully initialized before they react.
This is done by calling the first text change on ready deferred.

## 2026-03-28 — Scrolling should be handled in code instead of using ScrollContainer follow-focus

### Decision

The sequencer should not rely on `ScrollContainer` follow-focus behavior for timeline scrolling.

Scrolling should instead be handled explicitly in code for:
- clip dragging
- keyboard nudging
- keeping the selected clip visible during editing

### Reasoning

The current timeline is built as a custom-drawn `TimelineControl` where clips are rendered as rectangles inside a single control.
The clips are not separate child `Control` nodes, so built-in focus-follow does not work with this method.

## 2026-03-28 — Continuous drag scrolling should be frame-driven rather than mouse-motion-driven

### Decision

Continuous drag scrolling should be frame-driven rather than mouse-motion-driven so holding the cursor at the edge keeps the viewport moving.
This requires refactoring current code and adding a delta process function.

## 2026-03-28 — Clip length should have a minimum limit

### Decision

Clips should have a minimum allowed length so they are never resized to zero or a negative value.

### Reasoning

Without a lower limit, resizing could create clips that disappear visually, become impossible to select, or reach negative length states.


## 2026-03-28 — Settings panel switching should not change the main splitter layout

### Decision

The dock should use a stable left-side settings host inside the main `HSplitContainer`, and clip settings / timeline settings should switch inside that host rather than being shown or hidden as direct splitter children.

### Reasoning

Showing and hiding direct children of the splitter causes the split layout to recalculate and makes the dock width feel inconsistent.

## 2026-04-05 — Track management should be editor-driven with simple deterministic controls

### Decision

Track management in the timeline settings should support adding, deleting, renaming, and reordering tracks.
Reordering should use simple up/down controls.

### Reasoning

Track settings are part of the editor-facing workflow and should be directly manageable from the dock.
Adding, deleting, and renaming tracks are core editing actions, and reordering is useful.

Using up/down controls keeps the implementation coherent with the current timeline architecture and makes clip remapping during reorder easier to reason about.

## 2026-04-07 — Undo should be registered through EditorUndoRedoManager

### Decision

Undo for delete and move should be registered through EditorUndoRedoManager from the plugin layer instead of a custom function

## 2026-04-09 — Clip colors are derived exclusively from track colors

### Decision

Clip colors are derived exclusively from track colors. This eliminates per-clip color state, reducing save size, and enforcing a cleaner, deterministic visual model.

## 2026-04-12 — Clips on the same track should never overlap

### Decision

Clips on the same track should not be allowed to overlap.

This rule should apply consistently across all ways of editing clips, including:
- dragging
- resizing
- clip property edits from the dock
- clip creation
- clip duplication
- track reassignment

### Reasoning

Allowing overlapping clips on the same track creates ambiguous editing behavior.
Although top-most hit detection provides a fallback for overlapping clips, overlap should not be treated as a normal valid state for clips that share one track.

A non-overlap rule makes the timeline easier to read, simplifies selection behavior, and gives more predictable results for dragging, trimming, and property edits.

## 2026-04-13 — When clip creation or duplication fails because no valid open space exists, there should be feedback for this

### Decision

When clip creation or duplication fails because no valid open space exists, there should be feedback for this. This way it is clear to the user what is happening.

## 2026-04-14 — Deleting a track should remove all clips on that track

### Decision

Deleting a track should remove all clips on that track, with clip removal performed in reverse index order for safety.
Deleting a track should require an explicit confirmation because it is not undoable.

## 2026‑04‑16 — Insertion anchoring

### Decision

Clip creation should be based on an explicit insertion anchor instead of at the start of track 1.

### Insertion priority

1. Selected clip end
2. Playhead and mouse position
3. Start of timeline

## 2026‑04‑19 — Keep ctrl + A as add clip instead of select all

### Decision

The standard in godot for adding a new node is ctrl+A, making this the standard for new clip as well makes sense.
Currently, there are no plans to add select all.

## 2026‑04‑22 — Paste should align the clipboard group’s top-most clip to the hovered track

### Decision

Paste should align the clipboard group’s top-most clip to the hovered track.
It should clamp upward when needed so the full pasted group still fits vertically.

## 2026‑04‑22 — Commit clip name edits on submit/focus-exit instead of per-keystroke

### Decision

Commit clip name edits should be on submit/focus-exit instead of per-keystroke.
This way, dock-based renaming stays undoable without flooding the undo stack with every keystroke.

## 2026-04-24 — Clips should be audio-source references

### Decision
 
Clips should represent references to audio sources rather than merged or destructively edited audio data.
A clip should be able to store:
- source audio reference
- playback speed
- volume
- start offset

## 2026-04-24 — Clip creation should be possible in multiple ways

### Decision
 
Clip creation should be possible in multiple ways:
- create an empty clip, then assign an audio file in clip settings
- create a clip by choosing an audio file first
- drag-and-drop from Godot’s FileSystem dock

## 2026-04-24 — Sequence playback preview should trigger when the playhead crosses a clip start

### Decision
 
The sequencer should preview a clip’s audio when the playhead crosses that clip’s start position.
Playback should not trigger a clip just because playback begins in the middle of an already-started clip.

### Reasoning
 
This gives predictable sequencer-style preview behavior.
A clip should be triggered by crossing its start boundary. It should not catch up to clips whose start was already passed before playback began.

### Consequences
 
Playback logic should be based on start-crossing detection rather than only the current playhead position.

## 2026-04-24 — Track controls should be thoroughly implemented

### Decision
 
Tracks should support actual playback-related controls, not just naming and ordering.

Important settings are:
- mute
- volume
- timing interval offset
- pitch interval offset

### Reasoning
 
Tracks are not just visual lanes in an audio sequencer.
Basic mix and playback control at the track level is a core part of the editing workflow.
Timing and pitch interval offset on individual clips can make audio make sound less robotic
This is an important plus of working with a plugin like this as it can't easily be done by importing full audio files.

## 2026-04-26 — Preserve insertion intent before the audio picker opens

### Decision

Preserve insertion intent before the audio picker opens, but only resolve the clip’s final placement after the chosen audio file reveals the real clip length to avoid overlap.

## 2026-04-29 — Track list interaction and layout redesign

### Decision

The track list UI is redesigned around a selectable, draggable row model with a bottom track toolbar.

### Reasoning

The previous track list layout became too dense and hard to use once track-level controls were added directly into each row. Per-row move/delete controls took up too much horizontal space and the row layout scaled poorly in a narrow dock.

## 2026-05-09 — Split track-editing functions into public wrappers and internal mutators

### Decision

Split track-editing functions into:
- a public function that owns undo/redo integration
- an internal function that performs the actual data mutation
This split keeps the code easier to reason about.
The internal function stays focused on the actual track data change while the public function becomes the single place that adds the change in undo/redo behavior

## 2026-05-10 — Clip start preview triggering should use a very small positive epsilon offset

### Decision

Clip start preview triggering should use a very small positive epsilon offset instead of relying on exact start-boundary equality.
The preview trigger point is treated as:

clip_start + epsilon

A small epsilon should be used specifically to protect clip starts at timeline zero and similar boundary cases.

## 2026-05-10 — Audio preview triggering should support per-frame deduping

### Decision

Audio preview triggering should support per-frame deduping so the same clip cannot be previewed more than once in a single frame.
This deduping should be applied inside the audio preview runtime logic.

## 2026-05-11 — Track-based audio preview should be designed around audio bus routing

### Decision

Track-based audio preview should be designed around audio bus routing.
Preview players should not hardcode all playback directly to a single final output path.
Instead, the audio preview runtime should be able to resolve playback through track-specific bus routing later.

### Reasoning

Track effects and track-level audio processing are easier to support cleanly if playback is routed through buses instead of being treated as one flat output stream.
This keeps playback concerns in the audio preview runtime layer and avoids mixing runtime audio processing logic into timeline authoring code.

## 2026-05-15 — Seeking into clips should use audio offset, but mute should not catch up mid-clip

### Decision

When playback is explicitly repositioned into the middle of a clip, such as by dragging or seeking the playhead while playback is active, the clip should be able to start playback from the matching offset inside its source audio.

However, a track coming out of mute during playback should not cause clips that are currently under the playhead to start playing from the middle.
Muted tracks should resume clip triggering only when the playhead crosses a clip start after the track has been unmuted.

### Reasoning

Seeking the playhead is an explicit playback-position change.
In that case, it is expected that clips under the playhead can become audible from the correct source-audio offset so the preview reflects the current timeline position.

Mute is different.
Mute should behave as a playback gate for a track, not as a catch-up trigger for clips that were skipped while muted.

This matters for dynamic audio systems, especially short transient sounds such as drums.
If a drum track is muted and then unmuted while the playhead is in the middle of a drum hit, that hit should not suddenly start from the middle.
It should wait until the next clip start crossing.

For longer clips that need to fade in while already under the playhead, volume should be used instead of mute.
A track or clip can have volume set to 0 while still allowing the underlying playback timing to continue, so raising volume later can reveal the sound smoothly without creating a mid-hit retrigger.

## 2026-05-17 — Runtime playback should use explicit MasterPlayer and TrackPlayer nodes

### Decision

Runtime playback should be built around reusable custom nodes that users can add to their own scenes.

The main runtime nodes should be:

- `SequencerMasterPlayer`
- `SequencerTrackPlayer`

The `SequencerMasterPlayer` is responsible for the song-level playback state.
It controls the current song position, playback timing, track groups, and fading between track groups.
It also plays most tracks internally.

The `SequencerTrackPlayer` is responsible for playing one track or one track voice.
A `SequencerTrackPlayer` does not need to be a child of a `SequencerMasterPlayer`.
Instead, it should explicitly connect or sync to a `SequencerMasterPlayer`.

This allows `SequencerTrackPlayer` nodes to live throughout a game scene wherever they make sense.
For example, an instantiated singer scene can contain its own `SequencerTrackPlayer` and sync that player to a shared `SequencerMasterPlayer` elsewhere in the scene.

### Reasoning
A master player is needed because the song needs one authoritative playback position.
The master player should decide where in the song playback currently is and which track groups are currently active.
It should also own higher-level runtime behavior such as fading between track groups.

Track players should be separate nodes because track playback may need to happen from different scene objects.
This is especially important for track stacking and doubled performances.

For example, if two singers should perform the same track, each singer can have a `SequencerTrackPlayer`.
Both track players can sync to the same master player, but each one can apply small timing and pitch offsets.
This makes it possible to create a doubling effect without hiding the behavior inside one large playback node.

Requiring all track players to be children of the master player would make this less flexible.
It would force runtime audio structure to follow the master player's scene hierarchy instead of the game object's scene hierarchy.

## 2026-05-20 — Centralize runtime voice playback and treat runtime sequences as stable

### Decision

Runtime audio voice playback logic should be centralized in `SequencerAudioTrackVoice` instead of being duplicated separately in `SequencerTrackPlayer` and `SequencerMasterPlayer`.

`SequencerTrackPlayer` should own/delegate to one `SequencerAudioTrackVoice` for its external one-track voice playback.

`SequencerMasterPlayer` should also use `SequencerAudioTrackVoice` for internally played tracks from `internal_track_indices`, creating one voice per internally played track.
This keeps the clip-triggering, active-audio, stream-cache, volume, pitch, timing-offset, and bus-routing behavior in one reusable runtime component.
Runtime `SequencerSequence` data is assumed to be stable during gameplay. Sequence contents are configured before playback and are not expected to change while runtime playback is active.

## 2026-05-24 - Add separate playback advance from seek behavior to prevent unintended clip triggering

### Decision

Runtime playback should distinguish between normal playback advancement and explicit song position seeking.

- `sync_from_master()` is used for normal playback and should trigger clips only when their start is crossed.
- `seek_from_master()` is used for explicit position jumps and should not trigger crossed clip starts.

By default, seeking should stop audio and not start clips mid-play.

An optional mode allows seeking with `trigger_active_clip = true`, which starts the clip under the playhead from the correct offset.

## 2026-06-06 Use separate Curve resources for runtime track-group fade shapes

### Decision

Runtime track-group fades should use Godot `Curve` resources, not `Curve2D`.

Fade curves represent a normalized audio fade shape:

- x/time: `0.0` to `1.0`
- y/volume: `0.0` to `1.0`

Use separate curves for fade-in and fade-out:

- `fade_in_curve`
- `fade_out_curve`

This makes the curve behavior easier to reason about in an audio context. A fade-in curve directly describes how volume rises over time, and a fade-out curve directly describes how volume falls over time.

If either curve is `null`, runtime playback should fall back to a linear fade.

## 2026-06-27 — Do not add per-clip pitch offset

### Decision

Per-clip pitch offset will not be added as a clip property.
A clip-level pitch offset should not change the playback speed or timing of the clip.
If two identical clips are placed at the same timeline position and one is pitched differently, they should still stay aligned during playback.
Godot's normal `AudioStreamPlayer.pitch_scale` changes pitch and playback speed together, so using it for authored per-clip pitch offset would produce incorrect sequencer behavior.

Routing individual clips through audio buses is also not a good solution.
Track and group routing are important future systems, and clip-level bus routing would fight with track-level and group-level bus routing.

## 2026-06-27 — Audio changed / reimport length validation

### Decision
When the audio file for a clip changes, its length needs to be revalidated:
If audio becomes longer → keep clip length unchanged
If audio becomes shorter → shorten affected clips to the new max allowed length

## 2026-06-28 — Track group authoring should use a compact dock panel, not the left settings panel or a separate window

### Decision

Track group authoring should not be placed directly inside the left timeline settings panel, because that panel is already becoming too crowded.

Track group editing should also not use a separate operating-system-style window.  
Instead, group authoring should live inside the sequencer dock as a collapsible embedded panel opened from a `Groups` button in the top toolbar.

The group editor should use compact option-style controls:
- group selection should use an option picker / dropdown
- track membership should use a compact multi-select option-style control
- track membership selection should allow multiple tracks to be checked without the popup closing after every selection

A track can belong to multiple groups.  
Only one group is active at a time during runtime playback.

### Reasoning

Track groups are an important runtime arrangement feature, but they are not part of the basic timeline settings workflow.
Putting all group controls inside the left settings panel makes the main settings area too dense and competes with timeline, clip, and selected-track settings.

A separate floating window is also not ideal because it feels disconnected from the editor dock workflow.
The group editor should feel like part of the sequencer tool, not like a separate tool window.

## 2026-06-29 — Audio bus routing override priority

### Decision

Audio bus routing should resolve from the most specific override to the broadest fallback.

The priority order is:
1. Runtime/master track override
2. Authored track bus override
3. Active group bus override
4. Sequence default bus
5. Master/player fallback default bus

### Reasoning

A track-specific override should always win because it represents an explicit routing decision for that individual track.
A group bus override should apply only to tracks that do not have their own track override. This makes it possible to route a whole active group through shared processing, while still allowing individual tracks to use their own bus.

## 2026-07-01 — Master internal tracks act as an allow-list for group playback

### Decision

`SequencerMasterPlayer` should treat `internal_track_indices` as the master player's internal playback allow-list.
When no active track group is selected, the master internally plays the tracks listed in `internal_track_indices`.

When an active track group is selected, the master should only internally play tracks that are both:
- listed in `internal_track_indices`
- included in the active group's `track_indices`

The raw `internal_track_indices` inspector field is still not ideal UX. It should be hidden behind better editor UI, for example a named multiselect list of sequence tracks.

## 2026-07-04 — Track names should be unique

### Decision

Tracks should not be allowed to have duplicate names.
When a track is renamed to a name that already exists, the sequencer should automatically make it unique by appending a number.

Example:
- Bass
- Bass1
- Bass2

Track-name uniqueness should also be enforced during track-name refresh/normalization so unexpected external changes cannot leave duplicate names in the sequence.

## 2026-08-18 — TrackPlayers support runtime-controlled fade progress 

### Decision 

'SequencerTrackPlayer' should accept normalized runtime fade progress from gameplay systems such as distance. Increasing progress uses the MasterPlayer's fade_in_curve, while decreasing progress uses fade_out_curve. The value is runtime-only and should not be exported.