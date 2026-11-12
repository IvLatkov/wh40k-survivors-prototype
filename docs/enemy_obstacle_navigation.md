# Enemy obstacle navigation and safe spawning

Squigs, Orks, and the Warboss retain their existing movement speeds, damage,
attack ranges, cooldowns, and state machines. Chase movement now uses lightweight
local detours around solid terrain. Knockback retains collision-safe movement.

## Local steering

- Each enemy staggers terrain probes over a configurable 0.2-second interval.
  Center/side probes look 96px ahead and account for the actor's body radius.
- When blocked, select a short route around the obstacle's world-space bounds,
  expanded by body radius plus 8px. Nearby overlapping clearance bounds merge
  in at most two local queries, each limited to 16 bodies, to avoid unsafe gaps.
- Follow cached corners between probes. Recheck when the target moves, another
  prop obstructs the route, or an obstacle unloads. Revert to ordinary chase
  direction once clear; never increase the original desired speed.
- Open-area movement skips the steering helper between probes. Distant enemies
  retain throttled updates and collision sweeps, with the same detour logic.
- There is no navigation mesh, global route graph, autoload, or per-frame
  whole-map scan. This handles the current convex props and small clusters;
  arbitrary mazes and long connected walls may still require full pathfinding.

## Safe spawns

Normal enemies and the boss share a terrain-only circle query based on their
collision-body radius, with 2px additional clearance. Preserve an already-clear
requested position; otherwise check up to 128 deterministic candidates on rings
out to 512px. Relocations respect player distance and offscreen placement.
This consumes no gameplay RNG and queries the current physics space, including
the currently loaded streamed terrain. It does not pre-generate distant chunks.

If no valid point exists, free an uninserted normal enemy without registering
it or consuming the enemy cap. A blocked boss attempt remains retryable on the
next clock event; only successful placement sets the one-boss flag and stops
normal spawning. The normal first attempt remains at 10:00; F10 uses the same
production controller. Victory and audio behavior are unchanged.

## Verification

`tests/enemy_obstacle_navigation_test.gd` exercises:

- All three enemy types traversing each of the eight actual prop variants.
- Narrow-gap clusters and detour invalidation after collider removal.
- 200 mixed Squigs/Orks traversing a barrier with production separation enabled.
- Whole-body spawn clearance, unchanged clear positions, deterministic search,
  fully blocked failure, real spawner bookkeeping, and boss retry/uniqueness.
- Unchanged speed limits and Warboss 2000 HP / 5 armor / 40 speed.

Existing CI, spawner, F10, Warboss encounter/attack, Ork, Tier 1 contact damage,
and solid-terrain regressions also pass. The native gameplay preview exercises
Squigs and Orks moving around a real ruin.

## 200-enemy profiling

Windows/Godot 4.6.3, AMD RX 5700 XT, compatibility renderer, seed 741, 60 warmup
and 600 measured frames, upgraded weapons, approximately 197 active enemies.
Raw final results: `combat_obstacle_navigation_fast.json`. The earlier
`combat_obstacle_navigation.json` captures the initial unoptimized helper.

The open-area fast path reduced measured steering work from approximately
3.09 ms to 1.36 ms per rendered frame in these runs. The final run averaged
16.81 FPS (59.47 ms), with engine physics monitoring averaging 17.73 ms and
cleaning up to one node. The earlier pre-navigation run averaged 18.16 FPS
(55.08 ms), with physics monitoring at 17.65 ms. This feature adds work; it is
not an FPS optimization. Script profiling is enabled, timings are inclusive,
and real-time combat outcome/effect counts vary, so these single-run numbers
are observations rather than a controlled regression percentage.

The combat fixture starts in the clear origin area and reports no detour plans;
it measures the 200-enemy steady-state probe overhead. Actual detour traversal
at the full enemy cap is covered separately by the functional barrier test.
No full pathfinding is needed for the verified prototype scenarios.
