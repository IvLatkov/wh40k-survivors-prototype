extends SceneTree

const ORK_SCENE := preload("res://scenes/enemies/ork_boy.tscn")
const ORK_ART := preload("res://assets/art/effects/enemy/orc/ChatGPT Image Oct 19, 2026, 08_30_45 PM-1.png")
var checks: int = 0
var main: Node2D
var player: Player
var spawner: EnemySpawner
var grid: EnemySpatialGrid

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func spawn_ork(at: Vector2) -> Enemy:
	spawner._spawn_enemy(at, ORK_SCENE)
	var enemy := grid._enemies.back() as Enemy
	enemy.set_physics_process(false)
	check(enemy.damage_tier == Enemy.DamageTier.TIER_2, "Spawned enemy is Tier 2")
	return enemy

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	spawner = main.get_node("EnemySpawner")
	grid = spawner.spatial_grid
	var clock: RunClock = main.get_node("RunClock")
	clock.set_process(false)
	spawner.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	knife.set_physics_process(false)
	clock.elapsed_time = 300.0
	var ork := spawn_ork(Vector2(180, 0))
	check(ork is OrkBoy, "Ork specializes the shared Enemy script")
	check(ork.current_health == 50.0 and ork.max_health == 50.0 and ork.movement_speed == 50.0, "Ork HP and base movement")
	check((ork.visual.sprite_frames.get_frame_texture(&"walk", 0) as AtlasTexture).atlas == ORK_ART and ork.visual.sprite_frames.get_frame_count(&"walk") == 4, "Exact four-frame Ork walking artwork")
	check(ork.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and ork.visual.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE, "Sharp inherited pixel filtering")
	var squig := EnemySpawner.ENEMY_SCENE.instantiate() as Enemy
	main.add_child(squig)
	squig.set_physics_process(false)
	squig.position = Vector2(100, 0)
	var ork_height := 511.0 * ork.visual.scale.y
	var squig_height := squig.visual.sprite_frames.get_frame_texture(squig.visual.animation, 0).get_image().get_used_rect().size.y * squig.visual.scale.y
	check(ork_height / squig_height >= 1.3 and ork_height / squig_height <= 1.6, "Visible Ork height is 1.3 to 1.6 times Squig")
	check(ork.visual.scale.x == ork.visual.scale.y, "Ork scale is proportional")
	check((ork.get_node("CollisionShape2D").shape as CircleShape2D).radius == 18.0, "Ork body collision radius eighteen")
	check(ork.collision_layer == squig.collision_layer and ork.collision_mask == squig.collision_mask, "Shared collision architecture")
	ork._update_visual_facing(50.0)
	check(not ork.visual.flip_h, "Right-facing artwork stays unflipped moving right")
	ork._update_visual_facing(-50.0)
	check(ork.visual.flip_h, "Moving left flips existing art")
	ork._update_visual_facing(0.0)
	check(ork.visual.flip_h, "Stationary enemy preserves facing")
	ork._update_visual_facing(50.0)
	check(ork._individual_movement_speed >= 47.5 and ork._individual_movement_speed <= 52.5, "Small Ork speed variation")
	check(ork._individual_movement_speed < 54.0, "Even fastest Ork stays slower than slowest standard Squig")
	check(ork.target == player and ork.run_clock == clock and ork.spatial_grid == grid and grid._enemies.has(ork), "Spawner injects shared target clock and spatial grid")
	ork.position = Vector2(300, 0)
	ork._physics_process(0.016)
	check(ork.velocity.x < 0.0 and ork.velocity.length() <= 52.5, "Ork chases at slower movement speed")
	var neighbor := spawn_ork(ork.position + Vector2(20, 0))
	grid._rebuild_grid()
	check(ork._calculate_separation_direction().x < 0.0, "Ork participates in optimized local separation")
	check(ork.get_child_count() == squig.get_child_count(), "No extra separation Areas or permanent timers")
	ork.position = Vector2(180, 0)
	neighbor.position = Vector2(240, 0)
	if "--capture-ui" in OS.get_cmdline_user_args():
		player.get_node("Camera2D").zoom = Vector2(3, 3)
		player.get_node("Camera2D").force_update_scroll()
		squig.position = Vector2(50, 0)
		ork.position = Vector2(100, 0)
		neighbor.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("survivor_ork_boy.png"))
		player.get_node("Camera2D").zoom = Vector2.ONE
		player.get_node("Camera2D").force_update_scroll()
	squig.queue_free()
	neighbor.position = Vector2(1000, 1000)
	# Preserve raw damage weights; the animation suite verifies impact timing and defenses.
	seed(940)
	var counts: Array[int] = [0, 0, 0]
	for _sample in 100000:
		var amount := ork.get_attack_damage()
		check(amount in [3.0, 4.0, 5.0], "Tier 2 raw melee damage bounds")
		counts[int(amount) - 3] += 1
	for index in 3:
		check(absf(counts[index] / 100000.0 - [0.65, 0.25, 0.1][index]) < 0.01, "Tier 2 melee damage weights")
	print("Ork raw melee damage distribution: ", counts)
	player.current_health = player.max_health
	player.damage_invulnerability_timer.stop()
	ork.position = player.position + Vector2(30, 0)
	ork._physics_process(0.016)
	check(player.current_health == player.max_health and not ork.contact_damage_enabled, "Ork contact no longer deals immediate damage")
	(ork as OrkBoy)._finish_attack()
	player.combat_stats.modifiers.clear()
	# These multi-hit integration fixtures need HP above the production 50.
	for fixture in [ork, neighbor]:
		fixture.max_health = 150.0
		fixture.current_health = 150.0
	ork.position = Vector2(1500, 0)
	neighbor.position = Vector2(1545, 0)
	await physics_frame
	await physics_frame
	player.combat_stats.crit_chance = 1.0
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	bolt.monitoring = false
	bolt.position = ork.position
	bolt.combat_stats = player.combat_stats
	main.add_child(bolt)
	bolt.set_physics_process(false)
	bolt._explode(ork)
	check(ork.current_health == 112.5 and neighbor.current_health == 131.25, "Bolter direct and splash crits hit Orks with direct target excluded")
	bolt.damage *= 1.75
	bolt.splash_radius *= 1.5
	bolt._explode(ork)
	check(is_equal_approx(ork.current_health, 46.875) and is_equal_approx(neighbor.current_health, 98.4375), "Devastator empowered direct and splash damage use shared handling")
	bolt.free()
	# Forks select Orks from the spatial grid and damage them without splash.
	ork.current_health = ork.max_health
	neighbor.current_health = neighbor.max_health
	grid._rebuild_grid()
	var source := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	source.monitoring = false
	source.spatial_grid = grid
	source.combat_stats = player.combat_stats
	source.position = ork.position
	main.add_child(source)
	source.set_physics_process(false)
	var frozen_forks: Array[BoltProjectile] = []
	var freeze_fork := func(node: Node) -> void:
		if node is BoltProjectile:
			node.set_physics_process(false)
			node.set_deferred("monitoring", false)
			frozen_forks.append(node)
	main.child_entered_tree.connect(freeze_fork)
	source._spawn_forks(ork)
	await process_frame
	await process_frame
	check(frozen_forks.size() == 1, "Forking finds one alternative living Ork")
	frozen_forks[0]._explode(neighbor)
	check(neighbor.current_health == 131.25 and not frozen_forks[0].can_fork, "Fork direct crit deals expected damage to Ork without recursion")
	for fork in frozen_forks:
		fork.queue_free()
	source.queue_free()
	main.child_entered_tree.disconnect(freeze_fork)
	# Real Knife detection accepts the inherited enemy body in both coverage modes.
	ork.current_health = ork.max_health
	neighbor.current_health = neighbor.max_health
	ork.position = player.position + Vector2(40, 0)
	neighbor.position = player.position - Vector2(40, 0)
	player.facing_right = true
	await physics_frame
	await physics_frame
	await physics_frame
	await process_frame
	knife.cooldown_timer.stop()
	knife._attack()
	check(ork.current_health == 97.5 and neighbor.current_health == 150.0, "Normal 180 degree Knife crit hits forward Ork only")
	knife.activate_ultimate(&"whirlwind_assault")
	knife.cooldown_timer.stop()
	knife._attack()
	check(ork.current_health == 45.0 and neighbor.current_health == 97.5, "Whirlwind damages both Orks exactly once")
	await process_frame
	var critical_numbers := 0
	for child in main.get_children():
		if child is FloatingDamageNumber and child.is_critical:
			check(child.get_node("Label").modulate == Color.RED, "Ork critical damage numbers are red")
			critical_numbers += 1
	check(critical_numbers >= 3, "Shared damage-number feedback appears for Orks")
	check(ork.get_xp_reward() == ork.mid_xp_reward and ork.mid_xp_reward.xp_per_pickup == 5, "Ork uses actual five XP MID reward")
	check(ork.xp_quantity_reward.double_drop_chance == 0.07, "Ork quantity roll preserves seven percent doubles")
	for _sample in 100:
		check(ork.roll_xp_reward() == ork.mid_xp_reward, "Ork always chooses MID skull tier")
	# A seeded double death must create two real MID pickups and one blood burst.
	var double_seed := 0
	for sample in 10000:
		seed(sample)
		if ork.xp_quantity_reward.roll_pickup_count() == 2:
			double_seed = sample
			break
	var count_before := spawner.get_active_enemy_count()
	var hp_before := ork.current_health
	var dead_id := ork.get_instance_id()
	seed(double_seed)
	ork.take_damage(1000.0)
	check(ork.is_queued_for_deletion() and not ork.is_physics_processing() and ork.velocity == Vector2.ZERO, "Lethal hit stops movement and safely queues death")
	ork.take_damage(1000.0)
	check(ork.current_health == hp_before - 1000.0, "Queued death prevents additional damage")
	await process_frame
	await process_frame
	var still_registered := false
	for enemy in grid._enemies:
		if enemy.get_instance_id() == dead_id:
			still_registered = true
	check(spawner.get_active_enemy_count() == count_before - 1 and not still_registered, "Death decrements active tracking and unregisters spatial grid")
	var pickups: Array[XPPickup] = []
	var blood := 0
	for child in main.get_children():
		if child is XPPickup:
			pickups.append(child)
		if child is CPUParticles2D:
			blood += 1
	check(blood == 1 and pickups.size() == 2, "Death emits existing blood effect and two MID skulls on double proc")
	for pickup in pickups:
		check(pickup.xp_value == 5 and pickup.visual.texture == neighbor.mid_xp_reward.texture, "MID skull has real existing art and value")
	player.combat_stats.modifiers[&"xp_gain"] = 0.1
	player.combat_stats.add_modifier(&"pickup_radius", 0.5)
	check(player.get_pickup_radius() == 90.0, "Auto-Senses preserves real collection radius")
	player.level = 1
	player.xp = 0.0
	pickups[0].position = player.position + Vector2(75, 0)
	await physics_frame
	await physics_frame
	check(pickups[0]._magnetized, "MID Ork drop collects through enlarged Auto-Senses radius")
	pickups[0].position = player.position
	pickups[0]._process(0.016)
	check(is_equal_approx(player.xp, 5.5), "Purity Seals modifies collected Ork XP through existing player path")
	await create_timer(0.4).timeout
	# Explicit mixed bursts exercise shared enemy registration and count handling.
	neighbor.queue_free()
	await process_frame
	for burst in 40:
		spawner._spawn_burst(5, ORK_SCENE if burst % 10 == 0 else EnemySpawner.ENEMY_SCENE)
	var mixed_orks := 0
	for enemy in grid._enemies:
		enemy.set_physics_process(false)
		if enemy.damage_tier == Enemy.DamageTier.TIER_2:
			mixed_orks += 1
	check(grid._enemies.size() == 200 and spawner.get_active_enemy_count() == 200 and mixed_orks > 0 and mixed_orks < 50, "Mixed bursts register and track every enemy independently")
	grid._rebuild_grid()
	var started := Time.get_ticks_usec()
	for enemy in grid._enemies:
		enemy._calculate_separation_direction()
	print("200 mixed-enemy local separation queries: %.2f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(grid.get_average_candidate_count() < 100.0, "Separation stays local in a mixed swarm")
	print("PASS: %d Ork Boy checks" % checks)
	main.queue_free()
	await process_frame
	quit()
