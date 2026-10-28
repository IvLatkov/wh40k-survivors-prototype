# Battlefield terrain implementation

## Inspected source assets

The supplied ground directory is `assets/art/effects/terrain/battlefield_biome/`, not `battlefield_biom/`. No source assets were renamed or overwritten.

| Folder | Exact PNG filename | Dimensions | Structure / use |
| --- | --- | --- | --- |
| battlefield_biome | ChatGPT Image Oct 21, 2026, 07_17_37 PM-1.png | 1536 x 1024 | Six ground panels, 3 columns x 2 rows, 512 x 512 each. Dirt, ash, rocky earth and two cracked-earth variants. Used to prepare the ground atlas. |
| decorations | ChatGPT Image Oct 21, 2026, 07_17_38 PM-2.png | 1536 x 1024 | Six-object presentation sheet: skull, bones, blood, rocks, crater, industrial scrap. Opaque dark background with glows, not clean transparent sprites; excluded from runtime. |
| decorations | dark_dirt_ash_tile.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_2.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_3.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_4.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_5.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_6.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_7.png | 48 x 48 | Single transparent sprite; excluded from runtime |
| decorations | dark_dirt_ash_tile_8.png | 48 x 48 | Single transparent sprite; excluded from runtime |
| decorations | dark_dirt_ash_tile_9.png | 48 x 48 | Single transparent sprite; excluded from runtime |
| decorations | dark_dirt_ash_tile_10.png | 48 x 48 | Single transparent sprite; excluded from runtime |
| decorations | dark_dirt_ash_tile_11.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_12.png | 48 x 48 | Single transparent sprite |
| decorations | dark_dirt_ash_tile_13.png | 48 x 48 | Single transparent sprite; excluded from runtime |

The 48px sprites visually provide rubble, rock clusters, fragments, stained ground, ash, craters and scrap. Their generic filenames do not reliably identify specific objects; runtime selection explicitly uses these inspected files, rather than inferring objects from names. The skull on the large presentation sheet is not separately extracted.

## Ground preparation and TileSets

The source is mathematically divisible by 32, but blindly slicing it includes visible panel divider lines and does not yield a native, seamless 32px terrain atlas. Its useful layout is six 512px panels. `tools/prepare_terrain_atlas.ps1` samples the inner 496 x 496 area of each panel (8px inset), using nearest-neighbor sampling to produce six 128 x 128 panels laid horizontally in `battlefield_biome/prepared/battlefield_ground_atlas.png` (768 x 128). This removes the presentation dividers and preserves aspect ratio. The original artwork is unchanged. These textures are not authored with terrain edge transitions; some repetition and abrupt texture transitions remain possible.

One shared runtime ground TileSet uses 32 x 32 atlas regions (24 columns x 4 rows, 96 regions). Global cell coordinates select the appropriate subregion of each 128px panel; negative coordinates use positive modulo. A second shared runtime TileSet has eight atlas sources, each using the complete native 48 x 48 decoration sprite on a 32px placement grid. Neither TileSet has physics or navigation layers. Import metadata uses lossless textures with mipmaps disabled; the terrain root explicitly enforces nearest filtering.

## Streaming and generation

The existing `ChunkManager` and `chunk_manager.tscn` are reused without modification. Chunk size remains 1024 x 1024, with 32 x 32 ground cells. Active radius is 1: nine chunks in a 3 x 3 grid. Streaming occurs only when the player changes floor-based chunk coordinate. Distant chunks detach and free; gameplay objects retain their existing parents.

The placeholder grid drawing in `TerrainChunk` is replaced with Ground and Decorations TileMapLayers: two rendering nodes per chunk, eighteen for the full active grid. Ground inherits z=-10; decorations render at z=-9; XP at its existing -1 and combat at its existing order remain above scenery. Decorations retain native size with flips and transpose (the eight orthogonal orientations), with no arbitrary angles or fractional scaling. No scenery collisions or pathfinding obstacles exist.

Chunk data is now prefetched within 256px of boundaries under a 1.5ms frame budget, with a twelve-entry data-only cache. See [terrain_streaming_performance.md](terrain_streaming_performance.md) for the current architecture, exact-output verification and measurements.

Ground uses deterministic jittered regional patches approximately five cells across. Each world region seeds a private RNG with `hash(region_coordinate)`. A cell uses its nearest regional center, including neighbors across chunk boundaries. Region data is calculated once per chunk, rather than reseeding per tile. Ground category probabilities apply to patch centers; measured area proportions fluctuate locally:

- Common dirt: 65% (top-left panel 40%, bottom-left 25%).
- Secondary dirt/ash: 22% (top-middle).
- Cracks: 10% (bottom-middle 7%, bottom-right 3%).
- Rocky special ground: 3% (top-right).

