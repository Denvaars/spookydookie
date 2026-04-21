class_name TreePlacer
extends Node3D

## Places tree models throughout the forest.

const TREE_COUNT: int          = 5000
const PATH_CLEAR_RADIUS: float = 4.0  # Not used - grid system handles clearance
const CHUNK_SIZE: float = 100.0  # Size of each spatial chunk for culling (100m x 100m)
const CULL_DISTANCE: float = 300.0  # Cull chunks beyond this distance

var _terrain: TerrainGenerator
var _path: PathGenerator
var _poi_generator: POIGenerator = null
var _danger_manager = null  # DangerZoneManager (can't type hint due to circular dependency)
var _tree_meshes: Array[Mesh] = []
var _tree_scale_horizontal: float = 7.0
var _tree_scale_vertical: float = 7.0
var _tree_collision_shapes: Array[Shape3D] = []  # Collision shapes from tree scenes
var _current_cull_distance: float = CULL_DISTANCE


func _ready() -> void:
	add_to_group("tree_placer")


func place(terrain: TerrainGenerator, path: PathGenerator, tree_scale_horizontal: float = 1.0, tree_scale_vertical: float = 1.0, poi_generator: POIGenerator = null, danger_manager = null) -> void:
	_tree_scale_horizontal = tree_scale_horizontal
	_tree_scale_vertical = tree_scale_vertical
	_terrain = terrain
	_path    = path
	_poi_generator = poi_generator
	_danger_manager = danger_manager
	print("TreePlacer: place() called")

	# Clear any previous meshes
	_tree_meshes.clear()

	# ── Load tree meshes from trees.tscn ──────────────────────────────────────
	var trees_scene = load("res://trees.tscn")
	if not trees_scene:
		push_error("TreePlacer: failed to load res://trees.tscn")
		return

	var trees_root = trees_scene.instantiate()

	# Tree node names in the scene
	var tree_names = [
		"pine_tree_n_2_1",
		#"pine_tree_n_2_2",
		#"pine_tree_n_2_3",
		#"pine_tree_n_2_4"
	]

	for tree_name in tree_names:
		var tree_node = trees_root.get_node_or_null(tree_name)
		if tree_node:
			var mesh = _extract_mesh_from_node(tree_node)
			if mesh:
				_tree_meshes.append(mesh)
				print("TreePlacer: loaded mesh from %s" % tree_name)
			else:
				push_warning("TreePlacer: failed to extract mesh from %s" % tree_name)

			# Extract collision shape from the tree node
			var collision_shape = _extract_collision_shape(tree_node)
			_tree_collision_shapes.append(collision_shape)  # Can be null if no collision found
		else:
			push_warning("TreePlacer: tree node '%s' not found in trees.tscn" % tree_name)

	# Clean up the temporary instance
	trees_root.queue_free()

	if _tree_meshes.is_empty():
		push_error("TreePlacer: no tree meshes loaded")
		return

	print("TreePlacer: loaded %d tree variants" % _tree_meshes.size())

	# ── Calculate all tree transforms first ──────────────────────────────────
	var half_x := terrain.terrain_width  * 0.5 * 0.93
	var half_z := terrain.terrain_length * 0.5 * 0.93
	var skipped := 0

	# Calculate grid spacing for target tree count
	var area := (half_x * 2.0) * (half_z * 2.0)
	var spacing := sqrt(area / TREE_COUNT)
	var jitter := spacing * 0.4  # 40% randomness

	print("TreePlacer: grid spacing %.1f, jitter %.1f" % [spacing, jitter])

	# Collect transforms organized by spatial chunks for culling
	# Structure: chunks_per_variant[variant_idx][chunk_key] = [transforms]
	var chunks_per_variant: Array = []
	for i in range(_tree_meshes.size()):
		chunks_per_variant.append({})

	# Collect collision data: [position, scale, variant_idx]
	var collision_data: Array = []

	# Calculate all valid tree positions and their transforms
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

			# Skip if on path (using exclusion grid)
			if _path.call("is_on_path", rx, rz):
				skipped += 1
				x += spacing
				continue

			# Skip if near POI
			if _poi_generator and _poi_generator.is_near_poi(rx, rz):
				skipped += 1
				x += spacing
				continue

			var ry := _terrain.get_height(rx, rz)

			# Get danger level at this position to scale tree
			var danger_level := 1.0
			if _danger_manager and _danger_manager.has_method("get_danger_level"):
				danger_level = _danger_manager.get_danger_level(Vector3(rx, ry, rz))

			# Calculate horizontal scale based on danger (deeper = bigger/wider trees)
			# Formula: horizontal_scale = base + (danger - 1.0)
			var tree_scale_h := _tree_scale_horizontal + (danger_level - 1.0)

			# Calculate which spatial chunk this tree belongs to
			var chunk_x := int(floor(rx / CHUNK_SIZE))
			var chunk_z := int(floor(rz / CHUNK_SIZE))
			var chunk_key := Vector2i(chunk_x, chunk_z)

			# Create transform for this tree (relative to chunk origin)
			var chunk_origin := Vector3(chunk_x * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0, chunk_z * CHUNK_SIZE + CHUNK_SIZE * 0.5)
			var transform := Transform3D()
			transform = transform.scaled(Vector3(tree_scale_h, _tree_scale_vertical, tree_scale_h))
			transform = transform.rotated(Vector3.UP, randf_range(0.0, TAU))
			transform.origin = Vector3(rx, ry, rz) - chunk_origin  # Relative to chunk

			# Assign to random variant and chunk
			var variant_idx := randi() % _tree_meshes.size()
			if not chunks_per_variant[variant_idx].has(chunk_key):
				chunks_per_variant[variant_idx][chunk_key] = []
			chunks_per_variant[variant_idx][chunk_key].append(transform)

			# Store collision data (world position, scale, variant)
			collision_data.append({
				"position": Vector3(rx, ry, rz),
				"scale": Vector3(tree_scale_h, _tree_scale_vertical, tree_scale_h),
				"variant_idx": variant_idx
			})

			x += spacing
		z += spacing

	# ── Create MultiMeshInstances (one per chunk per variant) ───────────────
	var total_placed := 0
	var total_chunks := 0

	for variant_idx in range(_tree_meshes.size()):
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
			multimesh.mesh = _tree_meshes[variant_idx]
			multimesh.instance_count = transforms.size()

			# Set each instance transform (already relative to chunk origin)
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
			mmi.name = "TreeVariant%d" % (variant_idx + 1)
			# Distance culling: fade out trees 250-300m from chunk center
			mmi.visibility_range_end = _current_cull_distance
			mmi.visibility_range_end_margin = 50.0
			chunk_node.add_child(mmi)

			variant_total += transforms.size()
			total_chunks += 1

		total_placed += variant_total
		print("TreePlacer: variant %d - %d instances in %d chunks" % [variant_idx + 1, variant_total, chunks.size()])

	print("TreePlacer: finished — placed %d trees in %d chunks (MultiMesh), skipped %d" % [total_placed, total_chunks, skipped])

	# ── Create collision bodies for trees ─────────────────────────────────────
	print("TreePlacer: creating collision for %d trees..." % collision_data.size())
	_create_tree_collision(collision_data)
	print("TreePlacer: tree collision created")


