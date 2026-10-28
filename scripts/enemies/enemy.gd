class_name Enemy
extends CharacterBody2D

signal damage_received(amount: float, critical: bool)

const XP_PICKUP_SCENE := preload("res://scenes/pickups/xp_pickup.tscn")
const BLOOD_BURST_SCENE := preload("res://scenes/effects/blood_burst.tscn")
const DAMAGE_NUMBER_SCENE := preload("res://scenes/ui/damage_number.tscn")

enum XPTier { LOW, MID, HIGH, BOSS }
enum DamageTier { TIER_1, MID, HIGH, BOSS, TIER_2 }

# Cumulative Tier 1 thresholds: 70% one, 25% two, 5% three.
const TIER_1_ONE_DAMAGE_CHANCE: float = 0.70
const TIER_1_TWO_DAMAGE_THRESHOLD: float = 0.95
const TIER_2_THREE_DAMAGE_CHANCE: float = 0.65
const TIER_2_FOUR_DAMAGE_THRESHOLD: float = 0.90

const SQUIG_ANIMATIONS: Array[StringName] = [
	&"walk_green",
	&"walk_red",
	&"walk_purple",
]

## An empty list preserves a scene's static, single-frame visual.
@export var movement_animations: Array[StringName] = SQUIG_ANIMATIONS.duplicate()
@export var sprite_faces_right: bool = true
@export_range(0.0, 0.5, 0.01) var speed_variation_limit: float = 0.5
@export var movement_speed: float = 60.0
@export var max_health: float = 25.0
@export var stop_distance: float = 35.0
@export var separation_radius: float = 40.0
@export_range(0.0, 2.0, 0.05) var separation_strength: float = 0.4
@export_range(0.016, 0.2, 0.001) var separation_update_interval: float = 0.05
@export var knockback_distance: float = 20.0
@export var knockback_duration: float = 0.12
@export var contact_damage: float = 1.0
@export var contact_damage_enabled: bool = true
@export var damage_tier: DamageTier = DamageTier.TIER_1
@export var full_simulation_distance: float = 900.0
@export var reduced_simulation_distance: float = 1500.0
@export_range(0.05, 0.5, 0.01) var very_far_update_interval: float = 0.1

@export_group("XP Drops")
@export var xp_tier: XPTier = XPTier.LOW
@export_range(0.0, 3600.0, 1.0) var tier_1_mid_xp_unlock_seconds: float = 300.0
@export_range(0.0, 1.0, 0.01) var tier_1_mid_xp_chance: float = 0.10
@export_range(0.0, 1.0, 0.01) var tier_1_mid_xp_chance_cap: float = 0.50
@export_range(10.0, 40.0, 1.0) var xp_drop_offset: float = 10.0
## Optional quantity rules independent of the selected skull's art/value.
@export var xp_quantity_reward: XPReward
@export var low_xp_reward: XPReward = preload("res://assets/art/effects/xp/low_level/xp_reward.tres")
@export var mid_xp_reward: XPReward = preload("res://assets/art/effects/xp/mid_level/xp_reward.tres")
@export var high_xp_reward: XPReward = preload("res://assets/art/effects/xp/high_level/xp_reward.tres")
@export var boss_xp_reward: XPReward = preload("res://assets/art/effects/xp/boss/xp_reward.tres")

@onready var visual: AnimatedSprite2D = $Visual

var target: Node2D
var spatial_grid: EnemySpatialGrid
var run_clock: RunClock
var current_health: float
var _is_knocked_back: bool = false
var _contact_knockback_ready: bool = true
var _knockback_direction: Vector2 = Vector2.ZERO
var _knockback_time_remaining: float = 0.0
var _knockback_distance_remaining: float = 0.0
var _very_far_elapsed_time: float = 0.0
var _full_simulation_enabled: bool = true
var _separation_elapsed_time: float = 0.0
var _cached_separation_direction: Vector2 = Vector2.ZERO
var _separation_candidates: Array[Enemy] = []
var _chase_offset: Vector2 = Vector2.ZERO
var _movement_speed_multiplier: float = 1.0
var _individual_movement_speed: float
var _damage_number_slot: int = 0