Decorations use a separate local RNG seeded with `hash(chunk_coordinate)`. Cell iteration and orientation choices are stable; no global random stream is consumed. Unloading/reloading reconstructs identical ground and decoration tile data.

| Decoration file | Per-cell probability |
| --- | ---: |
| dark_dirt_ash_tile.png | 0.547573% |
| dark_dirt_ash_tile_2.png | 0.547573% |
| dark_dirt_ash_tile_3.png | 0.684466% |
| dark_dirt_ash_tile_4.png | 2.737864% |
| dark_dirt_ash_tile_5.png | 0.410680% |
| dark_dirt_ash_tile_6.png | 0.410680% |
| dark_dirt_ash_tile_11.png | 0.684466% |
| dark_dirt_ash_tile_12.png | 0.684466% |
| Total | 6.707767% |

Sprites with suffixes 7, 8, 9, 10 and 13 remain on disk but are excluded from runtime arrays, TileSets and generation. The eight remaining per-cell probabilities are unchanged from the previous pool, using the existing 0.0705 / 0.0515 scale factor. Removing the final entry lowers the total to 6.70776699%, without increasing any remaining probability or leaving dead ranges.

This averages about 69 decorations per chunk; all are batched TileMap cells, not individual Sprite2D nodes.

## Files changed for this work

- `scripts/systems/terrain_chunk.gd`: replaces placeholder drawing with ground/scenery generation and shared TileSets.
- `scenes/systems/terrain_chunk.tscn`: adds Ground and Decorations layers.
- `tests/terrain_chunk_streaming_test.gd`: updates the old zero-child assertion for two terrain layers and verifies regenerated tile data, retaining movement/combat/lifecycle checks.
- `tests/terrain_artwork_test.gd`: validates artwork, tile coverage, variants, clustering, density and collision settings.
- `tests/terrain_preview.gd`: runs the actual main scene for visual QA; optional `-- --stress` spawns 200 enemies for a short rendered smoke test.
- `tools/prepare_terrain_atlas.ps1`, the prepared PNG and its Godot import metadata.
- Godot-generated import metadata beside the thirteen previously unimported decoration sprites.
- This report and preview images under `tests/`.

No player, enemy, weapon, XP, spawner, spatial grid, ultimate or main-scene code was edited for this task. Existing unrelated working-tree changes were preserved.

## Verification (Godot 4.6.3)

Editor import/parser check, standalone terrain checks, main-scene rendered preview and rendered stress preview complete without Godot errors after allowing Godot access to its log/settings folders. The restricted sandbox initially prevented those writes; the unrestricted reruns resolved those environment errors.

- Terrain streaming: 901 checks passed, including floor boundaries in all directions, no regeneration within a chunk, retained neighbors, unloading/freeing, identical regenerated ground/decorations, existing movement across seams and preservation of combat objects and spatial-grid registration.
- Artwork: 25 chunks / 25,600 ground cells, all six variants, observed decoration density 6.558594% under the current 6.707767% target, matching horizontal neighbors 80.27% of total cells (excluding right-edge comparisons).
- Enemy spawning: 3,246 checks passed.
- Ork Boy: 100,147 checks passed.
- XP progression: 50 checks passed.
- Directional Knife: 127 checks passed.
- Dynamic Bolter splash: 41 checks passed.
- Tier 1 contact damage: 100,621 checks passed.
- Original synchronous baseline: approximately 25ms per diagonal transition. This remains relevant to cold teleports; prefetched normal crossings now average approximately 3ms. See the streaming performance report for matched timings and full-frame limits.
- Compatibility-renderer stress smoke test: 200 spawned enemies, 196 surviving after three seconds, nine chunks, approximately 50 FPS during a concurrent streaming test. This is a short smoke test, not a controlled before/after benchmark or guarantee for sustained loads.

- Project-default D3D12 Forward+ rendered stress rerun: 200 spawned enemies, 198 surviving after three seconds, nine chunks, 60 FPS; no debugger errors. This check ran independently of the headless streaming test.

## Current runtime pool

Only Ground and Decorations are instantiated by TerrainChunk. The eight active decoration sprites are the base file and suffixes 2, 3, 4, 5, 6, 11 and 12. Original source PNGs remain untouched. Prefetching, its bounded data cache, shared TileSets, edge-only streaming, negative floor coordinates and collision rules are unchanged.

The historical ground reference hashes remain unchanged. Decoration reference hashes were regenerated for the intentional pool change; direct generation, incremental preparation and chunk reloads must reproduce the current output exactly. Normal and stress previews contain only the two terrain layers and current allowed sprites.

Current-pool verification: all 901 streaming checks, original-ground/current-decoration hash checks, prefetch/cache tests, artwork tests and gameplay regressions pass. Both refreshed rendered previews run at approximately 60 FPS without debugger errors.
