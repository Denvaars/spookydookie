class_name PathGenerator
extends Node3D

## Generates the main forest trail as a random walk biased toward +Z,
## then branches off at irregular intervals.
## Builds flat path meshes that sit just above the terrain surface.

const PATH_WIDTH: float   = 5.0    # Trail width in metres
const PATH_FADE_DISTANCE: float = 1.0  # Distance over which path fades to grass
const STEP_LENGTH: float  = 1.5    # Distance between path waypoints (reduced for better connectivity)
const MAX_LATERAL: float  = 0.5    # Max sideways drift per step
const BRANCH_CHANCE: float = 0.09  # Probability per waypoint of a branch starting
const BRANCH_MIN: int = 6          # Min waypoints per branch
const BRANCH_MAX: int = 18         # Max waypoints per branch
const BRANCH_MIN_SPACING: float = 20.0  # Minimum distance along main path between branches (meters)
const BRANCH_MIN_LENGTH: float = 12.0   # Minimum physical length for a branch to be kept (meters)
const PATH_OFFSET: float  = 0.22   # Visual offset above terrain surface

var main_path: PackedVector3Array = []
var branches: Array[PackedVector3Array] = []

# Flat 2D cache of all path points for distance queries (XZ only).
var _all_points_2d: PackedVector2Array = []

# Distance grid for fast path blend lookups
var _distance_grid: Array = []  # 2D array [z][x] of floats
var _grid_size: float = 0.5  # Fine 0.5m cells for smooth paths
var _grid_width: int = 0
var _grid_length: int = 0
var _grid_offset_x: float = 0.0
var _grid_offset_z: float = 0.0

var _terrain: TerrainGenerator


func generate(terrain: TerrainGenerator) -> void:
	_terrain = terrain
	_generate_main_path()
	_generate_branches()
	_cache_2d_points()
	_build_distance_grid()
	# Note: Path mesh is now rendered via terrain texture blending instead of separate meshes
	print("PathGenerator: main path %d pts, %d branches, grid %dx%d (texture blending)" % [main_path.size(), branches.size(), _grid_width, _grid_length])


# Returns the distance from world position (wx, wz) to the nearest path.
# Uses precomputed distance grid with bilinear interpolation for smooth blending.
func get_distance_to_path(wx: float, wz: float) -> float:
	# Convert world coords to grid coords (continuous, not integer)
	var gx_f := (wx - _grid_offset_x) / _grid_size
	var gz_f := (wz - _grid_offset_z) / _grid_size

	# Get integer grid cell coords
	var gx := int(gx_f)
	var gz := int(gz_f)

	# Clamp to valid range
	gx = clampi(gx, 0, _grid_width - 2)
	gz = clampi(gz, 0, _grid_length - 2)

	# Get fractional part for interpolation
	var fx := gx_f - float(gx)
	var fz := gz_f - float(gz)
	fx = clampf(fx, 0.0, 1.0)
	fz = clampf(fz, 0.0, 1.0)

	# Sample 4 grid corners (explicit float type for type inference)
	var d00: float = _distance_grid[gz][gx]
	var d10: float = _distance_grid[gz][gx + 1]
	var d01: float = _distance_grid[gz + 1][gx]
	var d11: float = _distance_grid[gz + 1][gx + 1]

	# Validate all samples are valid
	if is_nan(d00) or is_nan(d10) or is_nan(d01) or is_nan(d11):
		print("PathGenerator: WARNING - NaN distance detected at grid[%d,%d]" % [gz, gx])
		return 999.0

	# Bilinear interpolation
	var d0 := lerpf(d00, d10, fx)
	var d1 := lerpf(d01, d11, fx)
	var result := lerpf(d0, d1, fz)

	# Validate result
	if is_nan(result) or is_inf(result):
		print("PathGenerator: WARNING - Invalid interpolated distance")
		return 999.0

	return result


# Returns true if the world position (wx, wz) is on or near a path.
func is_on_path(wx: float, wz: float) -> bool:
	var dist := get_distance_to_path(wx, wz)
	return dist < (PATH_WIDTH * 0.5 + 2.0)  # Same logic as before for tree placement


var _debug_lookup_count := 0  # Temporary debug counter


