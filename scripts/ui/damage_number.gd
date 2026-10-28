class_name FloatingDamageNumber
extends Node2D

@export var duration: float = 0.30
@export var rise_distance: float = 45.0
@export var normal_color: Color = Color.WHITE
@export var critical_color: Color = Color.RED

var pool: DamageNumberPool
var pooled_idle: bool = false
var _elapsed: float = 0.0
var _start_y: float

var damage_amount: float
var is_critical: bool


func configure(applied_damage: float, critical: bool) -> void:
	damage_amount = applied_damage
	is_critical = critical


func _ready() -> void:
	if pooled_idle:
		set_process(false)
		return
	start()


func start() -> void:
	if not CombatProfile.enabled:
		_profile_damage_number_ready()
		return
	var profile_start := Time.get_ticks_usec()
	_profile_damage_number_ready()
	CombatProfile.finish(&"number_setup", profile_start)


func _profile_damage_number_ready() -> void:
	if pooled_idle:
		set_process(false)
		return
	_elapsed = 0.0
	_start_y = position.y
	modulate.a = 1.0
	visible = true
	set_process(true)
	var label: Label = $Label
	# Formatting only: no weapon stats, crit rolls, or damage calculations here.
	label.text = String.num(damage_amount, 1).trim_suffix(".0")
	label.modulate = critical_color if is_critical else normal_color
	label.add_theme_font_size_override("font_size", 23 if is_critical else 18)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / maxf(duration, 0.000001), 0.0, 1.0)
	position.y = _start_y - rise_distance * progress
	modulate.a = 1.0 - clampf(progress * 2.0 - 1.0, 0.0, 1.0)
	if progress >= 1.0:
		set_process(false)
		if is_instance_valid(pool):
			visible = false
			pool.recycle(self)
		else:
			queue_free()
