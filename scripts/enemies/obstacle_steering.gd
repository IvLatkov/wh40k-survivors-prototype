class_name ObstacleSteering
extends RefCounted

const CLEARANCE: float = 8.0
const WAYPOINT_DISTANCE_SQUARED: float = 64.0
const TARGET_REPLAN_DISTANCE_SQUARED: float = 4096.0
const SIDE_PROBE_MARGIN: float = 4.0
const CLUSTER_QUERY_MARGIN: float = 16.0
const CLUSTER_QUERY_LIMIT: int = 16
const CLUSTER_EXPANSION_PASSES: int = 2

var _probe := PhysicsRayQueryParameters2D.new()
var _cluster_query := PhysicsShapeQueryParameters2D.new()
var _cluster_shape := RectangleShape2D.new()
var active: bool = false
var _waypoints: Array[Vector2] = []
var _obstacle: StaticBody2D
var _bounds: Rect2
var _goal: Vector2


func _init() -> void:
	_probe.collision_mask = TerrainObstacles.COLLISION_LAYER
	_probe.hit_from_inside = true
	_probe.collide_with_areas = false
	_cluster_query.shape = _cluster_shape
	_cluster_query.collision_mask = TerrainObstacles.COLLISION_LAYER
	_cluster_query.collide_with_areas = false


func direction(body: CharacterBody2D, goal: Vector2, desired: Vector2, probe_due: bool, lookahead: float, radius: float) -> Vector2:
	if desired.is_zero_approx():
		return desired
	var origin := body.global_position
	if not _waypoints.is_empty():
		if not is_instance_valid(_obstacle) or goal.distance_squared_to(_goal) > TARGET_REPLAN_DISTANCE_SQUARED:
			_waypoints.clear()
			probe_due = true
		elif not _crosses(origin, goal, _bounds.grow(-1.0)):
			_waypoints.clear()
	while not _waypoints.is_empty() and origin.distance_squared_to(_waypoints[0]) < WAYPOINT_DISTANCE_SQUARED:
		_waypoints.pop_front()
	if probe_due:
		var heading := origin.direction_to(_waypoints[0]) if not _waypoints.is_empty() else desired.normalized()
		var hit: Dictionary = {}
		# Side probes account for body width, including gaps a center ray can fit
		# through but a Squig/Ork/Warboss cannot.
		for offset in [Vector2.ZERO, heading.orthogonal() * (radius + SIDE_PROBE_MARGIN), -heading.orthogonal() * (radius + SIDE_PROBE_MARGIN)]:
			_probe.from = origin + offset
			_probe.to = _probe.from + heading * lookahead
			hit = body.get_world_2d().direct_space_state.intersect_ray(_probe)
			CombatProfile.count_event(&"obstacle_probes")
			if not hit.is_empty():
				break
		if not hit.is_empty() and hit.collider is StaticBody2D:
			var obstacle := hit.collider as StaticBody2D
			if _waypoints.is_empty() or (obstacle != _obstacle and not _bounds.encloses(_expanded_bounds(obstacle, radius))):
				var collision := obstacle.get_node_or_null("CollisionShape2D") as CollisionShape2D
				if collision != null and collision.shape != null:
					_obstacle = obstacle
					_bounds = _expanded_bounds(obstacle, radius)
					# Join touching clearance bounds locally so narrow gaps do not
					# make characters alternate endlessly between adjacent props.
					for _pass in CLUSTER_EXPANSION_PASSES:
						_cluster_shape.size = _bounds.size + Vector2.ONE * CLUSTER_QUERY_MARGIN
						_cluster_query.transform.origin = _bounds.get_center()
						for nearby in body.get_world_2d().direct_space_state.intersect_shape(_cluster_query, CLUSTER_QUERY_LIMIT):
							if nearby.collider is StaticBody2D:
								var other := _expanded_bounds(nearby.collider, radius)
								if other.has_area() and _bounds.intersects(other, true):
									_bounds = _bounds.merge(other)
					_goal = goal
					_waypoints = _detour(origin, goal, _bounds)
					CombatProfile.count_event(&"obstacle_plans")
	if _waypoints.is_empty():
		active = false
		return desired
	active = true
	return origin.direction_to(_waypoints[0]) * desired.length()


static func _expanded_bounds(obstacle: StaticBody2D, radius: float) -> Rect2:
	var collision := obstacle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return Rect2()
	return (collision.global_transform * collision.shape.get_rect()).grow(radius + CLEARANCE)


static func _crosses(from: Vector2, to: Vector2, bounds: Rect2) -> bool:
	if bounds.has_point(from) or bounds.has_point(to):
		return true
	var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false


static func _detour(origin: Vector2, goal: Vector2, bounds: Rect2) -> Array[Vector2]:
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var inner := bounds.grow(-1.0)
	var best: Array[Vector2] = []
	var best_length := INF
	for start in 4:
		# A character can be inside the conservative bounds without touching the
		# actual outline; let collision-safe movement bring it to the nearest edge.
		if not bounds.has_point(origin) and _crosses(origin, corners[start], inner):
			continue
		for step in [-1, 1]:
			var path: Array[Vector2] = []
			var length := origin.distance_to(corners[start])
			for count in 4:
				var corner := corners[posmod(start + step * count, 4)]
				if not path.is_empty():
					length += path.back().distance_to(corner)
				path.append(corner)
				if not bounds.has_point(goal) and _crosses(corner, goal, inner):
					continue
				var total := length + corner.distance_to(goal)
				if total < best_length:
					best_length = total
					best = path.duplicate()
	return best