func _ready() -> void:
	damage_received.connect(_show_damage_number)
	current_health = max_health
	_individual_movement_speed = movement_speed * _movement_speed_multiplier
	if not movement_animations.is_empty():
		visual.play(movement_animations.pick_random())


func set_target(new_target: Node2D) -> void:
	target = new_target


func set_spatial_grid(new_spatial_grid: EnemySpatialGrid) -> void:
	spatial_grid = new_spatial_grid


func set_run_clock(clock: RunClock) -> void:
	run_clock = clock


func configure_swarm_variation(chase_offset: Vector2, speed_multiplier: float) -> void:
	_chase_offset = chase_offset
	_movement_speed_multiplier = clampf(speed_multiplier, 0.1, 2.0)
	_individual_movement_speed = movement_speed * _movement_speed_multiplier


func take_damage(amount: float, critical: bool = false, attacker_stats: CombatStats = null, source: StringName = &"") -> void:
	if is_queued_for_deletion():
		return
	CombatProfile.count_event(&"damage_events")
	if critical: CombatProfile.count_event(&"crits")
	var previous_health := current_health
	current_health -= amount
	# Report the actual HP change after damage, including existing overkill behavior.
	var applied_damage := previous_health - current_health
	if applied_damage > 0.0:
		damage_received.emit(applied_damage, critical)
		if attacker_stats != null:
			attacker_stats.report_damage_dealt(minf(applied_damage, maxf(previous_health, 0.0)), source, current_health <= 0.0)
	if current_health <= 0.0:
		die()


func _show_damage_number(amount: float, critical: bool) -> void:
	if not CombatProfile.enabled:
		_profile_enemy_show_damage_number(amount, critical)
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_show_damage_number(amount, critical)
	CombatProfile.finish(&"number_creation", profile_start)


func _profile_enemy_show_damage_number(amount: float, critical: bool) -> void:
	var effect_parent := get_parent() as Node2D
	var number_pool := effect_parent.get_node_or_null("DamageNumberPool") as DamageNumberPool
	CombatProfile.count_event(&"numbers_spawned")
	# Separate simultaneous direct/splash hits without consuming combat RNG.
	var offset := Vector2((_damage_number_slot % 3 - 1) * 24.0, -30.0 - (_damage_number_slot % 2) * 18.0)
	_damage_number_slot += 1
	if number_pool != null:
		number_pool.spawn(global_position + offset, amount, critical)
		return
	var number := DAMAGE_NUMBER_SCENE.instantiate() as FloatingDamageNumber
	number.position = effect_parent.to_local(global_position + offset)
	number.configure(amount, critical)
	# Standalone scenes keep the existing unpooled path.
	if CombatProfile.enabled:
		CombatProfile.insert_child.call_deferred(effect_parent, number, &"number_insertion")
	else:
		effect_parent.add_child.call_deferred(number)


func die() -> void:
	if not CombatProfile.enabled:
		_profile_enemy_die()
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_die()
	CombatProfile.finish(&"death", profile_start)


func _profile_enemy_die() -> void:
	if is_queued_for_deletion():
		return
	set_physics_process(false)
	velocity = Vector2.ZERO
	_drop_xp()
	_spawn_blood_burst()
	CombatProfile.count_event(&"queue_free_requests")
	queue_free()


func _spawn_blood_burst() -> void:
	if not CombatProfile.enabled:
		_profile_enemy_spawn_blood_burst()
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_spawn_blood_burst()
	CombatProfile.finish(&"blood_creation", profile_start)


func _profile_enemy_spawn_blood_burst() -> void:
	var pool := get_parent().get_node_or_null("BloodBurstPool") as BloodBurstPool
	if pool != null:
		pool.spawn(global_position)
		return
	var effect := BLOOD_BURST_SCENE.instantiate() as Node2D
	var effect_parent := get_parent() as Node2D
	effect.position = effect_parent.to_local(global_position)
	# Death may happen in a physics callback; the parent survives this enemy.
	effect_parent.add_child.call_deferred(effect)


