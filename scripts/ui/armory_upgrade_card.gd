class_name ArmoryUpgradeCard
extends Button

# Presentation only: this button has no purchase or gameplay-stat connection.
var entry_id: StringName


func _ready() -> void:
	$Padding.minimum_size_changed.connect(_fit_content)
	_fit_content.call_deferred()


func configure(entry: Dictionary) -> void:
	entry_id = entry.id
	%UpgradeName.text = entry.name
	%Rank.text = "%d / %d" % [entry.rank, entry.max_rank]
	%Description.text = entry.description
	%Cost.text = "Cost: " + entry.cost
	tooltip_text = "Permanent upgrades are not available yet."
	for _rank in int(entry.max_rank):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 4)
		pip.color = Color(0.23, 0.29, 0.33)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%RankPips.add_child(pip)


func _fit_content() -> void:
	custom_minimum_size.y = maxf(164.0, $Padding.get_combined_minimum_size().y)
