class_name CombatStats
extends Resource

signal stat_changed(stat: StringName)
signal damage_dealt(amount: float, source: StringName, killed: bool)

const CRITICAL_DAMAGE_MULTIPLIER: float = 1.5
const MAX_PROJECTILES: int = 5

@export var crit_chance: float = 0.0
@export_range(1, 5) var base_projectile_count: int = 1
@export_range(0.0, 20.0) var bolter_spread_degrees: float = 12.0

var modifiers: Dictionary = {}
var temporary_modifiers: Dictionary = {}
var guaranteed_crit_interval: int = 0
var projectiles_fired: int = 0


class DamageRoll:
	extends RefCounted
	var amount: float
	var critical: bool

	func _init(final_amount: float, is_critical: bool) -> void:
		amount = final_amount
		critical = is_critical


func get_modifier(stat: StringName) -> float:
	var value := float(modifiers.get(stat, 0.0))
	for bonuses: Dictionary in temporary_modifiers.values():
		value += float(bonuses.get(stat, 0.0))
	return value


func add_modifier(stat: StringName, amount: float) -> void:
	modifiers[stat] = float(modifiers.get(stat, 0.0)) + amount
	stat_changed.emit(stat)


func scale_base(stat: StringName, base: float) -> float:
	return base * (1.0 + get_modifier(stat))


func get_projectile_count() -> int:
	return clampi(base_projectile_count + roundi(get_modifier(&"projectile_count")), 1, MAX_PROJECTILES)


func get_crit_multiplier() -> float:
	return CRITICAL_DAMAGE_MULTIPLIER + get_modifier(&"crit_damage")


func resolve_damage(base_damage: float, critical: bool) -> float:
	return base_damage * get_crit_multiplier() if critical else base_damage


func roll_damage(base_damage: float) -> float:
	return roll_hit(base_damage).amount


func roll_hit(base_damage: float, guaranteed_critical: bool = false) -> DamageRoll:
	var chance := get_crit_chance()
	var critical := guaranteed_critical or (chance > 0.0 and randf() < chance)
	return DamageRoll.new(resolve_damage(base_damage, critical), critical)


func get_projectile_angle(index: int) -> float:
	var count := get_projectile_count()
	if count == 1:
		return 0.0
	return deg_to_rad(bolter_spread_degrees) * (float(index) / float(count - 1) - 0.5)


func set_temporary_modifier(source: StringName, stat: StringName, amount: float) -> void:
	if not temporary_modifiers.has(source):
		temporary_modifiers[source] = {}
	temporary_modifiers[source][stat] = amount
	stat_changed.emit(stat)


func next_projectile_is_critical() -> bool:
	if guaranteed_crit_interval <= 0:
		return false
	projectiles_fired += 1
	return projectiles_fired % guaranteed_crit_interval == 0


func report_damage_dealt(amount: float, source: StringName, killed: bool) -> void:
	damage_dealt.emit(amount, source, killed)


func get_armor() -> int:
	return maxi(0, roundi(get_modifier(&"armor")))


func get_crit_chance() -> float:
	return clampf(crit_chance + get_modifier(&"crit_chance"), 0.0, 1.0)


func get_dodge_chance() -> float:
	return clampf(get_modifier(&"dodge_chance"), 0.0, 1.0)


func roll_dodge() -> bool:
	var chance := get_dodge_chance()
	return chance >= 1.0 or (chance > 0.0 and randf() < chance)
