class_name FloatingDamageNumber
extends Node2D

@export var duration: float = 0.30
@export var rise_distance: float = 45.0
@export var normal_color: Color = Color.WHITE
@export var critical_color: Color = Color.RED

var damage_amount: float
var is_critical: bool


func configure(applied_damage: float, critical: bool) -> void:
	damage_amount = applied_damage
	is_critical = critical


func _ready() -> void:
	var label: Label = $Label
	# Formatting only: no weapon stats, crit rolls, or damage calculations here.
	label.text = String.num(damage_amount, 1).trim_suffix(".0")
	label.modulate = critical_color if is_critical else normal_color
	label.add_theme_font_size_override("font_size", 23 if is_critical else 18)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_distance, duration)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.chain().tween_callback(queue_free)
