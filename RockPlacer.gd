class_name RockPlacer
extends Node3D

## Places rock models throughout the forest.

const ROCK_COUNT: int = 200
const PATH_CLEAR_RADIUS: float = 6.0  # Rocks should be further from path
const POI_CLEAR_RADIUS: float = 8.0  # Avoid POIs
const CHUNK_SIZE: float = 100.0  # Size of each spatial chunk for culling
const CULL_DISTANCE: float = 200.0  # Cull chunks beyond this distance

var _terrain: TerrainGenerator
var _path: PathGenerator
var _poi_generator: POIGenerator = null
var _danger_manager = null
var _rock_meshes: Array[Mesh] = []
var _rock_collision_shapes: Array[Shape3D] = []
var _current_cull_distance: float = CULL_DISTANCE


func _ready() -> void:
	add_to_group("rock_placer")


func place(terrain: TerrainGenerator, path: PathGenerator, poi_generator: POIGenerator = null, danger_manager = null) -> void:
	_terrain = terrain
	_path = path
	_poi_generator = poi_generator
	_danger_manager = danger_manager
	print("RockPlacer: place() called")

	# Clear any previous meshes
	_rock_meshes.clear()

	# ── Load rock meshes from rock_models.tscn ──────────────────────────────
	var rocks_scene = load("res://rock_models.tscn")
	if not rocks_scene:
		push_error("RockPlacer: failed to load res://rock_models.tscn")
		return

	var rocks_root = rocks_scene.instantiate()

	# Rock node names in the scene
	var rock_names = [
		"stone_1",
		"stone_2",
		"stone_3",
		"stone_4",
		"stone_5"
	]

	for rock_name in rock_names:
		var rock_node = rocks_root.get_node_or_null(rock_name)
		if rock_node:
			var mesh = _extract_mesh_from_node(rock_node)
			if mesh:
				_rock_meshes.append(mesh)
				print("RockPlacer: loaded mesh from %s" % rock_name)
			else:
				push_warning("RockPlacer: failed to extract mesh from %s" % rock_name)

			# Extract collision shape from the rock node
			var collision_shape = _extract_collision_shape(rock_node)
			_rock_collision_shapes.append(collision_shape)
		else:
			push_warning("RockPlacer: rock node '%s' not found in rock_models.tscn" % rock_name)

	# Clean up the temporary instance
	rocks_root.queue_free()

	if _rock_meshes.is_empty():
		push_error("RockPlacer: no rock meshes loaded")
		return

	print("RockPlacer: loaded %d rock variants" % _rock_meshes.size())

	# ── Calculate all rock transforms ──────────────────────────────────────
	var half_x := terrain.terrain_width * 0.5 * 0.93
	var half_z := terrain.terrain_length * 0.5 * 0.93
	var skipped := 0

	# Calculate grid spacing for target rock count
	var area := (half_x * 2.0) * (half_z * 2.0)
	var spacing := sqrt(area / ROCK_COUNT)
	var jitter := spacing * 0.4  # 40% randomness

	print("RockPlacer: grid spacing %.1f, jitter %.1f" % [spacing, jitter])

	# Collect transforms organized by spatial chunks for culling
	var chunks_per_variant: Array = []
	for i in range(_rock_meshes.size()):
		chunks_per_variant.append({})

	# Collect collision data
	var collision_data: Array = []

	# Calculate all valid rock positions and their transforms
	var z := -half_z
	while z < half_z:
		var x := -half_x
		while x < half_x:
			# Add random jitter to grid position
			var rx := x + randf_range(-jitter, jitter)
			var rz := z + randf_range(-jitter, jitter)

			# Keep within bounds
			rx = clampf(rx, -half_x, half_x)
			rz = clampf(rz, -half_z, half_z)

			# Skip if too close to path (6.0m clearance)
			var dist_to_path = _path.get_distance_to_path(rx, rz)
			if dist_to_path < PATH_CLEAR_RADIUS:
				skipped += 1
				x += spacing
				continue

			# Skip if near POI
			if _poi_generator and _poi_generator.is_near_poi(rx, rz):
				skipped += 1
				x += spacing
				continue

			var ry := _terrain.get_height(rx, rz)

			# Get danger level at this position to scale rock
			var danger_level := 1.0
			if _danger_manager and _danger_manager.has_method("get_danger_level"):
				danger_level = _danger_manager.get_danger_level(Vector3(rx, ry, rz))

			# Calculate rock scale based on danger (rocks grow 1.0x → 2.0x)
			var rock_scale := 1.0 + (danger_level - 1.0) * 0.5

			# Calculate which spatial chunk this rock belongs to
			var chunk_x := int(floor(rx / CHUNK_SIZE))
			var chunk_z := int(floor(rz / CHUNK_SIZE))
			var chunk_key := Vector2i(chunk_x, chunk_z)

			# Create transform for this rock (relative to chunk origin)
			var chunk_origin := Vector3(chunk_x * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0, chunk_z * CHUNK_SIZE + CHUNK_SIZE * 0.5)
			var transform := Transform3D()
			transform = transform.scaled(Vector3(rock_scale, rock_scale, rock_scale))
			transform = transform.rotated(Vector3.UP, randf_range(0.0, TAU))
			transform.origin = Vector3(rx, ry, rz) - chunk_origin  # Relative to chunk

			# Assign to random variant and chunk
			var variant_idx := randi() % _rock_meshes.size()
			if not chunks_per_variant[variant_idx].has(chunk_key):
				chunks_per_variant[variant_idx][chunk_key] = []
			chunks_per_variant[variant_idx][chunk_key].append(transform)

			# Store collision data (world position, scale, variant)
			collision_data.append({
				"position": Vector3(rx, ry, rz),
				"scale": Vector3(rock_scale, rock_scale, rock_scale),
				"variant_idx": variant_idx
			})

			x += spacing
		z += spacing

	# ── Create MultiMeshInstances (one per chunk per variant) ──────────────
	var total_placed := 0
	var total_chunks := 0

	for variant_idx in range(_rock_meshes.size()):
		var chunks: Dictionary = chunks_per_variant[variant_idx]
		if chunks.is_empty():
			continue

		var variant_total := 0

		# Create one MultiMeshInstance per chunk
		for chunk_key in chunks:
			var transforms: Array = chunks[chunk_key]
			if transforms.is_empty():
				continue

			# Create MultiMesh for this chunk
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _rock_meshes[variant_idx]
			multimesh.instance_count = transforms.size()

			# Set each instance transform
			for j in range(transforms.size()):
				multimesh.set_instance_transform(j, transforms[j])

			# Create chunk node positioned at chunk center
			var chunk_node := Node3D.new()
			chunk_node.name = "Chunk_%d_%d" % [chunk_key.x, chunk_key.y]
			var chunk_origin := Vector3(chunk_key.x * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0, chunk_key.y * CHUNK_SIZE + CHUNK_SIZE * 0.5)
			chunk_node.position = chunk_origin
			add_child(chunk_node)

			# Create MultiMeshInstance3D and add to chunk node
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = multimesh
			mmi.name = "RockVariant%d" % (variant_idx + 1)
			# Distance culling
			mmi.visibility_range_end = _current_cull_distance
			mmi.visibility_range_end_margin = 50.0
			chunk_node.add_child(mmi)

			variant_total += transforms.size()
			total_chunks += 1

		total_placed += variant_total
		print("RockPlacer: variant %d - %d instances in %d chunks" % [variant_idx + 1, variant_total, chunks.size()])

	print("RockPlacer: finished — placed %d rocks in %d chunks (MultiMesh), skipped %d" % [total_placed, total_chunks, skipped])

	# ── Create collision bodies for rocks ──────────────────────────────────
	print("RockPlacer: creating collision for %d rocks..." % collision_data.size())
	_create_rock_collision(collision_data)
	print("RockPlacer: rock collision created")


