extends Node2D

const BOLT_PROJECTILE_SCENE := preload("res://scenes/projectiles/bolt_projectile.tscn")

@export_range(0.05, 10.0, 0.05) var fire_interval: float = 0.75

@export var devastator_damage_multiplier: float = 1.75
@export var devastator_radius_multiplier: float = 1.5
@export var devastator_visual_scale: float = 1.6
var devastator_active: bool = false
var forking_active: bool = false
var _ultimate_volley_count: int = 0

var combat_stats: CombatStats
var _base_projectile_damage: float

@onready var muzzle: Marker2D = $Muzzle
@onready var fire_timer: Timer = $FireTimer


func _ready() -> void:
	var projectile_template := BOLT_PROJECTILE_SCENE.instantiate() as BoltProjectile
	_base_projectile_damage = projectile_template.damage
	projectile_template.free()
	combat_stats = (get_parent() as Player).combat_stats if get_parent() is Player else CombatStats.new()
	combat_stats.stat_changed.connect(_on_stat_changed)
	fire_timer.wait_time = get_fire_interval()
	fire_timer.timeout.connect(_fire)
	fire_timer.start()


func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())


func _fire() -> void:
	var mouse_position := get_global_mouse_position()
	var direction := muzzle.global_position.direction_to(mouse_position)
	if direction.is_zero_approx():
		return

	var empowered := false
	if devastator_active:
		_ultimate_volley_count += 1
		empowered = _ultimate_volley_count % 3 == 0
	var count := combat_stats.get_projectile_count()
	var primary_index := floori(float(count) / 2.0)
	for index in count:
		var shot_direction := direction.rotated(combat_stats.get_projectile_angle(index))
		if empowered and index == primary_index:
			shot_direction = direction
		var projectile := BOLT_PROJECTILE_SCENE.instantiate() as BoltProjectile
		projectile.combat_stats = combat_stats
		projectile.penetration = maxi(0, roundi(combat_stats.get_modifier(&"penetration")))
		projectile.guaranteed_critical = combat_stats.next_projectile_is_critical()
		projectile.damage = get_damage()
		projectile.splash_damage_bonus = combat_stats.get_modifier(&"splash_damage")
		projectile.splash_radius = combat_stats.scale_base(&"splash_radius", projectile.splash_radius)
		projectile.projectile_speed = combat_stats.scale_base(&"projectile_speed", projectile.projectile_speed)
		projectile.can_fork = forking_active
		projectile.spatial_grid = get_tree().current_scene.get_node_or_null("EnemySpawner/EnemySpatialGrid") as EnemySpatialGrid
		if empowered and index == primary_index:
			projectile.damage *= devastator_damage_multiplier
			projectile.splash_radius *= devastator_radius_multiplier
			projectile.get_node("Visual").scale *= devastator_visual_scale
		get_tree().current_scene.add_child(projectile)
		# Fan out muzzle positions as well as trajectories; single shots are unchanged.
		projectile.global_position = muzzle.global_position + (shot_direction - direction) * muzzle.position.length()
		projectile.set_direction(shot_direction)


func get_fire_interval() -> float:
	return fire_interval / maxf(0.01, 1.0 + combat_stats.get_modifier(&"fire_rate"))


func _on_stat_changed(stat: StringName) -> void:
	if stat != &"fire_rate":
		return
	var remaining_fraction := fire_timer.time_left / fire_timer.wait_time
	fire_timer.wait_time = get_fire_interval()
	if not fire_timer.is_stopped():
		fire_timer.start(maxf(0.001, fire_timer.wait_time * remaining_fraction))
		fire_timer.wait_time = get_fire_interval()


func get_damage() -> float:
	return combat_stats.scale_base(&"bolter_damage", _base_projectile_damage)


func get_splash_damage() -> float:
	return BoltProjectile.calculate_splash_damage(get_damage(), combat_stats.get_modifier(&"splash_damage"))


func activate_ultimate(id: StringName) -> void:
	match id:
		&"devastator_shells":
			if not devastator_active:
				_ultimate_volley_count = 0
			devastator_active = true
		&"forking_rounds":
			forking_active = true