func _drop_xp() -> void:
	if not CombatProfile.enabled:
		_profile_enemy_drop_xp()
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_drop_xp()
	CombatProfile.finish(&"xp_creation", profile_start)


func _profile_enemy_drop_xp() -> void:
	var reward := roll_xp_reward()
	# Tier 1 keeps its LOW quantity roll (7% double) even when upgraded to MID.
	var quantity_reward := xp_quantity_reward if xp_quantity_reward != null else (low_xp_reward if _uses_tier_1_xp_rules() else reward)
	var drop_count := quantity_reward.roll_pickup_count()
	var start_angle := randf_range(0.0, TAU)
	# Keep 16px sprites apart, including the four-pickup boss ring.
	var spread_radius := maxf(xp_drop_offset, 10.0)
	if drop_count > 2:
		spread_radius = maxf(spread_radius, 12.0 / sin(PI / drop_count))
	var drop_parent := get_parent() as Node2D
	for index: int in drop_count:
		var pickup := XP_PICKUP_SCENE.instantiate() as XPPickup
		pickup.configure(reward)
		var drop_position := global_position
		if drop_count > 1:
			var angle := start_angle + TAU * index / drop_count
			drop_position += Vector2.RIGHT.rotated(angle) * spread_radius
		pickup.position = drop_parent.to_local(drop_position)
		# Death can occur inside a physics overlap callback. The parent outlives us.
		if CombatProfile.enabled:
			CombatProfile.insert_child.call_deferred(drop_parent, pickup, &"xp_insertion")
		else:
			drop_parent.add_child.call_deferred(pickup)


func _uses_tier_1_xp_rules() -> bool:
	return damage_tier == DamageTier.TIER_1 and xp_tier == XPTier.LOW


func get_mid_xp_upgrade_chance() -> float:
	var salvage_bonus := 0.0
	if is_instance_valid(target) and target is Player:
		salvage_bonus = maxf(0.0, (target as Player).combat_stats.get_modifier(&"better_xp_drop_chance"))
	return clampf(tier_1_mid_xp_chance + salvage_bonus, 0.0, tier_1_mid_xp_chance_cap)


func roll_xp_reward() -> XPReward:
	# Called once at death; later time thresholds can be added here.
	if _uses_tier_1_xp_rules() and is_instance_valid(run_clock):
		if run_clock.elapsed_time >= tier_1_mid_xp_unlock_seconds and randf() < get_mid_xp_upgrade_chance():
			return mid_xp_reward
	return get_xp_reward()


func get_xp_reward() -> XPReward:
	match xp_tier:
		XPTier.MID:
			return mid_xp_reward
		XPTier.HIGH:
			return high_xp_reward
		XPTier.BOSS:
			return boss_xp_reward
	return low_xp_reward


func get_attack_damage() -> float:
	if damage_tier == DamageTier.TIER_2:
		var tier_2_roll := randf()
		if tier_2_roll < TIER_2_THREE_DAMAGE_CHANCE:
			return 3.0
		if tier_2_roll < TIER_2_FOUR_DAMAGE_THRESHOLD:
			return 4.0
		return 5.0
	# Other tiers retain their configured fixed damage until separately balanced.
	if damage_tier != DamageTier.TIER_1:
		return contact_damage
	var roll := randf()
	if roll < TIER_1_ONE_DAMAGE_CHANCE:
		return 1.0
	if roll < TIER_1_TWO_DAMAGE_THRESHOLD:
		return 2.0
	return 3.0


func _physics_process(delta: float) -> void:
	if not CombatProfile.enabled:
		_profile_enemy_physics_process(delta)
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_physics_process(delta)
	CombatProfile.finish(&"squig_update", profile_start)