func _extract_mesh_from_node(node: Node) -> Mesh:
	if not node:
		return null

	# Find ALL MeshInstance3D nodes in the tree
	var mesh_instances: Array[MeshInstance3D] = []
	_find_all_mesh_instances(node, mesh_instances)

	if mesh_instances.is_empty():
		return null

	# If only one mesh, return it directly
	if mesh_instances.size() == 1:
		return mesh_instances[0].mesh

	# Multiple meshes - combine them into one
	return _combine_meshes(mesh_instances, node)


func _extract_collision_shape(node: Node) -> Shape3D:
	if not node:
		return null

	# Look for StaticBody3D -> CollisionShape3D
	var static_body = _find_first_node_of_type(node, StaticBody3D)
	if not static_body:
		return null

	var collision_shape_node = _find_first_node_of_type(static_body, CollisionShape3D)
	if not collision_shape_node:
		return null

	return collision_shape_node.shape


func _find_first_node_of_type(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node

	for child in node.get_children():
		var result = _find_first_node_of_type(child, type)
		if result:
			return result

	return null


func _find_all_mesh_instances(node: Node, results: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh:
		results.append(node)

	for child in node.get_children():
		_find_all_mesh_instances(child, results)


func _combine_meshes(mesh_instances: Array[MeshInstance3D], root: Node3D) -> Mesh:
	var combined = ArrayMesh.new()
	var st = SurfaceTool.new()

	for mesh_instance in mesh_instances:
		var mesh = mesh_instance.mesh
		if not mesh:
			continue

		var local_transform = _get_relative_transform(mesh_instance, root)

		for surface_idx in range(mesh.get_surface_count()):
			st.begin(Mesh.PRIMITIVE_TRIANGLES)

			var material = mesh.surface_get_material(surface_idx)
			if material:
				st.set_material(material)

			var mdt = MeshDataTool.new()
			var temp_mesh = ArrayMesh.new()
			temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface_idx))
			mdt.create_from_surface(temp_mesh, 0)

			for i in range(mdt.get_vertex_count()):
				var vertex = mdt.get_vertex(i)
				var normal = mdt.get_vertex_normal(i)
				var uv = mdt.get_vertex_uv(i)
				var color = mdt.get_vertex_color(i)

				vertex = local_transform * vertex
				normal = local_transform.basis * normal

				st.set_normal(normal)
				st.set_uv(uv)
				st.set_color(color)
				st.add_vertex(vertex)

			for i in range(mdt.get_face_count()):
				var v0 = mdt.get_face_vertex(i, 0)
				var v1 = mdt.get_face_vertex(i, 1)
				var v2 = mdt.get_face_vertex(i, 2)
				st.add_index(v0)
				st.add_index(v1)
				st.add_index(v2)

			st.commit(combined)
			st.clear()

	return combined


