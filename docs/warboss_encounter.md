# First playable Ork Warboss encounter

## Implementation

- Boss scene/script: `scenes/enemies/warboss.tscn`, `scripts/enemies/warboss.gd`.
- Encounter owner: `scenes/systems/boss_encounter.tscn`, `scripts/systems/boss_encounter.gd`, bound by `scripts/systems/main.gd`.
- Shared projectile specialization: `scenes/projectiles/warboss_projectile.tscn`, `scripts/projectiles/warboss_projectile.gd`.
- Victory overlay: `scenes/ui/boss_hud.tscn`, `scripts/ui/boss_hud.gd`.

Uses the exact existing `assets/art/effects/enemy/bosses/Pixel-Art Ork Warboss in Mega-Armour.png`, without source changes or new artwork. A static, one-frame AnimatedSprite2D matches the existing Enemy visual interface. Nearest filtering, proportional **0.07 scale** (~88px tall; ~1.9x normal Ork visible height), and a 32px body radius (normal Ork: 18px). The standalone asset-only `boss_visual.tscn` is untouched.

| Stat | Value |
|---|---:|
| Maximum / starting HP | 2000 / 2000 |
| Flat armor | 5 |
| Movement | 40px/s, no spawn speed jitter |
| Contact damage | None; disabled |
| Separation strength | 0.65 |

`Warboss extends Enemy` reuses normal collision membership, player target, cached spatial-grid separation, chase movement, damage numbers and crit/stat reporting. Its incoming damage override applies `max(1, incoming - 5)` for positive incoming hits before delegating to Enemy. Weapon damage and crits are calculated at the original source, so direct Bolter, splash, forks, Devastator and Knife all use the same boss armor entry point. Examples: 25 -> 20, 6 -> 1, 5 -> 1; a normal 25-damage 1.5x crit becomes 37.5 -> 32.5. HP remains fractional where appropriate; armor does not reroll crits. Existing damage-number pooling is reused, with a brief 0.08s boss hit flash.

## Local developer shortcut

In debug builds, **F10** advances RunClock forward to 10:00 through its normal time-change event, triggering the real boss controller, HUD and normal spawn tier. `DEBUG_BOSS_SKIP_ENABLED` in `scripts/systems/main.gd` is the single disable switch; release builds also reject the shortcut. It ignores repeats, modified keys, text-entry focus, paused/modals, dead players and already spawned/completed encounters. Player HP, weapons and upgrades are retained. `tests/debug_boss_skip_test.gd` exercises the gameplay input route, modal/text guards, unchanged player state, duplicate/rewind protection and normal Victory. No separate debug boss exists.

## Spawn and ordinary enemies

The run-owned `BossEncounter` subscribes to `RunClock.seconds_changed`. At elapsed **600 seconds**, it sets `warboss_spawned` before constructing exactly one boss. It also synchronizes the current clock on initial binding, so a late bind past 600s is safe. Repeated clock notifications, rebinding, chunk streaming and boss removal cannot reset the flag.

The flag lives for the entire Main run, independent of terrain/boss scene lifetimes. Reloading the entire Main scene deliberately starts a new run with a fresh clock/flag; no boss state leaks between new runs. No autoload or disk persistence was added.

Spawn placement reuses `EnemySpawner._get_spawn_origin()` (off-camera, camera-lag-aware margin and minimum player clearance). The boss is manually registered in the existing enemy spatial grid, separately from the normal active count, so a full 200-enemy normal cap cannot defer the boss or suppress a normal spawn. **Normal Squig/Ork spawning continues** throughout the fight, with unchanged schedules, probabilities, cap, jitter and 0â€“6 minute scaling. The spawner source is unchanged.

## Attack states and timers

States: **CHASE, CLAW_WINDUP, CLAW_SWING, CLAW_RECOVERY, GUN_WINDUP, GUN_BURST, GUN_RECOVERY, DEAD**. One phase Timer owns the attack sequence. Separate one-shot, physics-processing **ClawCooldown** and **GunCooldown** timers own readiness; both freeze naturally with game pause. There are no timestamp cooldown hacks or overlapping attacks.

| Attack | Claw | Gun |
|---|---|---|
| Trigger | <=90px, claw ready | >90px and <=550px, gun ready |
| Wind-up | 0.55s | 0.45s |
| Damage | 12 raw | 6 raw per projectile |
| Hit geometry | <=105px, locked 180-degree front half-arc | Three real, non-homing projectiles |
| Cadence | One hit maximum per swing | 0.18s between shots |
| Recovery | 0.45s | 0.35s |
| Cooldown | 1.8s from completed swing/impact, including misses | 3.5s from final burst shot |
| Projectile | â€” | 320px/s; 2.5s lifetime (~800px maximum travel) |

