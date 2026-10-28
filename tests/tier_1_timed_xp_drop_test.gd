extends SceneTree

var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var clock: RunClock = main.get_node("RunClock")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var player: Player = main.get_node("Player")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var panel = main.get_node("CharacterInfoPanel")
	spawner.set_process(false)
	clock.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	spawner._spawn_enemy(Vector2(1000, 0))
	var enemy := main.get_child(main.get_child_count() - 1) as Enemy
	enemy.set_physics_process(false)
	check(enemy.run_clock == clock, "Spawner injects existing gameplay clock")
	check(enemy.low_xp_reward.xp_per_pickup == 1 and enemy.mid_xp_reward.xp_per_pickup == 5, "Existing XP values unchanged")
	check(enemy.low_xp_reward.double_drop_chance == 0.07 and enemy.mid_xp_reward.double_drop_chance == 0.10, "Existing LOW and MID resources unchanged")
	var mid_texture := preload("res://assets/art/effects/xp/mid_level/Skull_head_with_little_wings_blue.png")
	check(enemy.mid_xp_reward.texture == mid_texture, "Uses existing assigned MID PNG")
	for seconds in [0.0, 299.0, 299.999]:
		clock.elapsed_time = seconds
		for _sample in 1000:
			check(enemy.roll_xp_reward() == enemy.low_xp_reward, "Only LOW before five minutes")
	# No tier RNG is consumed before unlock; the old quantity roll stays first.
	clock.elapsed_time = 299.999
	seed(12)
	var expected_next := randf()
	seed(12)
	enemy.roll_xp_reward()
	check(randf() == expected_next, "Pre-unlock drops do not add a tier roll")
	clock.elapsed_time = 300.0
	seed(123456)
	var mid_count := 0
	var doubles := 0
	var mid_doubles := 0
	for _sample in 100000:
		var reward := enemy.roll_xp_reward()
		var count := enemy.low_xp_reward.roll_pickup_count()
		check(reward in [enemy.low_xp_reward, enemy.mid_xp_reward] and count in [1, 2], "Only allowed tier and quantity outcomes")
		if reward == enemy.mid_xp_reward:
			mid_count += 1
			if count == 2:
				mid_doubles += 1
		if count == 2:
			doubles += 1
	check(absf(mid_count / 100000.0 - 0.10) < 0.01, "Approximately ten percent MID and ninety percent LOW")
	check(absf(doubles / 100000.0 - 0.07) < 0.005, "Approximately seven percent double drops")
	check(mid_doubles > 0, "MID and double rolls can coincide")
	print("100000 rolls: MID=", mid_count, " LOW=", 100000 - mid_count, " doubles=", doubles, " MID doubles=", mid_doubles)
	# Find a deterministic MID double seed, then kill the already spawned enemy.
	var double_seed := -1
	for value in 10000:
		seed(value)
		if enemy.roll_xp_reward() == enemy.mid_xp_reward and enemy.low_xp_reward.roll_pickup_count() == 2:
			double_seed = value
			break
	check(double_seed >= 0, "A MID double seed exists")
	seed(double_seed)
	enemy.die()
	enemy.die()
	await process_frame
	var pickups: Array[XPPickup] = []
	for child in main.get_children():
		if child is XPPickup:
			pickups.append(child)
	check(pickups.size() == 2, "One death creates exactly two MID pickups with duplicate death ignored")
	for pickup in pickups:
		check(pickup.xp_value == 5 and pickup.visual.texture == mid_texture, "Every skull from MID double has existing MID value and visual")
		check(pickup.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and pickup._idle_tween != null, "Pixel filtering and idle bobbing preserved")
	check(not pickups[0].position.is_equal_approx(pickups[1].position), "Double skull spacing preserved")
	pickups[0].start_collecting(player)
	check(pickups[0]._magnetized and pickups[0]._idle_tween == null, "Existing magnet starts and idle animation stops")
	for pickup in pickups:
		pickup.queue_free()
	# Other explicit enemy XP tiers keep their original reward rules.
	var other := Enemy.new()
	other.set_run_clock(clock)
	for tier: Enemy.XPTier in [Enemy.XPTier.MID, Enemy.XPTier.HIGH, Enemy.XPTier.BOSS]:
		other.xp_tier = tier
		check(other.roll_xp_reward() == other.get_xp_reward(), "Other XP tiers unchanged")
	other.xp_tier = Enemy.XPTier.LOW
	other.damage_tier = Enemy.DamageTier.HIGH
	check(other.roll_xp_reward() == other.low_xp_reward, "Time rule applies only to Tier 1")
	other.damage_tier = Enemy.DamageTier.TIER_1
	other.set_run_clock(null)
	check(other.roll_xp_reward() == other.low_xp_reward, "Standalone enemy with no clock remains LOW")
	other.free()
	# Real SceneTree pauses at the threshold must not unlock the rule early.
	clock.elapsed_time = 299.999
	spawner._spawn_enemy(Vector2(1000, 0))
	var timed := main.get_child(main.get_child_count() - 1) as Enemy
	timed.set_physics_process(false)
	clock.elapsed_time = 299.999
	clock.set_process(true)
	player.level = 2
	rewards.queue_level()
	await create_timer(0.1).timeout
	check(clock.elapsed_time == 299.999 and timed.roll_xp_reward() == timed.low_xp_reward, "Normal menu excludes paused time from unlock")
	rewards.select_upgrade(rewards.offered[0].id)
	player.level = 10
	rewards.queue_level()
	await create_timer(0.1).timeout
	check(clock.elapsed_time == 299.999 and timed.roll_xp_reward() == timed.low_xp_reward, "Chapter menu excludes paused time from unlock")
	rewards.select_chapter_perk(rewards.chapter_offered[0].id)
	panel.open_panel()
	await create_timer(0.1).timeout
	check(clock.elapsed_time == 299.999 and timed.roll_xp_reward() == timed.low_xp_reward, "Character Info excludes paused time from unlock")
	panel.close_panel()
	paused = true
	await create_timer(0.1).timeout
	check(clock.elapsed_time == 299.999, "Generic pause excludes paused time")
	paused = false
	await create_timer(0.05).timeout
	check(clock.elapsed_time >= 300.0, "Active gameplay resumes clock past threshold")
	clock.set_process(false)
	seed(double_seed)
	timed.die()
	await process_frame
	var mids := 0
	for child in main.get_children():
		if child is XPPickup:
			check(child.xp_value == 5 and child.visual.texture == mid_texture, "Enemy born before unlock rolls MID at death after unlock")
			mids += 1
	check(mids == 2, "Death uses current time and Tier 1 seven-percent quantity rule")
	print("PASS: %d time-based Tier 1 XP checks" % checks)
	main.queue_free()
	await process_frame
	quit()