func _extract_mesh_from_node(node: Node) -> Mesh:
	# Extract mesh from an already instantiated tree node
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
	# Find and extract the first collision shape from the tree node
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
	# Recursively find first node of specific type
	if is_instance_of(node, type):
		return node

	for child in node.get_children():
		var result = _find_first_node_of_type(child, type)
		if result:
			return result

	return null


func _extract_mesh_from_glb(glb_path: String) -> Mesh:
	# Load the GLB as a packed scene
	var scene: PackedScene = load(glb_path)
	if not scene:
		return null

	# Instantiate it temporarily to extract the meshes
	var root = scene.instantiate()
	if not root:
		return null

	# Find ALL MeshInstance3D nodes in the scene tree
	var mesh_instances: Array[MeshInstance3D] = []
	_find_all_mesh_instances(root, mesh_instances)

	if mesh_instances.is_empty():
		root.queue_free()
		return null

	# If only one mesh, return it directly
	if mesh_instances.size() == 1:
		var extracted_mesh = mesh_instances[0].mesh
		root.queue_free()
		return extracted_mesh

	# Multiple meshes - combine them into one
	var combined_mesh = _combine_meshes(mesh_instances, root)

	# Clean up the temporary instance
	root.queue_free()

	return combined_mesh


func _find_all_mesh_instances(node: Node, results: Array[MeshInstance3D]) -> void:
	# Check if this node is a MeshInstance3D
	if node is MeshInstance3D and node.mesh:
		results.append(node)

	# Recursively search children
	for child in node.get_children():
		_find_all_mesh_instances(child, results)


