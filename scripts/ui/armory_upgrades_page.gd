extends VBoxContainer

const CARD := preload("res://scenes/ui/armory_upgrade_card.tscn")
# Menu-only display records, deliberately unrelated to run upgrade resources.
const ENTRIES: Array[Dictionary] = [
	{"id": &"armor", "name": "ARMOR", "rank": 0, "max_rank": 5, "description": "Increase flat damage reduction.", "cost": "—"},
	{"id": &"bolter_damage", "name": "BOLTER DAMAGE", "rank": 0, "max_rank": 5, "description": "Increase Bolter base damage.", "cost": "—"},
	{"id": &"movement", "name": "MOVEMENT", "rank": 0, "max_rank": 5, "description": "Increase movement speed.", "cost": "—"},
	{"id": &"max_health", "name": "MAX HEALTH", "rank": 0, "max_rank": 5, "description": "Increase maximum health.", "cost": "—"},
]


func _ready() -> void:
	for entry in ENTRIES:
		var card := CARD.instantiate() as ArmoryUpgradeCard
		card.name = str(entry.id).to_pascal_case() + "Upgrade"
		%UpgradeGrid.add_child(card)
		card.configure(entry)


func set_displayed_currency(amount: int) -> void:
	%ArmoryCurrency.text = "Currency: %d" % amount


func set_compact(compact: bool) -> void:
	%UpgradeGrid.columns = 1 if compact else 2
	%ArmoryHeader.columns = 1 if compact else 2
