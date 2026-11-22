# Collection placeholder and Deploy summary

Verified 22 November 2026 using Godot 4.6.3. Extends existing No-Te task `4ba86118-6b7f-4fa9-afda-c4e59868fc0e`, Redesign Main Menu as a mission preparation hub. No duplicate task was created. The task was already Done; the connector has no reopen action. This extension is uncommitted (commit SHA: null). Previous menu/Armory/selection work was committed as `2b18389`.

## Changes

The existing COLLECTION bottom-navigation button remains. Its page now has a COLLECTION heading, an inset steel-blue placeholder panel displaying Coming Soon, and Back. It uses existing menu styles and the shared submenu container. There are no collection records, unlock actions, achievements, bestiary, saves or persistence. Back and Escape return to preparation.

Directly above DEPLOY, the compact MISSION LOADOUT section displays five lines: Ultramarine, Bolter, Battlefield Alpha, 10:00 Mission and Normal Difficulty. Summary type is 18 pixels; DEPLOY remains 25 pixels with its existing 68-pixel minimum button height. Warboss details stay on the Mission panel.

`MenuSelectionData.deploy_summary_text()` formats the existing character and mission dictionaries. It reads character name, starting weapon, mission name, duration and difficulty. `MainMenu._refresh_selection()` uses it alongside the existing selection/detail displays. No second configuration store or gameplay initialization was added. The summary scene contains no duplicate default loadout text.

The current three-column dashboard still stacks below 900 pixels. Its existing scrolling allows the complete five-line summary and DEPLOY to be viewed together at 360×480. Collection uses wrapped text and fits at desktop and narrow sizes. No audio resources, gameplay code, startup settings, artwork or Armory behavior changed.

## Files changed

- `scenes/ui/main_menu.tscn`: Collection placeholder panel and mission-summary presentation.
- `scripts/ui/main_menu.gd`: refresh summary from shared selection data.
- `scripts/ui/menu_selection_data.gd`: format the five selected values for display.
- `tests/main_menu_test.gd`: shared-data refresh regression, Collection contents/navigation and summary/Collection geometry at five sizes, plus preview captures.
- `docs/main_menu_collection_report.md`: this report.

## Observed verification

- Final full CI: `godot --headless --path . --script tests/run_ci_tests.gd` exited 0; 8/8 suites passed, including 766 menu checks.
- Final native D3D12 capture run: `tests/main_menu_test.gd -- --capture` exited 0; 797 checks passed. Desktop dashboard, narrow Collection and scrolled narrow loadout screenshots were visually inspected.
- Responsive checks covered 1152×648, 1600×900, 960×540, 800×600 and 360×480. Tests verify bounds, wrapping, no overlap with DEPLOY/Back, desktop dashboard fitting without scrolling, and scroll access to the stacked loadout.
- A temporary test-only change to all five selection fields updated both the summary and relevant selection panels. Original dictionaries were restored before deployment; no extra choices were added to the product.
- Existing regression checks still exercise Character Select, Map Select, Armory, Collection, Settings, Back/Escape, production DEPLOY transition, scene unloading, menu music removal, gameplay ambience and unchanged player defaults.
- Native editor/import verification exited 0 after retry with normal filesystem access; the successful editor log has no parser/import errors. Normal native project startup and dedicated mouse-input Quit both exited 0. Project startup configuration still points to Main Menu; a physical editor F5 keypress was not performed.
- `git diff --check` passed, with informational line-ending normalization notices. Scope review found only the five files above changed.

## Execution limitations

An initial CI attempt, run alongside native rendering, crashed in the pre-existing XP suite with an engine access violation. Its cause was not established. Two subsequent serialized full CI runs passed 8/8. Later verification used a writable temporary Godot user-data directory outside the repository. An initial native run had reported an unavailable optional shader-cache folder; the final rendered run did not.

The first restricted editor launch reported safe-save errors and secondary editor-dialog errors. A retry with normal filesystem access completed cleanly; no editor setting or project configuration was changed to suppress errors. Existing gameplay fixtures and some immediate startup/Quit exits still emitted ObjectDB/resource/RID cleanup diagnostics despite exit 0. These were not suppressed or treated as parser failures. No subjective audio listening assessment is claimed.

Collection remains deliberately non-functional. The summary reflects current menu display data and does not introduce gameplay selection, difficulty rules or persistence. No commit or push was performed for this extension.

## No-Te task handling

The first transactional completion request was rejected because the task was already Done from the prior Armory work. No guide edits or report were saved by that rejected transaction. The user reopened the same task; its unchanged requirements and new To Do revision were read back before resubmitting the verified results. No new task or replacement guide was created, and no separate note/status write was used to bypass the required transaction.

The subsequent transaction confirmed Done, appended the implementation evidence to the existing task, and updated Mechanics and Animation and Design Choices in place. No new note was created.
