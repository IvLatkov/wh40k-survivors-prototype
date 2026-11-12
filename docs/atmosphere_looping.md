# Atmosphere loop diagnosis

## Current replacement

Gameplay now uses `res://assets/audio/Background/background_atmos.wav` in the
existing `Main/BackgroundAtmosphere` player. This is the actual filename on
disk; the requested `bacground_atmos.wav` spelling was not present. The older
WAV remains on disk but has no scene or gameplay-script reference.

The replacement is stereo 24-bit PCM at 44,100 Hz, with 9,408,000 sample frames
and duration 213.333333 seconds. Analysis found no exact-zero leading or
trailing padding and no sustained near-silent tail. Its first sample exceeds
-90 dBFS after approximately 0.023 ms; the trailing near-silent duration is
zero at thresholds from -90 to -50 dBFS. The old encoded fade described below
is absent. Neither source WAV was edited or normalized.

Import settings explicitly select native forward looping over the full source
(`edit/loop_mode=2`, begin 0, end -1). Autoplay, -30 dB atmosphere gain,
and the independent -26 dB music layer are unchanged.
Both background layers keep playing while level-up upgrade/chapter menus pause
gameplay, including an entire queue of rewards. `Main` temporarily gives these
players always-processing mode for that queue, without restarting playback.
After the final selection, normal inherited pause behavior returns. Character
Info, death, and Victory still pause both layers; terminal events override an
active reward queue.
No restart callback or additional player was added. Tests use the new path and
exercise two loop boundaries, modal pauses, F10, natural 10:00 spawning,
Victory, and reload.

Replacement SHA-256:
`85facc97add0dd8936859de13245aa925167efc5d9e3d2ac97b6cc043dfdec0c`.

## Previous source diagnosis (historical)

Source: `res://assets/audio/Background/Backround atmos.wav`.

`Main/BackgroundAtmosphere` is a single `AudioStreamPlayer` with autoplay enabled,
volume -30 dB, and inherited gameplay pause behavior. It has no script and no
`finished` restart connection. The separate background music remains at -26 dB.

The WAV import already uses native forward looping: import `edit/loop_mode=2`
produces `AudioStreamWAV.LOOP_FORWARD` (resource enum value 1). Loop begin is 0;
import loop end -1 resolves to sample 9,667,393, the final sample index. The
imported stream is stereo, 44,100 Hz, QOA, and 219.215283 seconds long. The source
contains 9,667,394 stereo sample frames at 16-bit PCM. No end padding or scripted
restart interval was found in the configured playback.

## Source fade and silence

Analysis of both PCM channels shows no meaningful leading silence. The first
100 ms has RMS around -26 dBFS. The final approximately 5.9 seconds contain an
encoded fade, descending from normal ambience into near silence:

| Source measurement | Trailing duration |
| --- | ---: |
| Both channels stay below -40 dBFS peak | 4.373 s |
| Both channels stay below -50 dBFS peak | 3.491 s |
| Both channels stay below -60 dBFS peak | 2.584 s |
| Both channels stay below -70 dBFS peak | 1.893 s |
| Both channels stay below -80 dBFS peak | 1.039 s |
| Both channels are exactly zero | 0.012 s |

These are source levels, before the additional -30 dB player attenuation.
The apparent silence at the seam is therefore present in the source, even
though the audio player continues playing. Native looping does not remove a
fade or silence encoded into the sample.

The source also contains a `smpl` entry with start 0 and end 9,407,999
(approximately 213.333 seconds), near the start of the fade. Its loop type is
1024, which Godot does not recognize as a supported embedded loop type. It was
not silently treated as an approved loop region: the full source loop remains
intact. Choosing a shorter loop region or preparing a seamless source can be
handled separately without confusing this with a script restart delay.

The original WAV is unchanged. SHA-256:
`540704a320cf40a43d3253b17fd657027396ffd6dae0494dbb87795c3f4befde`.

## Verification

The audio regression test checks native looping, absence of production
`finished` callbacks, both players and volumes, pause/resume, F10, natural 10:00
boss spawning, Victory, and scene reload. Its optional full-duration check runs
two whole ambience cycles without seeking, checks that the same playback stays
active, and rejects any `finished` signal:

```powershell
godot --headless --audio-driver WASAPI --path . --script tests/background_music_test.gd -- --full-atmosphere-loops
```

Verification is programmatic playback and source sample analysis; it does not
claim a subjective listening assessment of speaker output.

Results: both complete 219.215-second cycles passed on the Windows WASAPI audio
driver with the same active playback and zero `finished` signals. The full test
passed 8,024 checks, including the subsequent pause/boss/Victory/reload checks.
CI passed 6/6; some existing immediate-exit headless tests still reported audio
resource shutdown warnings. The dedicated full-loop test exited cleanly.

References: [Godot 4.6 WAV resource properties](https://docs.godotengine.org/en/4.6/classes/class_audiostreamwav.html),
[import loop-mode values](https://github.com/godotengine/godot/blob/4.6/editor/import/resource_importer_wav.cpp),
and [embedded loop-type handling](https://github.com/godotengine/godot/blob/4.6/scene/resources/audio_stream_wav.cpp).
