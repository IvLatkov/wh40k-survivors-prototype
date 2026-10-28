# Tier 2 Ork melee polish

## Behavior

`CHASE -> WINDUP -> SWING -> RECOVERY -> CHASE`, using the existing OrkBoy
specialization of Enemy. CHASE contains a numeric pre-attack countdown, not a new
state-machine framework or Timer node. Outside melee range the original Enemy
movement, distance throttling and spatial grid remain in use.

- Trigger range: **65px**. Impact range: **75px**.
- Preparation: one independent per-Ork RNG draw in **0.10?0.30s**. Standing in range
  does not reroll every frame. Preparation stops forward movement but retains local
  separation; moving beyond **85px** cancels it. Facing may still follow the player
  before wind-up. Standing/cooldown movement also uses the original stop distance.
- Once WINDUP starts, movement stops and the horizontal art-facing sign is captured.
  No player tracking or separation moves the Ork during the committed animation.
  Leaving range or running behind it never cancels the animation.
- Animation: existing four-frame sheet, **7 FPS**, non-looping. The first two poses
  provide **2/7s = 0.286s wind-up**. Frame **2 (third pose)** is the extended forward
  choppa strike/follow-through, retained after visual inspection of the original
  sheet. The frame_changed callback enters SWING and consumes one strike, including
  misses. Final pose frame 3 has duration weight 1.75: **0.25s recovery**. SWING pose
  lasts 1/7s. Animation length is approximately **0.679s**, plus local hit feedback.
- At impact use the player's current position, squared 75px range, and
  `offset.x * locked_facing >= 0`. This is a broad frontal half-plane, matching the
  two horizontal sprite facings, rather than a narrow aim cone. Range/rear-side
  misses and existing invulnerability consume no raw damage roll. A valid strike
  calls the existing `Player.take_damage`, preserving dodge, Armor and minimum
  damage. Iron Halo may consume its own dodge roll as before.
- Cooldown remains **1.25s from wind-up start**. Preparation may start in its last
  0.30s; the remaining cooldown and random delay overlap rather than accumulate.
  Sustained in-range attacks therefore keep approximately 1.25s start-to-start
  cadence. Initial eligibility/re-entry gets the random delay; initial group timing
  offsets persist rather than restarting everyone on a shared timer. Animation
  duration is not followed by another full 1.25s wait. Between animations the Ork
  stands while cooldown is pending, or resumes normal chase when out of range.
- Walk remains **6 FPS**, looping, only playing while moving. It pauses on stationary
  preparation/cooldown, and does not play under the attack animation.
- The existing watchdog still only cancels interrupted/stalled animations, never
  applies damage. Death clears preparation and feedback, stops animation, consumes
  the strike and uses the inherited blood/MID XP/tracking/queue_free path.

## Feedback and spacing

Wind-up lightly brightens the sprite with a warm multiplier (1.15, 1.10, 1.02).
The animation remains the main telegraph. An incoming damage_received event replaces
that tint with a short bright flash for **0.08s**; repeated hits refresh one numeric
countdown. It returns to the wind-up tint or original tint, without new timers or
per-hit tweens. All existing damage sources share this signal, including direct,
splash, Knife, Forking Rounds and Devastator Shells.

The hit frame instantiates the existing `knife_slash.tscn`, using
`assets/art/effects/sword_slash/sword_slash.png`, on the committed side. Scale 0.75,
warm translucent tint, 32px forward / 12px upward offset, and 1.5 playback multiplier
make it a small approximately **0.167s** cosmetic effect. Its own animation_finished
frees it. It never performs damage or holds an attack callback.

Only a successful reduction in player HP pauses this Ork's animation for **0.05s**.
The rest of the game and other enemies continue normally. Misses, invulnerability
and dodges do not cause a pause. No global time scale or new camera system is used.

Ork separation strength is **0.50**, versus unchanged Squig **0.40** (**25% stronger**).
The existing Ork 44px radius is retained (Squig 40px). This corrects the previous Ork
strength of 0.30, which was weaker than Squigs. The same grid, candidate filtering
and 0.05s refresh interval are reused; no Areas, global searches or raycasts added.
A deliberately complete close ring can still body-block the player: spacing does
not make enemies intangible or guarantee escape after full encirclement.

## Preserved balance

Ork HP 50, base speed 50 (existing small spawn variation retained), Squig HP 25.
Tier 2 raw damage remains 3/4/5 with 65%/25%/10% weights. Ork contact damage stays
disabled. MID XP, blood, body collision and tracking are unchanged. No spawn code,
player, Squig, weapon, terrain, source artwork or progression resources changed.
The additive Ork stream remains 0 before 150s, 10% at 150s ramping to 50% just before
300s, and 100% additional from 300s. Squig cadence is never replaced by Orks.

## Verification (Godot 4.6.3)

- 139 melee checks: preparation reuse/cancellation, feet alignment, animation timing,
  locked facing, current-position/rear-side misses without raw RNG consumption,
  one strike, local 49ms/50ms pause boundary, left/right slash placement and expiry,
  repeated-hit flash reset, defenses, no contact hit, real signal playback,
  interruption watchdog, death during all four phases and MID XP/tracking cleanup.
