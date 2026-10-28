# Terrain streaming performance report

Measured with Godot 4.6.3 on the current machine (AMD RX 5700 XT). Rendered runs use the project's D3D12 Forward+ renderer and 60 Hz presentation. Timing is diagnostic, not a cross-machine guarantee.

## Profile before implementation

Before changing generation, temporary `Time.get_ticks_usec()` instrumentation sampled 25 transitions: one long jump, then 24 diagonal moves. An uninstrumented run averaged **23.514 ms**, worst **41.216 ms**. The original approximately 25 ms report is consistent with this measurement. The first long jump loads nine chunks; steady diagonal transitions load five.

Fine-grained instrumentation adds overhead. Its mean total was 30.522 ms, worst 55.412 ms; these instrumented totals must not be compared directly with uninstrumented results. Stage totals divided by 25 transitions were:

| Original stage | Mean ms per transition |
| --- | ---: |
| Ground choice generation, including patch preparation | 17.078 |
| Ground TileMapLayer population | 2.639 |
| Decoration choice generation, including transforms | 4.521 |
| Decoration TileMapLayer population | 0.136 |
| Removal / detach / queue_free calls | 1.191 |
| Chunk scene instantiation | 0.150 |
| Shared TileSet setup calls on incoming chunks | 0.008 |
| Candidate classification, combined | 0.012 |
| Coordinate detection | 0.005 |
| Source image processing | 0 (no such calls) |

Separately sampling the unchanged detection/classification control flow over 10,000 iterations measured 0.000716 ms for coordinate detection, 0.002980 ms for unload-candidate determination, and 0.003190 ms for missing-candidate determination. These isolated timings exclude actual creation and removal.

**The bottleneck was ground choice generation**, especially the repeated nearest-region calculations. Decoration choice generation was next. TileSets were already shared static resources, and no source image processing occurred during transitions. Removal was comparatively small. Temporary instrumentation and its scripts were removed; production code has no new timing/logging output.

## Implementation

- Keep the exact region/nearest-center logic, thresholds, RNG seeds, RNG call order, iteration order and atlas coordinates.
- Separate generated values into `TerrainChunk.ChunkData`: ground atlas coordinates and decoration positions/source IDs/transforms.
- A small `TerrainChunk.Generation` state generates one complete row at a time. The synchronous path calls the same generator to completion; the incremental path yields between rows.
- Begin lookahead within **25% of a chunk edge: 256 px**. The threshold is exported as `prefetch_threshold`.
- Main-thread `_process` prepares data within an exported **1.5 ms budget per rendered frame**. It may exceed this slightly to finish one row or prepare a region table. No threads are used, and generation touches no Nodes, TileMapLayers or mutable resources.
- Prepare three incoming coordinates for an edge and up to seven for a corner, including the diagonal outer corner. Rebuild the candidate list only when its edge band or center changes. Completed coordinates are not repeatedly generated while standing still.
- A dictionary keyed by `Vector2i` caches data only, capped at **12 entries**, with at most one in-progress generator. Observed peak was seven completed entries. Reversals and teleports prune stale candidates/data.
- On crossing, consume prepared data and apply it to newly instantiated chunks. If a task is only partly finished, reuse its progress. Missing data is generated synchronously so rapid teleports never reveal empty terrain.
- Keep `set_cell` application: it already queues TileMap internals. Do not build undocumented binary TileMap buffers or call forced rebuilds per cell. Apply ground cells and decoration cells in their original respective insertion order.
- Continue sharing both original TileSets, atlas sources and imported textures. No runtime image cropping/resizing/texture building.
- Retain original immediate detachment and `queue_free` unloading. Neither removal nor cell application is staggered. Generation is staggered before the crossing instead.
- Cardinal moves still create three chunks and retain six; diagonal moves create five and retain four. The visible grid stays exactly nine chunks. There are no cached instantiated scenes.

## Measurements after implementation

`tests/terrain_streaming_performance_test.gd` runs 24 crossings: east, south, west, north, and all four diagonals, repeated three times. Each approach enters an actual edge band and runs the same budgeted preparation callback for 40 frames before crossing. It asserts completed incoming data, full ground coverage, retained overlapping nodes, shared TileSets, nine scene chunks and bounded cache size. The stress option keeps 200 nearby full-simulation enemies, initially 25% Orks, with existing AI, separation and player weapons enabled. It replenishes defeated enemies and repositions the test population after travel; production gameplay is unchanged.

