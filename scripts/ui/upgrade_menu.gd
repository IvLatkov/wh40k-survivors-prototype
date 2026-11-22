extends CanvasLayer

signal upgrade_selected(id: StringName)

@onready var choices_container: VBoxContainer = $Overlay/Center/Panel/Margin/Content/Choices
var stats: CombatStats
var _accepting_selection: bool = false


func end_run() -> void:
	_accepting_selection = false
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


func show_choices(choices: Array, levels: Dictionary) -> void:
	$Overlay/Center/Panel/Margin/Content/Title.text = "LEVEL UP — CHOOSE ONE UPGRADE"
	$Overlay/Center/Panel/Margin/Content/Subtitle.hide()
	for child in choices_container.get_children():
		choices_container.remove_child(child)
		child.queue_free()
	_accepting_selection = true
	for definition in choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(440, 105)
		if definition is UltimateDefinition:
			button.text = "ULTIMATE | %s\n%s" % [definition.display_name, definition.description]
			button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.075, 0.025)
			style.border_color = Color(1.0, 0.65, 0.15)
			style.set_border_width_all(2)
			for state in ["normal", "hover", "pressed", "focus"]:
				button.add_theme_stylebox_override(state, style)
		else:
			var current_level := int(levels.get(definition.id, 0))
			button.text = "%s  |  %s\n%s\n%s" % [definition.display_name, definition.effect_text(1.0 + stats.get_modifier(&"normal_upgrade_effectiveness") if stats != null else 1.0), definition.get_level_text(stats, current_level), definition.description]
			button.disabled = not definition.is_available(stats, current_level)
		button.pressed.connect(_select.bind(definition.id))
		choices_container.add_child(button)
	show()
	if choices_container.get_child_count() > 0:
		choices_container.get_child(0).grab_focus()


func show_supply_choices(choices: Array, levels: Dictionary) -> void:
	show_choices(choices, levels)
	$Overlay/Center/Panel/Margin/Content/Title.text = "SUPPLY CRATE"
	$Overlay/Center/Panel/Margin/Content/Subtitle.show()


func _select(id: StringName) -> void:
	if not _accepting_selection:
		return
	_accepting_selection = false
	for button in choices_container.get_children():
		button.disabled = true
	upgrade_selected.emit(id)


func show_chapter_choices(choices: Array[ChapterPerkDefinition], chapter_name: String, milestone: int) -> void:
	$Overlay.color = Color(0.015, 0.045, 0.15, 0.95)
	$Overlay/Center/Panel/Margin/Content/Title.text = "%s PERK ? LEVEL %d" % [chapter_name, milestone]
	$Overlay/Center/Panel/Margin/Content/Title.modulate = Color(0.55, 0.75, 1.0)
	for child in choices_container.get_children():
		choices_container.remove_child(child)
		child.queue_free()
	_accepting_selection = true
	for perk in choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(640, 105)
		button.text = "%s\n%s" % [perk.display_name, perk.description]
		button.pressed.connect(_select.bind(perk.id))
		choices_container.add_child(button)
	show()
	if choices_container.get_child_count() > 0:
		choices_container.get_child(0).grab_focus()
