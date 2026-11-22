extends CanvasLayer

const UPGRADE_SLOT_SCENE := preload("res://scenes/ui/character_upgrade_slot.tscn")
const STAT_ROW_SCENE := preload("res://scenes/ui/character_stat_row.tscn")
const ACCENT_COLOR := Color(0.58, 0.68, 0.78, 1.0)
const HEALTH_COLOR := Color(0.76, 0.38, 0.37, 1.0)
const STAT_ICONS: Dictionary = {
	"Health": preload("res://addons/pixel_ui_scifi/icons/heart.png"),
	"Armor": preload("res://addons/pixel_ui_scifi/icons/shield.png"),
	"Health Regen": preload("res://addons/pixel_ui_scifi/icons/health.png"),
	"Movement Speed": preload("res://addons/pixel_ui_scifi/icons/arrow_right.png"),
	"Pickup Radius": preload("res://addons/pixel_ui_scifi/icons/info.png"),
	"XP Gain": preload("res://addons/pixel_ui_scifi/icons/star.png"),
	"Dodge Chance": preload("res://addons/pixel_ui_scifi/icons/arrow_right.png"),
	"Better XP Drop Chance": preload("res://addons/pixel_ui_scifi/icons/star.png"),
	"Bolter Damage": preload("res://addons/pixel_ui_scifi/icons/crosshair.png"),
	"Bolter Projectiles": preload("res://addons/pixel_ui_scifi/icons/rocket.png"),
	"Bolter Fire Rate": preload("res://addons/pixel_ui_scifi/icons/energy.png"),
	"Crit Chance": preload("res://addons/pixel_ui_scifi/icons/crosshair.png"),
	"Crit Bonus": preload("res://addons/pixel_ui_scifi/icons/crosshair.png"),
	"Knife Damage": preload("res://addons/pixel_ui_scifi/icons/info.png"),
	"Knife Range": preload("res://addons/pixel_ui_scifi/icons/info.png"),
	"Knife Attack Rate": preload("res://addons/pixel_ui_scifi/icons/energy.png"),
}

var player: Player
var rewards: UpgradeSystem
var modal_menus: Array[CanvasLayer] = []
var _owns_pause: bool = false
var run_ended: bool = false
var _value_labels: Dictionary = {}
var _stat_labels: Dictionary = {}
var _stat_rows: Dictionary[String, CharacterStatRow] = {}
var _health_bar: ProgressBar

@onready var sheet_panel: PanelContainer = $Overlay/Center/Panel
@onready var content: VBoxContainer = $Overlay/Center/Panel/Margin/Scroll/Content
@onready var title: Label = content.get_node("Body/Details/Header/Title")
@onready var chapter_label: Label = content.get_node("Body/Details/Header/Identity/Chapter")
@onready var level_label: Label = content.get_node("Body/Details/Header/Identity/Level")
@onready var stats_grid: GridContainer = content.get_node("Body/Details/Stats")


func _ready() -> void:
	content.get_node("Close").pressed.connect(close_panel)
	_add_stat_section("SURVIVAL", ["Health", "Armor", "Health Regen", "Movement Speed", "Pickup Radius", "XP Gain", "Dodge Chance", "Better XP Drop Chance"])
	_add_stat_section("WEAPONS", ["Bolter Damage", "Bolter Projectiles", "Bolter Fire Rate", "Crit Chance", "Crit Bonus", "Knife Damage", "Knife Range", "Knife Attack Rate"])
	for section: String in ["Weapons", "Generic"]:
		var slots := content.get_node("Upgrades/" + section + "/Slots")
		for _index in _slot_limit(UpgradeDefinition.Category.WEAPON if section == "Weapons" else UpgradeDefinition.Category.GENERIC):
			var slot := UPGRADE_SLOT_SCENE.instantiate() as PanelContainer
			slot.add_theme_stylebox_override("panel", sheet_panel.theme.get_stylebox("panel", "UpgradeSlot"))
			for label_name: String in ["Group", "Level"]:
				slot.get_node("Row/" + label_name).add_theme_color_override("font_color", ACCENT_COLOR)
			slots.add_child(slot)
	get_viewport().size_changed.connect(_resize_panel)
	_resize_panel()


func _resize_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	sheet_panel.custom_minimum_size = Vector2(minf(1000.0, maxf(0.0, viewport_size.x - 32.0)), minf(616.0, maxf(0.0, viewport_size.y - 32.0)))
	(content.get_node("Upgrades") as GridContainer).columns = 1 if viewport_size.x < 800.0 else 2
	stats_grid.columns = 1 if viewport_size.x < 760.0 else 2
	var portrait := content.get_node("Body/Portrait") as TextureRect
	portrait.custom_minimum_size.x = 128 if viewport_size.x < 760.0 else 190
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if viewport_size.x < 760.0 else Control.SIZE_FILL


