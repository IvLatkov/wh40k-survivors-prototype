class_name UpgradeSystem
extends Node

signal choices_ready(choices: Array, levels: Dictionary)
signal chapter_choices_ready(choices: Array[ChapterPerkDefinition], chapter_name: String, milestone: int)
signal reward_queue_started
signal normal_choices_exhausted(reward_level: int)
signal ultimate_selected(id: StringName)
signal selection_finished

const MAX_WEAPON_TYPES: int = 4
const MAX_GENERIC_TYPES: int = 4

@export var ultimate_definitions: Array[UltimateDefinition] = [
	preload("res://resources/ultimates/devastator_shells.tres"),
	preload("res://resources/ultimates/whirlwind_assault.tres"),
	preload("res://resources/ultimates/forking_rounds.tres"),
]
var active_ultimates: Dictionary = {}
var offered_ultimates: Array[UltimateDefinition] = []

@export var definitions: Array[UpgradeDefinition] = []

var chapter_manager: ChapterPerkManager
var player: Player
var reward_levels: Array[int] = []
var chapter_offered: Array[ChapterPerkDefinition] = []
var stats: CombatStats
var levels: Dictionary = {}
var pending_levels: int = 0
var offered: Array[UpgradeDefinition] = []
var _was_paused: bool = false
var run_ended: bool = false
# Keep the full ownership catalog even if the eligible definition list is narrowed.
var _build_definitions: Array[UpgradeDefinition] = []


func bind_player(value: Player) -> void:
	_build_definitions = definitions.duplicate()
	player = value
	stats = player.combat_stats
	player.leveled_up.connect(queue_level)


func get_selected_upgrade_ids(category: UpgradeDefinition.Category) -> Array[StringName]:
	var selected: Array[StringName] = []
	for definition in get_selected_upgrades(category):
		selected.append(definition.id)
	return selected


func get_selected_upgrades(category: UpgradeDefinition.Category) -> Array[UpgradeDefinition]:
	var selected: Array[UpgradeDefinition] = []
	var catalog := _build_definitions if not _build_definitions.is_empty() else definitions
	# Dictionary insertion order preserves commitment order within each UI group.
	# Availability never affects ownership: maxed types retain their slots.
	for id: StringName in levels:
		if int(levels[id]) <= 0:
			continue
		for definition in catalog:
			if definition.id == id and definition.category == category:
				selected.append(definition)
				break
	return selected


func get_selected_weapon_ids() -> Array[StringName]:
	return get_selected_upgrade_ids(UpgradeDefinition.Category.WEAPON)


func get_selected_generic_ids() -> Array[StringName]:
	return get_selected_upgrade_ids(UpgradeDefinition.Category.GENERIC)


func can_select_upgrade(definition: UpgradeDefinition) -> bool:
	if not definition.is_available(stats, int(levels.get(definition.id, 0))):
		return false
	if int(levels.get(definition.id, 0)) <= 0:
		var slot_limit := MAX_WEAPON_TYPES if definition.category == UpgradeDefinition.Category.WEAPON else MAX_GENERIC_TYPES
		return get_selected_upgrade_ids(definition.category).size() < slot_limit
	return true


func available_upgrades() -> Array[UpgradeDefinition]:
	# Compatibility for existing callers; all filtering lives in one path.
	return get_eligible_upgrades()


func get_eligible_upgrades() -> Array[UpgradeDefinition]:
	var result: Array[UpgradeDefinition] = []
	var seen: Dictionary = {}
	for definition in definitions:
		if not seen.has(definition.id) and can_select_upgrade(definition):
			result.append(definition)
			seen[definition.id] = true
	return result