Claw direction locks when preparation begins, then actual player position is checked only at impact. Leaving 105px or moving behind the locked direction avoids damage. CLAW_SWING is the instantaneous impact event, followed immediately by recovery. The orange half-disc marks its reach; the existing KnifeSlash effect supplies swing feedback.

Gun aim also locks at preparation start. Its line telegraph, orange/red tinted existing Bolter texture and short procedural Line2D trail distinguish it from player rounds. The three directions have only +/-0.035 radians (~2 degrees) spread. The boss stops during aiming, burst and recovery; otherwise it chases if no eligible attack is ready. The projectile extends BoltProjectile, reusing direction, movement and lifetime, while overriding collision handling to damage Player only. It has no enemy damage, splash, forks, homing or recursive spawns, and disappears on player contact even when dodge/i-frames prevent damage.

Both attacks call **Player.take_damage**. Existing dodge, percentage reduction, flat armor, minimum damage and invulnerability windows remain authoritative; the boss does not duplicate or bypass them.

## HUD and Victory

The encounter HUD contains only the Victory overlay, hidden until the boss dies. There is no boss name label, health bar or remaining-HP display. The boss-only health-update signal and HUD binding have been removed; actual health, armored damage and death remain gameplay-owned. The normal player HP, XP, level and timer HUD is unchanged.

Boss death sets DEAD, stops all attack/flash timers and AI, and emits `defeated`. The boss-specific death path bypasses the normal enemy XP/reward drop entirely. The encounter stops normal spawning, dismisses informational/reward modals, clears pending reward offers, displays **VICTORY / WARLORD SLAIN / For the Emperor!**, and pauses immediately. Gameplay subtree disabling is deferred to avoid removing collision objects inside an Area2D hit callback. Always-processing reward/info menus are separately made terminal; stale close/selection/offer callbacks cannot release the Victory pause or reopen rewards.

Only terminal `run_ended` guards were added to existing UpgradeSystem and Character Info paths. Their normal behavior remains unchanged before Victory. There are no restart/menu buttons or post-boss gameplay.

## Verification

- `godot --headless --path . --script tests/run_ci_tests.gd`: **6/6 pass**.
- Full functional regression scripts: **39/39 pass**, including Squig/Ork attacks and spawning, fractional damage, Bolter/splash/ultimate/Knife, upgrades/modal ownership, XP, terrain artwork/determinism/chunk streaming/prefetch and roads. `docs/boss_spawn_stop_regressions.json` records the current outputs; `docs/warboss_regressions.json` retains the initial encounter evidence. The existing run-timer cap assertion now accounts for the separate boss in the spatial grid; normal cap expectations remain unchanged.
- `tests/warboss_test.gd`: **64 checks** covering requested stats, source/scale/filtering, armor/minimum/crit damage, actual Knife hits/crits, every trigger boundary, locked arc/range escapes, one-hit gate, real claw/gun timer cadence, defensive pipeline, stopped aiming, actual projectile collision/lifetime and non-homing behavior.
- `tests/warboss_encounter_test.gd`: **101 checks** covering 09:59.999 / 10:00, full-cap spawning, no duplicates after repeated events/rebind/chunk changes, preserved pre-encounter mobs and the disabled normal scheduler, live HUD, terminal pause under Character Info/Upgrade/Chapter menus, real lethal Bolter collision, interrupted attack timers, stale gun callbacks, frozen run state and no XP/upgrade reward.
- `tests/warboss_playthrough.gd`: rendered end-to-end fight using the real boss AI/timers/projectiles, eight pre-existing mobs and no reinforcements, actual player Bolter shots and existing legal upgrades. The fixture grants level-15-equivalent choices through XP/reward logic (Bolter damage 5, fire rate 5, multishot 2, Devastator plus eligible chapter choices), fast-forwards the clock to 10:00 and repositions the boss into camera view. It drives a deterministic evasive orbit; it does not weaken the boss or change weapon formulas. This is not a claim that a level-one loadout beats the 10-minute swarm.
- The playthrough escaped the claw, rendered gun volleys, killed the boss with a normal projectile and reached Victory after **9.27 simulated fight seconds**, 19 Bolter volleys and 7 boss projectiles (death cancels the last burst). Player finished **48/50 HP**, with **four of the eight original normal enemies** still present. Others died through ordinary combat; no replacements spawned. Fixture clock is held at 10:00 for repeatable screenshots; production clock runs normally until Victory.
- Rendered editor validation and the normal 300-frame project smoke test pass without parser/import/runtime errors. Source PNG SHA256 remains `5cde1f492f72184af44e72dee2e6c9c092ad847240116e9d26408a9e3bf944e2`.

