extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var ork: OrkBoy

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func begin_attack(offset: Vector2 = Vector2(60, 0)) -> void:
	ork._finish_attack()
	ork._cooldown_remaining = 0.0
	ork.position = player.position - offset
	player.current_health = player.max_health
	player.damage_invulnerability_timer.stop()
	ork._physics_process(0.016)
	check(ork.state == OrkBoy.State.CHASE and ork._pre_attack_remaining >= 0.10 and ork._pre_attack_remaining <= 0.30, "Range entry schedules one short random preparation")
	ork._physics_process(0.31)
	check(ork.state == OrkBoy.State.WINDUP and ork.visual.animation == &"attack", "Range entry starts attack animation")
	check(ork.velocity == Vector2.ZERO and ork.get_node("CollisionShape2D").disabled == false, "Swing stops movement while body collision remains enabled")

func frame_ground() -> Vector2:
	# All AtlasTexture margins use a shared feet anchor at (512, 712).
	return ork.visual.position + Vector2(0, 200.0 * ork.visual.scale.y)

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var clock: RunClock = main.get_node("RunClock")
	clock.set_process(false)
	spawner.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	spawner._spawn_enemy(Vector2(200, 0), spawner.tier_2_enemy_scene)
	ork = spawner.spatial_grid._enemies.back() as OrkBoy
	ork.set_physics_process(false)
	var frames := ork.visual.sprite_frames
	check(frames.get_frame_count(&"walk") == 4 and frames.get_frame_count(&"attack") == 4, "Exactly four frames per sheet")
	check(frames.get_animation_loop(&"walk") and not frames.get_animation_loop(&"attack"), "Walk loops and attack plays once")
	check(frames.get_animation_speed(&"walk") == 6.0 and frames.get_animation_speed(&"attack") == 7.0, "Configured heavy animation rates")
	check(ork.attack_range == 65.0 and ork.hit_range == 75.0 and ork.attack_cooldown == 1.25 and ork.hit_frame == 2, "Melee configuration")
	check(ork.max_health == 50.0 and ork.movement_speed == 50.0, "Ork HP and movement unchanged")
	for animation: StringName in [&"walk", &"attack"]:
		var sheet: Texture2D
		for index in 4:
			var atlas := frames.get_frame_texture(animation, index) as AtlasTexture
			check(atlas != null and atlas.atlas.get_size() == Vector2(1254, 1254), "Atlas uses real sheet dimensions")
			check(atlas.get_size() == Vector2(1024, 1024), "Frames share normalized virtual canvas")
			if index == 0:
				sheet = atlas.atlas
			check(atlas.atlas == sheet, "One original image per animation without duplicated PNGs")
	check(is_equal_approx(frames.get_frame_duration(&"attack", 3) / 7.0, 0.25), "Recovery pose lasts 250ms")
	check(is_equal_approx((frames.get_frame_duration(&"attack", 0) + frames.get_frame_duration(&"attack", 1)) / 7.0, 2.0 / 7.0), "Animation provides 286ms wind-up")
	var squig := EnemySpawner.ENEMY_SCENE.instantiate() as Enemy
	main.add_child(squig)
	squig.set_physics_process(false)
	check(squig.max_health == 25.0 and is_equal_approx(ork.separation_strength / squig.separation_strength, 1.25), "Orks have 25% stronger grid separation; Squig HP unchanged")
	squig.queue_free()
	ork.position = player.position - Vector2(60, 0)
	ork._attack_rng.seed = 723
	ork._physics_process(0.016)
	var pending := ork._pre_attack_remaining
	ork._physics_process(0.01)
	check(is_equal_approx(ork._pre_attack_remaining, pending - 0.01), "Preparation delay is not rerolled every frame")
	player.position.x += 120
	ork._physics_process(0.016)
	check(ork.state == OrkBoy.State.CHASE and ork._pre_attack_remaining < 0.0, "Escape before wind-up cancels preparation")
	player.position = Vector2.ZERO
	ork.take_damage(1.0)
	check(ork.visual.self_modulate.r > 1.5, "All shared damage events brighten the Ork")
	ork.take_damage(1.0)
	ork._physics_process(0.09)
	check(ork.visual.self_modulate == Color.WHITE, "Repeated hits expire back to original tint")
	ork.current_health = ork.max_health
	ork.position = Vector2(-200, 0)
	ork._physics_process(0.016)
	check(ork.velocity.x > 0 and ork.visual.animation == &"walk" and ork.visual.is_playing() and not ork.visual.flip_h, "Rightward chase walks facing right")
	ork.position = Vector2(200, 0)
	ork._physics_process(0.016)
	check(ork.velocity.x < 0 and ork.visual.flip_h, "Leftward chase flips walk sprite")
	var ground := frame_ground()
	begin_attack()
	check(not ork.visual.flip_h, "Attack locks facing toward player on right")
	check(frame_ground().is_equal_approx(ground), "Walk and attack feet stay anchored despite sheet scale correction")
	var hp := player.current_health
	ork.visual.frame = 1
	check(player.current_health == hp and not ork.attack_damage_applied, "Wind-up and swing start do not cause damage")
	seed(83)
	var raw := ork.get_attack_damage()
	seed(83)
	var slashes_before := 0
	for child in main.get_children():
		if child is KnifeSlashEffect: slashes_before += 1
	ork.visual.frame = 2
	var slashes_after := 0
	var strike_slash: KnifeSlashEffect
	for child in main.get_children():
		if child is KnifeSlashEffect:
			slashes_after += 1
			strike_slash = child
	check(slashes_after == slashes_before + 1 and is_zero_approx(strike_slash.rotation), "Right strike emits exactly one right-facing cosmetic slash")
	check(strike_slash.global_position.is_equal_approx(ork.global_position + ork.slash_offset), "Slash is anchored to the locked strike side")
	check(ork.state == OrkBoy.State.SWING and not ork.visual.is_playing() and is_equal_approx(ork._impact_pause_remaining, 0.05), "Successful strike pauses only this Ork for 50ms")
	check(player.current_health == hp - raw and ork.attack_damage_applied, "Third frame applies exactly the weighted raw strike")
	ork._physics_process(0.049)
	check(not ork.visual.is_playing() and ork.state == OrkBoy.State.SWING, "Impact pause remains local through 49ms")
	ork._physics_process(0.001)
	check(ork.visual.is_playing() and is_zero_approx(ork._impact_pause_remaining), "Impact pause resumes at 50ms")
	player.damage_invulnerability_timer.stop()
	ork.visual.frame_changed.emit()
	ork.visual.frame = 3
	check(ork.state == OrkBoy.State.RECOVERY, "Final pose enters recovery")
	check(player.current_health == hp - raw, "Duplicate frame signal and recovery never deal extra damage")
	ork.visual.animation_finished.emit()
	check(ork.state == OrkBoy.State.CHASE and ork.visual.animation == &"walk", "Attack finish returns to chase")
	ork._physics_process(0.2)
	check(ork.state == OrkBoy.State.CHASE, "Cooldown prevents immediate reattack")
	ork._physics_process(1.1)
	ork._physics_process(0.31)
	check(ork.state == OrkBoy.State.WINDUP, "Ready cooldown permits a new attack")
	# Misses consume the one strike without rolling raw damage.
	begin_attack()
	player.position += Vector2(100, 0)
	seed(55)
	var next := randf()
	seed(55)
	ork.visual.frame = 2
	check(player.current_health == player.max_health and ork.attack_damage_applied and randf() == next, "Movement beyond hit range misses without consuming damage RNG")
	player.position = Vector2.ZERO
	begin_attack()
	player.position = ork.position - Vector2(20, 0)
	var locked_flip := ork.visual.flip_h
	ork._physics_process(0.05)
	check(ork.visual.flip_h == locked_flip and ork.state == OrkBoy.State.WINDUP and ork.velocity == Vector2.ZERO, "Committed wind-up keeps facing and position when player runs behind")
	ork.visual.frame = 2
	check(player.current_health == player.max_health, "Swing cannot hit behind its committed facing")
	player.position = Vector2.ZERO
	begin_attack()
	player.damage_invulnerability_timer.start()
	seed(43)
	next = randf()
	seed(43)
	ork.visual.frame = 2
	check(player.current_health == player.max_health and randf() == next, "Invulnerable impact does not roll damage")
	player.combat_stats.modifiers[&"dodge_chance"] = 1.0
	begin_attack()
	ork.visual.frame = 2
	check(player.current_health == player.max_health and not player.can_take_damage(), "Iron Halo dodge remains centralized")
	player.combat_stats.modifiers.clear()
	player.combat_stats.modifiers[&"armor"] = 2.0
	begin_attack()
	seed(14)
	raw = ork.get_attack_damage()
	seed(14)
	ork.visual.frame = 2
	check(player.current_health == player.max_health - maxf(1.0, raw - 2.0), "Armor and minimum damage use Player.take_damage")
	player.combat_stats.modifiers[&"armor"] = 50.0
	begin_attack()
	ork.visual.frame = 2
	check(player.current_health == player.max_health - 1.0, "High Armor still allows minimum one damage")
	player.combat_stats.modifiers.clear()
	# A close body overlap never invokes the former contact/knockback branch.
	begin_attack(Vector2(30, 0))
	check(player.current_health == player.max_health and not ork._is_knocked_back, "No immediate contact hit or contact knockback on Ork")
	ork.visual.play(&"walk")
	ork._physics_process(0.016)
	check(ork.state == OrkBoy.State.CHASE, "Interrupted animation recovers chase state")
	begin_attack()
	ork.visual.pause()
	ork._physics_process(0.016)
	check(ork.state == OrkBoy.State.CHASE, "Stopped attack recovers without a missing finish signal")
	begin_attack()
	ork.visual.speed_scale = 0.0
	ork._physics_process(ork._attack_timeout + 0.1)
	check(ork.state == OrkBoy.State.CHASE and player.current_health == player.max_health, "Stalled animation watchdog cancels without damage")
	ork.visual.speed_scale = 1.0
	begin_attack(Vector2(-60, 0))
	ork.visual.frame = 2
	var left_slash: KnifeSlashEffect
	for child in main.get_children():
		if child is KnifeSlashEffect: left_slash = child
	check(is_equal_approx(cos(left_slash.rotation), -1.0), "Left-facing strike mirrors the slash direction")
	check(left_slash.global_position.is_equal_approx(ork.global_position + Vector2(-ork.slash_offset.x, ork.slash_offset.y)), "Left slash stays on committed side")
	# Actual playback verifies frame_changed and animation_finished signals.
	begin_attack(Vector2(-60, 0))
	check(ork.visual.flip_h, "Attack on left uses same flipped sprite")
	var strike_frames: Array[int] = []
	var record_hit := func(_current: float, _maximum: float) -> void: strike_frames.append(ork.visual.frame)
	player.health_changed.connect(record_hit)
	ork.set_physics_process(true)
	await create_timer(0.85).timeout
	ork.set_physics_process(false)
	player.health_changed.disconnect(record_hit)
	check(strike_frames == [2] and ork.state == OrkBoy.State.CHASE, "Real animation delivers one strike at frame three and completes")
	check(spawner.spatial_grid._enemies.has(ork) and spawner.get_active_enemy_count() == 1, "Attacking Ork remains tracked in shared grid")
	# Optional artifact: all poses on screen, with normalized feet and scale.
	if "--capture-ui" in OS.get_cmdline_user_args():
		player.get_node("Camera2D").zoom = Vector2(2, 2)
		player.get_node("Camera2D").force_update_scroll()
		ork.hide()
		for animation: StringName in [&"walk", &"attack"]:
			for index in 4:
				var pose := load("res://scenes/enemies/ork_boy.tscn").instantiate() as OrkBoy
				main.add_child(pose)
				pose.set_physics_process(false)
				pose.position = Vector2(-210 + index * 140, -90 if animation == &"walk" else 90)
				pose.visual.animation = animation
				pose.visual.stop()
				pose.visual.frame = index
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("survivor_ork_animations.png"))
	# Kill during wind-up, then try a late strike signal before deletion flushes.
	begin_attack()
	var count_before := spawner.get_active_enemy_count()
	var hp_before := player.current_health
	ork.take_damage(1000.0)
	ork.visual.animation = &"attack"
	ork.visual.frame = 2
	ork.visual.frame_changed.emit()
	check(player.current_health == hp_before and ork.is_queued_for_deletion() and not ork.visual.is_playing(), "Dead attacking Ork cannot deliver delayed damage")
	await process_frame
	await process_frame
	check(spawner.get_active_enemy_count() == count_before - 1 and spawner.spatial_grid._enemies.is_empty(), "Attack death clears active count and grid")
	var skulls := 0
	var blood := 0
	for child in main.get_children():
		if child is XPPickup:
			check(child.xp_value == 5, "Melee death still drops MID five XP skull")
			skulls += 1
	# Blood now lives under its scene-owned pool; count active effects only.
	for effect in main.find_children("*", "CPUParticles2D", true, false):
		if (effect as CPUParticles2D).visible:
			blood += 1
	check(skulls in [1, 2] and blood == 1, "Normal death retains skull quantity rules and blood VFX")
	# Every cancellation stage rejects late callbacks, even before queue_free flushes.
	for death_state: OrkBoy.State in [OrkBoy.State.CHASE, OrkBoy.State.WINDUP, OrkBoy.State.SWING, OrkBoy.State.RECOVERY]:
		spawner._spawn_enemy(player.position - Vector2(60, 0), spawner.tier_2_enemy_scene)
		var doomed := spawner.spatial_grid._enemies.back() as OrkBoy
		doomed.set_physics_process(false)
		doomed._start_attack()
		doomed.state = death_state
		if death_state == OrkBoy.State.CHASE: doomed._pre_attack_remaining = 0.2
		doomed.visual.frame = 0
		var hp_at_death := player.current_health
		doomed.take_damage(1000.0)
		doomed.visual.frame = doomed.hit_frame
		doomed.visual.frame_changed.emit()
		doomed._physics_process(1.0)
		check(doomed.is_queued_for_deletion() and doomed._pre_attack_remaining < 0.0 and player.current_health == hp_at_death, "Death cancels all pending attack work in state %s" % death_state)
	await create_timer(0.4).timeout
	for child in main.get_children():
		check(not child is KnifeSlashEffect, "Cosmetic slashes auto-free after strike")
	main.queue_free()
	await process_frame
	print("PASS: %d Ork melee animation checks" % checks)
	quit()
