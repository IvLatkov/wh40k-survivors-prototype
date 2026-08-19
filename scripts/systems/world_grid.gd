extends Node2D

@export var world_half_size := Vector2i(2048, 2048)
@export_range(16, 256, 16) var cell_size: int = 64
@export var background_color := Color("151918")
@export var grid_color := Color("29302d")
@export var axis_color := Color("46514b")


func _draw() -> void:
	var world_size := Vector2(world_half_size * 2)
	draw_rect(Rect2(-Vector2(world_half_size), world_size), background_color)

	for x in range(-world_half_size.x, world_half_size.x + 1, cell_size):
		var vertical_color := axis_color if x == 0 else grid_color
		draw_line(
			Vector2(x, -world_half_size.y),
			Vector2(x, world_half_size.y),
			vertical_color
		)

	for y in range(-world_half_size.y, world_half_size.y + 1, cell_size):
		var horizontal_color := axis_color if y == 0 else grid_color
		draw_line(
			Vector2(-world_half_size.x, y),
			Vector2(world_half_size.x, y),
			horizontal_color
		)