func _profile_enemy_physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var chase_target_position := target.global_position + _chase_offset
	var distance_squared := global_position.distance_squared_to(target.global_position)
	var chase_distance_squared := global_position.distance_squared_to(chase_target_position)
	var stop_distance_squared := stop_distance * stop_distance
	var full_simulation_distance_squared := full_simulation_distance * full_simulation_distance
	var reduced_simulation_distance_squared := reduced_simulation_distance * reduced_simulation_distance
	var uses_full_simulation := distance_squared <= full_simulation_distance_squared
	_set_full_simulation_enabled(uses_full_simulation)

	if distance_squared > reduced_simulation_distance_squared:
		_process_very_far_movement(delta)
		return

	if _is_knocked_back:
		_process_knockback(delta)
		return

	if distance_squared > stop_distance_squared:
		_contact_knockback_ready = true
	elif contact_damage_enabled and _contact_knockback_ready:
		if target is Player:
			var player := target as Player
			if player.can_take_damage():
				player.take_damage(get_attack_damage())
		_start_knockback()
		_process_knockback(delta)
		return

	var chase_direction := Vector2.ZERO
	if distance_squared > stop_distance_squared:
		if chase_distance_squared > stop_distance_squared:
			chase_direction = global_position.direction_to(chase_target_position)
		else:
			chase_direction = global_position.direction_to(target.global_position)

	var separation_direction := _get_separation_direction(delta) if uses_full_simulation else Vector2.ZERO
	var movement_direction := chase_direction + separation_direction * separation_strength
	velocity = movement_direction.limit_length(1.0) * _individual_movement_speed
	_update_visual_facing(velocity.x)

	move_and_slide()


func _start_knockback() -> void:
	_knockback_direction = (global_position - target.global_position).normalized()
	if _knockback_direction.is_zero_approx():
		_knockback_direction = Vector2.RIGHT

	_is_knocked_back = true
	_contact_knockback_ready = false
	_knockback_time_remaining = maxf(knockback_duration, 0.001)
	_knockback_distance_remaining = knockback_distance


func _process_knockback(delta: float) -> void:
	var safe_delta := maxf(delta, 0.000001)
	var knockback_speed := knockback_distance / maxf(knockback_duration, 0.001)
	var step_distance := minf(knockback_speed * safe_delta, _knockback_distance_remaining)
	velocity = _knockback_direction * step_distance / safe_delta
	_update_visual_facing(velocity.x)
	move_and_slide()

	_knockback_distance_remaining -= step_distance
	_knockback_time_remaining -= delta
	if _knockback_time_remaining <= 0.0 or _knockback_distance_remaining <= 0.0:
		_is_knocked_back = false
		velocity = Vector2.ZERO


func _update_visual_facing(horizontal_velocity: float) -> void:
	if not is_zero_approx(horizontal_velocity):
		visual.flip_h = (horizontal_velocity < 0.0) == sprite_faces_right


func _set_full_simulation_enabled(enabled: bool) -> void:
	if _full_simulation_enabled == enabled:
		return

	_full_simulation_enabled = enabled
	if enabled:
		visual.play()
	else:
		_separation_candidates.clear()
		_cached_separation_direction = Vector2.ZERO
		visual.pause()


func _process_very_far_movement(delta: float) -> void:
	_very_far_elapsed_time += delta
	if _very_far_elapsed_time < very_far_update_interval:
		return

	var movement_direction := global_position.direction_to(target.global_position + _chase_offset)
	velocity = movement_direction * _individual_movement_speed
	_update_visual_facing(velocity.x)
	global_position += velocity * _very_far_elapsed_time
	_very_far_elapsed_time = 0.0


func _get_separation_direction(delta: float) -> Vector2:
	if not is_instance_valid(spatial_grid):
		_cached_separation_direction = Vector2.ZERO
		return _cached_separation_direction

	_separation_elapsed_time += delta
	if _separation_elapsed_time >= separation_update_interval:
		_separation_elapsed_time = fmod(_separation_elapsed_time, separation_update_interval)
		_cached_separation_direction = _calculate_separation_direction()

	return _cached_separation_direction


func _calculate_separation_direction() -> Vector2:
	if not CombatProfile.enabled:
		return _profile_enemy_calculate_separation_direction()
	var profile_start := Time.get_ticks_usec()
	var profile_result := _profile_enemy_calculate_separation_direction()
	CombatProfile.finish(&"separation", profile_start)
	return profile_result


func _profile_enemy_calculate_separation_direction() -> Vector2:
	return spatial_grid.calculate_separation(self)
