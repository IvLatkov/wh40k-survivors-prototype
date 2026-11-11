extends SceneTree

const BOSS := preload("res://scenes/enemies/warboss.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
var checks: int = 0
var ticks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	physics_frame.connect(func(): ticks += 1)
	run.call_deferred()

func fixture() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := PLAYER.instantiate() as Player
	player.name = "Player"
	world.add_child(player)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("Bolter").set_process(false)
	player.get_node("KnifeAttack").set_physics_process(false)
	var boss := BOSS.instantiate() as Warboss
	world.add_child(boss)
	boss.set_target(player)
	boss.set_physics_process(false)
	return world

func advance(boss: Warboss) -> void:
	boss.phase_timer.stop()
	boss._on_phase_timeout()

func wait_seconds(seconds: float) -> void:
	for _tick in ceili(seconds * Engine.physics_ticks_per_second):
		await physics_frame
	await process_frame

func dispose(world: Node) -> void:
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	var world := fixture()
	var boss: Warboss = world.get_node("Warboss")
	var player: Player = world.get_node("Player")
	check(boss.max_health == 2000 and boss.current_health == 2000, "Warboss maximum and starting HP are 2000")
	check(boss.armor == 5 and boss.movement_speed == 40 and boss.separation_strength == 0.65, "Requested boss base stats")
	check(not boss.contact_damage_enabled and boss.contact_damage == 0 and boss.speed_variation_limit == 0, "No contact damage or speed jitter")
	check(boss.visual.sprite_frames.get_frame_texture(&"default", 0).resource_path.ends_with("Pixel-Art Ork Warboss in Mega-Armour.png"), "Exact integrated boss asset")
	var ratio := 1254 * boss.visual.scale.y / (511 * 0.09)
	check(ratio >= 1.5 and ratio <= 2.0, "Boss visible footprint 1.5-2x normal Ork")
	check(boss.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest filtering")
	var amounts: Array[float] = []
	var crits: Array[bool] = []
	boss.damage_received.connect(func(amount: float, critical: bool): amounts.append(amount); crits.append(critical))
	for incoming in [25.0, 6.0, 5.0, 0.5]:
		var old := boss.current_health
		boss.take_damage(incoming)
		check(boss.current_health == old - maxf(1, incoming - 5), "Armor and one-point minimum")
	var stats := CombatStats.new()
	var old := boss.current_health
	var hit := stats.roll_hit(25, true)
	boss.take_damage(hit.amount, hit.critical, stats, &"bolter")
	check(boss.current_health == old - 32.5 and crits.back() and amounts.back() == 32.5, "Armor follows crit; shared numbers receive post-armor damage")
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	world.add_child(bolt)
	bolt.set_physics_process(false)
	for incoming in [25.0, 12.5, 43.75, 12.5]:
		old = boss.current_health
		bolt._deal_damage(boss, incoming)
		check(boss.current_health == old - (incoming - 5), "Direct/splash/Devastator/fork all reach boss-specific armor")
	boss.position = Vector2(30, 0)
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	knife._on_body_entered(boss)
	old = boss.current_health
	knife._attack()
	check(boss.current_health == old - 30, "Real Knife hit is reduced from 35 to 30")
	knife.cooldown_timer.stop()
	player.combat_stats.crit_chance = 1.0
	old = boss.current_health
	knife._attack()
	check(boss.current_health == old - 47.5 and crits.back(), "Real Knife crit uses existing crit then boss armor")
	await dispose(world)
	# Trigger boundaries and state exclusivity, without changing cooldowns.
	for distance in [90.0, 90.01, 550.0, 550.01]:
		world = fixture()
		boss = world.get_node("Warboss")
		player = world.get_node("Player")
		player.position = Vector2(distance, 0)
		boss._physics_process(0)
		var expected := Warboss.State.CLAW_WINDUP if distance <= 90 else (Warboss.State.GUN_WINDUP if distance <= 550 else Warboss.State.CHASE)
		check(boss.state == expected, "Exact 90px claw / 550px gun triggers")
		if expected != Warboss.State.CHASE:
			player.position = Vector2(30, 0) if expected == Warboss.State.GUN_WINDUP else Vector2(400, 0)
			boss._physics_process(0.1)
			check(boss.state == expected, "No overlapping/interrupted attacks when target crosses ranges")
		await dispose(world)
	# Impact checks use the real current player position and the locked arc.
	for destination: Vector2 in [Vector2(105, 0), Vector2(105.1, 0), Vector2(-80, 0), Vector2(0, 100)]:
		world = fixture()
		boss = world.get_node("Warboss")
		player = world.get_node("Player")
		player.position = Vector2(90, 0)
		boss._physics_process(0)
		check(boss.phase_timer.wait_time == 0.55 and boss.attack_direction == Vector2.RIGHT, "0.55s windup and direction lock")
		player.position = destination
		advance(boss)
		var hits := destination.length() <= 105 and destination.x >= 0
		check(player.current_health == (38 if hits else 50), "Actual 105px impact / front half-arc / escape / behind miss")
		check(boss.state == Warboss.State.CLAW_RECOVERY and boss.phase_timer.wait_time == 0.45 and boss.claw_timer.wait_time == 1.8, "Recovery and dedicated 1.8s cooldown after hit or miss")
		boss._apply_claw_hit()
		check(player.current_health == (38 if hits else 50), "At most one player hit per swing")
		advance(boss)
		player.position = Vector2.ZERO
		boss._physics_process(0.01)
		check(boss.state == Warboss.State.CHASE and player.current_health == (38 if hits else 50), "Claw cannot repeat while cooldown runs; contact does no damage")
		await dispose(world)
	# Player defenses are still the existing player pipeline.
	for dodge in [false, true]:
		world = fixture()
		boss = world.get_node("Warboss")
		player = world.get_node("Player")
		player.combat_stats.add_modifier(&"armor", 2)
		player.combat_stats.add_modifier(&"damage_reduction", 0.25)
		if dodge:
			player.combat_stats.add_modifier(&"dodge_chance", 1.0)
		player.position = Vector2(80, 0)
		boss._physics_process(0)
		advance(boss)
		check(player.current_health == (50 if dodge else 43), "Player dodge/reduction/armor preserved")
		player.take_damage(12)
		check(player.current_health == (50 if dodge else 43), "Existing invulnerability window preserved")
		await dispose(world)
	# Real physics timers: no damage before the claw's telegraph completes.
	world = fixture()
	boss = world.get_node("Warboss")
	player = world.get_node("Player")
	player.position = Vector2(80, 0)
	boss._physics_process(0)
	await wait_seconds(0.48)
	check(player.current_health == 50 and boss.state == Warboss.State.CLAW_WINDUP, "Real timer does not hit early")
	await wait_seconds(0.12)
	check(player.current_health == 38 and boss.state == Warboss.State.CLAW_RECOVERY, "Real timer delivers claw impact once")
	await wait_seconds(0.5)
	check(boss.state == Warboss.State.CHASE and not boss.claw_timer.is_stopped(), "Real recovery ends while cooldown continues")
	await dispose(world)
	# Real 0.45s aim / three shots / 0.18s cadence; aim never homes.
	world = fixture()
	boss = world.get_node("Warboss")
	player = world.get_node("Player")
	player.position = Vector2(400, 0)
	var bullets: Array[BoltProjectile] = []
	var shot_ticks: Array[int] = []
	boss.shot_fired.connect(func(p: BoltProjectile): bullets.append(p); shot_ticks.append(ticks))
	var started := ticks
	boss._physics_process(0)
	check(boss.phase_timer.wait_time == 0.45 and boss.velocity == Vector2.ZERO, "Gun aim duration and stopped movement")
	player.position = Vector2(0, 400)
	await wait_seconds(0.9)
	check(bullets.size() == 3, "Exactly three real projectiles")
	var first_delay := float(shot_ticks[0] - started) / Engine.physics_ticks_per_second
	check(absf(first_delay - 0.45) < 0.04, "Real gun wind-up timing")
	for index in [1, 2]:
		check(absf(float(shot_ticks[index] - shot_ticks[index-1]) / Engine.physics_ticks_per_second - 0.18) < 0.04, "Real burst intervals")
	for bullet in bullets:
		check(bullet.damage == 6 and bullet.projectile_speed == 320 and bullet.collision_mask == 1 and not bullet.can_fork and not bullet.splash_enabled, "Player-only six-damage 320px/s nonrecursive projectiles")
		check(bullet._direction.x > 0.99 and absf(bullet._direction.y) < 0.04, "Locked aim, modest spread, no homing after launch")
	check(boss.gun_timer.wait_time == 3.5 and not boss.gun_timer.is_stopped(), "Dedicated gun cooldown after completed burst")
	await dispose(world)
	# Real collision: the bullet passes through an enemy and hits the player.
	world = fixture()
	boss = world.get_node("Warboss")
	boss.position = Vector2(-500, -500)
	player = world.get_node("Player")
	player.position = Vector2(150, 0)
	var enemy := EnemySpawner.ENEMY_SCENE.instantiate() as Enemy
	enemy.position = Vector2(80, 0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var bullet := Warboss.SHOT.instantiate() as WarbossProjectile
	bullet.position = Vector2.ZERO
	bullet.set_direction(Vector2.RIGHT)
	world.add_child(bullet)
	await wait_seconds(0.65)
	check(player.current_health == 44 and enemy.current_health == enemy.max_health and not is_instance_valid(bullet), "Physics bullet ignores enemies, hits player and disappears")
	bullet = Warboss.SHOT.instantiate() as WarbossProjectile
	bullet.position = Vector2(500, -500)
	world.add_child(bullet)
	bullet.set_physics_process(false)
	bullet._physics_process(2.51)
	check(bullet.is_queued_for_deletion(), "Projectile bounded 2.5-second lifetime")
	await dispose(world)
	print("PASS: ", checks, " Warboss stats/armor/attack/projectile checks")
	quit()
