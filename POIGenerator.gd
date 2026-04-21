class_name POIGenerator
extends Node3D

## Generates Points of Interest (POIs) along the main path
## Randomly spawns campsites (1-3) and cabins (1-3) at intervals

@export var min_poi_spacing: float = 150.0  # Minimum distance between POIs
@export var max_poi_spacing: float = 300.0  # Maximum distance between POIs
@export var path_offset_distance: float = 6.0  # Distance from path center to POI
@export var poi_clearance_radius: float = 8.0  # Radius to clear trees around POI

var terrain: TerrainGenerator = null
var path: PathGenerator = null
var poi_positions: Array[Vector3] = []
var poi_scenes: Array[PackedScene] = []

func initialize(p_terrain: TerrainGenerator, p_path: PathGenerator) -> void:
	terrain = p_terrain
	path = p_path

	# Load all POI scenes
	var poi_paths = [
		"res://campsite_1.tscn",
		"res://campsite_2.tscn",
		"res://campsite_3.tscn",
		"res://cabin_1.tscn",
		"res://cabin_2.tscn",
		"res://cabin_3.tscn"
	]

	for poi_path in poi_paths:
		var scene = load(poi_path)
		if scene:
			poi_scenes.append(scene)
			print("POIGenerator: loaded %s" % poi_path)
		else:
			push_warning("POIGenerator: failed to load %s" % poi_path)

	if poi_scenes.is_empty():
		push_error("POIGenerator: no POI scenes loaded!")
	else:
		print("POIGenerator: initialized with %d POI scenes" % poi_scenes.size())

func generate() -> void:
	if not terrain or not path:
		print("POIGenerator: ERROR - missing terrain or path reference")
		return

	var main_path = path.main_path
	if main_path.is_empty():
		print("POIGenerator: ERROR - main path is empty")
		return

	print("POIGenerator: generating POIs along path...")

	# Walk along the path and place POIs at intervals
	var accumulated_distance: float = 0.0
	var next_poi_distance: float = randf_range(min_poi_spacing, max_poi_spacing)

	for i in range(main_path.size() - 1):
		var segment_start = main_path[i]
		var segment_end = main_path[i + 1]
		var segment_length = segment_start.distance_to(segment_end)

		accumulated_distance += segment_length

		# Check if we should place a POI
		if accumulated_distance >= next_poi_distance:
			# Use the end point of this segment
			var poi_pos = segment_end
			spawn_platform(poi_pos, segment_start, segment_end)

			# Reset for next POI
			accumulated_distance = 0.0
			next_poi_distance = randf_range(min_poi_spacing, max_poi_spacing)

	print("POIGenerator: spawned %d POIs" % poi_positions.size())


func is_near_poi(world_x: float, world_z: float) -> bool:
	# Check if a position is within clearance radius of any POI
	var check_pos := Vector3(world_x, 0, world_z)
	for poi_pos in poi_positions:
		var poi_2d := Vector3(poi_pos.x, 0, poi_pos.z)
		if check_pos.distance_to(poi_2d) < poi_clearance_radius:
			return true
	return false

