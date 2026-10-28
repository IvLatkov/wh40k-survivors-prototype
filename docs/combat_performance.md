# Combat performance pass â€” 2026-10-28

## Result

Reduced the recurring separation cost and the measured mass-death allocation bursts. The requested p95 <20 ms and worst <33 ms targets are **not met**. No balance values, XP formulas/art/shader, terrain code, weapon targeting/damage formulas, or Ork state-machine behavior changed.

## Reproduce

Run one rendered benchmark at a time, with no editor, tests, or other benchmark competing for resources:

```powershell
C:/Godot/Godot_console.exe --path . --fixed-fps 60 --script tests/combat_performance_test.gd -- --label=latest
C:/Godot/Godot_console.exe --headless --path . --script tests/combat_optimization_test.gd
```

Optional `--capture` saves `docs/combat_benchmark.png` **after** all timing samples. Headless mode checks behavior but is not a rendered FPS benchmark. The initial exploratory capture run was discarded because screenshot readback inside its measured interval introduced a 132 ms spike.

Godot 4.6.3 stable, D3D12 Forward+, AMD Radeon RX 5700 XT, 1152Ã—648 window. Wall-clock intervals are sampled at `SceneTree.process_frame`, including render/presentation pacing, engine work and instrumentation. Fixed simulation step is 1/60 s; 60 warmup frames followed by 1,800 measured frames (30 simulated seconds). FPS is 1000 / mean wall-clock interval. Percentiles use the nearest rank. Normal project rendering settings/VSync are retained.

Fixture uses the actual main scene, its initial stationary terrain, production player input/acceleration, enemy movement, Ork animation attacks, projectile physics impacts, drops, pickup collection, and visual feedback. It replenishes toward 200 enemies before each frame, initially 150 Squigs + 50 Orks; every fourth replacement is an Ork. Death bursts briefly reduce the count; repeat-run average was 199.125, minimum 147, with replacement the next frame. The bounded right/left route stays in the initial terrain area. Player health is replenished and level-up menus are disconnected; XP collection/level calculation still run. This is a stress fixture, not a legal build or survival/difficulty test.

Global RNG seed 741; each Ork receives a reproducible independent attack RNG seed. Startup/physics and visual RNG scheduling can still yield modest differences in event totals between rendered runs; this is a fixed fixture and seed, not a byte-identical combat replay. Terrain determinism remains separately tested.

Fixture weapon configuration: 25 base direct Bolter damage, 12.5 normal splash before crit, five primary projectiles per volley, 0.5 s interval (2 volleys/s, 10 primary projectiles/s), Devastator and Forking active; Knife 35 damage, 82.5 px radius, unchanged 0.8 s base cooldown, Whirlwind active; shared crit 7.5%, 1.5Ã— multiplier. All are fixture-only settings using existing modifiers/ultimate APIs.

## Before / after

| Metric | Before | After | After repeat |
|---|---:|---:|---:|
| Mean ms | 16.687 | 16.664 | 16.664 |
| Median ms | 14.481 | 16.396 | 16.440 |
| p95 ms | 29.812 | 22.758 | 22.890 |
| p99 ms | 56.020 | 32.862 | 33.379 |
| Worst ms | 65.014 | 37.063 | 38.272 |
| Mean FPS | 59.925 | 60.008 | 60.008 |
| Frames >16.7 ms | 646 | 778 | 808 |
| Frames >25 ms | 507 | 43 | 43 |
| Frames >33.3 ms | 43 | 17 | 19 |
| Frames >50 ms | 27 | 0 | 0 |

p95 improved about 24%; >25 ms frames fell about 92%. Final worst frame fell from 65.014 to 37.063 ms (43% lower). Repeat p95 was 22.890 ms, worst 38.272 ms. Both final runs had zero frames above 50 ms. Average FPS stays near 60 because of presentation pacing; it does not imply every frame meets budget. The >16.7 ms count is higher after the changes despite fewer large spikes: presentation pacing and the very tight threshold matter, so this is not a claim that every frame distribution metric improved.

| Event (measured frames only) | Before | After | Repeat |
|---|---:|---:|---:|
| Projectiles, including forks | 528 | 512 | 512 |
| Impacts | 314 | 279 | 279 |
| Splash events | 114 | 106 | 106 |
| Splash targets | 595 | 559 | 559 |
| Knife swings | 37 | 37 | 37 |
| Knife hits | 1582 | 1561 | 1561 |
| Damage events / numbers | 2470 | 2385 | 2385 |
| Critical hits | 165 | 168 | 168 |
| Deaths / replacement enemies | 1636 | 1575 | 1575 |
| XP skulls spawned | 1748 | 1684 | 1684 |
| Ork slashes | 242 | 247 | 247 |

Observed projectile rates (including forks): 17.60/s before, 17.07/s after, 17.07/s repeat.

## Bottlenecks and changes

