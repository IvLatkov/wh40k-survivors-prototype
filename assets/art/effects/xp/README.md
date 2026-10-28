# XP tiers

Select an enemy root using `enemy.gd`, then set **XP Drops > Xp Tier** in
the Inspector to LOW, MID, HIGH, or BOSS. Existing enemies default to LOW.
All tiers use `scenes/pickups/xp_pickup.tscn` and award XP through `Player.add_xp`.

| Tier | Resource | XP per skull | Normal count | Double-drop chance |
| --- | --- | --- | --- | --- |
| LOW | `low_level/xp_reward.tres` | 1 | 1 | 7% |
| MID | `mid_level/xp_reward.tres` | 5 | 1 | 10% |
| HIGH | `high_level/xp_reward.tres` | 15 | 1 | 15% |
| BOSS | `boss/xp_reward.tres` | 25 | 4 | 0% |

The existing white, blue, red, and gold skull PNGs are assigned already.
The boss resource references the existing gold PNG in `bosses/`; it has not
been moved or duplicated. Future boss artwork can go in `boss/`.

To replace artwork, put a PNG in the corresponding tier folder and assign it
to **Texture** on that tier's `xp_reward.tres` resource. Use 16x16 artwork:
sprites remain centered with nearest filtering and a visual base scale of 1.12.
The shared outline mapping in `XPPickup.TIER_TEXTURES` uses the shipped textures;
update that mapping as well when replacing tier artwork. The standalone pickup
scene retains the original white skull.

Reward resources are shared. Editing a resource changes every enemy using it.
For an enemy-specific reward, use **Make Unique** on its reward resource in
the Inspector before changing values. Keep the boss defaults at four skulls,
25 XP each, and zero double-drop chance for a guaranteed 100 XP reward.

Drops are created only on death. Multiple drops use a randomly rotated ring;
boss drops have a wider minimum radius to keep the sprites separated.
Idle pickups have processing disabled. They occupy collision layer 4
(mask value 8) and do not monitor anything. The player's XPCollectionArea
detects only that layer with a centered 60px circle. When the pickup's 8px
circle overlaps it (up to 68px between centers), the skull starts flying
toward the player and becomes unmonitorable. Only flying skulls process
movement: 220px/s initially, accelerating at 600px/s² to 360px/s. XP is
awarded once within 10px of the player center, then the pickup is removed.
If its player is freed, the skull returns to idle and can be triggered again.

## Readability

The pickup's gameplay root and collision stay unchanged. A grounded shared oval
shadow renders at effective z=-2, the skull at its original z=-1. `VisualRoot`
keeps the existing 2px / 1.2s bob, while the sprite alone has 1.12 base scale.
A shared shader adds a one-source-pixel colored outline and faint dark outer
keyline; four fixed shared materials provide silver, cyan, violet and gold edges.
The original skull pixels are retained. The shader pulses 0.97?1.03 over 1.6s
with independent visual phases and no extra global RNG calls. Magnet acquisition
raises only the instance's outline strength to 1.2; movement is unchanged.

See `docs/xp_readability.md` for visibility checks, performance and regressions.