- Ork integration: 100147 checks (including all existing weapon paths and MID XP).
  Raw 100000-roll sample: [64719, 25141, 10140].
- Additive spawning: 50 checks; Squig contact damage: 100621; Armor: 183;
  Chapter perks: 307. These exercise unchanged distributions and defenses.
- Six simultaneously eligible Orks showed a 0.13?0.15s initial wind-up start spread.
  The shortest observed sustained cadence was 1.25s. Their 0.286s wind-ups can still
  overlap; desynchronization is subtle rather than enforcing attack reservations.
- The rendered group capture was visually inspected: anchored feet, consistent
  mirrored strikes, small slash accents and distinct attack poses. Six bodies can
  enclose the player; this intentional extreme fixture produced no geometric misses,
  so it is not evidence of guaranteed group escape.

### Automated progression observations

`--balance --fixed-fps 60` runs actual gameplay through 370 simulated seconds,
with a square input route and short periodic stops. Existing weapons/spawning/XP
remain enabled; the harness auto-selects the first offered reward and replenishes
player HP to observe every window. Ork RNG is independently randomized, so exact
counts vary. These are scripted pressure observations, **not a human fairness or
survivability assessment**. Geometric misses mean outside range or behind the locked
side; dodges/invulnerability are separate and not included in that count.

| Window | Peak active Orks | Peak simultaneous SWING poses | Wind-ups / strikes / geometric misses |
| --- | ---: | ---: | ---: |
| 2:30?2:40 | 3 | 0 | 0 / 0 / 0 |
| 4:00?4:10 | 12 | 1 | 8 / 6 / 4 |
| 4:50?5:00 | 11 | 1 | 1 / 1 / 0 |
| 5:00?5:10 | 28 | 2 | 12 / 9 / 4 |
| 6:00?6:10 | 39 | 3 | 20 / 18 / 5 |

At unlock, the first few Orks were still approaching. By 4:00, movement caused
four of six strikes to miss. The 5:00 additive frequency jump noticeably increased
pressure and overlap, with more misses still available from movement; by 6:00 up to
three swing poses overlapped. This shows a harder spike, but cannot establish whether
5:00 is fair for a human player. No automatic rebalance was made.

### Performance

Rendered, project-default D3D12 Forward+, RX 5700 XT, 60Hz. Each controlled group run
uses 720 frames (12 simulated seconds); first 60 frames omitted from frame timings.
Player HP is replenished. The harness itself observes states and sends movement input,
so these intervals include test bookkeeping and presentation.

| Crowd | Mean frame | p95 | Worst | Mean FPS |
| --- | ---: | ---: | ---: | ---: |
| 150 Squigs + 50 Orks, enemy-side attacks/spacing/VFX | 16.678ms | 23.129ms | 38.703ms | 59.96 |
| 200 Orks, enemy-side attacks/spacing/VFX | 16.657ms | 23.387ms | 33.863ms | 60.03 |
| Approximately 200 mixed enemies, full combat | 16.668ms | 28.762ms | 49.043ms | 59.99 |

The enemy-side fixtures disable player weapons to maintain a fixed crowd. Full combat
uses `--stress --combat`: Bolter/Knife, pickups and auto-selected rewards stay active;
the harness replenishes defeated enemies toward 200 each frame (596 replacements in
the recorded run). There were 153 strikes, including 21 geometric misses. This includes active
weapon effects rather than only enemy simulation. Frame spikes still occur; average
60FPS is not a claim that every frame stays within 16.7ms. Shared-grid 200-enemy
separation queries measured 5.11ms total in the existing integration fixture (prior
measurement about 5.04ms); no separation algorithm was replaced.

The harness drains existing explosion-effect coroutine timers before deleting the
scene, avoiding abrupt-shutdown timer warnings. No production effect code was altered.

## Reproduce

```powershell
Godot_console.exe --headless --path . --script tests/ork_melee_animation_test.gd
Godot_console.exe --headless --path . --script tests/ork_boy_test.gd
Godot_console.exe --headless --path . --script tests/additive_ork_spawning_test.gd
Godot_console.exe --headless --path . --fixed-fps 60 --script tests/ork_melee_playtest.gd -- --balance
Godot_console.exe --path . --script tests/ork_melee_playtest.gd -- --capture
Godot_console.exe --path . --script tests/ork_melee_playtest.gd -- --stress
Godot_console.exe --path . --script tests/ork_melee_playtest.gd -- --stress --all-orks
Godot_console.exe --path . --script tests/ork_melee_playtest.gd -- --stress --combat
```

Capture goes to the user's TEMP folder, not source assets. Fixed-FPS headless runs
validate simulated behavior; their wall-clock throughput is not a rendered FPS result.

Final editor import/parser check, rendered main-project smoke run and full-combat stress shutdown completed without debugger errors or warnings. Additional XP progression (50), directional Knife (127), Bolter splash (41) and Ultimate (121) checks passed.
