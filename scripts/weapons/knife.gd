class_name KnifeAttack
extends Area2D

const KNIFE_SLASH_SCENE := preload("res://scenes/effects/knife_slash.tscn")

@export var melee_range: float = 55.0
@export var melee_damage: float = 35.0
@export var melee_cooldown: float = 0.8

@onready var detection_shape: CollisionShape2D = $CollisionShape2D
@onready var cooldown_timer: Timer = $CooldownTimer

var combat_stats: CombatStats
var whirlwind_active: bool = false
var _player: Player

## Derived from the unchanged base radius; visible in the debugger.
var current_knife_radius: float:
	get:
		return combat_stats.scale_base(&"knife_range", melee_range) if combat_stats != null else melee_range

var _nearby_enemies: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as Player
	combat_stats = _player.combat_stats if _player != null else CombatStats.new()
	combat_stats.stat_changed.connect(_on_stat_changed)
	_update_range()

	cooldown_timer.wait_time = get_attack_cooldown()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	_attack()


func _get_attack_targets(direction: Vector2, radius: float) -> Array[Enemy]:
	var targets: Array[Enemy] = []
	var stale_ids: Array[int] = []
	for enemy_id: int in _nearby_enemies:
		var enemy := _nearby_enemies[enemy_id] as Enemy
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.current_health <= 0.0:
			stale_ids.append(enemy_id)
			continue

		# Area overlaps include enemy collider edges; enforce center-to-center reach.
		var offset := enemy.global_position - global_position
		if offset.length_squared() <= radius * radius and (whirlwind_active or offset.dot(direction) >= 0.0):
			targets.append(enemy)

	for enemy_id: int in stale_ids:
		_nearby_enemies.erase(enemy_id)
	return targets


func _attack() -> void:
	if _nearby_enemies.is_empty() or not cooldown_timer.is_stopped():
		return
	var direction := Vector2.LEFT if _player != null and not _player.facing_right else Vector2.RIGHT
	var radius := current_knife_radius
	var targets := _get_attack_targets(direction, radius)
	if targets.is_empty():
		return

	cooldown_timer.start(get_attack_cooldown())
	var damage := get_damage()
	for enemy in targets:
		var hit := combat_stats.roll_hit(damage)
		enemy.take_damage(hit.amount, hit.critical, combat_stats, &"knife")
	if whirlwind_active:
		var sweep := preload("res://scripts/effects/whirlwind_sweep.gd").new()
		sweep.radius = radius
		get_tree().current_scene.add_child(sweep)
		sweep.global_position = global_position
	else:
		_spawn_slash(direction, direction * radius * 0.5)


func _spawn_slash(direction: Vector2, offset: Vector2) -> void:
	var slash := KNIFE_SLASH_SCENE.instantiate() as KnifeSlashEffect
	if slash == null:
		return

	get_tree().current_scene.add_child(slash)
	slash.global_position = global_position + offset
	slash.set_direction(direction)
	slash.scale *= current_knife_radius / maxf(melee_range, 0.001)


func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		_nearby_enemies[body.get_instance_id()] = body


func _on_body_exited(body: Node2D) -> void:
	if body is Enemy:
		_nearby_enemies.erase(body.get_instance_id())


func _on_stat_changed(stat: StringName) -> void:
	if stat == &"knife_attack_rate":
		var remaining_fraction := cooldown_timer.time_left / cooldown_timer.wait_time
		cooldown_timer.wait_time = get_attack_cooldown()
		if not cooldown_timer.is_stopped():
			cooldown_timer.start(maxf(0.001, cooldown_timer.wait_time * remaining_fraction))
			cooldown_timer.wait_time = get_attack_cooldown()
	if stat == &"knife_range":
		_update_range()


func _update_range() -> void:
	var circle_shape := detection_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = current_knife_radius


func get_attack_cooldown() -> float:
	return melee_cooldown / maxf(0.01, 1.0 + combat_stats.get_modifier(&"knife_attack_rate"))


func get_damage() -> float:
	return combat_stats.scale_base(&"knife_damage", melee_damage)


func activate_ultimate(id: StringName) -> void:
	if id == &"whirlwind_assault":
		whirlwind_active = true
