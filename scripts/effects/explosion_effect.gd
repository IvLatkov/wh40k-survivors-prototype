class_name ExplosionEffect
extends Node2D

@export var initial_duration: float = 0.08
@export var after_impact_duration: float = 0.20

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.frame = 0
	await get_tree().create_timer(initial_duration, false).timeout
	animated_sprite.frame = 1
	await get_tree().create_timer(after_impact_duration, false).timeout
	queue_free()


func set_radius(_new_radius: float) -> void:
	pass
