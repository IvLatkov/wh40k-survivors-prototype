extends SceneTree

var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func f10() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func run() -> void:
	root.size = Vector2i(1152, 648)
	for shortcut in [false, true]:
		var main := preload("res://scenes/main.tscn").instantiate() as Node2D
		root.add_child(main)
		current_scene = main
		var player: Player = main.get_node("Player")
		var clock: RunClock = main.get_node("RunClock")
		var spawner: EnemySpawner = main.get_node("EnemySpawner")
		var encounter: BossEncounter = main.get_node("BossEncounter")
		player.set_physics_process(false)
		player.get_node("Bolter/FireTimer").stop()
		player.get_node("KnifeAttack").set_physics_process(false)
		clock.set_process(false)
		clock.advance_to(599.999)
		check(spawner.normal_spawning_enabled and spawner.is_processing() and not encounter.warboss_spawned, "Normal scheduler remains enabled before 10:00")
		spawner._schedule_next_normal_spawn()
		spawner._process(spawner._next_normal_spawn_delay)
		var survivors := spawner.spatial_grid._enemies.duplicate()
		var squigs: Array[Enemy] = []
		var orks: Array[Enemy] = []
		for enemy: Enemy in survivors:
			if enemy is OrkBoy:
				orks.append(enemy)
			else:
				squigs.append(enemy)
		check(squigs.size() > 0 and orks.size() > 0, "Real pre-10:00 scheduler still produces both Squigs and additive Orks")
		var count := spawner.get_active_enemy_count()
		var squig := squigs[0]
		var ork := orks[0] as OrkBoy
		var health_before: Array[float] = []
		for enemy: Enemy in survivors:
			health_before.append(enemy.current_health)
		# Almost-due spawn and already-deferred work cannot slip past the cutoff.
		spawner._elapsed_time = spawner._next_normal_spawn_delay - 0.0001
		spawner._spawn_enemy.call_deferred(Vector2(500, 0), spawner.ENEMY_SCENE)
		spawner._spawn_enemy.call_deferred(Vector2(500, 0), spawner.tier_2_enemy_scene)
		if shortcut:
			f10()
		else:
			clock.advance_to(600.0)
		check(encounter.warboss_spawned and is_instance_valid(encounter.boss), "Same production Warboss spawns at 10:00, naturally and via F10")
		var boss := encounter.boss
		boss.set_physics_process(false)
		check(not spawner.normal_spawning_enabled and not spawner.is_processing(), "Actual spawn scheduler is disabled at encounter start")
		check(spawner._elapsed_time == 0.0 and not spawner._has_scheduled_normal_spawn and is_inf(spawner._next_normal_spawn_delay), "Pending elapsed delay is canceled")
		check(spawner.get_active_enemy_count() == count and spawner.spatial_grid._enemies.size() == count + 1, "Transition preserves all survivors and adds only one boss")
		for index in survivors.size():
			var enemy := survivors[index] as Enemy
			check(is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.current_health == health_before[index] and enemy.is_physics_processing(), "Existing mob health/lifetime/AI stays untouched")
		check(spawner.spatial_grid.is_physics_processing() and spawner.spatial_grid.can_process(), "Stopping idle spawn callback leaves spatial-grid physics active")
		await process_frame
		await process_frame
		check(spawner.get_active_enemy_count() == count, "Already-deferred normal spawn calls are rejected after cutoff")
		for seconds in [601.0, 720.0, 1200.0]:
			clock.advance_to(seconds)
			spawner._process(100.0)
			spawner._spawn_burst(5)
			spawner._spawn_burst(5, spawner.tier_2_enemy_scene)
			spawner._spawn_additional_orks()
			spawner._schedule_next_normal_spawn()
			check(spawner.get_active_enemy_count() == count and not spawner._has_scheduled_normal_spawn, "No late scheduler/burst/additive callback can generate or reschedule either mob type")
		clock.seconds_changed.emit(600)
		f10()
		check(spawner.spatial_grid._enemies.filter(func(e: Enemy): return e is Warboss).size() == 1, "Repeated time events and F10 cannot duplicate the boss")
		# Live physics, not just enabled flags: survivors still chase and attack.
		squig.position = player.position + Vector2(180, 0)
		ork.position = player.position + Vector2(220, 100)
		var squig_at := squig.position
		var ork_at := ork.position
		await create_timer(0.2).timeout
		check(squig.position != squig_at and ork.position != ork_at, "Existing Squig and Ork continue moving through live physics")
		squig.position = player.position + Vector2(30, 0)
		var hp := player.current_health
		await physics_frame
		await physics_frame
		await process_frame
		check(player.current_health < hp and not squig._contact_knockback_ready, "Surviving Squig still applies its normal contact attack")
		squig.position = player.position + Vector2(600, 0)
		player.current_health = player.max_health
		player.damage_invulnerability_timer.stop()
		ork.position = player.position + Vector2(60, 0)
		hp = player.current_health
		await create_timer(1.1).timeout
		check(ork.attack_damage_applied and player.current_health < hp, "Surviving Ork still executes its normal melee attack")
		squig.position = Vector2(1000, 1000)
		ork.position = Vector2(-1000, -1000)
		squig.take_damage(9999)
		ork.take_damage(9999)
		await process_frame
		await process_frame
		check(not is_instance_valid(squig) and not is_instance_valid(ork) and spawner.get_active_enemy_count() == count - 2, "Survivors still take damage, die and update normal population count")
		var pickups := 0
		for child in main.get_children():
			pickups += int(child is XPPickup)
		check(pickups >= 2, "Normal enemy death rewards still work")
		spawner._process(100.0)
		check(spawner.get_active_enemy_count() == count - 2, "Killed survivors are not replenished during boss encounter")
		boss.take_damage(9999)
		check(encounter.run_ended and paused and encounter.hud.get_node("HUD/Victory").visible, "Existing Warboss Victory behavior remains intact")
		main.queue_free()
		await process_frame
		await process_frame
		paused = false
	print("PASS: ", checks, " boss spawn-stop / survivor AI / F10 checks")
	quit()