# Legacy function for backwards compatibility (redirects to is_on_path)
func is_near_path(wx: float, wz: float, radius: float) -> bool:
	return is_on_path(wx, wz)


func _build_distance_grid() -> void:
	# Calculate grid dimensions
	var half_x := _terrain.terrain_width * 0.5
	var half_z := _terrain.terrain_length * 0.5

	_grid_offset_x = -half_x
	_grid_offset_z = -half_z
	_grid_width = int(ceil(_terrain.terrain_width / _grid_size))
	_grid_length = int(ceil(_terrain.terrain_length / _grid_size))

	# Initialize grid with large distances (far from path)
	_distance_grid.clear()
	for _z in range(_grid_length):
		var row := []
		row.resize(_grid_width)
		row.fill(999.0)
		_distance_grid.append(row)

	# Rasterize each path segment into the grid (only updates nearby cells)
	_rasterize_segments(main_path)
	for branch in branches:
		_rasterize_segments(branch)


func _rasterize_segments(path: PackedVector3Array) -> void:
	# For each segment, only update grid cells within its bounding box
	var max_dist := PATH_WIDTH * 0.5 + PATH_FADE_DISTANCE + 1.0  # Max relevant distance

	for i in range(path.size() - 1):
		var p1 := Vector2(path[i].x, path[i].z)
		var p2 := Vector2(path[i + 1].x, path[i + 1].z)

		# Get bounding box for this segment
		var min_x := minf(p1.x, p2.x) - max_dist
		var max_x := maxf(p1.x, p2.x) + max_dist
		var min_z := minf(p1.y, p2.y) - max_dist
		var max_z := maxf(p1.y, p2.y) + max_dist

		# Convert to grid coordinates
		var gx_min := maxi(0, int((min_x - _grid_offset_x) / _grid_size))
		var gx_max := mini(_grid_width - 1, int((max_x - _grid_offset_x) / _grid_size))
		var gz_min := maxi(0, int((min_z - _grid_offset_z) / _grid_size))
		var gz_max := mini(_grid_length - 1, int((max_z - _grid_offset_z) / _grid_size))

		# Update only cells in this segment's bounding box
		for gz in range(gz_min, gz_max + 1):
			for gx in range(gx_min, gx_max + 1):
				# Get world position of cell center
				var cell_x := _grid_offset_x + (gx + 0.5) * _grid_size
				var cell_z := _grid_offset_z + (gz + 0.5) * _grid_size
				var cell_pos := Vector2(cell_x, cell_z)

				# Find distance to this segment
				var closest := _closest_point_on_segment(cell_pos, p1, p2)
				var dist := cell_pos.distance_to(closest)

				# Update if this is closer than previous value
				if dist < _distance_grid[gz][gx]:
					_distance_grid[gz][gx] = dist


# ── Private ──────────────────────────────────────────────────────────────────

func _generate_main_path() -> void:
	main_path.clear()
	var half_x := _terrain.terrain_width  * 0.5
	var half_z := _terrain.terrain_length * 0.5
	var start_z := -half_z * 0.9
	var end_z   :=  half_z * 0.9
	var cur := Vector2(0.0, start_z)

	# Continuous curving - bias accumulates to create actual curves
	var curve_direction := 1.0 if randf() > 0.5 else -1.0  # Start curving left or right
	var curve_strength := randf_range(0.02, 0.035)  # How fast the curve accumulates
	var current_lateral_velocity := 0.0  # Current sideways drift
	var steps_in_curve := 0
	var curve_duration := randi_range(30, 50)  # Curves switch every 45-75m (avg ~60m)

	while cur.y < end_z:
		var h := _terrain.get_height(cur.x, cur.y)
		main_path.append(Vector3(cur.x, h + PATH_OFFSET, cur.y))

		# Accumulate lateral velocity to create smooth curves
		current_lateral_velocity += curve_direction * curve_strength
		# Clamp to prevent too-sharp curves
		current_lateral_velocity = clampf(current_lateral_velocity, -0.8, 0.8)

		# Change curve direction periodically
		steps_in_curve += 1
		if steps_in_curve >= curve_duration:
			curve_direction *= -1.0  # Reverse curve direction
			curve_strength = randf_range(0.02, 0.035)  # New curve strength
			curve_duration = randi_range(30, 50)  # Curves switch every 45-75m
			steps_in_curve = 0
			# Gradually reduce velocity when switching to ease the transition
			current_lateral_velocity *= 0.5

		# Apply continuous curve plus small random variation
		cur.x += randf_range(-MAX_LATERAL, MAX_LATERAL) + current_lateral_velocity
		cur.x  = clampf(cur.x, -half_x * 0.5, half_x * 0.5)
		cur.y += STEP_LENGTH


