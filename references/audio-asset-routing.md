# Audio asset routing for narrated video

The full class-level procedure lives in `audio-asset-sourcing`. This reference records the pipeline-specific handoff:

1. After scene durations and word timestamps are validated, generate `sound-plan.json`.
2. Search Pixabay for BGM and SFX together when accessible; create three BGM candidates and a small SFX shortlist.
3. If Pixabay is blocked, use Openverse/Freesound/Mixkit or an approved local cache and record the actual source and license.
4. Place SFX from word timestamps for spoken events and cumulative scene boundaries for transitions.
5. Mix narration as the primary signal; duck BGM with narration as sidechain; keep SFX sparse and low gain.
6. Verify AAC output, duration, peak level, intelligibility, and playback in the target desktop player.

Default for the user's current channel: blue-professional visual system, 16:9, BGM ceiling 25%, usually one BGM and 6–9 SFX events for a 60–90 second knowledge video.
