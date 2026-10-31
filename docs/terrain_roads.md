# Connected battlefield roads

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

`TerrainRoads` uses 256px world cells and independent salted region RNG. A 16x16-cell (4096px) region has a 65% chance of a compact lane cluster: a left-to-right lane with a variable vertical bend and a 55% chance of a crossing vertical branch. Branches always connect to the main lane. All endpoints lie inside their region. These are occasional broken battlefield networks, not an infinite city grid.

At the default 1024px chunk size, a region spans 4x4 chunks. Every chunk reconstructs the same small region path from its world coordinates, then selects its own cells. A cell's mask is calculated from its actual four neighbors, including cells beyond the chunk. Thus reciprocal chunk-edge connections are guaranteed regardless of load order or eviction. Region boundaries have no exits on either side, so they agree too. Negative coordinates use floor division, not truncation.

Layouts are local bounded dictionaries, discarded after generation; no growing world cache exists. No chunk-manager/prefetch/cache architecture was changed. Chunk sizes below 256px or not divisible by 256 omit roads safely.

`TerrainChunk` now contains Ground, Decorations, Roads, LargeProps. Roads are lightweight shared-texture sprites, at most 16 per 1024px chunk. Roads draw above ground and decorations, below large props and all combat. Large-prop z-order is unchanged. There are no collision/navigation nodes, speed/pathing/spawning effects, shaders or per-frame road callbacks.

Ground/decor generation code, decoration exclusions and weights, tank rolls/positions and independent building rolls/positions are unchanged. No decoration RNG draw is removed and no decoration cell is suppressed. Opaque road artwork visually covers decorations underneath; surrounding decorations remain visible. Wrecks and ruins retain their placement and can overlap a road, rendering above it as abandoned obstacles; roads are not rerouted around them, and do not cut out entire cells around them, which would break continuity.

## Distribution and validation

`tests/terrain_roads_test.gd`: **10,000 coordinates**, x/y -50 through 49.

- **2,725 chunks (27.25%)** contain roads.
- **10,471 road pieces**, occupying **6.544375% of terrain cells**. The opaque road footprint covers less than the full tile area.
- All 15 masks occur naturally. Counts by mask 1..15: `237, 429, 171, 241, 3291, 174, 173, 430, 171, 4540, 23, 172, 177, 24, 218`.
- **4,840 directed chunk-edge connections** checked (both directions count).
- Pixel-for-pixel matching seam checks for every compatible pair of prepared masks.
- Repeated layout equality, unaffected global RNG, valid cell bounds, all directions, negative coordinates, and whole-neighbor reciprocal ports pass.
- **256 actual chunk scenes** instantiated/reconfigured; no duplicate accumulation, shared sprite resources, no material or processing/physics callbacks.
- **96,638 road checks** pass. All **34 functional regression scripts** pass, including ground/decor determinism, excluded decorations, 35% tanks and 25%-per-variant buildings. Existing 400-coordinate terrain baseline still matches.

Machine-readable distribution and regression outputs: `docs/roads_distribution.json`, `docs/roads_regressions.json`.

## Preview and performance

Rendered and inspected `docs/roads_overview.png` (49 natural chunks, 50 road pieces), `docs/roads_closeup.png` (nine natural chunks, 26 pieces), `docs/roads_junction.png` (native-scale natural crossroad) and `docs/roads_pieces.png` (all 15 extracted variants). Blue lines are preview-only chunk boundaries. Routes cross chunk borders cleanly; bends, T/cross junctions and broken ends are visible with tanks, ruins and normal decorations. Large open terrain areas remain. The original art's recurring imperial markings are intentionally retained.

Same rendered 48-transition route, 200 simulated enemies, Godot 4.6.3 Forward+ D3D12 / RX 5700 XT:

| Metric | Before roads | With roads |
|---|---:|---:|
| Normal frame mean | 16.657667ms | 16.661694ms |
| Normal measured FPS | 60.0324 | 60.0179 |
| Chunk update mean | 3.371979ms | 3.398250ms |
| Chunk update worst | 6.620ms | 5.408ms |
| Crossing p95 frame | 19.366ms | 19.909ms |
| Crossing worst frame | 31.468ms | 21.674ms |
| Prepared cache peak | 7 | 7 |
| Prefetch worst | 1.836ms | 1.740ms |

Roads were present in **18/48** measured active windows, peaking at **15 pieces across the nine loaded chunks**. Tanks/buildings remained active in 48/48 windows, peaks 3/6. Mean chunk-update difference is **+0.026271ms**, within run-to-run timing variation. This sample shows no material streaming regression; it does not claim zero cost or guarantee every frame on other hardware. Logs are locally retained as ignored `docs/roads_performance_before.log` and `docs/roads_performance_after.log`.

Final rendered editor import/parser validation (120 frames) and main-project smoke run (300 frames) completed successfully, without debugger/import errors or shutdown warnings.

## Files

- Modified production: `scripts/systems/terrain_chunk.gd`, `scenes/systems/terrain_chunk.tscn`.
- Added production: `scripts/systems/terrain_roads.gd` and its Godot UID.
- Added preparation: `tools/prepare_roads.ps1`.
- Added road assets: original user-supplied `road.png`, its Godot import metadata, 15 prepared PNGs and their import metadata. The source bytes were not modified.
- Modified tests: `tests/terrain_artwork_test.gd`, `tests/terrain_building_test.gd`, `tests/terrain_chunk_streaming_test.gd`, `tests/terrain_tank_test.gd` (dedicated road layer increases scene child count from three to four); `tests/terrain_streaming_performance_test.gd` (road counters only).
- Added tests/preview: `tests/terrain_roads_test.gd`, `tests/road_terrain_preview.gd` and their UIDs.
- Added documentation/evidence: this report, distribution/regression JSONs, four preview PNGs and their Godot import metadata.

No commit or push performed.
