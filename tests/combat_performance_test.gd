extends SceneTree

const WARMUP := 60
const FRAMES := 1800
const TARGET := 200
var main: Node2D
var player: Player
var spawner: EnemySpawner
var totals: Dictionary = {}
var cpu_totals: Dictionary = {}
var cpu_max: Dictionary = {}
var query_totals: Dictionary = {}
var spikes: Array = []
var samples: Array[float] = []
var serial := 0
var active_projectiles := 0
var active_orks := 0
var active_pickups := 0
var initial_nodes := 0
var enemy_sum := 0
var min_enemies := TARGET
var live_nodes := 0
var memory_samples: Array = []
var node_samples: Array = []

func _initialize() -> void:
	run.call_deferred()

func added(node: Node) -> void:
	live_nodes += 1
	if node is BoltProjectile:
		active_projectiles += 1
		CombatProfile.count_event(&"projectiles_spawned")
	elif node is OrkBoy:
		active_orks += 1
	elif node is XPPickup:
		active_pickups += 1
		CombatProfile.count_event(&"xp_spawned")

	elif node is KnifeSlashEffect or node is ExplosionEffect or node is CPUParticles2D:
		CombatProfile.count_event(&"vfx_spawned")

func removed(node: Node) -> void:
	live_nodes -= 1
	if node is BoltProjectile: active_projectiles -= 1
	if node is OrkBoy: active_orks -= 1
	if node is XPPickup: active_pickups -= 1
	CombatProfile.count_event(&"cleanup_nodes")

func replenish() -> void:
	while spawner.get_active_enemy_count() < TARGET:
		var angle := serial * 2.399963229728653
		var at := player.position + Vector2.from_angle(angle) * (180.0 + serial % 5 * 30.0)
		var ork := serial % 4 == 0
		spawner._spawn_enemy(at, spawner.tier_2_enemy_scene if ork else spawner.ENEMY_SCENE)
		if ork:
			(spawner.spatial_grid._enemies.back() as OrkBoy)._attack_rng.seed = 741 + serial
		serial += 1

func accumulate() -> void:
	for key in CombatProfile.counts:
		totals[key] = int(totals.get(key, 0)) + CombatProfile.counts[key]
	for key in CombatProfile.costs:
		cpu_totals[key] = int(cpu_totals.get(key, 0)) + CombatProfile.costs[key]
		cpu_max[key] = maxi(int(cpu_max.get(key, 0)), CombatProfile.costs[key])
	for key in CombatProfile.queries:
		var entry: Array = query_totals.get(key, [0, 0, 0])
		var frame_entry: Array = CombatProfile.queries[key]
		entry[0] += frame_entry[0]
		entry[1] += frame_entry[1]
		entry[2] = maxi(entry[2], frame_entry[2])
		query_totals[key] = entry

