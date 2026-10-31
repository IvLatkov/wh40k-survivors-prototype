# Road edge blending

## Inspection and method

Roads use shared 256x256 PNGs on lightweight Sprite2D nodes. The Roads node has local z=1 under terrain z=-10 (effective **-9**), above ground and decorations, below large props/combat. Textures use nearest filtering, lossless imports and no mipmaps. Existing road artwork already contains an irregular soil/rubble border, but the extraction's retained pixels are binary alpha (opaque or transparent), giving the soil a hard cutout outline.

All original/prepared road-art PNGs are **byte-identical**. There is no new road artwork, global opacity reduction, repainting, RGB/color correction or blur. The visual change uses one **shared alpha-only ShaderMaterial** and one shared **1280x768 edge-mask data atlas**, with a 16px inward transition through the existing dirt fringe. It adds no halo outside the existing art footprint.

`tools/prepare_road_blend_masks.ps1` reads the 15 existing prepared road PNGs offline, identifies transparency connected to the exterior (excluding enclosed internal cracks), computes a chamfer distance from that contour and bakes a smooth 16px opacity ramp. Existing broken silhouettes make the transition irregular. Only closed sprite boundaries count as exterior; open ports continue into the neighboring road and are not faded across that border. All compatible ports are checked for exactly matching blend weights before saving the atlas.

Reproduce with `powershell -NoProfile -ExecutionPolicy Bypass -File tools/prepare_road_blend_masks.ps1`. The atlas reproduces byte-for-byte; the tool is never invoked by the game. Original extraction tooling remains unchanged.

`assets/shaders/road_edge_blend.gdshader` multiplies **only COLOR.a** by the corresponding mask value. RGB is untouched. The input COLOR already contains the sprite texture/modulation in Godot's [CanvasItem fragment shader](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/canvas_item_shader.html). The shader adds one nearest-filtered mask lookup, no neighbor sampling, screen reads, TIME, particles, per-frame parameter updates or runtime mask/image generation. Every road shares `road_edge_blend.tres`; one scalar instance parameter selects its mask. There are no per-piece material copies or additional terrain nodes.

Road-core mask values are exactly 1.0, so core opacity, color, cracks and markings remain unchanged. Only the outer soil transition becomes translucent. Ground, ash and existing clutter can show through it naturally. Decoration placement, distribution, RNG and rendering order are unchanged; the opaque road center continues to cover clutter underneath.

## Before/after previews

`tests/road_terrain_preview.gd -- --unblended` reproduces the old appearance using the same natural world, disabling only the preview sprites' material. The default mode renders blended roads. Same coordinates, topology, props, camera and ground in both modes.

| View | Before | After |
|---|---|---|
| Multi-chunk overview | [Before](roads_overview_blend_before.png) | [After](roads_overview.png) |
| Straight, curves and ruins | [Before](roads_closeup_blend_before.png) | [After](roads_closeup.png) |
| Native-scale crossroad and border | [Before](roads_junction_blend_before.png) | [After](roads_junction.png) |
| Native-scale T, tank and building | [Before](roads_tjunction_blend_before.png) | [After](roads_tjunction.png) |
| All fifteen pieces | [Before](roads_pieces_blend_before.png) | [After](roads_pieces.png) |

All previews were rendered and visually inspected. The former brown cutout contour now transitions into the dirt/ash beneath it, while center surfaces and markings stay crisp. No rectangular fade, broad halo or chunk-border gap was observed. The fringe is intentionally subtle and confined to 16 native pixels; it does not darken or soften the whole road. No road density/topology/prop position changes appear between comparison views.

## Verification

