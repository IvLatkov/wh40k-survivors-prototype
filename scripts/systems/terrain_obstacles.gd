class_name TerrainObstacles
extends RefCounted

# Separate from player (1), enemies (2), bolts (4/16), and pickups (8).
const COLLISION_LAYER: int = 32
const TREE_TRUNK_RADIUS_RATIO: float = 0.14
const TREE_TRUNK_Y_RATIO: float = 0.34
static var _solid_shapes: Dictionary[Texture2D, ConvexPolygonShape2D] = {}


static func add_to(sprite: Sprite2D, tree_trunk: bool = false) -> void:
	var body := StaticBody2D.new()
	body.name = "Obstacle"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	if tree_trunk:
		var trunk := CircleShape2D.new()
		trunk.radius = sprite.texture.get_width() * TREE_TRUNK_RADIUS_RATIO
		collision.shape = trunk
		collision.position.y = sprite.texture.get_height() * TREE_TRUNK_Y_RATIO
	else:
		collision.shape = _get_solid_shape(sprite.texture)
	body.add_child(collision)
	sprite.add_child(body)


static func _get_solid_shape(texture: Texture2D) -> ConvexPolygonShape2D:
	if _solid_shapes.has(texture):
		return _solid_shapes[texture]
	# Build once per shared tank/ruin texture, keeping transparent corners clear.
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(texture.get_image(), 0.5)
	var points := PackedVector2Array()
	for polygon in bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, bitmap.get_size()), 2.0):
		for point in polygon:
			points.append(point - texture.get_size() * 0.5)
	var shape := ConvexPolygonShape2D.new()
	shape.points = Geometry2D.convex_hull(points)
	_solid_shapes[texture] = shape
	return shape