func run() -> void:
	root.size = Vector2i(1152, 648)
	initial_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	seed(741)
	CombatProfile.enabled = true
	node_added.connect(added)
	node_removed.connect(removed)
	main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	spawner = main.get_node("EnemySpawner")
	spawner.set_process(false)
	main.get_node("RunClock").set_process(false)
	# Keep pickups/XP functional while removing reward menus from timing.
	player.leveled_up.disconnect(main.get_node("UpgradeSystem").queue_level)
	var stats := player.combat_stats
	stats.add_modifier(&"projectile_count", 4)
	stats.add_modifier(&"fire_rate", 0.5)
	stats.add_modifier(&"knife_range", 0.5)
	stats.crit_chance = 0.075
	var bolter := player.get_node("Bolter")
	bolter.activate_ultimate(&"devastator_shells")
	bolter.activate_ultimate(&"forking_rounds")
	player.get_node("KnifeAttack").activate_ultimate(&"whirlwind_assault")
	root.warp_mouse(Vector2(1100, 324))
	replenish()
	await process_frame
	var start := Time.get_ticks_usec()
	for frame in WARMUP + FRAMES:
		CombatProfile.clear_frame()
		player.current_health = player.max_health
		# Bounded movement uses production input/acceleration, no terrain crossings.
		var phase := frame % 240
		Input.action_release(&"move_right")
		Input.action_release(&"move_left")
		if phase >= 100 and phase < 130: Input.action_press(&"move_right")
		if phase >= 160 and phase < 190: Input.action_press(&"move_left")
		replenish()
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - start) / 1000.0
		start = now
		if frame < WARMUP: continue
		enemy_sum += spawner.get_active_enemy_count()
		min_enemies = mini(min_enemies, spawner.get_active_enemy_count())
		samples.append(ms)
		accumulate()
		if ms > 25.0:
			var spike := {"frame": frame - WARMUP, "ms": ms, "enemies": spawner.get_active_enemy_count(), "orks": active_orks, "squigs": spawner.get_active_enemy_count() - active_orks, "projectiles": active_projectiles, "events": CombatProfile.counts.duplicate(), "cpu_us": CombatProfile.costs.duplicate()}
			spikes.append(spike)
		if frame % 300 == 0:
			memory_samples.append(Performance.get_monitor(Performance.MEMORY_STATIC))
			node_samples.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	samples.sort()
	var sum := 0.0
	var over := [0, 0, 0, 0]
	for ms in samples:
		sum += ms
		for i in 4:
			if ms > [16.7, 25.0, 33.3, 50.0][i]: over[i] += 1
	var average := sum / FRAMES
	var cpu: Dictionary = {}
	for key in cpu_totals:
		cpu[key] = {"average_ms_per_frame": cpu_totals[key] / 1000.0 / FRAMES, "max_ms_per_frame": cpu_max[key] / 1000.0}
	var queries: Dictionary = {}
	for key in query_totals:
		var q: Array = query_totals[key]
		queries[key] = {"count": q[0], "average_candidates": float(q[1]) / maxi(1, q[0]), "worst_candidates": q[2]}
	var result := {"seed": 741, "warmup": WARMUP, "frames": FRAMES, "renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(), "average_ms": average, "median_ms": samples[FRAMES / 2], "p95_ms": samples[ceili(FRAMES * 0.95) - 1], "p99_ms": samples[ceili(FRAMES * 0.99) - 1], "worst_ms": samples.back(), "fps": 1000.0 / average, "over_16_7_25_33_3_50": over, "events": totals, "cpu": cpu, "queries": queries, "memory_bytes_every_300_frames": memory_samples, "nodes_every_300_frames": node_samples, "spikes": spikes}
	var label := "latest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	result["average_active_enemies"] = float(enemy_sum) / FRAMES
	result["minimum_active_enemies"] = min_enemies
	result["remaining_xp_pickups"] = active_pickups
	assert(totals.get(&"numbers_spawned", 0) == totals.get(&"damage_events", 0), "Exactly one number per damage event")
	assert(totals.get(&"death", 0) == totals.get(&"xp_creation", 0), "Exactly one XP drop operation per death")
	var file := FileAccess.open("res://docs/combat_" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	var summary := result.duplicate()
	summary.erase("spikes")
	print("COMBAT_BENCHMARK ", JSON.stringify(summary))
	print("SPIKE_DETAILS docs/combat_", label, ".json count=", spikes.size())
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/combat_benchmark.png")
	Input.action_release(&"move_right")
	Input.action_release(&"move_left")
	CombatProfile.enabled = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await create_timer(0.5).timeout
	main.queue_free()
	await process_frame
	await process_frame
	result["nodes_before_world"] = initial_nodes
	result["nodes_after_cleanup"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	assert(result["nodes_after_cleanup"] == initial_nodes, "Benchmark world fully cleans up")
	file.seek(0)
	file.store_string(JSON.stringify(result, "  "))
	print("CLEANUP nodes_before=", initial_nodes, " nodes_after=", result["nodes_after_cleanup"])
	quit()
