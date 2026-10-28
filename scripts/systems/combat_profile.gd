class_name CombatProfile
extends RefCounted

# Opt-in benchmark telemetry. Inclusive CPU timings; nested paths must not be summed.
static var enabled: bool = false
static var counts: Dictionary = {}
static var costs: Dictionary = {}
static var queries: Dictionary = {}

static func count_event(key: StringName, amount: int = 1) -> void:
	if enabled:
		counts[key] = int(counts.get(key, 0)) + amount

static func finish(key: StringName, start: int) -> void:
	if enabled:
		costs[key] = int(costs.get(key, 0)) + Time.get_ticks_usec() - start
		count_event(key)

static func query(key: StringName, candidates: int) -> void:
	if not enabled: return
	var entry: Array = queries.get(key, [0, 0, 0])
	entry[0] += 1
	entry[1] += candidates
	entry[2] = maxi(entry[2], candidates)
	queries[key] = entry

static func clear_frame() -> void:
	counts.clear()
	costs.clear()
	queries.clear()


static func insert_child(parent: Node, child: Node, key: StringName) -> void:
	var start := Time.get_ticks_usec()
	parent.add_child(child)
	finish(key, start)
