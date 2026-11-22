# Main Menu polish and animation

Verified 22 November 2026 with Godot 4.6.3. Existing No-Te task: `4ba86118-6b7f-4fa9-afda-c4e59868fc0e`, Redesign Main Menu as a mission preparation hub. The user reopened the same task for this extension; no duplicate task was created. This extension is uncommitted (commit SHA null). Earlier Collection/summary work is committed as `3a0975b`.

## Presentation

| Effect | Settings |
| --- | --- |
| Background | Sine color pulse between the existing near-black color and a slightly brighter blue-black; 3 seconds each direction, 6-second loop |
| DEPLOY idle emphasis | Normal and keyboard-focus borders pulse gently over 2.4 seconds each direction; 4.8-second loop |
| Hover and keyboard focus | 0.12-second glow fade; 6-pixel shadow radius / 0.22 alpha for DEPLOY, weaker 3-pixel / 0.12 alpha for secondary buttons |
| Portraits | Dashboard and Character Select image move from 0 to -2 pixels and back, 1.6 seconds each direction; positions rounded to whole pixels, nearest filtering, no scaling |
| Page transitions | Incoming page fades from 0.72 to 1 alpha while sliding 10 pixels into its container position; 0.18-second cubic ease-out after two layout frames |

The initial dashboard is immediately visible; there is no startup fade or loading delay. All five submenus and Back/Escape returns share the transition. New requests cancel the previous reveal and restore its opacity and position. A generation check invalidates pending layout waits. Resizing cancels the slide and lets the existing containers lay out the page. No navigation input lock or queued navigation sequence was introduced.

Portrait images sit inside fixed 140-pixel layout slots. Only their image children move, so character text and neighboring controls remain stable. The shared selection-card scene retains its existing portrait API and also reserves a slot for the static map preview. Button hit targets and scale remain unchanged. DEPLOY stays the primary label and strongest action. Currency, mission details and stats have no continuous animation.

`MainMenuPolish` is a scene-owned presentation helper. It finds buttons once during setup, duplicates their style resources locally, connects hover/focus events and starts four looping tweens. It has no `_process`, physics loop, per-frame scene scan, custom shader, particles, new textures, autoload or gameplay dependency. Short hover tweens replace previous tweens per button; only one reveal can be active. The helper's Inspector `enabled` switch can disable polish before startup, including for the static benchmark comparison. It is not a new in-game Settings option.

## Audio

Repository audio inspection found only `Background foley.wav` and `background_atmos.wav` under `assets/audio`. Neither is a suitable short UI click or hover sound. Both UI sounds were skipped; no assets were generated, downloaded, trimmed or repurposed. The optional extra menu ambience was also skipped, retaining the existing separation between menu music and gameplay atmosphere.

The menu retains exactly one native-loop music player at -26 dB on Music. DEPLOY unloads that player and the polish helper, then the existing gameplay ambience starts at -30 dB. No audio scenes, import metadata, gameplay sound settings or source files changed.

## Files

- `scenes/ui/main_menu.tscn`: presentation helper node and fixed dashboard portrait slot.
- `scenes/ui/selection_card.tscn`: fixed portrait slot while preserving the existing texture reference/API.
- `scripts/ui/main_menu.gd`: initialize polish, reveal changed pages and cancel slides before relayout.
- `scripts/ui/main_menu_polish.gd` and `.uid`: focused tween/style/transition implementation.
- `tests/main_menu_test.gd`: motion bounds, real mouse/focus glow events, every page transition/return, rapid input, resize cancellation, settled container positions, bounded active tweens and helper unloading; captures also include an in-flight transition.
- `tests/main_menu_polish_performance.gd` and its Godot-generated `.uid`: repeatable native static/animated comparison, plus isolated tween-update measurement.
- `docs/main_menu_polish_report.md`: this report.

## Verification

- Final `godot --headless --path . --script tests/run_ci_tests.gd`: exit 0, 8/8 suites; final menu regression passed 878 checks.
- Native D3D12 `tests/main_menu_test.gd -- --capture`: exit 0, 912 checks. Opening dashboard, motion snapshots, in-flight Character Select transition and narrow scrolled loadout were visually inspected.
- Existing regression coverage still checks Character Select, Map Select, Armory, Collection, Settings, Back/Escape, DEPLOY, music continuity, one audio player per scene and unchanged deployed player defaults. Repeated Escape/Back/navigation requests preserve one active page; no fade/position remains after interruption.
- Layout checks and captured previews cover 1152×648, 1600×900, 960×540, 800×600 and 360×480. Controls settle at container-authoritative coordinates; portrait layout slots stay fixed. The complete summary and DEPLOY remain viewable together when scrolling the narrow stacked layout.
- Godot editor import/class registration passed without parser/import errors. Native project startup and mouse-input Quit were also run. The project startup scene remains Main Menu; no physical editor F5 press is claimed.
- `git diff --check` passed, with informational line-ending notices. No artwork, audio, ground/terrain, gameplay, selection data, balance or project startup configuration changed.

## Performance evidence

Native D3D12, Radeon RX 5700 XT, Forward+, 1152×648, VSync disabled and 120 FPS cap. Four phases run in static/animated/animated/static order, each with 180 warm-up frames and 600 measured frames. No screenshots were taken inside measurements.

| Phase | Mean engine process monitor, ms | P95 monitor, ms | Wall frame, ms | Mean draw calls | Idle tweens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Static | 0.8660 | 0.9070 | 8.3330 | 42 | 0 |
| Animated | 4.0096 | 30.8370 | 8.3331 | 42 | 4 |
| Animated | 1.3427 | 1.5320 | 8.3330 | 42 | 4 |
| Static | 0.8182 | 1.0970 | 8.3330 | 42 | 0 |

Both versions maintained the configured 120 FPS cap with the same draw-call count. Engine process-monitor readings were variable, including an outlier in the first animated phase; they do not establish a precise total CPU overhead. This is an idle-menu test on the current desktop, not an uncapped GPU throughput or broad hardware guarantee.

Two separate manual-update probes each advanced the four live idle tweens 10,000 times. They measured 136.271 and 136.715 microseconds per four-tween update batch (about 0.14 ms). These exclude rendering, frame pacing and page transitions; they are supporting CPU evidence, not rendered frame times. Earlier shorter 240-frame probes were noisier and motivated the longer comparison.

## Limitations

The visual pass is deliberately subtle. No UI sound or additional ambience was added because the existing sources did not provide suitable short UI feedback. No subjective audio listening review is claimed. Existing CI and immediate-exit fixtures can still emit ObjectDB/resource cleanup diagnostics despite exit 0; they were not suppressed. A new test-only WeakRef type annotation caught during development was corrected before final verification. No commit or push was performed.

No-Te confirmed the same task Done after saving implementation evidence and updating Mechanics, Animation and Design Choices, and Optimization in place. No replacement or duplicate guide was created.
