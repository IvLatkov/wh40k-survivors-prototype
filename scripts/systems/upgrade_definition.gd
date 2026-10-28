class_name UpgradeDefinition
extends Resource

enum Category { WEAPON, GENERIC }
enum WeaponUpgradeGroup { BOLTER, KNIFE, SHARED }

const WEAPON_MAX_LEVEL: int = 5
const GENERIC_MAX_LEVEL: int = 8

# Category determines normal level limits and build-slot availability.
@export var category: Category = Category.WEAPON
## Organization/UI only; ignored for GENERIC and never used for slot filtering.
@export var weapon_group: WeaponUpgradeGroup = WeaponUpgradeGroup.SHARED
@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var stat: StringName
@export var amount: float = 0.1
@export var percentage: bool = true
@export var scales_with_mastery: bool = true
## Zero uses the category cap; positive values specify a stricter override.
@export var max_level: int = 0
## Zero means no stat cap.
@export var stat_cap: float = 0.0


func get_max_level() -> int:
	var category_limit := WEAPON_MAX_LEVEL if category == Category.WEAPON else GENERIC_MAX_LEVEL
	return mini(category_limit, max_level) if max_level > 0 else category_limit


func get_level_text(stats: CombatStats, current_level: int) -> String:
	var maxed := not is_available(stats, current_level)
	return "Lv. %d / %d%s" % [current_level, get_max_level(), " MAX" if maxed else ""]


func is_available(stats: CombatStats, current_level: int) -> bool:
	if current_level >= get_max_level():
		return false
	if stat_cap > 0.0 and stats != null:
		var current := stats.get_modifier(stat)
		if stat == &"projectile_count":
			current = stats.get_projectile_count()
		return current < stat_cap and not is_equal_approx(current, stat_cap)
	return true


func apply(stats: CombatStats) -> void:
	var multiplier := 1.0 + stats.get_modifier(&"normal_upgrade_effectiveness") if percentage and scales_with_mastery else 1.0
	stats.add_modifier(stat, amount * multiplier)


func effect_text(multiplier: float = 1.0) -> String:
	if not scales_with_mastery:
		multiplier = 1.0
	var percent_text := "+%s%%" % String.num(amount * multiplier * 100.0, 2).trim_suffix(".0")
	match stat:
		&"pickup_radius":
			return percent_text + " Pickup Radius"
		&"movement_speed":
			return percent_text + " Movement Speed"
		&"xp_gain":
			return percent_text + " XP Gain"
		&"dodge_chance":
			return percent_text + " Dodge Chance"
		&"better_xp_drop_chance":
			return percent_text + " Better XP Drop Chance"
		&"health_regen":
			return "+%.1f HP/s" % amount
		&"fire_rate":
			return percent_text + " Fire Rate"
		&"knife_attack_rate":
			return percent_text + " Attack Rate"
		&"max_health_bonus":
			return percent_text + " Max Health"
	if stat == &"armor":
		return "+%s Armor" % String.num(amount, 0)
	if stat == &"crit_chance":
		return "+%s%% Crit Chance" % String.num(amount * multiplier * 100.0, 2).trim_suffix(".0")
	return "+%s%%" % String.num(amount * multiplier * 100.0, 2).trim_suffix(".0") if percentage else "+%s Bolter Projectile" % str(amount)
