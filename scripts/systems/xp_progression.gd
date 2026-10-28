class_name XPProgression
extends Resource

## Index 0 is level 1 -> 2. Extend this table to override later requirements.
@export var requirements: PackedInt32Array = PackedInt32Array()
## Each level beyond the table adds this amount to the last requirement.
@export_range(1, 1000, 1) var subsequent_level_increase: int = 15


func get_requirement(current_level: int) -> int:
	var index := maxi(current_level, 1) - 1
	if index < requirements.size():
		return maxi(requirements[index], 1)
	var last_requirement := 0 if requirements.is_empty() else requirements[requirements.size() - 1]
	var additional_levels := index - requirements.size() + 1
	return maxi(last_requirement + additional_levels * maxi(subsequent_level_increase, 1), 1)