1. Separation copied each relevant bucket into a per-enemy candidate array, validated/cast entries, then validated/traversed them again. It was the largest recurring script cost. It now iterates the same nine cells and candidate order directly, with the same live positions, weighting and overlap tie-break. Grid registration owns a one-shot tree-exit callback and removes the enemy from its indexed bucket promptly. This permits typed bucket iteration and a shared empty bucket. No separation cadence, force, radius, collision mask or movement speed changed.
2. Blood CPUParticles2D scene construction dominated mass-death creation. The worst baseline frame (653, 65.014 ms) killed 50 enemies in a 60-target Knife attack: blood creation 10.383 ms, full death path 13.262 ms, number instantiation/configuration 4.243 ms plus deferred Label/Tween setup 3.742 ms, and separation 10.656 ms. These costs overlapped/nested; they must not be blindly summed.
3. Added scene-owned blood and damage-number pools: prewarm 64 of each at main-scene startup; retain at most 128 idle nodes each. Demand can exceed 128 active nodes; overflow is created immediately, so no visual is dropped, then freed on return if the idle cap is full. Nodes are released with their world; there is no autoload or global pool. Blood uses the same scene/particles, restart, position and 0.32 s lifetime. Numbers retain the same text rounding, color, 18/23 font sizes, position offsets, 0.30 s/45 px linear rise and fade over the second half. A small `_process` replaces per-number Tween allocation. Numbers remain attached under their pool for their entire lifetime: activation resets them in place, and recycling hides/disables them without remove_child/add_child/reparent work. Profiling the first pool version found that recycling through the scene tree still peaked at 12.578 ms/frame; eliminating those insertions was a necessary additional optimization (see intermediate `combat_after_detailed.json`).
4. Blood activation keeps the existing deferred physics-safe scheduling; no death damage, XP creation or spawn schedule is staggered across frames. XP remains immediate/deferred exactly as before. No XP, enemy, projectile, explosion or slash pooling was added.

## CPU telemetry

`CombatProfile.enabled` defaults to false and is enabled only by the benchmark. Timings use `Time.get_ticks_usec()`. Wrapper functions cover early-return paths; timing/counter dictionaries are unused when disabled. Event logs are written only for >25 ms frames plus aggregated results; normal gameplay prints no telemetry.

Timings are inclusive. The historical key `squig_update` measures Enemy base update, **including calls from Ork super**, while `ork_update` includes that super call too. Do not add them to estimate total enemy cost. `knife_attack` includes damage/death work; `death` includes XP and blood scheduling. `number_creation` after pooling measures scheduling; `number_activation` includes reuse/cold creation and Label setup. `blood_creation` after pooling measures scheduling; `blood_activation` measures actual activation. Enemy instantiation/insertion, deferred XP insertion and Knife damage now have separate spans. Rendering/presentation, actual engine object destruction and OS scheduling remain unassigned wall time. `cleanup_nodes` counts node tree exits; `queue_free_requests` counts the explicit requests instrumented in enemy death and projectile cleanup (not every engine/scene cleanup).

| Path | Before mean / peak ms per frame | After mean / peak ms per frame |
|---|---:|---:|
| Separation | 4.589 / 17.434 | 2.100 / 6.786 |
| Enemy base update (includes Ork super) | 6.353 / 20.627 | 3.936 / 9.362 |
| Ork inclusive update | 2.557 / 7.049 | 1.884 / 3.819 |
| Death processing | 0.235 / 16.285 | 0.053 / 2.964 |
| Blood construction / pooled scheduling | 0.179 / 12.600 | 0.003 / 0.156 |
| Number construction / pooled scheduling | 0.111 / 5.285 | 0.007 / 0.338 |
| Number Label/Tween / Label setup | 0.086 / 3.776 | 0.075 / 3.478 |
| XP creation (before deferred insertion) | 0.049 / 3.275 | 0.043 / 2.468 |
| Enemy instantiate/configure/tree insert | 0.099 / 5.056 | 0.100 / 5.667 |
| Grid rebuild | 0.130 / 0.632 | 0.182 / 1.245 |
| Splash physics lookup | 0.002 / 0.101 | 0.002 / 0.127 |
| Fork lookup + creation | 0.045 / 2.025 | 0.044 / 1.949 |
| Knife inclusive attack | 0.292 / 23.645 | 0.067 / 4.421 |
| Knife local target filter | 0.003 / 0.254 | 0.003 / 0.174 |
| Blood activation | not separately recorded | 0.010 / 0.581 |
| Number activation (no recurring tree insert) | not separately recorded | 0.086 / 4.413 |
| Deferred XP insertion (includes ready) | not separately recorded | 0.062 / 3.864 |
| Enemy scene instantiation | not separately recorded | 0.048 / 2.663 |
| Enemy tree insertion | not separately recorded | 0.032 / 1.887 |
| Knife damage (includes death) | not separately recorded | 0.058 / 4.233 |

## Spatial queries and allocation audit

