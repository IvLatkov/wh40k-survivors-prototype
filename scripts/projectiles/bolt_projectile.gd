class_name BoltProjectile
extends Area2D

const EXPLOSION_EFFECT_SCENE := preload("res://scenes/effects/explosion_effect.tscn")
const ENEMY_COLLISION_MASK := 2

@export var projectile_speed: float = 900.0
@export var damage: float = 25.0
@export var lifetime: float = 2.0
@export var splash_radius: float = 70.0
@export var splash_damage: float = 12.0

var _direction: Vector2 = Vector2.RIGHT
var _remaining_lifetime: float
var _has_impacted: bool = false


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

	_has_impacted = true
	set_deferred(&"monitoring", false)
	_explode(body as Enemy)
	queue_free()


func _explode(direct_target: Enemy) -> void:
	var splash_targets: Dictionary = {
		direct_target.get_instance_id(): direct_target,
	}
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
		if collider is Enemy:
			splash_targets[collider.get_instance_id()] = collider

	direct_target.take_damage(damage)
	for enemy: Enemy in splash_targets.values():
		if is_instance_valid(enemy):
			enemy.take_damage(splash_damage)

	var effect := EXPLOSION_EFFECT_SCENE.instantiate() as ExplosionEffect
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position
	effect.set_radius(splash_radius)
