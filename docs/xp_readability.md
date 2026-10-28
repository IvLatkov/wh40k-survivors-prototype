# XP skull readability polish

Visual-only changes, validated in Godot 4.6.3 with the project D3D12 Forward+
renderer. Original PNGs, reward resources, enemy drops, combat and terrain are
unchanged. LOW/MID/HIGH remain 1/5/15 XP; BOSS remains four 25-XP skulls (100 total).

## Scene and rendering

```
XPPickup (Area2D, unchanged gameplay position/collision, z=-1)
??? Shadow (Sprite2D, relative z=-1, effective z=-2)
??? VisualRoot (Node2D, existing bob position)
?   ??? Visual (Sprite2D, base scale 1.12)
??? CollisionShape2D (original radius 8)
```

The old sprite scale was 1.0. Its new base scale is **1.12**, with no root or
collision scaling. `XPPickup.visual` remains the public sprite reference.
Only its internal node path changes. The existing sine/ease tween still moves
between +/-2px in 1.2s, with the same randomized phase and exactly the same global
RNG call. As before, magnetization stops the bob and target loss restarts it.
The shadow remains at (0,5), rather than bobbing with the skull.

`xp_outline.gdshader` expands the render quad by two source pixels to avoid clipping
wing tips. It preserves the original sampled skull color, adding a crisp **one
source-pixel colored outline** (about 1.12 screen px at native zoom), with a faint
**two-source-pixel dark outer keyline** (about 2.24px) for ash/rock contrast. There
is no blurred halo, light or particle effect. The fixed kernel uses 13 texture
samples. UV bounds are explicitly masked to avoid edge smearing. Nearest filtering
is inherited from the pickup root; all four existing imports retain lossless
compression and disabled mipmaps. Scaling/pulsing rasterizes in nearest-filtered
pixel steps; fractional scale cannot guarantee completely shimmer-free rasterization.
No gameplay position is rounded or snapped to conceal that tradeoff.

| Tier | Shared outline color | Normal opacity |
| --- | --- | ---: |
| LOW | Pale silver (0.85, 0.90, 1.00) | 0.65 |
| MID | Light cyan (0.40, 0.80, 1.00) | 0.75 |
| HIGH | Violet (0.75, 0.50, 1.00) | 0.80 |
| BOSS | Warm gold (1.00, 0.72, 0.28) | 0.85 |

Four preloaded ShaderMaterials share one Shader. No materials are duplicated per
pickup. Instance uniforms carry phase and magnet strength. A 1.6s GPU sine scales
explicit base vertices from 0.97 to 1.03, so the effective skull scale ranges from
1.0864 to 1.1536. Phase derives from instance ID, without consuming gameplay RNG.
There is no extra pulse Tween, Timer, idle `_process` or per-frame uniform update.
Magnetization changes only that instance's outline multiplier from 1.0 to **1.2**
(alpha clamped); target loss resets it. Shared materials are never mutated for this.

The shared shadow is a 16x8 radial GradientTexture2D, max alpha 0.28, generated once
and reused. Shadows render below all skulls, preventing a neighbor's shadow from
covering a skull and allowing their draw calls to batch. Both remain above terrain
Ground z=-10 and Decorations z=-9, below normal combat z=0 and CanvasLayer UI.

## Visual checks

The preview scans actual loaded terrain for five-cell-wide dirt, ash, crack and
rock patches, plus a decoration-heavy site, and places all four tiers on each.
It does not modify terrain generation. Stationary and moving-camera captures at
native zoom were inspected: skull silhouettes remain distinct from clutter and
tier edges remain readable while original white/blue/red/gold artwork is visible.
The dark ground aesthetic remains intact. Captures go to TEMP, not source assets.

## Performance

Rendered at 1152x648, 60Hz, RX 5700 XT, D3D12 Forward+. 100/200 active on-screen
pickups, evenly split between tiers, moving camera, 420 frames per run with a
60-frame warmup. No screenshot capture occurs during timings. Baseline mode disables
the new material, shadow and scale increase, retaining the same fixture hierarchy
and original bob. It approximates old rendering rather than benchmarking an old
checkout; the disabled added nodes remain in the fixture.

| Pickups / mode | Mean frame | FPS | p95 | Worst | Max draw calls |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 baseline | 16.666ms | 60.001 | 16.977ms | 17.172ms | 197 |
| 100 polished | 16.667ms | 59.998 | 16.999ms | 17.208ms | 198 |
| 200 baseline | 16.667ms | 59.999 | 16.967ms | 17.200ms | 297 |
| 200 polished | 16.667ms | 59.999 | 16.959ms | 17.130ms | 298 |

No measurable FPS regression at this presentation limit. This is not a GPU cost
measurement or guarantee on other hardware. Node/resource count deltas after warmup
were zero in all four runs. All 100/200 pickup weak references became null after
cleanup, with no shutdown warnings. There were no observed frame allocation spikes;
counts and short benchmarks do not constitute a long-duration native/GPU heap audit.

## Regression results

- 104 visual/isolation checks: exact XP/count/chance data, original texture/tint,
  sprite-only scale, collision/layers, shared materials/shader/shadow, unchanged
  global RNG consumption, bob/shadow isolation, 220 -> 360px/s magnet speeds,
  600px/s? acceleration, 10px arrival distance, instance-only magnet feedback,
  target loss, and node deletion. The existing 0.1s movement step remains 28px.
- Timed Tier 1 XP: 103029 checks. Seeded 100000-roll results remain MID=9961,
  LOW=90039, double drops=7073, MID doubles=715.
- Generic upgrades: 1204 checks, including Battlefield Salvage, Auto-Senses,
  actual pickup radius/magnetization and XP multipliers. Salvage sample remains
  MID=20142 and doubles=7073.
- XP progression: 50 checks; Ork integration: 100147 (including MID death drops,
  offsets, double drops and Purity Seals); Squig contact/death checks: 100621.
- 25 terrain coordinates match exact original Ground/current Decorations reference
  bytes. No terrain code, collision, combat code, player stats, XP requirements,
  reward chances or movement parameters were edited.

## Reproduce

```powershell
Godot_console.exe --headless --path . --script tests/xp_pickup_visual_test.gd
Godot_console.exe --headless --path . --script tests/tier_1_timed_xp_drop_test.gd
Godot_console.exe --path . --script tests/xp_readability_preview.gd -- --visibility
Godot_console.exe --path . --script tests/xp_readability_preview.gd -- --visibility --baseline
Godot_console.exe --path . --script tests/xp_readability_preview.gd -- --100 --baseline
Godot_console.exe --path . --script tests/xp_readability_preview.gd -- --100
Godot_console.exe --path . --script tests/xp_readability_preview.gd -- --baseline
Godot_console.exe --path . --script tests/xp_readability_preview.gd
```

Final editor/import check and rendered main-project smoke run completed without parser, shader, import or runtime errors. The shader's initial sampler-helper compiler issue was corrected before rendered validation; final runs are clean.
