extends Node3D

## Loot Spawner Node
## Place this as an empty Node3D in your scene and assign a loot table name
## On ready, it will spawn items from the loot table at its position

@export var loot_table_name: String = "medical_supplies"  # Available: medical_supplies, survival_gear, camping_supplies
@export var spawn_on_ready: bool = true  # Spawn loot immediately when scene loads
@export var spawn_single_item: bool = true  # If true, only spawn 1 random item instead of rolling all entries

var terrain: TerrainGenerator = null

func _ready() -> void:
	# Find terrain for height placement
	terrain = get_tree().get_first_node_in_group("terrain")

	if spawn_on_ready:
		# Use call_deferred to wait until scene is fully loaded
		call_deferred("spawn_loot")

func spawn_loot() -> void:
	if loot_table_name.is_empty():
		return

	# Roll the loot table
	var items_to_spawn = LootTablesRegistry.roll_loot(loot_table_name)

	if items_to_spawn.is_empty():
		return

	# If spawn_single_item is enabled, pick just one random item
	if spawn_single_item and items_to_spawn.size() > 0:
		var random_item = items_to_spawn[randi() % items_to_spawn.size()]
		items_to_spawn = [random_item]

	# Spawn each item
	for item_scene in items_to_spawn:
		await spawn_item(item_scene)

func spawn_item(item_scene: PackedScene) -> void:
	var item = item_scene.instantiate()

	# Spawn at exact spawner position
	var spawn_pos = global_position

	# Add to scene root (so it persists when this node is freed)
	var root = get_tree().root
	root.call_deferred("add_child", item)

	# Wait for item to be added to tree, then set position
	await get_tree().process_frame
	item.global_position = spawn_pos

	print("    Item added to tree: %s" % item.is_inside_tree())
	print("    Item type: %s" % item.name)

	# Check for mesh/visual components
	var mesh_instance = item.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		print("    Has MeshInstance3D, visible: %s" % mesh_instance.visible)
	else:
		print("    WARNING: No MeshInstance3D found!")

	# Add slight upward velocity if it's a RigidBody (items will drop naturally)
	if item is RigidBody3D:
		item.linear_velocity = Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))

	print("  Spawned: %s at %v" % [item.name, spawn_pos])

	# Create a debug sphere at spawn location
	#await create_debug_marker(spawn_pos)

func create_debug_marker(pos: Vector3) -> void:
	# Create a HUGE bright colored sphere at spawn position to visualize where items spawn
	var marker = MeshInstance3D.new()
	marker.name = "LootDebugMarker"
	var sphere = SphereMesh.new()
	sphere.radius = 2.0  # Much larger - 2 meter radius
	sphere.height = 4.0
	marker.mesh = sphere

	# Create bright red material with strong emission
	#var material = StandardMaterial3D.new()
	#material.albedo_color = Color(1, 0, 0)
	#material.emission_enabled = true
	#material.emission = Color(1, 0, 0)
	#material.emission_energy = 5.0  # Very bright
	#material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always visible
	#marker.set_surface_override_material(0, material)

	# Add to scene
	var root = get_tree().root
	root.call_deferred("add_child", marker)

	# Set position after adding (deferred)
	await get_tree().process_frame
	marker.global_position = pos