func can_select_ultimate(ultimate: UltimateDefinition) -> bool:
	if active_ultimates.has(ultimate.id):
		return false
	var catalog := _build_definitions if not _build_definitions.is_empty() else definitions
	for id: StringName in ultimate.prerequisites:
		var definition: UpgradeDefinition = null
		for candidate in catalog:
			if candidate.id == id:
				definition = candidate
				break
		if definition == null or definition.category != UpgradeDefinition.Category.WEAPON:
			return false
		var level := int(levels.get(id, 0))
		if level >= int(ultimate.prerequisites[id]):
			continue
		if level > 0 and ultimate.accept_functional_cap.has(id) and not definition.is_available(stats, level):
			continue
		return false
	return true


func get_eligible_ultimates() -> Array[UltimateDefinition]:
	var result: Array[UltimateDefinition] = []
	var seen: Dictionary = {}
	for ultimate in ultimate_definitions:
		if not seen.has(ultimate.id) and can_select_ultimate(ultimate):
			result.append(ultimate)
			seen[ultimate.id] = true
	return result


func get_selected_ultimates() -> Array[UltimateDefinition]:
	var result: Array[UltimateDefinition] = []
	for ultimate in ultimate_definitions:
		if active_ultimates.has(ultimate.id):
			result.append(ultimate)
	return result


func queue_level() -> void:
	if run_ended:
		return
	if pending_levels == 0:
		# Allow an informational overlay to release its pause before rewards own it.
		reward_queue_started.emit()
	# Capture now: add_xp may emit several times before the first choice is made.
	reward_levels.append(player.level)
	pending_levels = reward_levels.size()
	if pending_levels == 1:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_offer_choices()


func _offer_choices() -> void:
	if run_ended:
		return
	if reward_levels.is_empty():
		return
	var reward_level := reward_levels[0]
	if chapter_manager != null and chapter_manager.is_milestone(reward_level):
		chapter_offered = chapter_manager.choices_for(reward_level)
		chapter_choices_ready.emit(chapter_offered.duplicate(), chapter_manager.catalog.display_name, reward_level)
		return
	offered = get_eligible_upgrades()
	offered_ultimates = get_eligible_ultimates()
	if offered.is_empty() and offered_ultimates.is_empty():
		# No invalid substitute rewards or empty modal: retain XP/level progression.
		normal_choices_exhausted.emit(reward_level)
		_finish_reward()
		return
	offered.shuffle()
	# Unselected unlocked Ultimates take priority; fill remaining cards normally.
	offered_ultimates.shuffle()
	if offered_ultimates.size() > 3:
		offered_ultimates.resize(3)
	offered.resize(mini(offered.size(), 3 - offered_ultimates.size()))
	var choices: Array = []
	choices.append_array(offered_ultimates)
	choices.append_array(offered)
	choices_ready.emit(choices, levels.duplicate())


func select_upgrade(id: StringName) -> void:
	if run_ended:
		return
	for ultimate in offered_ultimates:
		if ultimate.id == id and can_select_ultimate(ultimate):
			offered = []
			offered_ultimates = []
			active_ultimates[id] = true
			ultimate_selected.emit(id)
			_finish_reward()
			return
	for definition in offered:
		if definition.id != id:
			continue
		# Clear before applying so repeated button events cannot select twice.
		if not can_select_upgrade(definition):
			return
		offered = []
		offered_ultimates = []
		definition.apply(stats)
		levels[id] = int(levels.get(id, 0)) + 1
		_finish_reward()
		return


func select_chapter_perk(id: StringName) -> void:
	if run_ended:
		return
	for perk in chapter_offered:
		if perk.id == id:
			chapter_offered = []
			if chapter_manager.apply_perk(perk):
				_finish_reward()
			return


func _finish_reward() -> void:
	if run_ended:
		return
	reward_levels.pop_front()
	pending_levels = reward_levels.size()
	selection_finished.emit()
	if pending_levels > 0:
		_offer_choices.call_deferred()
	else:
		get_tree().paused = _was_paused


func end_run() -> void:
	run_ended = true
	reward_levels.clear()
	pending_levels = 0
	offered.clear()
	offered_ultimates.clear()
	chapter_offered.clear()