func spawn_platform(path_position: Vector3, segment_start: Vector3, segment_end: Vector3) -> void:
	print("=== POIGenerator: spawn_platform() called ===")

	if poi_scenes.is_empty():
		print("POIGenerator: no POI scenes loaded, skipping")
		return

	# Randomly select a POI scene
	var selected_scene = poi_scenes[randi() % poi_scenes.size()]
	print("POIGenerator: POI scene selected")

	# Calculate path direction
	var path_direction = (segment_end - segment_start).normalized()
	print("POIGenerator: path_direction = %v" % path_direction)

	# Get perpendicular vector (rotate 90 degrees around Y axis)
	var perpendicular = Vector3(-path_direction.z, 0, path_direction.x).normalized()

	# Randomly choose left or right side
	var side_multiplier = 1.0 if randf() > 0.5 else -1.0
	perpendicular = perpendicular * side_multiplier

	# Offset the position to the side of the path
	var spawn_pos = path_position + (perpendicular * path_offset_distance)

	# Check if position is on a branch path - if so, skip this POI
	if path.is_on_path(spawn_pos.x, spawn_pos.z):
		print("POIGenerator: skipping campsite at %v (would spawn on path branch)" % spawn_pos)
		return

	# Get terrain height
	spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)

	# Instance the POI scene
	print("POIGenerator: Instantiating POI scene...")
	var poi = selected_scene.instantiate()
	print("POIGenerator: POI instantiated, type: %s" % poi.get_class())
	poi.global_position = spawn_pos
	print("POIGenerator: POI position set to %v" % spawn_pos)

	# Make POI face the path
	# Front of POI is +Z axis, we want it to point toward the path
	# The perpendicular vector points to the side (away from path center)
	# To face the path, we need to rotate to point BACK toward the path center
	# Which means we want to face in the OPPOSITE direction of perpendicular
	var toward_path = -perpendicular

	# In Godot, rotation.y with +Z forward:
	# 0 = facing +Z, PI/2 = facing +X, PI = facing -Z, -PI/2 = facing -X
	# atan2(x, z) gives the angle to rotate +Z to point in direction (x, z)
	var angle_to_path = atan2(toward_path.x, toward_path.z)
	poi.rotation.y = angle_to_path

	print("  Perpendicular: %v, Toward path: %v" % [perpendicular, toward_path])
	print("  POI rotation: %.2f radians (%.1f degrees)" % [angle_to_path, rad_to_deg(angle_to_path)])

	# Add to scene
	print("POIGenerator: Adding POI to scene...")
	add_child(poi)
	print("POIGenerator: POI added successfully")

	# Randomize tent texture hue (for campsites)
	print("POIGenerator: Calling randomize_tent_hue()...")
	randomize_tent_hue(poi)
	print("POIGenerator: randomize_tent_hue() completed")

	poi_positions.append(spawn_pos)

	# Mark this area in the path's exclusion grid to prevent tree spawning
	print("POIGenerator: Marking exclusion area...")
	mark_exclusion_area(spawn_pos)

	print("=== POIGenerator: POI SPAWN COMPLETE at %v ===" % spawn_pos)
	print("")

func randomize_tent_hue(poi: Node3D) -> void:
	# Find all MeshInstance3D nodes in the POI (recursively)
	var meshes = find_all_meshes(poi)

	print("  Found %d meshes in POI" % meshes.size())

	# Randomize hue for nodes that have "tent" in their name
	for mesh in meshes:
		print("  - Checking mesh: %s" % mesh.name)
		if "tent" in mesh.name.to_lower():
			print("    Found tent mesh: %s" % mesh.name)

			# Try to get material from material_override first, then surface
			var material = mesh.material_override
			if not material:
				material = mesh.get_surface_override_material(0)
			if not material:
				material = mesh.get_active_material(0)

			if material:
				print("    Material found: %s" % material.get_class())
				# Duplicate material so each tent is unique
				material = material.duplicate()
				mesh.material_override = material

				# Randomize hue
				if material is StandardMaterial3D:
					var base_color = material.albedo_color
					print("    Base color: %s" % base_color)

					# Generate completely random vibrant color
					var random_hue = randf()  # 0.0 to 1.0
					var saturation = 0.8  # High saturation for vibrant colors
					var value = 0.9  # Bright

					var new_color = hsv_to_rgb(Vector3(random_hue, saturation, value))

					material.albedo_color = new_color
					print("    New color: %s (hue: %.2f, sat: %.2f, val: %.2f)" % [new_color, random_hue, saturation, value])
				else:
					print("    Material is not StandardMaterial3D: %s" % material.get_class())
			else:
				print("    No material found on tent mesh")

