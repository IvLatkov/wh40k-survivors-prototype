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
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for animation in Enemy.SQUIG_ANIMATIONS:
		var squig := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		world.add_child(squig)
		squig.set_physics_process(false)
		squig.visual.play(animation)
		check(squig.max_health == 25.0 and squig.current_health == 25.0, "Every Squig color starts with twenty five HP")
		check(squig.movement_speed == 60.0 and squig.damage_tier == Enemy.DamageTier.TIER_1, "Squig movement and damage tier unchanged")
		squig.take_damage(12.5)
		check(squig.current_health == 12.5 and not squig.is_queued_for_deletion(), "Fractional damage retains exact remaining health")
		squig.take_damage(12.5)
		check(squig.current_health == 0.0 and squig.is_queued_for_deletion(), "Two half damage hits kill at exactly zero")
	var ork := preload("res://scenes/enemies/ork_boy.tscn").instantiate() as OrkBoy
	world.add_child(ork)
	ork.set_physics_process(false)
	check(ork.max_health == 50.0 and ork.current_health == 50.0, "Ork starts with fifty HP")
	check(ork.movement_speed == 50.0 and ork.attack_cooldown == 1.25 and ork.attack_range == 65.0, "Ork movement and melee configuration unchanged")
	ork.take_damage(13.75)
	check(ork.current_health == 36.25, "Ork HP retains quarters without truncation")
	var amounts := [25.0, 12.5, 13.75, 18.75, 16.5, 0.125]
	var expected := ["25", "12.5", "13.8", "18.8", "16.5", "0.1"]
	for index in amounts.size():
		var number := preload("res://scenes/ui/damage_number.tscn").instantiate() as FloatingDamageNumber
		number.configure(amounts[index], index == 3)
		world.add_child(number)
		check(number.get_node("Label").text == expected[index], "Clean one-decimal damage display")
		check(number.damage_amount == amounts[index], "Formatting never rounds underlying damage")
		if index == 3:
			check(number.get_node("Label").modulate == Color.RED, "Fractional critical number remains red")
	await create_timer(0.4).timeout
	world.queue_free()
	await process_frame
	print("PASS: %d enemy health and fractional damage checks" % checks)
	quit()