| Query | Before avg / worst candidates | After avg / worst candidates |
|---|---:|---:|
| separation | 58.08 / 131 | 60.05 / 126 |
| splash | 6.22 / 25 | 6.27 / 30 |
| knife | 46.62 / 81 | 45.52 / 77 |
| fork | 180.72 / 200 | 184.65 / 200 |

Separation inspects only the existing 3Ã—3 neighborhood. Forks use radius-bounded grid cells and retain the nearest two targets in one pass. Knife uses its existing Area2D overlap dictionary, filters center distance and facing, and does not query all world enemies; this is an existing local broad phase, so it was retained instead of adding a second grid query. No global group scan exists in these combat paths.

Splash currently uses a fresh CircleShape2D, PhysicsShapeQueryParameters2D, physics hit array (existing limit 100), and deduplication dictionary. Its measured mean was under 0.002 ms/frame; it was deliberately retained to preserve collider-edge semantics and hit order/crit draws. Fork target arrays and Knife result/stale-ID arrays occur at attacks, not per-enemy per-frame. Grid rebuild arrays/dictionary rebuilding were retained (peak ~1 ms after adding prompt bucket cleanup). XP still has its existing bob Tween/shared materials; no unique XP materials or shape changes were introduced. Blood retains the existing Timer per reusable effect. Explosion SceneTreeTimers and slash completion signals remain unchanged.

## Regression and visual verification

All 30 functional `*test.gd` scripts passed; `combat_regressions.json` records individual outputs. This includes 2,406 focused optimization checks, 100,147 Ork Boy checks, 136 Ork melee-animation checks, direct/splash/independent crit behavior, directional Knife/range, ultimate effects, damage-number exact values, fractional health, XP progression/drop/visual/pickup behavior, armor/regen, spawn schedules, chapter/upgrade eligibility, UI pause handling, terrain artwork/streaming/prefetch and deterministic reference checks. Existing blood and number assertions now inspect visible pooled descendants rather than assuming they are direct world children. Their exact damage, critical styling, one-effect and XP-quantity assertions remain intact.

The focused test compares exact Vector2 separation results against the old algorithm, including overlap and removal cases, and exercises repeated 200-blood and 150-number bursts, overflow disposal, style/fade reset and idle caps. Benchmark assertions match numbers to damage events and XP creation calls to deaths. Repeated rendered runs complete without runtime/debugger errors. Rendered screenshot was inspected for white/red numbers, blood, sprites, outlined/tiered XP, shadows and terrain. Rendered editor import/parser check and main-project smoke test also ran.

Memory rises during the fixture as uncollected XP accumulates (repeat ended with 411 live pickups). This is expected retained gameplay content, not proof of a leak. Both pools remain bounded in repeated overflow tests. The repeated benchmark returned the world from 1 node before creation to 1 node after cleanup; no orphaned scene nodes remained. Process-wide static memory samples and node counts are in the JSON; a long-session allocator/GPU leak has not been ruled out by this short test.

## Remaining risks

Large Knife deaths still cause same-frame XP insertion/Label setup and replacement enemy instantiation the next frame. The worst final repeat frame was 38.272 ms at frame 751; its event and CPU counters are in the JSON. Separation remains the largest recurring explicitly measured script path (~2.1 ms/frame); base enemy update includes it. Actual engine physics/render and deferred cleanup add costs outside those script timers. No terrain change or gameplay timing adjustment was justified.

An intermediate run had a 51.932 ms frame with no combat burst and little script work; its engine/render/presentation/OS source was unresolved. It did not recur in either final run. Long-tail scheduling stalls can still occur, and this pass does not claim the original frame-budget targets were achieved.

## Files

Production: `scripts/enemies/enemy.gd`, `scripts/enemies/ork_boy.gd` (telemetry only), `scripts/projectiles/bolt_projectile.gd` (telemetry only), `scripts/weapons/knife.gd` (telemetry only), `scripts/systems/enemy_spatial_grid.gd`, `scripts/systems/enemy_spawner.gd`, `scripts/systems/main.gd`, `scripts/systems/combat_profile.gd`, `scripts/effects/blood_burst_pool.gd`, `scripts/ui/damage_number.gd`, `scripts/ui/damage_number_pool.gd`.

Tests: `tests/combat_performance_test.gd`, `tests/combat_optimization_test.gd`, `tests/ork_boy_test.gd`, `tests/ork_melee_animation_test.gd`, `tests/chapter_perks_test.gd`, `tests/directional_knife_test.gd`, `tests/dynamic_bolter_splash_test.gd`, `tests/ultimate_upgrades_test.gd`, `tests/weapon_upgrade_groups_test.gd`. New GDScript UID files accompany the scripts.

Evidence: this document, `combat_before.json`, `combat_after.json`, `combat_after_repeat.json`, intermediate `combat_after_detailed.json`, `combat_regressions.json`, `combat_benchmark.png` and its Godot import metadata. Raw JSON contains per-spike counts/CPU correlations and full aggregate counters. No commits or pushes.
