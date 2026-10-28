class_name DamageNumberPool
extends Node2D

const NUMBER := preload("res://scenes/ui/damage_number.tscn")
const PREWARM := 64
const MAX_IDLE := 128
var _idle: Array[FloatingDamageNumber] = []

func _ready() -> void:
	for index in PREWARM:
		_idle.append(_create())

func _create() -> FloatingDamageNumber:
	var number := NUMBER.instantiate() as FloatingDamageNumber
	number.pool = self
	number.pooled_idle = true
	number.visible = false
	add_child(number)
	return number

func spawn(at: Vector2, amount: float, critical: bool) -> void:
	# Preserve physics-safe deferred activation, without repeated tree insertion.
	_activate.call_deferred(at, amount, critical)

func _activate(at: Vector2, amount: float, critical: bool) -> void:
	var start := Time.get_ticks_usec() if CombatProfile.enabled else 0
	var number := _idle.pop_back() as FloatingDamageNumber if not _idle.is_empty() else _create()
	number.pooled_idle = false
	number.position = to_local(at)
	number.configure(amount, critical)
	number.start()
	CombatProfile.finish(&"number_activation", start)

func recycle(number: FloatingDamageNumber) -> void:
	number.pooled_idle = true
	if _idle.size() >= MAX_IDLE:
		number.queue_free()
		return
	_idle.append(number)
