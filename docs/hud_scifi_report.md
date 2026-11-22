# Local Pixel UI Sci-Fi HUD styling

Task: `2e5c23dc-7c61-4f6d-98a9-f4fa1babe0fd` — 22 November 2026.
Changes are uncommitted (commit SHA null). Baseline is `0012f33`, the committed Character Info styling.

## Presentation

The gameplay HUD now uses the Character Info palette and installed Pixel UI Sci-Fi pack: charcoal-blue backing surfaces, thin muted steel-blue cut-corner frames, a small heart beside HP and a star beside level/XP. Health uses the same subdued tiled red segments as Character Info; XP uses tiled blue segments. Empty tracks remain visible. Text keeps the original wording, numeric formatting and bindings. The run timer uses the pack's bitmap font at 24 px (3× its native size); body text remains the readable default font at 14 px. Nearest filtering is applied only on the HUD root.

The clock stays top-center and vitals stay bottom-center. After the requested size adjustment, bars are 228×12 px with continuous fractional values and no percentage overlay. A compact 248×88 frame contains the HP/XP displays, replacing the initial 324×128 frame (about 47% less area). Row spacing is tightened while retaining readable 14 px labels and native 16 px icons. The optional performance counters retain their update timer and values; their new frame is a child of the label so hiding the counters also hides the decoration. All added decoration ignores mouse input and takes no keyboard focus.

The theme is assigned only to HealthHUD/HUD. Character Info keeps its separate theme; Main Menu, upgrade menus, global settings, source art, audio and gameplay scripts are unchanged. Existing scene paths and script bindings remain stable. Death retains its original text, visibility and terminal pause. The separate Victory overlay is unchanged; no boss health display was added.

## Files

- `scenes/ui/health_hud.tscn`: local theme, frames/backings, icons and bar style variations.
- `resources/ui/hud_theme.tres`: pack frame, track, tiled red/blue fills, typography and palette.
- `tests/hud_styling_test.gd` and `.uid`: value/binding/layout/input-locality regression checks and native preview capture.
- `tests/run_ci_tests.gd`: includes the HUD test.
- `docs/hud_scifi_report.md`: this report.

No production GDScript changed, including `health_hud.gd`, `boss_hud.gd`, player and system scripts. No project settings or original pack files changed.

## Observed verification

- Focused headless HUD test: 137 checks passed, exit 0.
- Native D3D12 / Radeon RX 5700 XT HUD test: 145 checks passed, exit 0, including eight saved previews. Fresh, damaged, hidden-counter, four resized long-value fixtures and death were captured. Fresh/damaged, 640×480 long-value and death images were visually inspected. The new panels, icons, full/partial/empty bars and readable values fit without overlap.
- Geometry and text-fit checks passed at 1152×648, 1600×900, 800×600 and 640×480, including level 100 / XP 999 of 1000 and the double-digit-minute clock. Production initial, fractional damage/XP, upgraded max-HP, pause/resume, counter hiding and death bindings passed.
- Full CI: 12/12 suites passed, exit 0. Character Info passed 603 checks, including local-theme isolation across the expanded HUD tree; Main Menu passed 885 checks.
- Additional existing suites: run timer 1051, health regeneration 58, F10 boss skip 20, Warboss encounter 159 and boss spawn-stop 42 checks, all passed with exit 0.
- Native editor opened the updated HUD scene and completed with exit 0, without parser/import errors. Native live gameplay (240 frames) and normal Main Menu startup (120 frames) exited 0 without runtime errors.
- `git diff --check` passed. Changes are confined to the files above; no commit or push was performed.

Logs are ignored local files under `docs/hud_*.log` and `docs/hud_styling_*.log`. Native previews are saved as `hud_scifi_v1_*.png` under the Codex visualization directory. These static fixtures are layout checks, not FPS measurements. The original fixed 300 px bars remain; sizes smaller than 640×480 were not verified. One initial invocation using the default user-data environment crashed before the engine banner; subsequent isolated-user-data headless/native/editor/gameplay/CI runs all passed. No source change was made to hide that environment-specific startup failure.

## Compact health/XP follow-up

The earlier verification above describes the initial HUD pass. The follow-up changes only health/XP scene geometry in `scenes/ui/health_hud.tscn` and this report: 300×22 bars become 228×12, vertical container separation becomes 2 px, and the bottom-centered frame becomes 248×88. Timer, counters, theme, font/icon sizes, labels, production scripts, values and behavior remain unchanged. The bars now have a fixed 228 px width; sizes below 640×480 remain unverified.

Reused the existing focused HUD test without adding tests for numeric layout constants: 137 headless checks and 145 native checks passed. Eight fresh `hud_compact_v1_*` previews were captured; normal damaged and 640×480 long-value renders were visually inspected and remain clear without overlap. Full CI passed 12/12 suites. Native editor/import and normal project startup exited 0; startup reported the previously observed exit-time ObjectDB/two-resource cleanup diagnostics. `git diff --check` passed. The same No-Te task was reopened for this revision. All HUD work remains uncommitted; no push was performed.
