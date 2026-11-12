# Tree sprite generation

Generated with the built-in image generation tool. Transparent PNG source assets
are saved in `assets/art/terrain/trees/`. Original generated files were preserved.

The sprites are now used by `TerrainTrees` when terrain chunks populate their
large props. Each fixed 3x2-chunk region selects two or three distinct tree
chunks; each selected chunk tries up to 64 safe positions. Conflicting chunks
may remain empty. All three variants share a 160x160 visual footprint, nearest
filtering, and the existing prop layer below combatants. Trees now have solid
trunk/root circles; their branches remain visually overlapping and walkable.
Tanks and ruins have cached convex collision outlines. All use the dedicated
terrain obstacle layer (32), scanned by the player, Squigs, Orks, and Warboss.
Roads, base ground, and small ground decorations have no collision. Collider
nodes belong to the prop sprites, so chunk unload and reconfigure remove them
automatically. Projectile and pickup collision masks are unchanged.
Placement clears the starting area's 300px radius, keeps 48px from road cells,
64px from tank/ruin footprints, and 96px from chunk edges. Independent seeded
RNG preserves gameplay RNG and existing ground, roads, tanks, and ruins.

A 2,400-chunk sample placed 950 trees: 2.375 per six chunks. Tests cover density,
all variants, safety bounds, RNG isolation, reconfiguration, and streamed return.

## olive_tree.png

Use case: game sprite asset for an existing Godot top-down grimdark sci-fi survivor game. Asset: ONE isolated tree sprite, genuinely transparent background. Art direction: hand-placed 16-bit pixel art matching muted dark brown and ash-grey ruined battlefield sprites, crisp nearest-neighbor pixel clusters, restrained readable detail, no photorealism, no smooth painterly gradients, no vector outlines. Camera: fixed elevated three-quarter top-down game view, looking down about 45 degrees, parallel projection, no horizon. Light from upper left. Entire tree including trunk, branches and roots visible, centered, comfortably inside frame. Clear silhouette, subtle shading; bark charcoal brown with desaturated grey highlights. Output square PNG with alpha. No labels, text, frame, watermark, ground tile, surrounding scenery, floating debris, or opaque backdrop. Design should read well when displayed about 90-150 pixels tall beside pixel-art gothic ruins. Primary request: A battered but living medium tree for a ruined battlefield. Asymmetric sparse rounded canopy of dusty olive and dark sage leaves in chunky pixel clusters, visible gnarled trunk and roots below, several exposed branches; somber subdued colors, no bright green. One single tree only.

## dead_tree.png

Use case: game sprite asset for an existing Godot top-down grimdark sci-fi survivor game. Asset: ONE isolated tree sprite, genuinely transparent background. Art direction: hand-placed 16-bit pixel art matching muted dark brown and ash-grey ruined battlefield sprites, crisp nearest-neighbor pixel clusters, restrained readable detail, no photorealism, no smooth painterly gradients, no vector outlines. Camera: fixed elevated three-quarter top-down game view, looking down about 45 degrees, parallel projection, no horizon. Light from upper left. Entire tree including trunk, branches and roots visible, centered, comfortably inside frame. Clear silhouette, subtle shading; bark charcoal brown with desaturated grey highlights. Output square PNG with alpha. No labels, text, frame, watermark, ground tile, surrounding scenery, floating debris, or opaque backdrop. Design should read well when displayed about 90-150 pixels tall beside pixel-art gothic ruins. Primary request: A medium dead leafless tree, twisted dark trunk splitting into irregular skeletal branches with broken tips and a few exposed roots. Weathered ash-grey bark over brown core, dramatic but natural branching silhouette. No leaves, no skulls, no faces, no supernatural glow. One single tree only.

## blasted_tree.png

Use case: game sprite asset for an existing Godot top-down grimdark sci-fi survivor game. Asset: ONE isolated tree sprite, genuinely transparent background. Art direction: hand-placed 16-bit pixel art matching muted dark brown and ash-grey ruined battlefield sprites, crisp nearest-neighbor pixel clusters, restrained readable detail, no photorealism, no smooth painterly gradients, no vector outlines. Camera: fixed elevated three-quarter top-down game view, looking down about 45 degrees, parallel projection, no horizon. Light from upper left. Entire tree including trunk, branches and roots visible, centered, comfortably inside frame. Clear silhouette, subtle shading; bark charcoal brown with desaturated grey highlights. Output square PNG with alpha. No labels, text, frame, watermark, ground tile, surrounding scenery, floating debris, or opaque backdrop. Design should read well when displayed about 90-150 pixels tall beside pixel-art gothic ruins. Primary request: A short war-blasted dead tree with a thick jagged broken crown, two snapped side limbs, splintered brown heartwood visible inside charred grey bark, and a compact rooted base. Visibly distinct shorter silhouette than a full tree. No flames, no smoke, no glow, no machinery. One single tree only.

