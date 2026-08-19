class_name KnifeSlashEffect
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.animation_finished.connect(queue_free)
	animated_sprite.play(&"slash")


func set_direction(direction: Vector2) -> void:
	rotation = direction.angle()
