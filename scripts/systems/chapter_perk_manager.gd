class_name ChapterPerkManager
extends Node

@export var catalogs: Array[ChapterPerkCatalog] = []
var player: Player
var stats: CombatStats
var catalog: ChapterPerkCatalog
var selected: Dictionary = {}
var efficiency: ChapterPerkDefinition
var efficiency_stacks: int = 0
var efficiency_remaining: float = 0.0
var adaptive: ChapterPerkDefinition
var adaptive_remaining: float = 0.0
var adaptive_stat: StringName = &""
var recent_damage: Dictionary = {}
var recent_kills: Dictionary = {}

func bind_player(value: Player) -> void:
	player = value
	stats = player.combat_stats
	for candidate in catalogs:
		if candidate.chapter == player.chapter:
			catalog = candidate
	stats.damage_dealt.connect(_on_damage_dealt)

func is_milestone(level: int) -> bool:
	return catalog != null and catalog.has_milestone(level)

func choices_for(level: int) -> Array[ChapterPerkDefinition]:
	var choices: Array[ChapterPerkDefinition] = []
	var seen: Dictionary = {}
	if catalog == null:
		return choices
	for perk in catalog.perks:
		if perk.chapter == player.chapter and perk.milestone == level and not selected.has(perk.id) and not seen.has(perk.id):
			choices.append(perk)
			seen[perk.id] = true
	choices.shuffle()
	if choices.size() > 3:
		choices.resize(3)
	return choices

func apply_perk(perk: ChapterPerkDefinition) -> bool:
	if catalog == null or not catalog.perks.has(perk) or perk.chapter != player.chapter or selected.has(perk.id):
		return false
	selected[perk.id] = true
	for stat: StringName in perk.modifiers:
		stats.add_modifier(stat, float(perk.modifiers[stat]))
	match perk.behavior:
		ChapterPerkDefinition.Behavior.COMBAT_EFFICIENCY:
			efficiency = perk
		ChapterPerkDefinition.Behavior.ADAPTIVE_WARFARE:
			adaptive = perk
			adaptive_remaining = perk.duration
			recent_damage.clear()
			recent_kills.clear()
		ChapterPerkDefinition.Behavior.PERFECT_DISCIPLINE:
			stats.guaranteed_crit_interval = perk.projectile_interval
			stats.projectiles_fired = 0
	return true

func _on_damage_dealt(amount: float, source: StringName, killed: bool) -> void:
	if adaptive != null and source in [&"bolter", &"knife"]:
		recent_damage[source] = float(recent_damage.get(source, 0.0)) + amount
		if killed:
			recent_kills[source] = int(recent_kills.get(source, 0)) + 1
	if killed and efficiency != null:
		efficiency_stacks = mini(efficiency_stacks + 1, efficiency.max_stacks)
		efficiency_remaining = efficiency.duration
		stats.set_temporary_modifier(&"combat_efficiency", &"fire_rate", efficiency.bonus * efficiency_stacks)
		stats.set_temporary_modifier(&"combat_efficiency", &"movement_speed", efficiency.bonus * efficiency_stacks)

func _process(delta: float) -> void:
	if efficiency_remaining > 0.0:
		efficiency_remaining = maxf(0.0, efficiency_remaining - delta)
		if efficiency_remaining == 0.0:
			efficiency_stacks = 0
			stats.set_temporary_modifier(&"combat_efficiency", &"fire_rate", 0.0)
			stats.set_temporary_modifier(&"combat_efficiency", &"movement_speed", 0.0)
	if adaptive != null:
		adaptive_remaining -= delta
		if adaptive_remaining <= 0.0:
			_update_adaptive_bonus()
			adaptive_remaining = adaptive.duration

func _update_adaptive_bonus() -> void:
	var bolter_damage := float(recent_damage.get(&"bolter", 0.0))
	var knife_damage := float(recent_damage.get(&"knife", 0.0))
	var dominant: StringName = &""
	if bolter_damage > knife_damage:
		dominant = &"bolter_damage"
	elif knife_damage > bolter_damage:
		dominant = &"knife_damage"
	elif bolter_damage > 0.0:
		var bolter_kills := int(recent_kills.get(&"bolter", 0))
		var knife_kills := int(recent_kills.get(&"knife", 0))
		if bolter_kills != knife_kills:
			dominant = &"bolter_damage" if bolter_kills > knife_kills else &"knife_damage"
		else:
			dominant = adaptive_stat
	stats.set_temporary_modifier(&"adaptive_warfare", &"bolter_damage", adaptive.bonus if dominant == &"bolter_damage" else 0.0)
	stats.set_temporary_modifier(&"adaptive_warfare", &"knife_damage", adaptive.bonus if dominant == &"knife_damage" else 0.0)
	adaptive_stat = dominant
	recent_damage.clear()
	recent_kills.clear()
