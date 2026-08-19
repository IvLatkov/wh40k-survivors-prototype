extends Node2D

const BOLT_PROJECTILE_SCENE := preload("res://scenes/projectiles/bolt_projectile.tscn")

@export_range(0.05, 10.0, 0.05) var fire_interval: float = 0.75

@onready var muzzle: Marker2D = $Muzzle
@onready var fire_timer: Timer = $FireTimer


func _ready() -> void:
	fire_timer.wait_time = fire_interval
	fire_timer.timeout.connect(_fire)
	fire_timer.start()


func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())


func _fire() -> void:
	var mouse_position := get_global_mouse_position()
	var direction := muzzle.global_position.direction_to(mouse_position)
	if direction.is_zero_approx():
		return

	var projectile := BOLT_PROJECTILE_SCENE.instantiate() as BoltProjectile
	if projectile == null:
		return

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.set_direction(direction)
