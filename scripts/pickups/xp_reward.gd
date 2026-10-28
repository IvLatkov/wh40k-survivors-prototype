class_name XPReward
extends Resource

@export_range(1, 1000, 1) var xp_per_pickup: int = 1
@export_range(1, 4, 1) var pickup_count: int = 1
@export_range(0.0, 1.0, 0.01) var double_drop_chance: float = 0.07
@export var texture: Texture2D


func roll_pickup_count() -> int:
	return pickup_count * (2 if randf() < double_drop_chance else 1)
