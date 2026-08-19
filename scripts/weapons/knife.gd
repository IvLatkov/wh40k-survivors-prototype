class_name KnifeAttack
extends Area2D

const KNIFE_SLASH_SCENE := preload("res://scenes/effects/knife_slash.tscn")

@export var melee_range: float = 55.0
@export var melee_damage: float = 35.0
@export var melee_cooldown: float = 0.8

@onready var detection_shape: CollisionShape2D = $CollisionShape2D
@onready var cooldown_timer: Timer = $CooldownTimer

var _nearby_enemies: Dictionary = {}


func _ready() -> void:
	var circle_shape := detection_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = melee_range

	cooldown_timer.wait_time = melee_cooldown
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if _nearby_enemies.is_empty() or not cooldown_timer.is_stopped():
		return

	var closest_enemy := _get_closest_enemy()
	if closest_enemy != null:
		_attack(closest_enemy)


func _get_closest_enemy() -> Enemy:
	var closest_enemy: Enemy = null
	var closest_distance_squared := INF
	var stale_ids: Array[int] = []

	for enemy_id: int in _nearby_enemies:
		var enemy := _nearby_enemies[enemy_id] as Enemy
		if not is_instance_valid(enemy):
			stale_ids.append(enemy_id)
			continue

		var distance_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_enemy = enemy

	for enemy_id: int in stale_ids:
		_nearby_enemies.erase(enemy_id)

	return closest_enemy


func _attack(enemy: Enemy) -> void:
	var attack_offset := enemy.global_position - global_position
	var attack_direction := attack_offset.normalized()
	cooldown_timer.start(melee_cooldown)
	enemy.take_damage(melee_damage)
	_spawn_slash(attack_direction, attack_offset * 0.5)


func _spawn_slash(direction: Vector2, offset: Vector2) -> void:
	var slash := KNIFE_SLASH_SCENE.instantiate() as KnifeSlashEffect
	if slash == null:
		return

	get_tree().current_scene.add_child(slash)
	slash.global_position = global_position + offset
	slash.set_direction(direction)


func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		_nearby_enemies[body.get_instance_id()] = body


func _on_body_exited(body: Node2D) -> void:
	if body is Enemy:
		_nearby_enemies.erase(body.get_instance_id())