func _get_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result = Transform3D.IDENTITY
	var current = node

	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D

	return result


func _create_rock_collision(rock_data: Array) -> void:
	var collision_parent = StaticBody3D.new()
	collision_parent.name = "RockCollision"
	collision_parent.collision_layer = 1
	collision_parent.collision_mask = 0
	add_child(collision_parent)

	var created_count = 0

	for data in rock_data:
		var variant_idx: int = data["variant_idx"]
		var position: Vector3 = data["position"]
		var scale: Vector3 = data["scale"]

		if variant_idx >= _rock_collision_shapes.size():
			continue

		var shape: Shape3D = _rock_collision_shapes[variant_idx]
		if not shape:
			continue

		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = shape.duplicate()
		collision_shape.position = position
		collision_shape.scale = scale

		collision_parent.add_child(collision_shape)
		created_count += 1

	print("RockPlacer: created %d collision shapes" % created_count)


func set_cull_distance(distance: float) -> void:
	_current_cull_distance = distance

	# Update all MultiMeshInstance3D children
	for chunk_node in get_children():
		if chunk_node is Node3D:
			for child in chunk_node.get_children():
				if child is MultiMeshInstance3D:
					child.visibility_range_end = distance
					child.visibility_range_end_margin = 50.0

	print("RockPlacer: cull distance updated to %.1fm" % distance)
