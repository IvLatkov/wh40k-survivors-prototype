class_name Player
extends CharacterBody2D

const ChapterTypes = preload("res://scripts/systems/space_marine_chapter.gd")
const XPProgressionData = preload("res://scripts/systems/xp_progression.gd")
# Keep decimal bonuses such as 15% from rounding 57.5 down due to float error.
const HEALTH_ROUNDING_EPSILON: float = 0.000001
const REGEN_HEALTH_UPDATE_INTERVAL: float = 0.1
const XP_COMPARISON_EPSILON: float = 0.000000001

signal health_changed(current_health: float, max_health: float)
signal health_depleted
signal xp_changed(current_xp: float, required_xp: int, current_level: int)
signal leveled_up

@export var chapter: ChapterTypes.Type = ChapterTypes.Type.ULTRAMARINES
@export var combat_stats: CombatStats = CombatStats.new()
@export var xp_progression: XPProgressionData = preload("res://resources/progression/default_xp_progression.tres")

@export var speed: float = 250.0
@export var acceleration: float = 1200.0
@export var deceleration: float = 1600.0
@export var max_health: float = 50.0
@export var damage_invulnerability_duration: float = 0.5

@onready var xp_collection_shape: CollisionShape2D = $XPCollectionArea/CollisionShape2D

@onready var visual: AnimatedSprite2D = $Visual
@onready var damage_invulnerability_timer: Timer = $DamageInvulnerabilityTimer

var facing_right: bool = true
var current_health: float = 50.0
var xp: float = 0.0
var level: int = 1
var _is_dead: bool = false
var _normal_max_health_bonus: float = 0.0
var _regen_health_update_elapsed: float = 0.0
var _base_pickup_radius: float
var _base_max_health: float


func _enter_tree() -> void:
	# Keep run modifiers private to each player, before weapon children enter.
	combat_stats = combat_stats.duplicate(true) as CombatStats


func _ready() -> void:
	max_health = maxf(max_health, 1.0)
	_base_max_health = max_health
	current_health = max_health
	var pickup_circle := xp_collection_shape.shape.duplicate() as CircleShape2D
	xp_collection_shape.shape = pickup_circle
	_base_pickup_radius = pickup_circle.radius
	_update_pickup_radius()
	combat_stats.stat_changed.connect(_on_combat_stat_changed)
	damage_invulnerability_timer.timeout.connect(_on_damage_invulnerability_ended)
	health_changed.emit(current_health, max_health)


func add_xp(amount: float) -> void:
	if amount <= 0:
		return
	xp += maxf(0.0, combat_stats.scale_base(&"xp_gain", amount))
	var required_xp := get_xp_required()
	while xp + XP_COMPARISON_EPSILON >= required_xp:
		xp = maxf(0.0, xp - required_xp)
		level += 1
		leveled_up.emit()
		required_xp = get_xp_required()
	xp_changed.emit(xp, required_xp, level)


func get_xp_required() -> int:
	return xp_progression.get_requirement(level)


func _on_xp_collection_area_entered(area: Area2D) -> void:
	if area is XPPickup:
		(area as XPPickup).start_collecting(self)


func can_take_damage() -> bool:
	return not _is_dead and damage_invulnerability_timer.is_stopped()


func take_damage(amount: float) -> void:
	if amount <= 0.0 or not can_take_damage():
		return

	if combat_stats.roll_dodge():
		# A dodged event still consumes the existing contact invulnerability window.
		damage_invulnerability_timer.start(damage_invulnerability_duration)
		return

	var previous_health := current_health
	# Preserve percentage reductions, then apply flat Armor and the final minimum.
	var reduced_damage := amount * (1.0 - clampf(combat_stats.get_modifier(&"damage_reduction"), 0.0, 1.0))
	var final_damage := maxf(1.0, reduced_damage - combat_stats.get_armor())
	current_health = clampf(current_health - final_damage, 0.0, max_health)
	if is_equal_approx(current_health, previous_health):
		return

	health_changed.emit(current_health, max_health)
	visual.modulate = Color(1.0, 0.55, 0.55)
	damage_invulnerability_timer.start(damage_invulnerability_duration)

	if is_zero_approx(current_health):
		_is_dead = true
		health_depleted.emit()


func _physics_process(delta: float) -> void:
	_regenerate_health(delta)
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	_update_facing(input_direction.x)
	_update_animation(input_direction)
	var target_velocity := input_direction * get_movement_speed()

	if input_direction.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	else:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)

	move_and_slide()


func get_movement_speed() -> float:
	return combat_stats.scale_base(&"movement_speed", speed)


func get_pickup_radius() -> float:
	return (xp_collection_shape.shape as CircleShape2D).radius


func _update_pickup_radius() -> void:
	(xp_collection_shape.shape as CircleShape2D).radius = combat_stats.scale_base(&"pickup_radius", _base_pickup_radius)


func get_health_regen() -> float:
	return maxf(0.0, combat_stats.get_modifier(&"health_regen"))


func _regenerate_health(delta: float) -> void:
	if _is_dead or get_tree().paused or current_health >= max_health:
		return
	var regen := get_health_regen()
	if regen <= 0.0 or delta <= 0.0:
		return
	current_health = minf(max_health, current_health + regen * delta)
	# Keep fractional gameplay HP continuous; notify the HUD at most 10 times/s.
	_regen_health_update_elapsed += delta
	if _regen_health_update_elapsed >= REGEN_HEALTH_UPDATE_INTERVAL or current_health >= max_health:
		_regen_health_update_elapsed = 0.0
		health_changed.emit(current_health, max_health)


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


func _on_combat_stat_changed(stat: StringName) -> void:
	if stat == &"pickup_radius":
		_update_pickup_radius()
	elif stat == &"max_health_bonus":
		var previous_multiplier := 1.0 + combat_stats.get_modifier(&"max_health") + _normal_max_health_bonus
		_normal_max_health_bonus = combat_stats.get_modifier(&"max_health_bonus")
		var multiplier := 1.0 + combat_stats.get_modifier(&"max_health") + _normal_max_health_bonus
		var was_full := is_equal_approx(current_health, max_health)
		max_health = maxf(1.0, roundf(_base_max_health * multiplier + HEALTH_ROUNDING_EPSILON))
		# Scale by the change in the total bonus, before rounding Max HP.
		current_health = max_health if was_full else clampf(roundf(current_health * multiplier / maxf(previous_multiplier, 0.001) + HEALTH_ROUNDING_EPSILON), 0.0, max_health)
		health_changed.emit(current_health, max_health)
	elif stat == &"max_health":
		var previous_max := max_health
		max_health = _base_max_health * (1.0 + combat_stats.get_modifier(&"max_health") + _normal_max_health_bonus)
		if _normal_max_health_bonus > 0.0:
			max_health = roundf(max_health + HEALTH_ROUNDING_EPSILON)
		current_health = clampf(current_health + max_health - previous_max, 0.0, max_health)
		health_changed.emit(current_health, max_health)
