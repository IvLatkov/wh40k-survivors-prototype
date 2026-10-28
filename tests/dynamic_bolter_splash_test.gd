extends SceneTree

var checks: int = 0
var main: Node2D
var bolter: Node2D

class ScriptedStats extends CombatStats:
	var rolls: int = 0
	var critical_results: Array[bool] = [false, true]
	func roll_hit(base_damage: float, _guaranteed_critical: bool = false) -> DamageRoll:
		var critical := critical_results[rolls % critical_results.size()]
		rolls += 1
		return DamageRoll.new(resolve_damage(base_damage, critical), critical)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func fire() -> BoltProjectile:
	bolter._fire()
	var bolt := main.get_child(main.get_child_count() - 1) as BoltProjectile
	bolt.set_physics_process(false)
	bolt.monitoring = false
	return bolt

func enemy_at(scene: PackedScene, at: Vector2) -> Enemy:
	var enemy := scene.instantiate() as Enemy
	enemy.position = at
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("KnifeAttack").set_physics_process(false)
	bolter = player.get_node("Bolter")
	bolter.set_process(false)
	bolter.fire_timer.stop()
	root.warp_mouse(Vector2i(900, 320))
	check(bolter.get_damage() == 25.0 and bolter.get_splash_damage() == 12.5, "Base direct damage unchanged and splash is half")
	for damage in [25.0, 27.5, 30.0, 33.0, 40.0, 50.0]:
		player.combat_stats.modifiers.clear()
		player.combat_stats.add_modifier(&"bolter_damage", damage / 25.0 - 1.0)
		check(is_equal_approx(bolter.get_damage(), damage) and is_equal_approx(bolter.get_splash_damage(), damage * 0.5), "Current Bolter damage automatically updates splash")
		var bolt := fire()
		check(is_equal_approx(bolt.damage, damage) and is_equal_approx(bolt.splash_damage, damage * 0.5), "Real fired projectile snapshots current damage and derives splash")
		bolt.damage += 3.5
		check(is_equal_approx(bolt.splash_damage, bolt.damage * 0.5), "Projectile damage changes cannot leave stale independent splash")
		bolt.free()
	# Devastator is derived exactly once from the upgraded normal damage.
	player.combat_stats.modifiers.clear()
	player.combat_stats.add_modifier(&"bolter_damage", 0.6)
	bolter.activate_ultimate(&"devastator_shells")
	for volley in range(1, 4):
		var bolt := fire()
		check(is_equal_approx(bolt.damage, 70.0 if volley == 3 else 40.0), "Devastator preserves normal direct damage and third-volley multiplier")
		check(is_equal_approx(bolt.splash_damage, 35.0 if volley == 3 else 20.0), "Forty direct yields twenty splash or thirty five empowered splash")
		bolt.free()
	var manager: ChapterPerkManager = main.get_node("ChapterPerkManager")
	for perk in manager.catalog.perks:
		if perk.id == &"explosive_doctrine":
			check(manager.apply_perk(perk), "Existing Explosive Doctrine applies normally")
	check(is_equal_approx(bolter.get_splash_damage(), 24.0), "Approved perk exception produces sixty percent splash")
	for volley in range(1, 4):
		var bolt := fire()
		check(is_equal_approx(bolt.splash_damage, 42.0 if volley == 3 else 24.0), "Perk and Devastator multiply the current derived splash without double scaling")
		check(is_equal_approx(bolt.splash_radius, 120.75 if volley == 3 else 80.5), "Existing Chapter and Ultimate radius bonuses unchanged")
		bolt.free()
	player.combat_stats.modifiers.clear()
	# Actual production Ork/Squig HP with fractional splash and independent crits.
	var direct := enemy_at(preload("res://scenes/enemies/ork_boy.tscn"), Vector2(2000, 0))
	var nearby := enemy_at(preload("res://scenes/enemies/enemy.tscn"), Vector2(2040, 0))
	var outside := enemy_at(preload("res://scenes/enemies/enemy.tscn"), Vector2(2300, 0))
	var stats := ScriptedStats.new()
	var impact := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	impact.combat_stats = stats
	impact.monitoring = false
	impact.position = direct.position
	main.add_child(impact)
	impact.set_physics_process(false)
	await physics_frame
	await physics_frame
	impact._explode(direct)
	check(stats.rolls == 2 and direct.current_health == 25.0, "Direct receives one normal hit and no splash or extra crit roll")
	check(nearby.current_health == 6.25 and outside.current_health == 25.0, "Independent splash crit applies eighteen point seven five without integer rounding")
	check(stats.get_crit_multiplier() == 1.5, "Base critical multiplier unchanged")
	await process_frame
	await process_frame
	var found_fractional_crit := false
	for child in main.get_children():
		if child is FloatingDamageNumber and child.damage_amount == 18.75:
			check(child.is_critical and child.get_node("Label").text == "18.8" and child.get_node("Label").modulate == Color.RED, "Fractional critical splash formats red eighteen point eight")
			found_fractional_crit = true
	check(found_fractional_crit, "Real fractional splash creates expected damage number")
	# No-splash fork flag remains effective even with the Chapter bonus.
	impact.damage = 12.5
	impact.splash_damage_bonus = 0.2
	impact.splash_enabled = false
	impact._explode(direct)
	check(impact.splash_damage == 0.0 and nearby.current_health == 6.25 and stats.rolls == 3, "Direct-only fork behavior never queries or rolls splash")
	impact.free()
	var plain_direct := enemy_at(preload("res://scenes/enemies/ork_boy.tscn"), Vector2(3000, 0))
	var plain_splash := enemy_at(preload("res://scenes/enemies/enemy.tscn"), Vector2(3040, 0))
	var plain := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	plain.monitoring = false
	plain.position = plain_direct.position
	main.add_child(plain)
	plain.set_physics_process(false)
	await physics_frame
	await physics_frame
	plain._explode(plain_direct)
	check(plain_splash.current_health == 12.5, "Uncritical splash leaves exactly twelve point five HP")
	plain._explode(plain_direct)
	check(plain_splash.current_health == 0.0 and plain_splash.is_queued_for_deletion(), "Two twelve point five splash hits kill a twenty five HP Squig")
	plain.free()
	await create_timer(0.4).timeout
	main.queue_free()
	await process_frame
	print("PASS: %d dynamic Bolter splash checks" % checks)
	quit()
