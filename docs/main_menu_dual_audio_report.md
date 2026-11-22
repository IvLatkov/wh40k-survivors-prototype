# Both background layers belong to Main Menu

Verified 22 November 2026 using Godot 4.6.3. Existing No-Te task: `4ba86118-6b7f-4fa9-afda-c4e59868fc0e`, Redesign Main Menu as a mission preparation hub. The user reopened that same task. This request explicitly supersedes the older task-description requirement to retain gameplay ambience. No new task was created. Current changes are uncommitted (commit SHA null).

## Configuration

| Main Menu child | Exact stream | Volume | Bus |
| --- | --- | ---: | --- |
| BackgroundMusic | `res://assets/audio/Background/Background foley.wav` | -26 dB, unchanged | Music |
| BackgroundAtmosphere | `res://assets/audio/Background/background_atmos.wav` | -34 dB | Music |

Both are ordinary non-positional AudioStreamPlayer nodes directly owned by Main Menu, with autoplay enabled. The actual existing filename is `background_atmos.wav`; the request's `bacground_atmos.wav` spelling does not exist. The asset was reused without renaming or editing it.

Both existing imported WAVs already have native forward looping across their entire length. Their import metadata, source audio, normalization settings and loop boundaries were left intact. There are no finished-to-play callbacks, global players, autoloads or scripted restart timers. Music is approximately 23.032 seconds long; atmosphere approximately 213.333 seconds. The atmosphere gain is configured 8 dB below the music; source loudness was not normalized or changed.

The gameplay scene's BackgroundAtmosphere node and resource reference were removed. The main gameplay script's background-only reward/pause hooks were also removed because their player no longer exists. Character Info, reward queues, Chapter choices, F10, natural boss spawning, Victory and death retain their normal gameplay behavior. No weapon/enemy SFX, audio buses, gameplay stats or balance were changed.

Page navigation leaves the two scene-owned players alone. Both keep their existing playback objects and continue advancing through Character Select, Map Select, Armory, Collection, Settings and return to the dashboard. Music volume/mute settings affect both through the existing Music bus. DEPLOY frees both players with Main Menu; gameplay creates neither track.

## Immediate DEPLOY cleanup fix

The focused regression opens a menu page and immediately uses the real DEPLOY signal. This exposed a pre-existing presentation coroutine attempting a second get_tree() after the scene had left the tree. The polish helper now keeps its initial tree reference, checks cancellation/tree membership between layout waits, and invalidates pending reveals on exit. Native and headless audio regression runs no longer report that runtime error. This changes transition teardown only, not the animation design or gameplay path.

## Files changed

- `scenes/ui/main_menu.tscn`: second autoplay Music-bus player at -34 dB; existing music configuration preserved.
- `scenes/main.tscn`: removed gameplay atmosphere node/resource.
- `scripts/systems/main.gd`: removed obsolete background-audio pause callbacks/connections.
- `scripts/ui/main_menu_polish.gd`: cancel layout-wait coroutine safely on scene exit.
- `tests/main_menu_test.gd`: two simultaneous menu layers, both loop boundaries, navigation continuity, both freed by DEPLOY and neither present in gameplay.
- `tests/background_music_test.gd`: updated ownership/loop/navigation/settings regression, retaining gameplay modal/reward/boss/Victory/death coverage with background tracks absent.
- `tests/run_ci_tests.gd`: added the existing background-audio test to the CI list, now nine suites.
- `docs/main_menu_dual_audio_report.md`: this report.

## Observed verification

- Headless `tests/background_music_test.gd`: 63 checks passed, exit 0, after the teardown fix.
- Native D3D12 `tests/background_music_test.gd`: 63 checks passed, exit 0.
- Final native and headless `tests/main_menu_test.gd`: 885 checks passed in each, exit 0.
- Final `godot --headless --path . --script tests/run_ci_tests.gd`: 9/9 suites passed, exit 0; includes the 885 menu checks and 63 background-audio checks.
- Both tracks auto-started, were simultaneously playing on Music with the expected gains, and each crossed its native loop boundary twice without replacing playback. Tests seek near the end to exercise the seams efficiently; they do not claim two complete natural 213-second atmosphere cycles were observed.
- Every menu page preserved exactly two players and both original advancing playbacks. Music mute/unmute did not stop playback. Production DEPLOY destroyed both players; later gameplay modals, queued rewards, F10/repeated boss requests, natural 10:00, Victory and death did not recreate either track.
- Native Godot editor/import and normal project startup completed; project startup still points to Main Menu. No physical editor F5 press is claimed.
- `git diff --check` passed. Scope audit found no audio-source/import metadata, bus-layout, project configuration, artwork, weapon/enemy sound or terrain changes.

These are observed engine playback/ownership checks, not a subjective listening judgment about mix or source seam quality. The optional `--full-background-loops` flag (also accepting the old `--full-atmosphere-loops` flag) can monitor two natural loops of both layers; that long mode was not used for these results. No commit or push was performed.

No-Te confirmed the existing task Done, saved the implementation report, and updated Mechanics, Animation and Design Choices, and Bugs in place. Current audio descriptions were reconciled; dated historical evidence and independent guide relationships were preserved. No new note or task was created.
