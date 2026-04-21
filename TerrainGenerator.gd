class_name TerrainGenerator
extends Node3D

## Procedural terrain using FastNoiseLite.
## Builds a long rectangular corridor mesh with analytical normals and trimesh collision.

const RES_W: int = 45          # Vertex columns (X axis) - optimized for load time
const RES_L: int = 350         # Vertex rows    (Z axis) - optimized for load time
const HEIGHT_SCALE: float = 5.0

@export var grass_texture_path: String = "res://Grass_20-256x256.png"  # Path to grass texture (e.g. "res://textures/grass.png")
@export var texture_tile_scale: float = 1  # How many times the texture tiles (smaller = more tiles)

@export_group("Path Settings")
@export var path_texture_path: String = "res://assets/Dirt_10-256x256.png"  # Dirt/path texture
@export var path_blend_sharpness: float = 0.9  # How sharp the path edges are (0.0 - 1.0)

@export_group("Noise Settings")
@export var use_procedural_noise: bool = true  # Add procedural noise for variety
@export var noise_tile_scale: float = 0.03  # Noise tiling (smaller = larger patches)
@export var noise_blend_strength: float = 0.7  # How much variation (0.0 - 1.0)
@export var noise_frequency: float = 0.03  # Noise detail level
@export var noise_octaves: int = 4  # Noise complexity (more = more detail)

var terrain_width: float       # X extent in world units
var terrain_length: float      # Z extent in world units

var _noise: FastNoiseLite
var _height_grid: PackedFloat32Array  # indexed [zi * (RES_W+1) + xi]
var _path_generator: PathGenerator = null  # Reference to path for texture blending
var _terrain_material: ShaderMaterial = null  # Store reference to update camera position


func setup(width: float, length: float, p_seed: int) -> void:
	terrain_width  = width
	terrain_length = length

	_noise = FastNoiseLite.new()
	_noise.seed = p_seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.008
	_noise.fractal_octaves = 5
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5

	_precompute_heights()


func set_path_generator(path_gen: PathGenerator) -> void:
	_path_generator = path_gen

	# Remove old mesh if it exists
	for child in get_children():
		if child.name == "TerrainMesh":
			child.queue_free()

	_build_visual_mesh()
	_build_collision()
	await get_tree().process_frame  # Wait for physics to be ready
	_build_navigation()
	print("TerrainGenerator: rebuilt terrain with path blending (%dx%d)" % [RES_W, RES_L])


func _process(_delta: float) -> void:
	# Update camera position in shader for distance-based LOD
	if _terrain_material:
		var camera = get_viewport().get_camera_3d()
		if camera:
			_terrain_material.set_shader_parameter("camera_position", camera.global_position)


# Returns the terrain height at any world XZ position (samples noise directly).
func get_height(world_x: float, world_z: float) -> float:
	return _noise.get_noise_2d(world_x, world_z) * HEIGHT_SCALE


# ── Private ──────────────────────────────────────────────────────────────────

func _precompute_heights() -> void:
	var map_w := RES_W + 1
	var map_l := RES_L + 1
	var step_x := terrain_width  / RES_W
	var step_z := terrain_length / RES_L
	var half_x := terrain_width  * 0.5
	var half_z := terrain_length * 0.5

	_height_grid = PackedFloat32Array()
	_height_grid.resize(map_w * map_l)

	for zi in range(map_l):
		for xi in range(map_w):
			var wx := xi * step_x - half_x
			var wz := zi * step_z - half_z
			_height_grid[zi * map_w + xi] = _noise.get_noise_2d(wx, wz) * HEIGHT_SCALE


func _gh(xi: int, zi: int) -> float:
	xi = clampi(xi, 0, RES_W)
	zi = clampi(zi, 0, RES_L)
	return _height_grid[zi * (RES_W + 1) + xi]


# Analytical normal from finite differences on the cached height grid.
func _gn(xi: int, zi: int) -> Vector3:
	var scale_x := float(RES_W) / terrain_width
	var scale_z := float(RES_L) / terrain_length
	var dh_dx := (_gh(xi + 1, zi) - _gh(xi - 1, zi)) * scale_x * 0.5
	var dh_dz := (_gh(xi, zi + 1) - _gh(xi, zi - 1)) * scale_z * 0.5
	return Vector3(-dh_dx, 1.0, -dh_dz).normalized()