func _combine_meshes(mesh_instances: Array[MeshInstance3D], root: Node3D) -> Mesh:
	# Create a new ArrayMesh to combine all meshes
	var combined = ArrayMesh.new()
	var st = SurfaceTool.new()

	for mesh_instance in mesh_instances:
		var mesh = mesh_instance.mesh
		if not mesh:
			continue

		# Get the local transform relative to root (walk up the parent chain)
		var local_transform = _get_relative_transform(mesh_instance, root)

		# Process each surface in the mesh
		for surface_idx in range(mesh.get_surface_count()):
			st.begin(Mesh.PRIMITIVE_TRIANGLES)

			# Get material from the mesh
			var material = mesh.surface_get_material(surface_idx)
			if material:
				st.set_material(material)

			# Create mesh data tool to read vertices
			var mdt = MeshDataTool.new()
			var temp_mesh = ArrayMesh.new()
			temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface_idx))
			mdt.create_from_surface(temp_mesh, 0)

			# Copy all vertices with transform applied
			for i in range(mdt.get_vertex_count()):
				var vertex = mdt.get_vertex(i)
				var normal = mdt.get_vertex_normal(i)
				var uv = mdt.get_vertex_uv(i)
				var color = mdt.get_vertex_color(i)

				# Apply local transform
				vertex = local_transform * vertex
				normal = local_transform.basis * normal

				st.set_normal(normal)
				st.set_uv(uv)
				st.set_color(color)
				st.add_vertex(vertex)

			# Add indices
			for i in range(mdt.get_face_count()):
				var v0 = mdt.get_face_vertex(i, 0)
				var v1 = mdt.get_face_vertex(i, 1)
				var v2 = mdt.get_face_vertex(i, 2)
				st.add_index(v0)
				st.add_index(v1)
				st.add_index(v2)

			# Commit this surface
			st.commit(combined)
			st.clear()

	return combined


func _get_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	# Calculate the transform of 'node' relative to 'ancestor' by walking up the parent chain
	var result = Transform3D.IDENTITY
	var current = node

	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D

	return result


func _create_tree_collision(tree_data: Array) -> void:
	# Create a single StaticBody3D parent to hold all tree collision shapes
	var collision_parent = StaticBody3D.new()
	collision_parent.name = "TreeCollision"
	collision_parent.collision_layer = 1  # Layer 1 (world geometry)
	collision_parent.collision_mask = 0   # Trees don't need to detect anything
	add_child(collision_parent)

	var created_count = 0

	for data in tree_data:
		var variant_idx: int = data["variant_idx"]
		var position: Vector3 = data["position"]
		var scale: Vector3 = data["scale"]

		# Get the collision shape for this variant
		if variant_idx >= _tree_collision_shapes.size():
			continue

		var shape: Shape3D = _tree_collision_shapes[variant_idx]
		if not shape:
			continue  # This tree variant has no collision shape

		# Create collision shape node
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = shape.duplicate()  # Duplicate so we can scale it
		collision_shape.position = position

		# Scale the collision shape to match tree scale
		collision_shape.scale = scale

		collision_parent.add_child(collision_shape)
		created_count += 1

	print("TreePlacer: created %d collision shapes" % created_count)


func set_cull_distance(distance: float) -> void:
	_current_cull_distance = distance

	# Update all MultiMeshInstance3D children
	for chunk_node in get_children():
		if chunk_node is Node3D:
			for child in chunk_node.get_children():
				if child is MultiMeshInstance3D:
					child.visibility_range_end = distance
					child.visibility_range_end_margin = 50.0

	print("TreePlacer: cull distance updated to %.1fm" % distance)
