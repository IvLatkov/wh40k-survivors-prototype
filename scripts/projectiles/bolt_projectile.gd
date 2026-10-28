class_name BoltProjectile
extends Area2D

const EXPLOSION_EFFECT_SCENE := preload("res://scenes/effects/explosion_effect.tscn")
const ENEMY_COLLISION_MASK := 2
const SPLASH_DAMAGE_RATIO: float = 0.5

@export var projectile_speed: float = 600.0
@export var damage: float = 25.0
@export var lifetime: float = 2.0
@export var splash_radius: float = 70.0
var splash_enabled: bool = true
## Snapshot of the existing Chapter splash bonus at firing time.
var splash_damage_bonus: float = 0.0
## Derived from pre-crit direct damage, never an independent damage value.
var splash_damage: float:
	get:
		return calculate_splash_damage(damage, splash_damage_bonus) if splash_enabled else 0.0

@export var penetration: int = 0
@export var fork_search_radius: float = 300.0
@export var fork_damage_multiplier: float = 0.5
@export var fork_visual_scale: float = 0.75
var can_fork: bool = false
var spatial_grid: EnemySpatialGrid
var guaranteed_critical: bool = false
var _direct_hit_ids: Dictionary = {}
var combat_stats: CombatStats

var _direction: Vector2 = Vector2.RIGHT
var _remaining_lifetime: float
var _has_impacted: bool = false


static func calculate_splash_damage(direct_damage: float, splash_bonus: float = 0.0) -> float:
	return direct_damage * SPLASH_DAMAGE_RATIO * (1.0 + splash_bonus)


func _ready() -> void:
	_remaining_lifetime = lifetime
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += _direction * projectile_speed * delta
	_remaining_lifetime -= delta
	if _remaining_lifetime <= 0.0:
		queue_free()


func set_direction(new_direction: Vector2) -> void:
	_direction = new_direction.normalized()
	rotation = _direction.angle()


func _on_body_entered(body: Node2D) -> void:
	if _has_impacted or not body is Enemy:
		return

	if body.current_health <= 0.0 or body.is_queued_for_deletion():
		return
	if _direct_hit_ids.has(body.get_instance_id()):
		return
	_direct_hit_ids[body.get_instance_id()] = true
	_explode(body as Enemy)
	if penetration > 0:
		penetration -= 1
	else:
		_has_impacted = true
		set_deferred(&"monitoring", false)
		queue_free()


func _explode(direct_target: Enemy) -> void:
	if can_fork:
		_spawn_forks(direct_target)
	_deal_damage(direct_target, damage, guaranteed_critical)
	if splash_damage <= 0.0 or splash_radius <= 0.0:
		return
	var splash_targets: Dictionary = {}
	var splash_shape := CircleShape2D.new()
	splash_shape.radius = splash_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = splash_shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = ENEMY_COLLISION_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits := get_world_2d().direct_space_state.intersect_shape(query, 100)
	for hit: Dictionary in hits:
		var collider := hit.get("collider") as Node
		# All direct targets of this projectile stay excluded, including after penetration.
		if collider == direct_target or (collider != null and _direct_hit_ids.has(collider.get_instance_id())):
			continue
		if collider is Enemy:
			splash_targets[collider.get_instance_id()] = collider

	for enemy: Enemy in splash_targets.values():
		if is_instance_valid(enemy):
			_deal_damage(enemy, splash_damage)

	var effect := EXPLOSION_EFFECT_SCENE.instantiate() as ExplosionEffect
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position
	effect.set_radius(splash_radius)


func _deal_damage(enemy: Enemy, base_damage: float, force_critical: bool = false) -> void:
	if combat_stats == null:
		enemy.take_damage(base_damage)
		return
	var hit := combat_stats.roll_hit(base_damage, force_critical)
	enemy.take_damage(hit.amount, hit.critical, combat_stats, &"bolter")


func _spawn_forks(direct_target: Enemy) -> void:
	if not is_instance_valid(spatial_grid):
		return
	var candidates: Array[Enemy] = []
	spatial_grid.append_candidates_in_radius(global_position, fork_search_radius, candidates)
	# Keep only the closest two distinct living targets in one local pass.
	var targets: Array[Enemy] = []
	for enemy in candidates:
		if not is_instance_valid(enemy) or enemy == direct_target or enemy.is_queued_for_deletion() or enemy.current_health <= 0.0:
			continue
		if targets.has(enemy):
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance > fork_search_radius * fork_search_radius:
			continue
		var index := 0
		while index < targets.size() and global_position.distance_squared_to(targets[index].global_position) <= distance:
			index += 1
		if index < 2:
			targets.insert(index, enemy)
			if targets.size() > 2:
				targets.pop_back()
	for target in targets:
		# Instantiate our scene only at impact; no permanent fork objects or recursion.
		var fork := load("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
		fork.damage = damage * fork_damage_multiplier
		fork.combat_stats = combat_stats
		fork.projectile_speed = projectile_speed
		fork.can_fork = false
		fork._direct_hit_ids[direct_target.get_instance_id()] = true
		fork.splash_enabled = false
		fork.splash_radius = 0.0
		fork.get_node("Visual").scale *= fork_visual_scale
		# Impacts run inside physics callbacks: defer Area2D insertion safely.
		fork.position = (get_tree().current_scene as Node2D).to_local(global_position)
		fork.set_direction(global_position.direction_to(target.global_position))
		get_tree().current_scene.add_child.call_deferred(fork)
