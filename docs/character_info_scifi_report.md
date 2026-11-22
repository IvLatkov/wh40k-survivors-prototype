# Character Info: local Pixel UI Sci-Fi styling test

Verified 22 November 2026 using Godot 4.6.3. No-Te task: `ff3a9b19-a04a-47c9-9302-88c30ef7b256`, Restyle Character Info with Pixel UI Sci-Fi Free. No existing task matched this scope, so a dedicated To Do task was created and read before implementation. The initial missing-pack prerequisite was resolved when the user-installed addon appeared at `addons/pixel_ui_scifi/`. Current changes are uncommitted (commit SHA null).

## Scope and implementation

The skin applies only to `CharacterInfoPanel/Overlay/Center/Panel` and its descendants, through `resources/ui/character_info_theme.tres`. No project-global Theme, viewport/content scale, cursor, Main Menu skin, HUD skin, player resource, stat calculation, pause ownership or gameplay behavior changed. The existing shared upgrade-slot scene was not modified; Character Info applies its own local slot styles at instantiation.

The local theme uses cut-corner nine-slice frames, portrait brackets, textured close-button states, locally styled upgrade slots and a segmented health fill. Original textures are tinted by StyleBoxTexture.modulate_color and icons by self_modulate, preserving the source PNGs. The original full cyan Theme resource is not applied or loaded as the local theme.

All existing survival/weapon values, upgrade counters/levels/group labels, empty slots, Ultimates, Chapter choices, portrait and close actions remain. A health bar mirrors existing current/max HP alongside the original rounded health text, including fractional HP; it adds no health calculation. No XP bar was added. Updates use the existing refresh and health/stat signals, with no new per-frame processing or animation.

At normal resolution the previous layout remains. Below 760 pixels wide, Survival and Weapons stack and the portrait narrows to 128 pixels, eliminating horizontal stat scrolling found in the first 640×480 preview. Existing upgrade sections still stack below 800 pixels. Short/narrow windows retain vertical scrolling and I/Escape closing. The default 1152×648 sheet fits without vertical scrolling.

## Exact source components used

All paths below are relative to `addons/pixel_ui_scifi/`:

- `themes/cyan/panel.png`: outer cut-corner frame.
- `themes/cyan/panel_inset.png`: upgrade slot surfaces.
- `themes/cyan/bracket.png`: portrait corner frame.
- `themes/cyan/button_normal.png`, `button_hover.png`, `button_pressed.png` and `focus.png`: close-button states.
- `themes/cyan/progress_bg.png`: health track.
- `bars/bar_red.png`: health fill, tiled horizontally with the source nine-slice margins so segments are not stretched.
- `icons/heart.png`, `icons/shield.png`, `icons/crosshair.png`: Health, Ceramite Plating and Crit Chance respectively. No icon was forced onto Movement or every stat; no boot icon exists in this free pack.
- `font/pixel_ui_scifi_font.fnt` and `font/pixel_ui_scifi_font.png`: CHARACTER title only.

Window/title-bar, tabs, checkbox/radio, cursor, reticles and other icons were inspected but not applied. Pack README and `themes/slices.json` supplied the slice margins. The skin uses the selected components directly rather than importing the full pack Theme or changing global viewport scaling as the pack README suggests.

## Typography and colors

The pack bitmap font has 8-pixel ASCII glyphs. CHARACTER uses it at 24 pixels, an integer 3× scale; the existing body font remains at 14 pixels for detailed stats, punctuation and readability. Texture filtering is nearest only within the sheet; 16×16 icons stay at native size. Source imports already have mipmaps disabled and were left alone.

Text colors: body `(0.86, 0.89, 0.91)`, steel-blue headings/icons `(0.58, 0.68, 0.78)`, subdued health red `(0.76, 0.38, 0.37)`. Main frame modulation is `(1, 0.55, 0.8)`; unoccupied slots use `(0.55, 0.28, 0.42)`. Button normal/hover/focus tints are `(1, 0.45, 0.65)`, `(1, 0.6, 0.8)` and `(1, 0.7, 0.9)`. Health fill is modulated by `(0.75, 0.65, 0.65)`. These multiply original source pixels rather than defining flat replacement colors, producing the rendered near-black/charcoal-blue panels and muted blue borders. Existing gold Ultimate distinction remains.