func replace_campfire_with_interactive(poi: Node3D) -> void:
	# Find the campfire node in the POI scene
	var static_campfire = find_campfire_node(poi)

	if not static_campfire:
		print("  No campfire found in POI to replace")
		return

	print("  Found static campfire: %s" % static_campfire.name)

	# Get the campfire's transform before removing it
	var campfire_transform = static_campfire.global_transform
	var campfire_position = static_campfire.global_position
	var campfire_rotation = static_campfire.global_rotation
	var campfire_scale = static_campfire.scale

	# Load the interactive campfire scene
	var interactive_campfire_scene = load("res://campfire.tscn")
	if not interactive_campfire_scene:
		print("  ERROR: Could not load campfire.tscn")
		return

	# Remove the static campfire
	var campfire_parent = static_campfire.get_parent()
	static_campfire.queue_free()

	# Instance the interactive campfire
	var interactive_campfire = interactive_campfire_scene.instantiate()

	# Add to the same parent
	campfire_parent.add_child(interactive_campfire)

	# Restore transform (use global transform to maintain world position)
	interactive_campfire.global_position = campfire_position
	interactive_campfire.global_rotation = campfire_rotation
	interactive_campfire.scale = campfire_scale

	# Check if script is attached
	var campfire_script = interactive_campfire.get_script()
	print("  Interactive campfire script: %s" % (campfire_script.resource_path if campfire_script else "NO SCRIPT ATTACHED!"))
	print("  Interactive campfire has _process: %s" % interactive_campfire.has_method("_process"))
	print("  Interactive campfire has check_player_interaction: %s" % interactive_campfire.has_method("check_player_interaction"))

	print("  Replaced static campfire with interactive campfire at %v (scale: %v)" % [campfire_position, campfire_scale])

func find_campfire_node(node: Node) -> Node3D:
	# Recursively search for a node with "campfire" in its name
	if "campfire" in node.name.to_lower():
		if node is Node3D:
			return node

	for child in node.get_children():
		var result = find_campfire_node(child)
		if result:
			return result

	return null

func find_all_meshes(node: Node) -> Array:
	var meshes = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(find_all_meshes(child))
	return meshes

func rgb_to_hsv(color: Color) -> Vector3:
	var r = color.r
	var g = color.g
	var b = color.b

	var max_c = max(r, max(g, b))
	var min_c = min(r, min(g, b))
	var delta = max_c - min_c

	var h = 0.0
	var s = 0.0 if max_c == 0.0 else delta / max_c
	var v = max_c

	if delta > 0.0:
		if max_c == r:
			h = fmod((g - b) / delta, 6.0)
		elif max_c == g:
			h = (b - r) / delta + 2.0
		else:
			h = (r - g) / delta + 4.0
		h /= 6.0
		if h < 0.0:
			h += 1.0

	return Vector3(h, s, v)

func hsv_to_rgb(hsv: Vector3) -> Color:
	var h = hsv.x * 6.0
	var s = hsv.y
	var v = hsv.z

	var i = int(floor(h))
	var f = h - i
	var p = v * (1.0 - s)
	var q = v * (1.0 - f * s)
	var t = v * (1.0 - (1.0 - f) * s)

	var r = 0.0
	var g = 0.0
	var b = 0.0

	match i % 6:
		0: r = v; g = t; b = p
		1: r = q; g = v; b = p
		2: r = p; g = v; b = t
		3: r = p; g = q; b = v
		4: r = t; g = p; b = v
		5: r = v; g = p; b = q

	return Color(r, g, b, 1.0)

func mark_exclusion_area(center: Vector3) -> void:
	# Mark a circular area in the path's exclusion grid to prevent trees
	if not path or not path.has_method("_rasterize_circle_to_grid"):
		# Fallback: mark grid cells manually
		if path and "_exclusion_grid" in path:
			var grid_size = path._grid_size if "_grid_size" in path else 2.0
			var grid_offset_x = path._grid_offset_x if "_grid_offset_x" in path else 0.0
			var grid_offset_z = path._grid_offset_z if "_grid_offset_z" in path else 0.0
			var grid_width = path._grid_width if "_grid_width" in path else 0
			var grid_length = path._grid_length if "_grid_length" in path else 0

			# Mark all cells within clearance radius
			var cells_to_check = int(ceil(poi_clearance_radius / grid_size)) + 1

			for dz in range(-cells_to_check, cells_to_check + 1):
				for dx in range(-cells_to_check, cells_to_check + 1):
					var wx = center.x + dx * grid_size
					var wz = center.z + dz * grid_size

					# Check if within clearance radius
					if Vector2(wx, wz).distance_to(Vector2(center.x, center.z)) <= poi_clearance_radius:
						# Convert to grid coords
						var gx = int((wx - grid_offset_x) / grid_size)
						var gz = int((wz - grid_offset_z) / grid_size)

						# Check bounds and mark
						if gx >= 0 and gx < grid_width and gz >= 0 and gz < grid_length:
							path._exclusion_grid[gz][gx] = true

			print("POIGenerator: marked exclusion area of radius %.1fm around POI" % poi_clearance_radius)
