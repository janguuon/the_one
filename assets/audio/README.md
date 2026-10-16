# THE ONE M5 original audio

All `.wav` files in this folder were composed and synthesized specifically for
this project by the M5 implementation. They contain no recordings, samples,
melodies, or assets from EITR or any other game. The dark, sparse mood follows
the project's art direction rather than copying a soundtrack.

Source: [`tools/generate_audio.py`](../../tools/generate_audio.py), Python 3
standard library only, deterministic per named asset. Run it from the project
root to recreate all 32 files and `manifest.json`. Audio and synthesis source
are original project assets; no third-party sample license is required.

## Content

- Five stereo, 22,050 Hz, PCM16 music loops, each 16 seconds / eight bars at
  120 BPM. P1 uses stone and sparse low drums; P2 alternates fracture accents
  between channels; P3 uses a paired heartbeat; P4 answers its first strike with
  an audible echo; P5 removes drums and leaves low tone and synthesized breath.
- Five distinct weapon swings and five impacts. The double dagger sounds at
  both real active windows, not when its action starts.
- Separate preview, aim-lock, execution and echo warning sounds. Warning bands
  are higher than the music drone. Execution comes from actual damage events,
  and repeated overlapping frames cannot replay it.
- Four element pickups, dodge, hurt, transition, death, victory, weapon exchange,
  oath selection, menu movement and confirmation.

`scripts/audio_director.gd` never changes simulation or derives attack time from
audio duration. It reads combat ticks and the same hazard event records used by
damage. Static attacks are already locked when previewed and use one preview
chime; tracking attacks add a distinct lock click. Simultaneous identical danger
cues coalesce to one voice, preserving warning headroom.

## Mixing and pause

There are at most eight SFX voices. A warning can replace a decorative voice.
Every asset is at most −8 dBFS, warnings at most −15 dB, other sounds −18 dB and
the normalized music crossfade −14 dB. Even eight coincident maximum warning
samples plus music stay below 0.65 full scale at all volume sliders = 100%.
This is a mathematical PCM mixing bound, not a claim about loudspeaker quality.

Master, music and SFX sliders are independent; music and SFX each have a mute.
Reduced visual effects never disables important warning cues. Combat streams
pause during pause, oath choice, and hitstop, while menu feedback stays usable.
All warnings retain their visual equivalent so sound is never required to dodge.

The quit path awaits `AudioDirector.shutdown()` before freeing the scene. Godot
4.5 schedules stopped playback for audio-thread deletion and releases its final
references during a subsequent main-thread `AudioServer.update()`. A blocking
sleep immediately followed by quit prevents that cleanup. Shutdown stops and
unpauses streams, yields a latency-aware interval plus main frames, then releases
PCM resources; repeated shutdown cannot schedule another cue. See the engine's
[audio server implementation](https://github.com/godotengine/godot/blob/4.5-stable/servers/audio_server.cpp).

`tests/audio_tests.gd` verifies real PCM headers, decoded durations, hashes, peak
headroom, loop seams, identities, cue timing against all 15 pattern timelines,
weapon strike windows and pause/mute logic. Automated tests do not establish
human listening quality or the suitability of a particular headset.
Accelerated timeline tests inspect issued commands without scheduling minutes
of playback in one CPU frame. The lifecycle section uses real playback objects,
then asserts weak references to both the paused playback and its PCM resource
are gone before quitting. Native rendering runs use normal playback throughout.