func _add_stat_section(heading: String, names: Array[String]) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 1)
	stats_grid.add_child(section)
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_color_override("font_color", ACCENT_COLOR)
	section.add_child(heading_label)
	for stat_name in names:
		var row := STAT_ROW_SCENE.instantiate() as CharacterStatRow
		row.name = stat_name.replace(" ", "") + "Row"
		section.add_child(row)
		var health_stat := stat_name in ["Health", "Health Regen"]
		var display_name: String = {"Armor": "Ceramite Plating", "Health Regen": "Gene-Seed Resilience"}.get(stat_name, stat_name)
		row.configure(display_name, STAT_ICONS[stat_name], HEALTH_COLOR if health_stat else ACCENT_COLOR, stat_name == "Health")
		if health_stat:
			row.stat_label.add_theme_color_override("font_color", HEALTH_COLOR)
			row.value_label.add_theme_color_override("font_color", HEALTH_COLOR)
		if stat_name == "Health":
			_health_bar = row.health_bar
		_stat_rows[stat_name] = row
		_stat_labels[stat_name] = row.stat_label
		_value_labels[stat_name] = row.value_label

func bind_player(value: Player, upgrade_system: UpgradeSystem, menus: Array[CanvasLayer]) -> void:
	player = value
	rewards = upgrade_system
	modal_menus = menus
	rewards.reward_queue_started.connect(close_panel)
	rewards.selection_finished.connect(_on_selection_finished)
	player.health_depleted.connect(close_panel)
	player.health_changed.connect(_on_health_changed)
	player.xp_changed.connect(_on_xp_changed)
	player.combat_stats.stat_changed.connect(_on_stat_changed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("character_info"):
		if visible:
			close_panel()
		else:
			open_panel()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _other_modal_active() -> bool:
	if rewards != null and rewards.pending_levels > 0:
		return true
	for menu in modal_menus:
		if menu.visible:
			return true
	return false


func open_panel() -> void:
	if run_ended:
		return
	if visible or player == null or player.current_health <= 0.0 or get_tree().paused or _other_modal_active():
		return
	_owns_pause = true
	get_tree().paused = true
	refresh()
	show()
	content.get_node("Close").grab_focus()


func close_panel() -> void:
	if run_ended:
		return
	if not visible:
		return
	hide()
	if _owns_pause and not _other_modal_active() and player.current_health > 0.0:
		get_tree().paused = false
	_owns_pause = false


func end_run() -> void:
	run_ended = true
	_owns_pause = false
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


func refresh_stats() -> void:
	if player == null:
		return
	var stats := player.combat_stats
	var bolter = player.get_node("Bolter")
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	chapter_label.text = "Chapter: " + player.ChapterTypes.Type.keys()[player.chapter].capitalize()
	level_label.text = "Level: %d" % player.level
	_value_labels["Health"].text = "%d / %d" % [roundi(player.current_health + Player.HEALTH_ROUNDING_EPSILON), roundi(player.max_health + Player.HEALTH_ROUNDING_EPSILON)]
	_health_bar.max_value = player.max_health
	_health_bar.value = player.current_health
	_value_labels["Health Regen"].text = "%.1f HP/s" % player.get_health_regen()
	_value_labels["Movement Speed"].text = _number(player.get_movement_speed())
	_value_labels["Pickup Radius"].text = "%s px" % _number(player.get_pickup_radius())
	_value_labels["XP Gain"].text = "+%s%%" % _number(stats.get_modifier(&"xp_gain") * 100.0)
	_value_labels["Dodge Chance"].text = "%s%%" % _number(stats.get_dodge_chance() * 100.0)
	_value_labels["Better XP Drop Chance"].text = "+%s%%" % _number(stats.get_modifier(&"better_xp_drop_chance") * 100.0)
	_value_labels["Armor"].text = str(stats.get_armor())
	_value_labels["Bolter Damage"].text = _number(bolter.get_damage())
	_value_labels["Bolter Fire Rate"].text = "%.2f /s" % (1.0 / bolter.get_fire_interval())
	_value_labels["Bolter Projectiles"].text = "%d / %d" % [stats.get_projectile_count(), CombatStats.MAX_PROJECTILES]
	_value_labels["Crit Chance"].text = "%s%%" % _number(stats.get_crit_chance() * 100.0)
	_value_labels["Crit Bonus"].text = "+%s%%" % _number((stats.get_crit_multiplier() - 1.0) * 100.0)
	_value_labels["Knife Damage"].text = _number(knife.get_damage())
	_value_labels["Knife Attack Rate"].text = "%.2f /s" % (1.0 / knife.get_attack_cooldown())
	_value_labels["Knife Range"].text = "%s px" % _number(knife.current_knife_radius)


func refresh() -> void:
	refresh_stats()
	refresh_weapon_upgrades()
	refresh_generic_upgrades()
	refresh_chapter_perks()
	refresh_ultimates()


func _slot_limit(category: UpgradeDefinition.Category) -> int:
	return UpgradeSystem.MAX_WEAPON_TYPES if category == UpgradeDefinition.Category.WEAPON else UpgradeSystem.MAX_GENERIC_TYPES


func _selected_upgrades(category: UpgradeDefinition.Category) -> Array[UpgradeDefinition]:
	return rewards.get_selected_upgrades(category) if rewards != null else []


func refresh_weapon_upgrades() -> void:
	_refresh_upgrade_slots("Weapons", "Weapon Upgrades", UpgradeDefinition.Category.WEAPON)


func refresh_generic_upgrades() -> void:
	_refresh_upgrade_slots("Generic", "Generic Upgrades", UpgradeDefinition.Category.GENERIC)


func _upgrade_display_name(definition: UpgradeDefinition) -> String:
	# String.capitalize() drops hyphens; preserve named upgrades such as Auto-Senses.
	var parts := definition.display_name.split("-")
	for index in parts.size():
		parts[index] = parts[index].capitalize()
	return "-".join(parts)


func _refresh_upgrade_slots(section_name: String, heading: String, category: UpgradeDefinition.Category) -> void:
	var section := content.get_node("Upgrades/" + section_name)
	var slot_limit := _slot_limit(category)
	var selected := _selected_upgrades(category)
	if category == UpgradeDefinition.Category.WEAPON:
		# Present contiguous groups within the same four slots and single counter.
		var grouped: Array[UpgradeDefinition] = []
		for group: int in UpgradeDefinition.WeaponUpgradeGroup.values():
			for definition in selected:
				if definition.weapon_group == group:
					grouped.append(definition)
		selected = grouped
	(section.get_node("Count") as Label).text = "%s: %d / %d" % [heading, selected.size(), slot_limit]
	for index in slot_limit:
		var slot := section.get_node("Slots").get_child(index) as PanelContainer
		var name_label := slot.get_node("Row/Name") as Label
		var count_label := slot.get_node("Row/Level") as Label
		var occupied := index < selected.size()
		var group_label := slot.get_node("Row/Group") as Label
		group_label.visible = occupied and category == UpgradeDefinition.Category.WEAPON
		group_label.text = UpgradeDefinition.WeaponUpgradeGroup.keys()[selected[index].weapon_group] if group_label.visible else ""
		name_label.text = _upgrade_display_name(selected[index]) if occupied else "Empty"
		count_label.text = selected[index].get_level_text(player.combat_stats, int(rewards.levels[selected[index].id])) if occupied else ""
		name_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.91) if occupied else Color(0.43, 0.47, 0.5))
		var style := slot.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
		style.modulate_color = Color(1, 0.55, 0.8) if occupied else Color(0.55, 0.28, 0.42)
		slot.add_theme_stylebox_override("panel", style)
	var overflow := section.get_node("Overflow") as Label
	var extra: PackedStringArray = []
	for index in range(slot_limit, selected.size()):
		extra.append("%s (Lv. %d)" % [selected[index].display_name.capitalize(), int(rewards.levels[selected[index].id])])
	overflow.text = "Also selected: " + "; ".join(extra)
	overflow.visible = not extra.is_empty()


