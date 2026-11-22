# Character and mission selection extension

Verified locally on 22 November 2026. Changes are uncommitted.

Existing No-Te project: `54238fa8-e6c1-415e-b747-f257b5a790d9`.
Existing task: `4ba86118-6b7f-4fa9-afda-c4e59868fc0e` — Redesign Main Menu as a mission preparation hub.
No duplicate task was created.

## What changed

The existing dashboard is preserved. Clicking its Character or Mission panel,
or the smaller View Dossier / Mission Brief buttons, opens the matching selection
screen. Each screen has a reusable selected card, a larger details panel and Back.
Escape returns to preparation. Cards and details stack on narrow windows.

Character Select displays the existing Ultramarine portrait, Chapter Ultramarines,
starting Bolter, Unlocked and Selected. The displayed starting stats come from
the real player scene and CombatStats methods: 50 maximum HP, 150 px/s movement,
0 armor and 0% crit chance. A temporary player scene is inspected outside the
scene tree and then freed; gameplay never runs behind the menu.

Passive Bonus is None. ChapterPerkManager grants selected milestone perks during
the run; those perks are not automatically granted at spawn.

Mission Select displays Battlefield Alpha, the existing ruin preview, 10 Minutes,
Squigs, Orks, Ork Warboss, Normal difficulty, Warboss at 10:00, Unlocked and Selected.
Timing comes from BossEncounter.SPAWN_SECONDS. Names and descriptive display facts
without gameplay metadata live together in MenuSelectionData.

The dashboard uses the same selected display data. DEPLOY still loads the existing
gameplay scene. Only the existing character and stage are available. No unlock
rules, purchases, difficulty selector, persistence, new art, terrain changes or
gameplay balance changes were added.

Menu music remains -26 dB and is freed with the menu. Gameplay ambience remains
the existing background_atmos.wav at -30 dB, using its existing native loop and
pause behavior.

## Files

- `scenes/ui/main_menu.tscn`: expanded selection pages; clickable dashboard panels.
- `scenes/ui/selection_card.tscn`: reusable card with portrait, description and states.
- `scripts/ui/main_menu.gd`: shared display binding, selection navigation and sizing.
- `scripts/ui/menu_selection_data.gd` and its `.uid`: menu-only starting data reader.
- `scripts/ui/selection_card.gd` and its `.uid`: selected state and content sizing.
- `tests/main_menu_test.gd`: additional selection/data/input/layout regression checks.
- `docs/main_menu_selection_report.md`: this verified implementation record.

## Observed checks

- Godot 4.6.3 editor import/parser check: exit 0, no parser/import errors.
- `godot --headless --path . --script tests/run_ci_tests.gd`: exit 0, 8/8 suites;
  dedicated main-menu script included 378 checks.
- Native D3D12 `tests/main_menu_test.gd -- --capture`: exit 0, 391 checks including
  captures. Character and mission previews were visually inspected.
- Stats test changes a packed player fixture to 75 HP, 180 speed, 3 armor and
  12.5% crit and confirms the reader reflects scene/resource overrides.
- Both selection pages and dashboard geometry checked at 1152x648, 1600x900,
  960x540, 800x600 and 360x480. Checks cover column count, horizontal bounds,
  card content height and card/details overlap.
- Navigation checks cover dashboard-card clicks, reselecting the sole option,
  Back/Escape, Upgrades, Collection, Settings, DEPLOY and audio ownership.
- Separate Quit process: exit 0 after clicking the actual Quit control.
- `tests/background_music_test.gd`: exit 0, 73 ambience checks including looping,
  gain, pauses, reward queues, F10/natural boss, Victory/death and reload.
- Native normal project startup: exit 0. Startup configuration is asserted by
  the menu test; a physical editor F5 key press was not performed.
- `git diff --check`: passed before adding this Markdown report.

Existing ObjectDB/resource-still-in-use shutdown diagnostics still occur in some
CI/Quit/short-launch processes despite exit 0. They were not suppressed.
No subjective audio listening test is claimed.

## Pending No-Te synchronization

The existing task was already Done when this extension was requested. Neither
the connector nor the current user interface exposes reopening. Its requirements
and linked guides were read before implementation and reviewed again afterward.
A fresh-revision transactional completion was attempted only after successful
verification. The server rejected it: "Task is no longer To Do. Read its current
state before proceeding." Read-back confirmed the task is still Done with its
earlier completion evidence unchanged.

No completion report or canonical-guide edits from this extension were saved by
that rejected transaction. The Mechanics and Animation and Design Choices updates
remain pending, along with the new task-linked report. Existing guide content and
task links were preserved. No separate completion-note/status fallback was used.

When reopening is supported, use this same task, re-read its requirements/revision
and both canonical guides, reconcile any changes, then record the verified
extension transactionally. This report describes completed local implementation;
it does not claim that the No-Te extension was completed.
