class_name SelectionCard
extends Button

var entry_id: StringName


func _ready() -> void:
	$Padding.minimum_size_changed.connect(_fit_content)
	_fit_content.call_deferred()


func _fit_content() -> void:
	custom_minimum_size.y = maxf(340.0, $Padding.get_combined_minimum_size().y)


func configure(entry: Dictionary, description: String) -> void:
	entry_id = entry.id
	%Portrait.texture = entry.portrait
	%Name.text = str(entry.name).to_upper()
	%Description.text = description
	%UnlockState.text = "Unlocked" if entry.unlocked else "Locked"
	set_selected(true)


func set_selected(value: bool) -> void:
	set_pressed_no_signal(value)
	%SelectionState.text = "Selected" if value else "Select"
