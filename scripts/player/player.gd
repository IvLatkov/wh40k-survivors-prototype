class_name Player
extends CharacterBody2D

signal health_changed(current_health: float, max_health: float)
signal health_depleted

@export var speed: float = 250.0
@export var acceleration: float = 1200.0
@export var deceleration: float = 1600.0
@export var max_health: float = 50.0
@export var damage_invulnerability_duration: float = 0.5

@onready var visual: AnimatedSprite2D = $Visual
@onready var damage_invulnerability_timer: Timer = $DamageInvulnerabilityTimer

var facing_right: bool = true
var current_health: float = 50.0
var _is_dead: bool = false


func _ready() -> void:
	max_health = maxf(max_health, 1.0)
	current_health = max_health
	damage_invulnerability_timer.timeout.connect(_on_damage_invulnerability_ended)
	health_changed.emit(current_health, max_health)


func take_damage(amount: float) -> void:
	if _is_dead or amount <= 0.0 or not damage_invulnerability_timer.is_stopped():
		return

	var previous_health := current_health
	current_health = clampf(current_health - amount, 0.0, max_health)
	if is_equal_approx(current_health, previous_health):
		return

	health_changed.emit(current_health, max_health)
	visual.modulate = Color(1.0, 0.55, 0.55)
	damage_invulnerability_timer.start(damage_invulnerability_duration)

	if is_zero_approx(current_health):
		_is_dead = true
		health_depleted.emit()


func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	_update_facing(input_direction.x)
	_update_animation(input_direction)
	var target_velocity := input_direction * speed

	if input_direction.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	else:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)

	move_and_slide()


func _update_facing(horizontal_direction: float) -> void:
	if horizontal_direction > 0.0:
		facing_right = true
	elif horizontal_direction < 0.0:
		facing_right = false


func _update_animation(input_direction: Vector2) -> void:
	var animation_name: StringName
	if input_direction.is_zero_approx():
		animation_name = &"idle_right" if facing_right else &"idle_left"
	else:
		animation_name = &"walk_right" if facing_right else &"walk_left"

	if visual.animation != animation_name or not visual.is_playing():
		visual.play(animation_name)


func _on_damage_invulnerability_ended() -> void:
	visual.modulate = Color.WHITE
