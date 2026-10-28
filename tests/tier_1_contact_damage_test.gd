extends SceneTree

var checks: int = 0

class CountingEnemy extends Enemy:
	var rolls: int = 0
	func get_attack_damage() -> float:
		rolls += 1
		return super.get_attack_damage()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	world.add_child(player)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var enemy := CountingEnemy.new()
	var visual := AnimatedSprite2D.new()
	visual.name = "Visual"
	visual.sprite_frames = SpriteFrames.new()
	for animation: StringName in Enemy.SQUIG_ANIMATIONS:
		visual.sprite_frames.add_animation(animation)
	enemy.add_child(visual)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_target(player)
	seed(123456)
	var counts: Array[int] = [0, 0, 0]
	for _sample in 100000:
		var raw := enemy.get_attack_damage()
		check(raw in [1.0, 2.0, 3.0], "Tier 1 raw damage is 1, 2, or 3")
		counts[int(raw) - 1] += 1
	for index in 3:
		var expected: float = [0.70, 0.25, 0.05][index]
		check(absf(counts[index] / 100000.0 - expected) < 0.01, "Weighted frequency within one percentage point")
	print("Tier 1 distribution over 100000 rolls: ", counts)
	for armor in 3:
		player.combat_stats.modifiers.clear()
		player.combat_stats.modifiers[&"armor"] = float(armor)
		for raw in [1.0, 2.0, 3.0]:
			player.current_health = player.max_health
			player.damage_invulnerability_timer.stop()
			player.take_damage(raw)
			check(player.current_health == player.max_health - maxf(1.0, raw - armor), "Armor reduces raw damage with minimum one")
	# Seed replay verifies the contact path sends the actual raw roll to Armor.
	for armor in 3:
		player.combat_stats.modifiers[&"armor"] = float(armor)
		for event_seed in range(100):
			seed(event_seed)
			var expected_raw := enemy.get_attack_damage()
			seed(event_seed)
			player.current_health = player.max_health
			player.damage_invulnerability_timer.stop()
			enemy.position = player.position + Vector2(20, 0)
			enemy._is_knocked_back = false
			enemy._contact_knockback_ready = true
			var before_rolls := enemy.rolls
			enemy._physics_process(0.016)
			check(enemy.rolls == before_rolls + 1, "One roll per eligible contact")
			check(player.current_health == player.max_health - maxf(1.0, expected_raw - armor), "Contact rolls before Armor")
	var rolls_before := enemy.rolls
	var hp_before := player.current_health
	for _frame in 30:
		enemy.position = player.position + Vector2(20, 0)
		enemy._physics_process(0.016)
	check(enemy.rolls == rolls_before and player.current_health == hp_before, "Knockback and held contact do not repeat attacks")
	enemy.position = player.position + Vector2(100, 0)
	enemy._physics_process(0.016)
	check(enemy._contact_knockback_ready, "Leaving contact rearms existing gate")
	enemy.position = player.position + Vector2(20, 0)
	enemy._physics_process(0.016)
	check(enemy.rolls == rolls_before and player.current_health == hp_before, "Invulnerability rejects contact without a roll")
	check(enemy._is_knocked_back and not enemy._contact_knockback_ready, "Rejected contact keeps existing knockback timing")
	enemy._is_knocked_back = false
	enemy.position = player.position + Vector2(100, 0)
	enemy._physics_process(0.016)
	player.damage_invulnerability_timer.stop()
	enemy.position = player.position + Vector2(20, 0)
	enemy._physics_process(0.016)
	check(enemy.rolls == rolls_before + 1, "Re-entry after invulnerability accepts one attack")
	player._is_dead = true
	check(not player.can_take_damage(), "Dead players cannot accept damage")
	for tier: Enemy.DamageTier in [Enemy.DamageTier.MID, Enemy.DamageTier.HIGH, Enemy.DamageTier.BOSS]:
		enemy.damage_tier = tier
		enemy.contact_damage = 7.0
		check(enemy.get_attack_damage() == 7.0, "Other tiers retain configured fixed damage")
	print("PASS: %d Tier 1 contact damage checks" % checks)
	world.queue_free()
	await process_frame
	quit()
