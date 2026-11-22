# Supply Crate v1

Verified 22 November 2026 with Godot 4.6.3. Existing No-Te task: `5775fe7c-2012-41c5-9bc7-a387f55028fc`, Treasure / supply crate system. This implements the requested first milestone version; elite drops and weapon evolution remain future work. Changes are uncommitted (commit SHA null). No new task was created.

## Run milestone and world placement

`scenes/pickups/supply_crate.tscn` and `scripts/pickups/supply_crate.gd` form a reusable Area2D pickup. `scripts/systems/supply_crate_encounter.gd` owns its per-run milestone state and binds to the existing RunClock seconds_changed signal. There is no parallel spawn timer or per-frame placement work.

At 300 seconds the controller attempts one crate near the player. It tries 16 fixed directions at radii 320, 380 and 260 pixels, consuming no shared gameplay or terrain RNG. Candidate clearance uses the existing terrain-obstacle collision layer, plus enemy layer 2. All four corners of the 28-pixel clearance footprint must be on loaded chunks. A swept 16-pixel circle requires a direct clear approach from the player, avoiding inaccessible placements without introducing pathfinding. The crate is parented to the run, not streamed into terrain chunks; terrain generation and streaming are unchanged.

The successful spawn flag is committed before insertion and never reset on collection. Repeated notifications cannot spawn another crate. If all nearby positions are blocked, placement retries on the next run-clock notification before 10:00; a completely blocked area can therefore delay or prevent the single spawn. It never forces a crate inside a solid or outside loaded terrain.

At 600 seconds the crate window closes, whether reached naturally or by F10. A direct skip from 0:00 to 10:00 never spawns a stale 5:00 crate; later stale notifications cannot reopen the window. The existing boss_spawned signal also retires an uncollected crate. Death closes the milestone. Each fresh gameplay scene starts a new run-owned state; binding is guarded against repeated setup.

## Placeholder and collection

No suitable crate image or short pickup/open audio was found in the existing assets. The placeholder uses olive/steel Polygon2D case pieces, straps, a gold keyline and supply marking, a readable SUPPLY label and a faint ground shadow. One scene-owned tween bobs the visual two pixels over a 2.4-second cycle. No source image, generated/downloaded artwork, shader, particle system or audio was added.

The Area2D has collision layer 0 and mask 1, a 25-pixel collection radius and no solid body. It only accepts a living Player. The first overlap immediately marks it collected, hides it and defers monitoring changes. A deferred completion emits the reward request and queues removal after the physics query. Repeated overlap callbacks cannot create another reward. This pickup is independent of the XP attraction/magnet system.

## Shared reward and pause integration

The existing UpgradeSystem queue now accepts a SUPPLY_REWARD entry (reserved value zero; normal captured player levels remain positive). It uses the same normal eligibility, four weapon/four generic slot ownership, category level limits, stat caps, duplicate filtering and upgrade application path. It grants up to three unique eligible normal upgrade choices. Selecting one applies the normal effect, with no XP award/cost, no player-level change and no XP-requirement change.

Crate v1 does not offer Chapter perks or existing Ultimates/evolution. Existing Ultimate eligibility and offers on real level-up rewards are preserved. If no normal upgrade remains, the existing exhausted-reward path consumes the free queue entry without presenting an empty modal, violating a cap or substituting an evolution.

The existing UpgradeMenu renders the same cards under SUPPLY CRATE and Choose Requisition. Normal level rewards restore the normal heading and hide that subtitle. No second upgrade UI or implementation was introduced.

Crates enter the existing reward queue, including behind Chapter choices or ahead of later normal level rewards. The existing reward_queue_started handoff closes Character Info before the reward queue captures pause ownership. Completing the final reward restores only that queue's previously captured pause state; a pre-existing external pause stays paused. Victory already clears/locks the reward system and menus. Death now also ends the shared reward queue and disables its reward menus, preventing stale crate or normal reward selections from applying upgrades or resuming an ended run. No other pause architecture was replaced.

## Files changed

- `scenes/pickups/supply_crate.tscn` — new reusable primitive pickup visual and Area2D.
- `scripts/pickups/supply_crate.gd` and `.uid` — guarded overlap, deferred collection/removal and bob.
- `scripts/systems/supply_crate_encounter.gd` and `.uid` — milestone, bounded safe placement and run cleanup.
- `scenes/main.tscn` — run-owned controller node.
- `scripts/systems/main.gd` — bind controller, route reward presentation and close reward menus on death.
- `scripts/systems/upgrade_system.gd` — free normal reward in the existing queue, preserving eligibility/application and terminal guards.
- `scripts/ui/upgrade_menu.gd` and `scenes/ui/upgrade_menu.tscn` — shared Supply Crate heading/subtitle.
- `tests/supply_crate_test.gd` and `.uid` — focused end-to-end regression and native preview capture.
- `tests/run_ci_tests.gd` — include the crate regression; CI now has ten suites.
- `docs/supply_crate_report.md` — this report.

## Observed verification

- Focused crate regression: 51 headless checks; 53 native D3D12 checks including two saved previews. The native run used actual player/body overlap and engine mouse input on the paused upgrade buttons. World and reward screenshots were visually inspected.
- Covered before/at 5:00, one-time spawn/repeated milestones, annulus/loaded terrain, enemy clearance, no solid crate collision, no shared RNG consumption, duplicate overlap suppression, removal, three unique eligible choices, actual stat application, unchanged level/XP/requirements, caps/full slots, existing-Ultimate exclusion, mixed Chapter/normal/free queues, Character Info handoff, preservation of another pause, exhausted choices, fully blocked placement/retry, boss removal, F10/stale notifications, real Warboss Victory, death and stale reward rejection.
- Full CI: `godot --headless --path . --script tests/run_ci_tests.gd` passed 10/10 suites, including the new crate regression and the existing XP, armor, additive spawning, combat, Ultimate, pickup visual, terrain, menu and dual-audio checks.
- Additional existing suites passed: upgrade system 88 checks; upgrade level caps 658; Chapter perks 307; weapon groups 71; generic upgrades 1,217; Warboss encounter 159; F10 20; Character Info sheet 48.
- Native editor/import and normal project startup completed without parser/import errors. Relevant native testing ran the production gameplay scene. The focused fixture suspends ordinary enemy/weapon/clock updates for deterministic assertions; screenshots are visual evidence, not FPS measurements.
- Placement probe in the final native run measured 3.700 ms for the clear milestone tick including first crate creation, and 0.416 ms for the fully blocked tick. These are individual samples, not averages or a general performance guarantee. Tightening the annulus search reduced an earlier fully blocked sample of 15.081 ms. Placement work happens only at the milestone/retry clock ticks; normal operation adds just one bob tween and one collection area.
- `git diff --check` passed. No terrain generation/streaming, source assets, audio configuration, enemy stats/spawn progression, XP progression values or game balance resources were changed.

## Limitations

The crate is placeholder art with no pickup audio. Placement deliberately favors a direct clear route and retries when the nearby area is blocked; it does not solve mazes. The uncollected crate stays at its original world location until collected or retired, rather than following the player. An exhausted normal-upgrade pool produces no choice screen, following the existing empty-reward behavior. Elite drops, multiple crates, persistent rewards and weapon evolution are not part of v1. No commit or push was performed.

No-Te confirmed the existing Supply Crate task Done after saving implementation evidence and updating Mechanics, Animation and Design Choices, Optimization and Bugs in place. No new task or replacement guide was created.