Screenshots inspected: [claw](warboss_claw.png), [gun/boss health](warboss_gun.png), [Victory](warboss_victory.png). No new artwork was generated. Local ignored logs: `warboss_ci.log`, `warboss_playthrough.log`, `warboss_editor.log`, `warboss_smoke.log`.

## Performance

The rendered playthrough maintained **60 FPS** (mean observed frame interval 16.85ms, including capture overhead). Across **556 real boss AI updates**, mean update CPU was **38.11 microseconds (0.038ms)**, worst **242 microseconds (0.242ms)**. This timer measures the boss update, including reused chase/separation, not all rendering, timers or projectile costs. It is a live-fight measurement with eight pre-existing normal enemies, not a paired 200-enemy benchmark or a universal hardware guarantee.

Boss code performs a direct target-distance check and reuses the bounded local grid for separation. It adds no per-frame scene-tree scans, global enemy searches, pathfinding or custom physics-query loops. Existing projectile collision callbacks provide hit detection. The controller is clock-event-driven, not polled per frame.

## Files

Modified:

- `scenes/main.tscn`: encounter instance.
- `scripts/systems/main.gd`: bind clock/player/spawner/rewards/modals to encounter.
- `scripts/systems/upgrade_system.gd`: terminal reward/selection guards and queue cleanup.
- `scripts/ui/character_info_panel.gd`: terminal pause ownership/visibility guard.
- `scripts/ui/upgrade_menu.gd`: disable stale menu interaction after Victory.
- `tests/run_timer_test.gd`: distinguish normal cap from separately registered boss; populate the survivor before the 10:00 cutoff and test jitter while scheduling is still enabled.
- `scripts/systems/enemy_spawner.gd`: explicit normal-spawn enable flag, idempotent scheduler cancellation and stale-call guards.
- `tests/debug_boss_skip_test.gd`: F10 now expects the normal scheduler to stop.
- `tests/warboss_encounter_test.gd`: preserve a pre-existing mob rather than requiring new spawns during the encounter.
- `tests/warboss_playthrough.gd`: seed eight pre-encounter survivors, assert cutoff, and report no reinforcements.

Added:

- `scenes/enemies/warboss.tscn`, `scripts/enemies/warboss.gd`.
- `scenes/projectiles/warboss_projectile.tscn`, `scripts/projectiles/warboss_projectile.gd`.
- `scenes/systems/boss_encounter.tscn`, `scripts/systems/boss_encounter.gd`.
- `scenes/ui/boss_hud.tscn`, `scripts/ui/boss_hud.gd`.
- `tests/warboss_test.gd`, `tests/warboss_encounter_test.gd`, `tests/warboss_playthrough.gd`; `tests/boss_spawn_stop_test.gd` adds natural/F10 cutoff, pending-callback rejection, survivor movement/attacks/death/rewards and no-refill tests.
- Beside-script Godot UID files for new scripts.
- This report; `docs/warboss_regressions.json`, `docs/warboss_playthrough.json`; claw/gun/Victory screenshots and their Godot import metadata.

No modifications to Enemy/Ork/Player damage or behavior, spatial grid, RunClock, player weapons/projectiles, terrain, XP resources, existing upgrade definitions, source art or asset catalog. No commits or pushes.

## Reinforcement cutoff follow-up

Changed production files: `scripts/systems/enemy_spawner.gd` and `scripts/systems/boss_encounter.gd`. Updated the four existing shortcut/encounter/timer/playthrough tests, added `tests/boss_spawn_stop_test.gd` (and UID), updated this report and rendered playthrough JSON/three screenshots. Current functional evidence: `docs/boss_spawn_stop_regressions.json`; requested CI log: locally ignored `docs/boss_spawn_stop_ci.log`.

The new test uses actual physics to verify that pre-existing Squigs and Orks move and damage the player after spawning stops, then die and grant their usual pickups. It exercises both natural 10:00 and F10; near-due delays, deferred spawn calls, later time events, direct burst/additive calls and deaths cannot replenish mobs. It also checks that the boss remains unique and Victory still freezes the run. No Victory implementation changes were needed.