func _build_visual_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step_x  := terrain_width  / RES_W
	var step_z  := terrain_length / RES_L
	var half_x  := terrain_width  * 0.5
	var half_z  := terrain_length * 0.5
	var uv_scale := texture_tile_scale
	var noise_uv_scale := noise_tile_scale

	for zi in range(RES_L):
		for xi in range(RES_W):
			var x0 := xi * step_x - half_x
			var x1 := x0 + step_x
			var z0 := zi * step_z - half_z
			var z1 := z0 + step_z

			var h00 := _gh(xi,     zi    )
			var h10 := _gh(xi + 1, zi    )
			var h01 := _gh(xi,     zi + 1)
			var h11 := _gh(xi + 1, zi + 1)

			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x1, h10, z0)
			var v01 := Vector3(x0, h01, z1)
			var v11 := Vector3(x1, h11, z1)

			# Check if vertices are on path (store in vertex color red channel)
			# Grid lookup now uses bilinear interpolation for smooth blending
			var c00 := clampf(_get_path_blend(x0, z0), 0.0, 1.0)
			var c10 := clampf(_get_path_blend(x1, z0), 0.0, 1.0)
			var c01 := clampf(_get_path_blend(x0, z1), 0.0, 1.0)
			var c11 := clampf(_get_path_blend(x1, z1), 0.0, 1.0)

			# Triangle 1
			st.set_normal(_gn(xi,     zi    ))
			st.set_uv(Vector2(x0, z0) * uv_scale)
			st.set_uv2(Vector2(x0, z0) * noise_uv_scale)
			st.set_color(Color(c00, 0, 0, 1))
			st.add_vertex(v00)

			st.set_normal(_gn(xi + 1, zi    ))
			st.set_uv(Vector2(x1, z0) * uv_scale)
			st.set_uv2(Vector2(x1, z0) * noise_uv_scale)
			st.set_color(Color(c10, 0, 0, 1))
			st.add_vertex(v10)

			st.set_normal(_gn(xi,     zi + 1))
			st.set_uv(Vector2(x0, z1) * uv_scale)
			st.set_uv2(Vector2(x0, z1) * noise_uv_scale)
			st.set_color(Color(c01, 0, 0, 1))
			st.add_vertex(v01)

			# Triangle 2
			st.set_normal(_gn(xi + 1, zi    ))
			st.set_uv(Vector2(x1, z0) * uv_scale)
			st.set_uv2(Vector2(x1, z0) * noise_uv_scale)
			st.set_color(Color(c10, 0, 0, 1))
			st.add_vertex(v10)

			st.set_normal(_gn(xi + 1, zi + 1))
			st.set_uv(Vector2(x1, z1) * uv_scale)
			st.set_uv2(Vector2(x1, z1) * noise_uv_scale)
			st.set_color(Color(c11, 0, 0, 1))
			st.add_vertex(v11)

			st.set_normal(_gn(xi,     zi + 1))
			st.set_uv(Vector2(x0, z1) * uv_scale)
			st.set_uv2(Vector2(x0, z1) * noise_uv_scale)
			st.set_color(Color(c01, 0, 0, 1))
			st.add_vertex(v01)

	var mat: Material = null

	# Generate procedural noise texture if enabled
	var noise_tex: Texture2D = null
	if use_procedural_noise:
		# Use the NoiseTexture2D directly - Godot handles it efficiently
		noise_tex = _generate_noise_texture()
		print("Terrain: Generated procedural noise texture")
	else:
		# Create a simple white 1x1 texture as placeholder (no noise variation)
		var img = Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		noise_tex = ImageTexture.create_from_image(img)
		print("Terrain: Using plain white noise texture (no variation)")

	# Use shader if we have both grass texture and noise
	if noise_tex and not grass_texture_path.is_empty():
		var grass_tex = load(grass_texture_path)
		var path_tex = load(path_texture_path) if not path_texture_path.is_empty() else null

		if grass_tex:
			var shader_mat = ShaderMaterial.new()
			shader_mat.shader = load("res://terrain_grass.gdshader")
			shader_mat.set_shader_parameter("grass_texture", grass_tex)
			shader_mat.set_shader_parameter("noise_texture", noise_tex)
			shader_mat.set_shader_parameter("noise_strength", noise_blend_strength)
			shader_mat.set_shader_parameter("roughness", 0.95)

			# Set LOD distances: 0-5m full quality, 5-15m medium LOD, 15m+ high LOD
			shader_mat.set_shader_parameter("lod_near_distance", 5.0)
			shader_mat.set_shader_parameter("lod_far_distance", 15.0)
			shader_mat.set_shader_parameter("camera_position", Vector3.ZERO)

			# Set path texture if available
			if path_tex:
				shader_mat.set_shader_parameter("path_texture", path_tex)
				shader_mat.set_shader_parameter("path_blend_sharpness", path_blend_sharpness)
				print("Terrain: Using shader with grass + noise + path textures")
			else:
				# Use grass texture as fallback for path
				shader_mat.set_shader_parameter("path_texture", grass_tex)
				print("Terrain: Using shader with grass + procedural noise")

			# Store reference to update camera position in _process
			_terrain_material = shader_mat
			mat = shader_mat
		else:
			push_warning("Terrain: Failed to load grass texture")

	# Fallback to standard material
	if mat == null:
		var std_mat := StandardMaterial3D.new()
		std_mat.roughness = 0.95
		std_mat.metallic = 0.0

		if not grass_texture_path.is_empty():
			var texture = load(grass_texture_path)
			if texture:
				std_mat.albedo_texture = texture
				std_mat.albedo_color = Color.WHITE
				std_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				print("Terrain: Applied grass texture (no noise)")
			else:
				std_mat.albedo_color = Color(0.14, 0.22, 0.09)
		else:
			std_mat.albedo_color = Color(0.14, 0.22, 0.09)

		mat = std_mat

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "TerrainMesh"
	mesh_inst.material_override = mat
	mesh_inst.mesh = st.commit()
	add_child(mesh_inst)


