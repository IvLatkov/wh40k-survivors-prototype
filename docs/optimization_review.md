# Terrain and combat optimization measurements

## Changes

- Cap Godot's imports of the three tree textures at 256x256. Preserve original
  1254x1254 PNG files, 160x160 world footprints, and trunk collision dimensions.
  Imported RGBA pixel data drops from 18,870,192 bytes to 786,432 bytes (95.8%).
- Retain the current chunk's road layout for tree clearance checks instead of
  generating it twice. Pass the existing tank position into ruin placement.
  Keep the standalone placement helpers working and their seeded output exact.
- Recycle typed enemy-grid buckets across rebuilds. Keep live positions,
  candidate ordering, and separation summation unchanged. Idle buckets remain
  owned by the grid and are bounded by its historical occupied-cell count.
- Add an optional benchmark frame count and engine process/physics timing,
  draw-call, and texture-memory measurements.

## Measurements

Command for each comparison, with labels `optimization_before` and
`optimization_after` respectively:

```powershell
godot --path . --rendering-method gl_compatibility --audio-driver WASAPI --script tests/combat_performance_test.gd -- --frames=600 --label=optimization_after
```

Both runs used Godot 4.6.3, Windows, the compatibility renderer on an AMD RX 5700
XT, 60 warmup frames, 600 measured frames, seed 741, approximately 197 active
enemies, and upgraded player weapons. The benchmark maintains the enemy
population, exercises effects/pickups, and enables inclusive script profiling.

| Metric | Before | After |
| --- | ---: | ---: |
| Average frame interval | 54.68 ms | 55.08 ms |
| Average FPS | 18.29 | 18.16 |
| 95th percentile frame interval | 63.17 ms | 64.50 ms |
| Grid rebuild CPU per rendered frame | 0.529 ms | 0.536 ms |
| Separation CPU per rendered frame | 6.587 ms | 6.418 ms |
| Projectile movement CPU per rendered frame | 0.112 ms | 0.116 ms |
| Impact CPU per rendered frame | 0.282 ms | 0.319 ms |
| Engine texture-memory monitor | 90,601,349 bytes | 66,497,705 bytes |
| Nodes after full cleanup | 1 | 1 |

There is no demonstrated FPS improvement in this pair of runs. The definite
benefits are reduced tree pixel storage, eliminated duplicate terrain planning,
and reused grid buckets. Grid reuse reduced allocations but did not demonstrate
a timing improvement here. Engine texture memory covers all scene textures;
its full change should not be attributed solely to trees.

These are short debug/compatibility-renderer observations, not release-build
targets or statistically established improvements. Real-time physics scheduling
changes combat outcomes and effect counts between runs, even with the same
seed. Inclusive script timings overlap and must not be summed. Engine timing
monitors do not establish a GPU bottleneck by themselves.

## Pooling decision

Projectile movement and the inclusive impact path cost much less than enemy
movement/separation in these measurements. The impact path already includes
fork lookup/creation and explosion creation. No projectile/explosion pool was
added: the earlier recommendation was conditional on allocation spikes being a
material bottleneck, which this profile did not establish. Existing blood and
damage-number pools remain in use. Further combat optimization should measure
enemy separation and render costs before adding more object-lifecycle code.

## Verification

- CI suite: 6/6 passing.
- Exact separation and grid reuse: 2,622 checks passing.
- Tree texture sizes/source preservation, prepared-road equivalence, placement
  density, and streaming: 16,627 checks passing.
- Static obstacle and actor movement: 201 checks passing.
- Building baseline: 99,467 checks passing, with terrain/tank baselines unchanged.
- Existing streaming suite: 901 checks passing.
- Editor import and native game preview of all three resized tree variants pass.
- Known immediate-exit headless audio resource warnings remain unrelated to
  these changes; native audio test runs and benchmark cleanup complete.

Raw results: `combat_optimization_before.json` and
`combat_optimization_after.json` alongside this report.