func refresh_chapter_perks() -> void:
	var manager := rewards.chapter_manager if rewards != null else null
	var owned: PackedStringArray = []
	var chapter_name: String = player.ChapterTypes.Type.keys()[player.chapter] if player != null else "CHAPTER"
	if manager != null and manager.catalog != null:
		chapter_name = manager.catalog.display_name
		for perk in manager.catalog.perks:
			if manager.selected.has(perk.id):
				owned.append(perk.display_name.capitalize())
	(content.get_node("ChapterPerks/Title") as Label).text = chapter_name.to_upper() + " PERKS"
	(content.get_node("ChapterPerks/Owned") as Label).text = " · ".join(owned) if not owned.is_empty() else "None selected"


func _number(value: float) -> String:
	return String.num(value, 2).trim_suffix(".0")


func _on_selection_finished() -> void:
	if visible:
		refresh_weapon_upgrades()
		refresh_generic_upgrades()
		refresh_chapter_perks()
		refresh_ultimates()


func _on_health_changed(_current: float, _maximum: float) -> void:
	if visible:
		refresh_stats()


func _on_xp_changed(_xp: float, _required: int, _level: int) -> void:
	if visible:
		refresh_stats()


func _on_stat_changed(_stat: StringName) -> void:
	if visible:
		refresh_stats()


func refresh_ultimates() -> void:
	var names: PackedStringArray = []
	if rewards != null:
		for ultimate in rewards.get_selected_ultimates():
			names.append(ultimate.display_name.capitalize())
	(content.get_node("Ultimates/Owned") as Label).text = "\n".join(names) if not names.is_empty() else "None"
