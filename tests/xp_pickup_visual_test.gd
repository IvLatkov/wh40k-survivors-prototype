extends SceneTree

const PICKUP := preload("res://scenes/pickups/xp_pickup.tscn")
const REWARDS: Array[XPReward] = [
	preload("res://assets/art/effects/xp/low_level/xp_reward.tres"),
	preload("res://assets/art/effects/xp/mid_level/xp_reward.tres"),
	preload("res://assets/art/effects/xp/high_level/xp_reward.tres"),
	preload("res://assets/art/effects/xp/boss/xp_reward.tres"),
]
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)
	if not condition: quit(1)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var material_ids: Dictionary = {}
	var shader_ids: Dictionary = {}
	var shadow_ids: Dictionary = {}
	var pickups: Array[XPPickup] = []
	for tier in 4:
		for copy in 2:
			var pickup := PICKUP.instantiate() as XPPickup
			pickup.configure(REWARDS[tier])
			seed(147)
			var expected_rng := randf_range(0, pickup.idle_bob_duration)
			var expected_next := randf()
			seed(147)
			root.add_child(pickup)
			check(randf() == expected_next and expected_rng >= 0, "Only the existing bob phase consumes global RNG")
			pickups.append(pickup)
			check(pickup.xp_value == [1, 5, 15, 25][tier], "XP amount unchanged, boss remains four 25-XP skulls")
			check(REWARDS[tier].pickup_count == [1, 1, 1, 4][tier] and REWARDS[tier].double_drop_chance == [0.07, 0.10, 0.15, 0.0][tier], "Drop quantity/probabilities untouched")
			check(pickup.visual.scale == Vector2(1.12, 1.12) and pickup.scale == Vector2.ONE, "Only sprite scale increases 12 percent")
			check(pickup.visual.texture == REWARDS[tier].texture and pickup.visual.modulate == Color.WHITE, "Original skull artwork and tint retained")
			check(pickup.visual.material == XPPickup.TIER_MATERIALS[tier], "Fixed shared tier material")
			material_ids[pickup.visual.material.get_instance_id()] = true
			shader_ids[(pickup.visual.material as ShaderMaterial).shader.get_instance_id()] = true
			var shadow := pickup.get_node("Shadow") as Sprite2D
			shadow_ids[shadow.texture.get_instance_id()] = true
			check(shadow.position == Vector2(0, 5) and shadow.get_parent() == pickup and shadow.get_child_count() == 0 and shadow.z_index == -1, "Shadow is grounded and has no collision")
			check(pickup.z_index == -1 and pickup.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Original z-order and nearest filtering")
			check((pickup.get_node("CollisionShape2D").shape as CircleShape2D).radius == 8.0 and pickup.collision_layer == 8 and pickup.collision_mask == 0, "Collision unchanged")
			check(pickup.travel_speed == 220.0 and pickup.maximum_travel_speed == 360.0 and pickup.travel_acceleration == 600.0 and pickup.arrival_distance == 10.0, "Magnet and collection distances/speeds unchanged")
			check(pickup.idle_bob_distance == 2.0 and pickup.idle_bob_duration == 1.2 and pickup._idle_tween != null, "Existing bob configuration")
	check(material_ids.size() == 4 and shader_ids.size() == 1 and shadow_ids.size() == 1, "Four shared materials, one shader and one shadow texture")
	check(pickups[0].visual.get_instance_shader_parameter(&"pulse_phase") != pickups[1].visual.get_instance_shader_parameter(&"pulse_phase"), "Visual phases differ without extra gameplay RNG")
	var pickup := pickups[0]
	pickup._idle_tween.custom_step(0.3)
	check(absf(pickup.visual_root.position.y) <= 2.0 and pickup.get_node("Shadow").position.y == 5.0, "Bob cannot move shadow or gameplay root")
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	player.position = Vector2(1000, 0)
	pickup.start_collecting(player)
	check(pickup._magnetized and pickup._idle_tween == null and pickup.visual_root.position == Vector2.ZERO, "Existing magnet state stops bob without touching pulse scale")
	check(is_equal_approx(pickup.visual.get_instance_shader_parameter(&"magnet_strength"), 1.2), "Magnet state only strengthens this instance's outline")
	check(pickups[1].visual.get_instance_shader_parameter(&"magnet_strength") == 1.0, "Shared material does not leak instance state")
	pickup._process(0.1)
	check(is_equal_approx(pickup.position.x, 28.0), "Existing acceleration produces the original 28px movement over 0.1s")
	player.queue_free()
	await process_frame
	pickup._process(0.016)
	check(not pickup._magnetized and pickup._idle_tween != null and pickup.visual.get_instance_shader_parameter(&"magnet_strength") == 1.0, "Lost target restores idle bob and outline intensity")
	var references: Array[WeakRef] = []
	for item in pickups:
		references.append(weakref(item))
		item.queue_free()
	await process_frame
	await process_frame
	for reference in references: check(reference.get_ref() == null, "Pickup nodes release cleanly")
	print("PASS: ", checks, " XP visual/isolation checks")
	quit()