func _build_collision() -> void:
	var step_x := terrain_width  / RES_W
	var step_z := terrain_length / RES_L
	var half_x := terrain_width  * 0.5
	var half_z := terrain_length * 0.5
	var faces  := PackedVector3Array()
	faces.resize(RES_W * RES_L * 6)

	var idx := 0
	for zi in range(RES_L):
		for xi in range(RES_W):
			var x0 := xi * step_x - half_x
			var x1 := x0 + step_x
			var z0 := zi * step_z - half_z
			var z1 := z0 + step_z

			var h00 := _gh(xi,     zi    )
			var h10 := _gh(xi + 1, zi    )
			var h01 := _gh(xi,     zi + 1)
			var h11 := _gh(xi + 1, zi + 1)

			faces[idx    ] = Vector3(x0, h00, z0)
			faces[idx + 1] = Vector3(x1, h10, z0)
			faces[idx + 2] = Vector3(x0, h01, z1)
			faces[idx + 3] = Vector3(x1, h10, z0)
			faces[idx + 4] = Vector3(x1, h11, z1)
			faces[idx + 5] = Vector3(x0, h01, z1)
			idx += 6

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	var col := CollisionShape3D.new()
	col.shape = shape

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.add_child(col)
	add_child(body)


func _build_navigation() -> void:
	print("TerrainGenerator: building navigation mesh...")

	# Create NavigationRegion3D
	var nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"

	# Create NavigationMesh
	var nav_mesh = NavigationMesh.new()

	# Configure navigation mesh parameters
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.region_min_size = 2.0
	nav_mesh.region_merge_size = 20.0
	nav_mesh.edge_max_length = 12.0
	nav_mesh.edge_max_error = 1.3
	nav_mesh.vertices_per_polygon = 6.0
	nav_mesh.detail_sample_distance = 6.0
	nav_mesh.detail_sample_max_error = 1.0

	nav_region.navigation_mesh = nav_mesh
	add_child(nav_region)

	# Note: The navigation mesh will bake automatically when the scene is ready
	# Godot will use the terrain mesh for baking
	print("TerrainGenerator: navigation mesh setup complete (will bake automatically)")


func _get_path_blend(wx: float, wz: float) -> float:
	# Returns 0.0 for grass, 1.0 for path, with smooth gradient fade
	if not _path_generator:
		return 0.0

	# Get distance to nearest path segment from precomputed grid
	var dist := _path_generator.get_distance_to_path(wx, wz)

	# Validate distance
	if is_nan(dist) or is_inf(dist):
		return 0.0

	# Path geometry constants from PathGenerator
	var path_half_width := _path_generator.PATH_WIDTH * 0.5
	var fade_distance := _path_generator.PATH_FADE_DISTANCE

	# Calculate fade region
	var fade_start := path_half_width - fade_distance
	var fade_end := path_half_width

	# Return blend value based on distance
	if dist <= fade_start:
		return 1.0  # Full path (dirt)
	elif dist >= fade_end:
		return 0.0  # Full grass
	else:
		# Smooth gradient in fade region
		var t := (dist - fade_start) / fade_distance
		return 1.0 - t  # Linear fade from 1.0 to 0.0


func _generate_noise_texture() -> NoiseTexture2D:
	# Create a new noise generator with random seed
	var noise = FastNoiseLite.new()
	noise.seed = randi()  # Random seed each time for variety
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_frequency
	noise.fractal_octaves = noise_octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

	# Create noise texture
	var noise_texture = NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.width = 512
	noise_texture.height = 512
	noise_texture.seamless = true  # Make it tileable
	noise_texture.normalize = true  # Normalize to 0-1 range

	return noise_texture
