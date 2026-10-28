class_name XPPickup
extends Area2D

@export_range(1, 100, 1) var xp_value: int = 1
@export var travel_speed: float = 220.0
@export var maximum_travel_speed: float = 360.0
@export var travel_acceleration: float = 600.0
@export var arrival_distance: float = 10.0
@export_range(0.0, 3.0, 0.5) var idle_bob_distance: float = 2.0
@export_range(1.0, 1.4, 0.1) var idle_bob_duration: float = 1.2

@onready var visual: Sprite2D = $Visual

var _idle_tween: Tween
var _target: Player
var _magnetized: bool = false
var _collected: bool = false
var _current_speed: float = 0.0


func _ready() -> void:
	set_process(false)
	_start_idle_bob()


func _start_idle_bob() -> void:
	visual.position.y = -idle_bob_distance
	_idle_tween = create_tween().set_loops()
	_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(visual, "position:y", idle_bob_distance, idle_bob_duration * 0.5)
	_idle_tween.tween_property(visual, "position:y", -idle_bob_distance, idle_bob_duration * 0.5)
	# Advance within the cycle so newly dropped skulls don't bob in unison.
	_idle_tween.custom_step(randf_range(0.0, idle_bob_duration))


func _stop_idle_bob() -> void:
	if _idle_tween != null:
		_idle_tween.kill()
		_idle_tween = null
	visual.position.y = 0.0


func configure(reward: XPReward) -> void:
	xp_value = reward.xp_per_pickup
	if reward.texture != null:
		($Visual as Sprite2D).texture = reward.texture


func start_collecting(player: Player) -> void:
	if _magnetized or _collected or not is_instance_valid(player):
		return

	_target = player
	_magnetized = true
	_stop_idle_bob()
	_current_speed = travel_speed
	# The radius signal runs during physics queries; defer detection changes.
	set_deferred(&"monitorable", false)
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = null
		_magnetized = false
		set_process(false)
		set_deferred(&"monitorable", true)
		_start_idle_bob()
		return

	_current_speed = move_toward(
		_current_speed, maximum_travel_speed, travel_acceleration * delta
	)
	global_position = global_position.move_toward(_target.global_position, _current_speed * delta)
	if global_position.distance_squared_to(_target.global_position) > arrival_distance * arrival_distance:
		return

	# Set the guard before awarding XP, since that emits player/HUD signals.
	_collected = true
	set_process(false)
	_target.add_xp(xp_value)
	queue_free()
