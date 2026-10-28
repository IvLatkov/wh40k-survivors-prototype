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
	for facing_right in [true, false]:
		var main := preload("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		var player: Player = main.get_node("Player")
		var knife: KnifeAttack = player.get_node("KnifeAttack")
		var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
		var menu = main.get_node("UpgradeMenu")
		main.get_node("EnemySpawner").set_process(false)
		player.set_physics_process(false)
		knife.set_physics_process(false)
		player.get_node("Bolter/FireTimer").stop()
		player.facing_right = facing_right
		var direction := Vector2.RIGHT if facing_right else Vector2.LEFT
		var range_upgrade: UpgradeDefinition
		for definition in rewards.definitions:
			if definition.id == &"knife_range":
				range_upgrade = definition
		# Keep the real three-choice menu; make the range card available deterministically.
		rewards.definitions = [range_upgrade, rewards.definitions[0], rewards.definitions[1]]
		var offsets: Array[Vector2] = [Vector2(59, 0), Vector2(44, 44), Vector2(44, -44), Vector2(0, 71), Vector2(77, 0), Vector2(80, 0), Vector2(83, 0), Vector2(-59, 0), Vector2(-44, 44)]
		var enemies: Array[Enemy] = []
		for offset in offsets:
			var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
			enemy.max_health = 50.0 # Keep repeated radius checks nonlethal.
			enemy.position = Vector2(offset.x * direction.x, offset.y)
			main.add_child(enemy)
			enemy.set_physics_process(false)
			enemies.append(enemy)
		var expected_radii := [55.0, 60.5, 66.0, 71.5, 77.0, 82.5]
		for selections in range(6):
			if selections > 0:
				player.add_xp(player.get_xp_required())
				check(paused and menu.visible and rewards.offered.size() == 3, "Actual level-up menu shown")
				var range_button: Button
				for child in menu.choices_container.get_children():
					if child.text.begins_with("KNIFE RANGE"):
						range_button = child
				check(range_button != null and range_button.text.contains("Lv. %d / 5" % (selections - 1)), "Displayed selected count before purchase")
				range_button.pressed.emit()
				check(not paused and not menu.visible and int(rewards.levels[&"knife_range"]) == selections, "Selection applies once and updates count")
			check(knife.melee_range == 55.0, "Original base radius never changes")
			check(is_equal_approx(player.combat_stats.get_modifier(&"knife_range"), selections * 0.1), "Total bonus stacks additively")
			check(is_equal_approx(knife.current_knife_radius, expected_radii[selections]), "Exact expected radius")
			check(is_equal_approx(knife.detection_shape.shape.radius, expected_radii[selections]), "Collision shape synchronizes immediately")
			await physics_frame
			await physics_frame
			for enemy in enemies:
				enemy.current_health = 50.0
			knife.cooldown_timer.stop()
			knife._attack()
			for index in enemies.size():
				var offset := offsets[index]
				var expected_hit: bool = offset.x >= 0.0 and offset.length() <= expected_radii[selections]
				check(enemies[index].current_health == (15.0 if expected_hit else 50.0), "Real hit matches upgraded directional radius, including diagonals")
			for child in main.get_children():
				if child is KnifeSlashEffect:
					check(is_equal_approx(child.scale.x, 1.0 + selections * 0.1), "Slash scale matches gameplay radius")
					check(is_equal_approx(child.position.dot(direction), expected_radii[selections] * 0.5), "Slash position matches gameplay radius")
					child.queue_free()
			await process_frame
		check(knife.melee_damage == 35.0 and knife.melee_cooldown == 0.8, "Damage and cooldown unchanged")
		check(is_zero_approx(player.combat_stats.get_modifier(&"crit_chance")), "Range upgrade does not change crit chance")
		main.queue_free()
		await process_frame
	print("PASS: %d knife range upgrade checks" % checks)
	quit()