- **35/35 functional regression scripts pass**, including road/terrain determinism, decoration exclusions/distribution, tanks, buildings, streaming/prefetch, combat and progression. Evidence: `road_blending_regressions.json`.
- Rendered `road_edge_blend_test.gd`: **1,015,824 checks** across all 15 pieces. **485,660 opaque core pixels** remain exactly equal before/after on the GPU; **124,312 fringe pixels** receive the expected partial alpha. Transparent pixels remain transparent; no outside halo. Evidence: `road_blending_validation.json`.
- All east/west and north/south port blend weights match pixel-for-pixel; existing road seam texels also still match.
- 40,000-chunk distribution remains **12,087 participating / 30.2175%** against the unchanged 30% target: **34,880 straights, 3,090 curves, 1,518 T-junctions, 951 crossroads, 5,906 ends**. Entire distribution JSON equals the before-blending snapshot, not just the participation percentage.
- **21,244 directed cross-border connections** pass; road generation methods are source-identical, including negative-coordinate handling and piece selection. The only runtime additions attach the shared material and select its mask.
- Original source PNG and all 15 prepared road PNGs compare byte-for-byte with Git HEAD. Ground, decorations, tank/building generators, chunk manager, terrain scene and z-order are unchanged. No collision, navigation, movement or gameplay changes.

## Performance

Same rendered 48-transition natural road route, 200 enemies, Godot 4.6.3 Forward+ D3D12 / Radeon RX 5700 XT:

| Metric | Before blending | After blending |
|---|---:|---:|
| Mean normal frame | 16.661666ms | 16.661315ms |
| Normal FPS | 60.0180 | 60.0193 |
| Mean chunk update | 3.464646ms | 3.456083ms |
| Worst chunk update | 4.631ms | 5.469ms |
| Crossing p95 frame | 19.566ms | 19.382ms |
| Worst crossing frame | 20.023ms | 19.874ms |
| Prefetch worst | 1.815ms | 1.760ms |
| Prepared cache peak | 7 | 7 |

Roads were present in **48/48** windows in both runs, peaking at **15 pieces** across nine chunks, with tanks/buildings present throughout (peaks 3/6). Mean chunk-update difference is **-0.008563ms**, while the worst CPU sample increased 0.838ms; frame timings stayed near 60 FPS. This measured run shows no material streaming regression. It does not isolate GPU instruction cost or guarantee timings on other hardware. Added GPU work is one nearest mask lookup per road fragment; storage is one bounded shared 1280x768 atlas, with no extra nodes per road or per-instance material copies.

Rendered editor validation and the 300-frame main-project smoke run completed without debugger/import/shader errors or shutdown warnings. Local ignored logs: `docs/roads_blend_before.log`, `docs/roads_blend_after.log`, `docs/roads_blend_editor.log`, `docs/roads_blend_smoke.log`.

## Files changed for blending

- `scripts/systems/terrain_roads.gd`: shared material preload and per-sprite mask selection; the preceding uncommitted explicit-30% target remains intact.
- `assets/shaders/road_edge_blend.gdshader` (and UID), `assets/shaders/road_edge_blend.tres`: shared alpha-only shader/material.
- `assets/art/effects/terrain/roads/prepared/road_edge_masks.png` and `.import`: new derived mask DATA; source/prepared road ART is unchanged.
- `tools/prepare_road_blend_masks.ps1`: reproducible offline data preparation and port validation.
- `tests/road_edge_blend_test.gd` (and UID): static seam/data tests and actual rendered core/alpha comparison.
- `tests/terrain_roads_test.gd`: shared-material assertion; its preceding 30%-target/sample-size changes remain intact.
- `tests/road_terrain_preview.gd`: shared-material gallery, reproducible unblended mode and natural T-junction view.
- `docs/road_edge_blending.md`, update to `docs/terrain_roads.md`, validation/regression JSONs and `docs/roads_blend_distribution_before.json`.
- Four refreshed existing previews (`roads_overview`, `roads_closeup`, `roads_junction`, `roads_pieces`), new `roads_tjunction`, and five `*_blend_before` comparison PNGs, with beside-file Godot imports.

The preceding uncommitted 30%-target report/distribution/overview/regression changes are preserved. No commit or push performed.