## Attribution and source preservation

The included license identifies **heyheythere**, copyright 2026, and **CC BY 4.0**. The requested attribution and original source/license links were added to root `CREDITS.md`. The pack's full `LICENSE.txt`, README, author details, source images, font and Theme resources remain untouched. SHA-256 comparison confirmed all 67 pack source files unchanged from the post-install baseline; Godot-generated `.import` metadata is excluded from that source-file count. No artwork was generated, downloaded or destructively recolored by this task.

The user-installed `addons/pixel_ui_scifi/` is retained as supplied, including its metadata. Only selected assets are referenced by the local skin. It is currently untracked along with the new local resources/credits/report; no automatic staging or commit was performed.

## Files changed by this styling pass

- `scenes/ui/character_info_panel.tscn` — local theme/filter, portrait frame, title variation, muted headings, responsive stat grid.
- `scripts/ui/character_info_panel.gd` — local icon/slot presentation, mirrored health bar and narrow layout; existing calculations and pause handlers preserved.
- `resources/ui/character_info_theme.tres` — local reusable Theme and StyleBoxTextures; includes `SheetHealthBar` for explicit future reuse, not applied to HUD.
- `CREDITS.md` — pack attribution and links to preserved original license/source.
- `tests/character_sheet_test.gd` — all previous checks plus local scope, frame/icon/font sharpness, live fractional health, narrow layout, I/Escape and optional rendered captures.
- `tests/run_ci_tests.gd` — includes the Character Info regression; eleven suites total.
- `docs/character_info_scifi_report.md` — this report.

`project.godot`, Main Menu/HUD scenes/scripts, shared upgrade-slot scene, gameplay systems/player code, audio, assets catalog and original README are unchanged. The addon remains in its installed `addons/` structure.

## Observed verification

- Baseline before styling: 48 Character Info checks passed.
- Final headless Character Info regression: 77 checks passed as part of CI.
- Final native D3D12 capture regression: 84 checks passed; captured empty/upgraded sheets at normal resolution, 1600×900, 800×600, 640×480, plus HUD and Main Menu after closing the sheet.
- Visually inspected normal/upgraded sheet, 800×600, corrected 640×480, unchanged HUD and unchanged Main Menu. Text and three icons remain sharp; health fill shows individual segments; narrow stat columns no longer require horizontal scrolling.
- Tested unchanged stats/counters, ownership/max levels, real live health updates, local-only theme, no global theme assignment, current-resolution fit, resize/centering, I opening, Escape closing and pause release.
- Full `godot --headless --path . --script tests/run_ci_tests.gd`: 11/11 suites passed, exit 0. Existing XP, caps/combat/Ultimates, terrain, menu/audio and crate checks remain passing.
- Additional `tests/weapon_upgrade_groups_test.gd`: 71 checks passed.
- Godot import/native editor and normal project startup completed. One short editor run emitted Asset Library HTTPRequest teardown messages on close; reopening directly into the Character Info scene with a longer run exited 0 with a clean editor log. No parser/import or Character Info runtime error remains in the final checks.
- `git diff --check` passed. Source hash and scope checks confirm the pack sources and gameplay/Main Menu/HUD configuration were preserved. Captures are test-fixture visual evidence, not FPS benchmarks or a full-playthrough claim.

## Recommendation and limits

The restrained cut-corner frames, muted blue states and sparse icons fit the existing military presentation well. A separate local Main Menu experiment is recommended next, preserving its current layout/body text and applying selected components. Do not roll out the original cyan Theme or 8-pixel body font globally.

This evaluation covers the current game resolution and tested sizes; short windows use vertical scrolling. The bitmap title font is ASCII-only and deliberately confined to a static heading. No XP styling or HUD bar replacement was introduced. No commit or push was performed.

No-Te confirmed this task Done after saving the verified implementation report and updating Mechanics, Animation and Design Choices, and Bugs in place. No replacement guide was created.
