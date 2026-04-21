class_name DangerZoneManager
extends Node

## Manages danger zones throughout the forest
## Danger increases with distance from path start and distance from path

@export var max_danger_distance: float = 500.0  # Distance along path for max danger
@export var off_path_danger_rate: float = 0.02  # Danger increase per meter off path
@export var max_off_path_danger: float = 1.0  # Max additional danger from being off path

var _path_generator: PathGenerator = null
var _path_length: float = 0.0

func initialize(path_gen: PathGenerator) -> void:
	_path_generator = path_gen
	_calculate_path_length()
	print("DangerZoneManager: initialized with path length %.1f" % _path_length)

func _calculate_path_length() -> void:
	if not _path_generator:
		return

	# Calculate total length of main path
	var main_path = _path_generator.main_path
	_path_length = 0.0

	for i in range(main_path.size() - 1):
		var dist = main_path[i].distance_to(main_path[i + 1])
		_path_length += dist

	print("DangerZoneManager: calculated path length = %.1f" % _path_length)

func get_danger_level(world_pos: Vector3) -> float:
	if not _path_generator:
		return 1.0

	# Find nearest point on path and distance along path
	var nearest_info = _find_nearest_path_point(world_pos)
	var distance_along_path: float = nearest_info["distance_along"]
	var distance_from_path: float = nearest_info["distance_from"]

	# Base danger from progress along path (1.0 at start, 3.0 at end)
	var progress = clampf(distance_along_path / max_danger_distance, 0.0, 1.0)
	var base_danger = lerp(1.0, 3.0, progress)

	# Additional danger from being off the path
	var off_path_danger = distance_from_path * off_path_danger_rate
	off_path_danger = clampf(off_path_danger, 0.0, max_off_path_danger)

	# Combine dangers
	var total_danger = base_danger + off_path_danger
	total_danger = clampf(total_danger, 1.0, 3.0)

	return total_danger

func _find_nearest_path_point(world_pos: Vector3) -> Dictionary:
	var main_path = _path_generator.main_path
	if main_path.is_empty():
		return {"distance_along": 0.0, "distance_from": 0.0}

	var nearest_distance = INF
	var distance_along_path = 0.0
	var accumulated_distance = 0.0

	# Check each path segment
	for i in range(main_path.size() - 1):
		var segment_start = main_path[i]
		var segment_end = main_path[i + 1]

		# Find closest point on this segment
		var closest_point = _closest_point_on_segment(world_pos, segment_start, segment_end)
		var dist_to_segment = Vector3(world_pos.x, 0, world_pos.z).distance_to(Vector3(closest_point.x, 0, closest_point.z))

		# If this is the closest segment so far
		if dist_to_segment < nearest_distance:
			nearest_distance = dist_to_segment
			# Calculate how far along this segment the closest point is
			var segment_length = segment_start.distance_to(segment_end)
			var point_on_segment = segment_start.distance_to(closest_point)
			distance_along_path = accumulated_distance + point_on_segment

		# Add this segment's length to accumulated distance
		accumulated_distance += segment_start.distance_to(segment_end)

	return {
		"distance_along": distance_along_path,
		"distance_from": nearest_distance
	}

func _closest_point_on_segment(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> Vector3:
	# Project point onto line segment (ignoring Y axis)
	var px = point.x
	var pz = point.z
	var ax = segment_start.x
	var az = segment_start.z
	var bx = segment_end.x
	var bz = segment_end.z

	# Vector from A to B
	var abx = bx - ax
	var abz = bz - az

	# Vector from A to P
	var apx = px - ax
	var apz = pz - az

	# Dot products
	var ab_ab = abx * abx + abz * abz
	var ap_ab = apx * abx + apz * abz

	# Avoid division by zero
	if ab_ab == 0.0:
		return segment_start

	# Parameter t (0 = start, 1 = end)
	var t = clampf(ap_ab / ab_ab, 0.0, 1.0)

	# Closest point on segment
	var closest_x = ax + t * abx
	var closest_z = az + t * abz

	return Vector3(closest_x, 0, closest_z)

func get_danger_zone(danger_level: float) -> int:
	# Convert danger level (1.0-3.0) to zone (1-3)
	if danger_level < 1.667:
		return 1
	elif danger_level < 2.334:
		return 2
	else:
		return 3
