# Character Info: all sixteen styled stat rows

Verified 22 November 2026 with Godot 4.6.3. Extends No-Te task `ff3a9b19-a04a-47c9-9302-88c30ef7b256`, Restyle Character Info with Pixel UI Sci-Fi Free. The user reopened the existing task; no duplicate task was created. Changes remain uncommitted (commit SHA null), including the previous styling pass already pending in this working tree.

## Reusable row presentation

`scenes/ui/character_stat_row.tscn` with `scripts/ui/character_stat_row.gd` supplies all sixteen stat rows. Its passive structure is PanelContainer → HBoxContainer → Icon, StatName, Value, with an optional inline health bar created only for Health. Every row has a 24-pixel minimum height, six-pixel horizontal/two-pixel vertical padding, a subtle dark background and a one-pixel bottom separator. Values reserve a 72-pixel right-aligned column; labels are muted and values brighter. Sections use a one-pixel gap between rows so the normal-resolution sheet still fits without scrolling.

The existing local `character_info_theme.tres` now includes the CharacterStatRow style variation. The shell, pixel title, portrait frame, upgrade sections, colors and existing content remain. Survival and Weapons stay side-by-side where they fit and retain the previous stacking behavior below 760 pixels, including the narrow portrait adjustment. No new global Theme or screen redesign was introduced.

Health retains its existing segmented fill and numeric value. The segments are inline, allowing the Health row to remain the same height as every other stat. Existing health/max values, rounding and all other displayed formatting/calculation code remain unchanged. Ceramite Plating and Gene-Seed Resilience keep their thematic names.

## Icon mapping

All images are existing 16×16 files under `addons/pixel_ui_scifi/icons/`, drawn at native size with nearest filtering. Shared images are intentionally reused; the pack has no dedicated radar, blade, boot, bullet-stack, impact-variant or clock art.

| Stat | Icon | Meaning |
| --- | --- | --- |
| Health | heart.png | Health |
| Ceramite Plating (Armor) | shield.png | Protection |
| Gene-Seed Resilience (Health Regen) | health.png | Medical/recovery |
| Movement Speed | arrow_right.png | Shared movement cue |
| Pickup Radius | info.png | Neutral information fallback; no radar icon |
| XP Gain | star.png | Shared progression cue |
| Dodge Chance | arrow_right.png | Shared movement/evade cue |
| Better XP Drop Chance | star.png | Shared XP/reward cue; no dedicated loot icon |
| Bolter Damage | crosshair.png | Shared offense cue |
| Bolter Projectiles | rocket.png | Generic projectile cue, not dedicated bullet art |
| Bolter Fire Rate | energy.png | Shared attack-cadence cue, not a clock |
| Crit Chance | crosshair.png | Aim/critical cue |
| Crit Bonus | crosshair.png | Shared critical cue; no impact variant |
| Knife Damage | info.png | Neutral fallback; no blade icon |
| Knife Range | info.png | Neutral fallback; no blade/range icon |
| Knife Attack Rate | energy.png | Shared attack-cadence cue |

No source pack image, font, Theme, license or author file was edited. SHA-256 comparison still confirms all 67 pack source files unchanged. Existing CREDITS.md attribution remains applicable. No new artwork or audio was generated or downloaded.

## Data and interaction scope

The panel still fills the same `_value_labels` and `_stat_labels` bindings, now pointing into row instances. Comparisons against the pre-extension source confirmed `refresh_stats()` and the entire bind/input/open/close/pause block were unchanged. The row component has no stat calculations, input handlers, gameplay signals, animation or per-frame processing. It only configures presentation. All gameplay/player/combat/upgrade/pause code remains outside this change.

The previous uncommitted shell/theme/credits/import work is retained. Main Menu, gameplay HUD, global project configuration, shared upgrade-slot scene and source assets were not changed by this extension.

## Extension files

- `scenes/ui/character_stat_row.tscn` — new reusable row structure.
- `scripts/ui/character_stat_row.gd` and `.uid` — configure text/icon and optional inline health presentation.
- `scripts/ui/character_info_panel.gd` — build all sixteen rows through one helper; central icon mapping and existing value bindings.
- `resources/ui/character_info_theme.tres` — local row background/separator/padding variation.
- `tests/character_sheet_test.gd` — complete value, structure, alignment, sizing and responsive regressions; explicit capture paths in output.
- `docs/character_stat_rows_report.md` — this report.

The broader working tree also contains the earlier styling pass's Character Info scene, CI integration, CREDITS.md and user-installed pack. These were preserved, not reverted or newly authored as part of this extension.

## Observed verification

- Focused Character Info: 595 headless checks passed, exit 0. Tests cover exact default values and non-default modifier fixtures for all sixteen stats, thematic labels, live fractional health, shared components, consistent row heights/padding, native-size icons, aligned values, contained health segments, and no overlap at 1152×648, 1600×900, 800×600 and 640×480.
- Native D3D12 verification: 602 checks passed, exit 0, including seven captured previews. Fresh `character_stat_rows_v2_*` captures were saved with direct filesystem access to avoid reusing the earlier preview files. Normal, upgraded and narrow sheet images were visually inspected; all rows now visibly have the new treatment.
- Full `tests/run_ci_tests.gd`: 11/11 suites passed, exit 0, including the 595 Character Info checks and unchanged menu/audio/crate/gameplay regressions.
- Additional `tests/weapon_upgrade_groups_test.gd`: 71 checks passed.
- Existing I/Escape, close behavior, pause release, ownership/counters and local-theme isolation checks remain passing. The normal-resolution sheet needs no vertical scrolling; short/narrow windows keep the existing vertical scrolling and stacked sections without overlapping fields.
- Editor/import and normal startup were checked; source pack integrity and protected-scope checks passed. `git diff --check` passed, with informational line-ending normalization notices only.

Screenshots are deterministic fixture previews, not FPS measurements. Icon meanings that lack dedicated pack art are explicitly documented above rather than presented as bespoke weapon/radar assets. No commit or push was performed.

The native editor/import check exited 0 without parser/import errors. Normal project startup also exited 0, with the previously observed immediate-exit ObjectDB/resource cleanup diagnostics; these were not suppressed or treated as functional test failures.

No-Te confirmed task `ff3a9b19-a04a-47c9-9302-88c30ef7b256` Done with the implementation evidence saved and the canonical Mechanics and Animation and Design Choices documents updated transactionally. Changes remain uncommitted.
