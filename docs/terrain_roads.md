# Connected battlefield roads

Visual edge blending is documented in [road_edge_blending.md](road_edge_blending.md); the 30% network generation described below is unchanged.

## Source and preparation

Found `assets/art/effects/terrain/roads/road.png`, **1536x1024 RGBA**. It is an irregularly arranged presentation sheet with genuine transparency (including faint background haze), three vertical straights, large bends, T/cross/Y junctions and broken fragments. It is not a ready-to-use tile atlas. The angled Y and small decorative round fragment are not used in the orthogonal network.

Original SHA256, verified after preparation and by the Godot test:
`1eae96eebc904c5b94cf81cbf1d10bea85698054c3da53eb3e904ff7981d4523`.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/prepare_roads.ps1` to reproduce the **15 reusable 256x256 transparent PNGs** under `assets/art/effects/terrain/roads/prepared/`. Preparation uses System.Drawing, no additional Python packages. The source is only read, never saved. No new artwork was generated.

The script extracts actual straight, NW bend, T, cross and broken-end artwork at source origins `(22,100)`, `(1272,192)`, `(140,407)`, `(644,523)` and `(528,800)`. The last crop is transparently padded outside the sheet. All crops retain native pixel size. Low-alpha presentation haze (<200) and disconnected islands belonging to neighboring pieces are removed offline. Retained RGB values are preserved. Copies of a 24px collar from the same source straight standardize joins. The four required connection directions are checked for continuous opaque silhouettes during preparation. Only exact 90-degree rotations create additional orientations; there is no interpolation, runtime cropping or runtime image processing.

Filenames encode **N=1, E=2, S=4, W=8**, added together:

| Pieces | Files |
|---|---|
| Four ends | `road_01`, `road_02`, `road_04`, `road_08` |
| Two straights | `road_05`, `road_10` |
| Four corners | `road_03`, `road_06`, `road_09`, `road_12` |
| Four T junctions | `road_07`, `road_11`, `road_13`, `road_14` |
| Cross | `road_15` |

All have `.png` extensions and shared lossless, non-mipmapped imports. The original source PNG is not loaded by the game.

## Generation and continuity

`TerrainRoads` uses 256px world cells and independent salted region RNG. The explicit chunk-network participation target is **30%**. A 16x16-cell (4096px) region has a derived **75.93975446%** chance of a compact lane cluster: a left-to-right lane with a variable vertical bend and a 55% chance of a crossing vertical branch. Branches always connect to the main lane. All endpoints lie inside their region. These are occasional broken battlefield networks, not an infinite city grid.

At the default 1024px chunk size, a region spans 4x4 chunks. Exact enumeration of the current route choices gives 4.86 participating chunks without a branch and 7.516 with one; weighting by the unchanged 55% branch chance gives 6.3208 of 16 chunks per active region. Therefore `PARTICIPATION_TARGET = 0.30`, `ACTIVE_REGION_CHUNK_FRACTION = 6.3208 / 16`, and `REGION_CHANCE = 0.30 / ACTIVE_REGION_CHUNK_FRACTION`. This targets 30% chunk participation across connected networks, rather than rolling for isolated roads in each chunk. Route shapes and all RNG draws/order are unchanged; increasing the region threshold only activates additional complete deterministic networks. Every chunk reconstructs the same small region path from its world coordinates, then selects its own cells. A cell's mask is calculated from its actual four neighbors, including cells beyond the chunk. Thus reciprocal chunk-edge connections are guaranteed regardless of load order or eviction. Region boundaries have no exits on either side, so they agree too. Negative coordinates use floor division, not truncation.

Layouts are local bounded dictionaries, discarded after generation; no growing world cache exists. No chunk-manager/prefetch/cache architecture was changed. Chunk sizes below 256px or not divisible by 256 omit roads safely.

`TerrainChunk` now contains Ground, Decorations, Roads, LargeProps. Roads are lightweight shared-texture sprites, at most 16 per 1024px chunk. Roads draw above ground and decorations, below large props and all combat. Large-prop z-order is unchanged. There are no collision/navigation nodes, speed/pathing/spawning effects or per-frame road callbacks. Roads now share an alpha-only edge-blend shader with offline-prepared data; see the blending report.

Ground/decor generation code, decoration exclusions and weights, tank rolls/positions and independent building rolls/positions are unchanged. No decoration RNG draw is removed and no decoration cell is suppressed. Opaque road artwork visually covers decorations underneath; surrounding decorations remain visible. Wrecks and ruins retain their placement and can overlap a road, rendering above it as abandoned obstacles; roads are not rerouted around them, and do not cut out entire cells around them, which would break continuity.

## Distribution and validation

`tests/terrain_roads_test.gd`: **40,000 coordinates**, x/y -100 through 99, covering 2,500 complete route regions.

- **12,087 chunks (30.2175%)** contain roads, against the explicit **30% target**.
- **46,345 road pieces**, occupying **7.24140625% of terrain cells**. The opaque road footprint covers less than the full tile area.
- **34,880 straight segments**, **3,090 curves**, **1,518 T-junctions**, **951 crossroads**, **5,906 end caps**.
- All 15 masks occur naturally. Counts by mask 1..15: `1038, 1915, 755, 1038, 14577, 791, 664, 1915, 784, 20303, 100, 760, 666, 88, 951`.
- **21,244 directed chunk-edge connections** checked (both directions count).
- Pixel-for-pixel matching seam checks for every compatible pair of prepared masks.
- Repeated layout equality, unaffected global RNG, valid cell bounds, all directions, negative coordinates, and whole-neighbor reciprocal ports pass.
- **256 actual chunk scenes** instantiated/reconfigured; no duplicate accumulation, shared sprite resources, one shared edge material and no processing/physics callbacks.
- **305,981 road checks** pass. The focused terrain regression suite is recorded in `docs/roads_target_regressions.json`, including ground/decor determinism, excluded decorations, unchanged 35% tanks and 25%-per-variant buildings. Existing 400-coordinate terrain baseline still matches. The original integration's 34-script functional regression evidence remains in `docs/roads_regressions.json`.

Machine-readable current distribution: `docs/roads_distribution.json`. The preceding 10,000-chunk sample measured 27.25% under the old 65% region activation rule; the current sample is larger and region-aligned, so those two observed percentages are not a paired sample comparison.

## Preview and performance

Rendered and inspected `docs/roads_overview.png` (49 natural chunks), `docs/roads_closeup.png` (nine natural chunks), `docs/roads_junction.png` (native-scale natural crossroad) and `docs/roads_pieces.png` (all 15 extracted variants). Blue lines are preview-only chunk boundaries. Routes cross chunk borders cleanly; bends, T/cross junctions and broken ends are visible with tanks, ruins and normal decorations. Large open terrain areas remain. The original art's recurring imperial markings are intentionally retained.

The current 30% target is benchmarked on the same rendered 48-transition route, 200 simulated enemies, Godot 4.6.3 Forward+ D3D12 / RX 5700 XT. The prior rule was measured immediately before the change; this is separate from the initial integration benchmark.

| Metric | Previous rule | Explicit 30% target |
|---|---:|---:|
| Normal frame mean | 16.662501ms | 16.662297ms |
| Normal measured FPS | 60.0150 | 60.0157 |
| Chunk update mean | 3.329021ms | 3.476479ms |
| Chunk update worst | 5.448ms | 4.463ms |
| Crossing p95 frame | 19.767ms | 19.041ms |
| Crossing worst frame | 21.202ms | 19.576ms |
| Prepared cache peak | 7 | 7 |
| Prefetch worst | 2.680ms | 1.823ms |
| Windows with road pieces | 18/48 | 48/48 |
| Peak active road pieces | 15 | 15 |

Mean chunk-update CPU increased by **0.147458ms (about 4.4%)**, with roads now present in all measured windows. Normal frame rate remained about 60 FPS, crossing frame timings stayed acceptable, and cache bounds were unchanged. This run shows no material streaming regression; timing fluctuations do not imply zero cost or guarantee other hardware. Both runs ended with 200 enemies and retained tanks/buildings throughout. Local ignored logs: `docs/roads_target_before.log`, `docs/roads_target_after.log`.

All **eight focused terrain regression scripts passed**. The existing preview was rendered and visually inspected: 49 natural chunks / 53 pieces in the overview, matching joins and open terrain preserved. Curve/junction/piece images were regenerated but remain byte-identical; only the overview image changed. The main-project 300-frame smoke run completed without runtime/import errors or warnings (`docs/roads_target_smoke.log`). No scene/structural changes required another editor validation in this follow-up.

## Files

- Modified production: `scripts/systems/terrain_chunk.gd`, `scenes/systems/terrain_chunk.tscn`.
- Added production: `scripts/systems/terrain_roads.gd` and its Godot UID.
- Added preparation: `tools/prepare_roads.ps1`.
- Added road assets: original user-supplied `road.png`, its Godot import metadata, 15 prepared PNGs and their import metadata. The source bytes were not modified.
- Modified tests: `tests/terrain_artwork_test.gd`, `tests/terrain_building_test.gd`, `tests/terrain_chunk_streaming_test.gd`, `tests/terrain_tank_test.gd` (dedicated road layer increases scene child count from three to four); `tests/terrain_streaming_performance_test.gd` (road counters only).
- Added tests/preview: `tests/terrain_roads_test.gd`, `tests/road_terrain_preview.gd` and their UIDs.
- Added documentation/evidence: this report, distribution/regression JSONs, four preview PNGs and their Godot import metadata.

No commit or push performed.

### Files changed for the 30% target follow-up

- `scripts/systems/terrain_roads.gd`: explicit target and derived region activation constant only.
- `tests/terrain_roads_test.gd`: 40,000-chunk region-aligned sample, target verification and grouped piece counters.
- `docs/roads_distribution.json`: refreshed distribution.
- `docs/roads_target_regressions.json`: focused terrain regression evidence.
- `docs/terrain_roads.md`: current target, calibration, counts and benchmark.
- `docs/roads_overview.png`: refreshed 49-chunk preview; other regenerated previews are unchanged.

No source/prepared road PNG, terrain generation, decoration, tank/building, scene, chunk manager, collision or gameplay code changed in this follow-up. No commit/push.