func _generate_branches() -> void:
	var last_branch_pos := -999.0  # Distance along path where last branch spawned
	var distance_along_path := 0.0

	for i in range(3, main_path.size() - 3):
		# Calculate cumulative distance along main path
		if i > 3:
			distance_along_path += main_path[i].distance_to(main_path[i - 1])

		# Check if we're far enough from the last branch
		var distance_since_last_branch := distance_along_path - last_branch_pos

		if distance_since_last_branch >= BRANCH_MIN_SPACING and randf() < BRANCH_CHANCE:
			var branch := _walk_branch(main_path[i])

			# Calculate actual branch length
			var branch_length := _calculate_path_length(branch)

			# Only keep branches that are long enough
			if branch_length >= BRANCH_MIN_LENGTH:
				branches.append(branch)
				last_branch_pos = distance_along_path


func _calculate_path_length(path: PackedVector3Array) -> float:
	if path.size() < 2:
		return 0.0

	var total_length := 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])

	return total_length


func _walk_branch(origin: Vector3) -> PackedVector3Array:
	var branch: PackedVector3Array = []
	branch.append(origin)

	var half_x := _terrain.terrain_width  * 0.5
	var half_z := _terrain.terrain_length * 0.5
	var angle  := randf_range(PI * 0.15, PI * 0.85)
	if randf() < 0.5:
		angle = -angle

	var cur   := Vector2(origin.x, origin.z)
	var steps := randi_range(BRANCH_MIN, BRANCH_MAX)

	for _i in range(steps):
		# Smaller angle variation to prevent branches looping back
		angle  += randf_range(-0.12, 0.12)
		cur.x  += sin(angle) * STEP_LENGTH
		cur.y  += cos(angle) * STEP_LENGTH * 0.6

		if absf(cur.x) > half_x * 0.88 or absf(cur.y) > half_z * 0.88:
			break

		var h := _terrain.get_height(cur.x, cur.y)
		branch.append(Vector3(cur.x, h + PATH_OFFSET, cur.y))

	return branch


func _cache_2d_points() -> void:
	_all_points_2d.clear()
	for pt in main_path:
		_all_points_2d.append(Vector2(pt.x, pt.z))
	for branch in branches:
		for pt in branch:
			_all_points_2d.append(Vector2(pt.x, pt.z))


func _closest_point_on_segment(pos: Vector2, p1: Vector2, p2: Vector2) -> Vector2:
	var line := p2 - p1
	var len2 := line.length_squared()

	if len2 < 0.0001:  # Degenerate segment
		return p1

	var t := clampf((pos - p1).dot(line) / len2, 0.0, 1.0)
	return p1 + line * t


func _build_path_mesh(points: PackedVector3Array, is_main: bool) -> void:
	if points.size() < 2:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := PATH_WIDTH * 0.5
	if not is_main:
		half_w *= 0.65

	for i in range(points.size() - 1):
		var p0  := points[i]
		var p1  := points[i + 1]
		var fwd := (p1 - p0)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := Vector3.UP.cross(fwd).normalized()

		var v00 := p0 - right * half_w
		var v10 := p0 + right * half_w
		var v01 := p1 - right * half_w
		var v11 := p1 + right * half_w

		var n := Vector3.UP

		st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v00)
		st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v10)
		st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v01)

		st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v10)
		st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v11)
		st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v01)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.26, 0.18)
	mat.roughness    = 1.0
	mat.metallic     = 0.0
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MainPathMesh" if is_main else "BranchMesh"
	mesh_inst.material_override = mat
	mesh_inst.mesh = st.commit()
	add_child(mesh_inst)