| Run | Transition CPU mean / worst | Transition frame interval mean / worst | FPS |
| --- | ---: | ---: | ---: |
| Headless, prefetched, 24 mixed crossings | 2.901 / 3.635 ms | 9.191 / 11.735 ms | 145 |
| Rendered, prefetched, normal | 3.241 / 5.469 ms | 16.647 / 17.103 ms | 60 |
| Rendered, prefetched, 200 nearby mixed enemies | 2.938 / 3.953 ms | 17.031 / 20.887 ms | 60 |
| Rendered, same stress route, prefetch disabled (`--cold`) | 20.714 / 26.692 ms | 32.107 / 44.635 ms | approximately 60 between crossings |

The matching cold comparison uses the new synchronous fallback, not the old implementation. The original baseline route differs and includes an initial nine-chunk jump, so use the matched cold/prefetched stress rows for a controlled route comparison. The stress transition CPU mean fell about 86% with preparation available.

These are **streaming CPU times and complete measured intervals**, not interchangeable metrics. Prefetched streaming work stays below 6 ms in these rendered samples, but the full stress frame interval still occasionally exceeds 16 ms. The longest measured prefetch slice was 1.799 ms. Normal gameplay is presentation-limited near 60 FPS on this setup.

Cold startup and unanticipated teleports still perform synchronous generation and can retain roughly the previous spike. Normal movement at the existing 250 px/s gives about one second of lead time in the 256px band, much longer than the measured preparation requirement. No terrain is hidden or delayed to meet the timing target.

## Determinism and regressions

Before refactoring, serialized `tile_map_data` from 25 original chunks was captured. Its SHA-256 hashes are preserved in `tests/terrain_reference_hashes.json`. `tests/terrain_determinism_test.gd` compares actual rendered-layer data against the recorded hashes and compares synchronous/incremental generated arrays. Historical ground hashes are retained; decoration hashes were updated for the intentional eight-sprite pool change. Source IDs and every orientation bit are verified under the current configuration.

Passed:

- All 901 existing terrain streaming checks, including negative floor coordinates, movement across seams, unloading/freeing and surviving combat objects.
- Existing terrain artwork/variant/density/collision checks: unchanged ground distribution; current decoration density follows the eight-sprite 6.707767% target.
- New prefetch tests: threshold, idle data reuse over 1,000 updates, corners, reversals, consumption, partial tasks, teleport fallback, bounded cache.
- 24-crossing benchmarks: edge reuse, shared TileSets, complete coverage, no stale scene chunks and cache peak seven. Terrain memory is structurally bounded to nine live chunks, twelve prepared data objects and one partial task; unrelated combat effects/pickups may have their own lifetime.
- Existing enemy spawner (3,246), Ork (100,147), XP (50), Knife (127), Bolter splash (41) and Ultimate (121) checks.
- Final editor/parser, standalone scene and rendered main-scene verification without debugger errors.

No probability, asset, atlas, chunk/tile dimensions, active radius, collision, player, enemy, weapon, XP or other gameplay behavior changed.

## Files

Production changes: `scripts/systems/chunk_manager.gd` and `scripts/systems/terrain_chunk.gd`. No scenes were modified.

Added: `tests/terrain_determinism_test.gd`, `tests/terrain_reference_hashes.json`, `tests/terrain_prefetch_test.gd`, `tests/terrain_streaming_performance_test.gd`, their Godot UID metadata, and this report. Updated the terrain documentation to refer to this optimization. Original source-art files and prepared atlas were not edited.

Reproduce:

```powershell
Godot_console.exe --headless --path . --script tests/terrain_determinism_test.gd
Godot_console.exe --headless --path . --script tests/terrain_prefetch_test.gd
Godot_console.exe --path . --script tests/terrain_streaming_performance_test.gd
Godot_console.exe --path . --script tests/terrain_streaming_performance_test.gd -- --stress
Godot_console.exe --path . --script tests/terrain_streaming_performance_test.gd -- --stress --cold
```
