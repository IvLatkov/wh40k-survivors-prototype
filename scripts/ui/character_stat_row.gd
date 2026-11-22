class_name CharacterStatRow
extends PanelContainer

@onready var icon: TextureRect = %Icon
@onready var stat_label: Label = %StatName
@onready var value_label: Label = %Value
var health_bar: ProgressBar


func configure(display_name: String, texture: Texture2D, tint: Color, is_health: bool = false) -> void:
	stat_label.text = display_name + ":"
	icon.texture = texture
	icon.self_modulate = tint
	if is_health and health_bar == null:
		health_bar = ProgressBar.new()
		health_bar.name = "HealthBar"
		health_bar.theme_type_variation = &"SheetHealthBar"
		health_bar.custom_minimum_size = Vector2(72, 8)
		health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		health_bar.show_percentage = false
		health_bar.step = 0.0
		health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%Body.add_child(health_bar)
		%Body.move_child(health_bar, value_label.get_index())
	if health_bar != null:
		health_bar.visible = is_health
