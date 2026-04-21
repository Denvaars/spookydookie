extends Node

## Console command manager

signal command_executed(result: String)
signal command_error(error: String)

# Reference to player for spawning
var player: CharacterBody3D = null

func _ready() -> void:
	# Find player reference
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

func execute_command(command_text: String) -> void:
	command_text = command_text.strip_edges()

	if command_text.is_empty():
		return

	# Split command into parts
	var parts = command_text.split(" ", false)
	if parts.is_empty():
		return

	var command = parts[0].to_lower()

	match command:
		"/give":
			_command_give(parts)
		"/summon":
			_command_summon(parts)
		_:
			command_error.emit("Unknown command: " + command)

func _command_give(parts: Array) -> void:
	# /give <item_id> [amount]
	if parts.size() < 2:
		command_error.emit("/give usage: /give <item_id> [amount]")
		return

	var item_id = parts[1]
	var amount = 1

	if parts.size() >= 3:
		amount = parts[2].to_int()
		if amount <= 0:
			command_error.emit("Amount must be greater than 0")
			return

	# Load the item
	var item_path = "res://items/" + item_id + ".tres"
	if not ResourceLoader.exists(item_path):
		command_error.emit("Item not found: " + item_id)
		return

	var item_resource: InventoryItem = load(item_path)
	if not item_resource:
		command_error.emit("Failed to load item: " + item_id)
		return

	if not player:
		command_error.emit("Player not found")
		return

	# Get inventory manager
	var ui = player.get_node_or_null("UI")
	if not ui:
		command_error.emit("UI not found")
		return

	var inventory_ui = ui.get_node_or_null("InventoryUI")
	if not inventory_ui:
		command_error.emit("Inventory UI not found")
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		command_error.emit("Inventory manager not found")
		return

	# Duplicate the item resource
	var item_copy = item_resource.duplicate(true)

	# Set stack size for stackable items
	if item_copy.stackable and amount > 1:
		item_copy.current_stack = amount

	# Try to find a spot in the inventory
	var placed = false
	var grid_size = manager.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if manager.can_place_item(item_copy, x, y):
				if manager.place_item(item_copy, x, y):
					placed = true
					break
		if placed:
			break

	if placed:
		# Refresh inventory display
		if inventory_ui.has_method("refresh_display"):
			inventory_ui.refresh_display()

		if item_copy.stackable and amount > 1:
			command_executed.emit("Added %d %s to inventory" % [amount, item_copy.item_name])
		else:
			command_executed.emit("Added %s to inventory" % item_copy.item_name)
	else:
		# Inventory full, drop it
		_drop_item_at_player(item_resource, amount)
		if amount > 1:
			command_executed.emit("Inventory full, dropped %d %s" % [amount, item_resource.item_name])
		else:
			command_executed.emit("Inventory full, dropped %s" % item_resource.item_name)

func _drop_item_at_player(item: InventoryItem, quantity: int = 1) -> void:
	if not player:
		return

	# Construct pickup scene path from item name
	# e.g., "Pain Killers" -> "pickup_pain_killers.tscn"
	var item_name_lower = item.item_name.to_lower().replace(" ", "_")
	var pickup_scene_path = "res://pickup_%s.tscn" % item_name_lower

	# Try to load the pickup scene
	var pickup_scene = load(pickup_scene_path)
	if not pickup_scene:
		command_error.emit("Could not find pickup scene: " + pickup_scene_path)
		return

	# Spawn the pickup at player's feet
	var pickup = pickup_scene.instantiate()
	pickup.global_position = player.global_position + Vector3(0, 0.5, 0)

	# Set quantity if stackable (modify the item resource's current_stack)
	if item.stackable and quantity > 1:
		# Duplicate the item resource to set the stack size
		var item_copy = item.duplicate(true)
		item_copy.current_stack = quantity
		pickup.item_resource = item_copy

	# Add to scene
	player.get_parent().add_child(pickup)

func _command_summon(parts: Array) -> void:
	# /summon <entity_id> <natural:true/false>
	if parts.size() < 3:
		command_error.emit("/summon usage: /summon <entity_id> <natural:true/false>")
		return

	var entity_id = parts[1]
	var natural_str = parts[2].to_lower()
	var natural = (natural_str == "true")

	if not player:
		command_error.emit("Player not found")
		return

	match entity_id:
		"bear":
			_summon_bear(natural)
		"deer":
			_summon_deer(natural)
		"enemy_stalker", "stalker":
			_summon_stalker(natural)
		_:
			command_error.emit("Unknown entity: " + entity_id)

func _summon_bear(natural: bool) -> void:
	var bear_scene = load("res://animal_bear.tscn")
	if not bear_scene:
		command_error.emit("Failed to load bear scene")
		return

	var bear = bear_scene.instantiate()

	if natural:
		# Spawn naturally (random position around player)
		var spawn_pos = _get_natural_spawn_position(20.0, 40.0)
		bear.global_position = spawn_pos
		command_executed.emit("Spawned bear naturally at distance: %.1fm" % player.global_position.distance_to(spawn_pos))
	else:
		# Spawn at crosshair (where player is looking)
		var spawn_pos = _get_crosshair_spawn_position()
		bear.global_position = spawn_pos
		command_executed.emit("Spawned bear at crosshair")

	player.get_parent().add_child(bear)

func _summon_deer(natural: bool) -> void:
	var deer_scene = load("res://animal_deer.tscn")
	if not deer_scene:
		command_error.emit("Failed to load deer scene")
		return

	if natural:
		# Spawn group of 3-5 deer
		var group_size = randi_range(3, 5)
		var center_pos = _get_natural_spawn_position(30.0, 60.0)

		for i in range(group_size):
			var deer = deer_scene.instantiate()
			# Random offset within 5m of center
			var offset = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
			deer.global_position = center_pos + offset
			player.get_parent().add_child(deer)

		command_executed.emit("Spawned %d deer naturally" % group_size)
	else:
		# Spawn single deer at crosshair
		var deer = deer_scene.instantiate()
		var spawn_pos = _get_crosshair_spawn_position()
		deer.global_position = spawn_pos
		player.get_parent().add_child(deer)
		command_executed.emit("Spawned deer at crosshair")

func _summon_stalker(natural: bool) -> void:
	var stalker_scene = load("res://enemy_stalker.tscn")
	if not stalker_scene:
		command_error.emit("Failed to load stalker scene")
		return

	var stalker = stalker_scene.instantiate()

	if natural:
		# Spawn naturally (far from player, out of sight)
		var spawn_pos = _get_natural_spawn_position(40.0, 80.0)
		stalker.global_position = spawn_pos
		command_executed.emit("Spawned stalker naturally at distance: %.1fm" % player.global_position.distance_to(spawn_pos))
	else:
		# Spawn at crosshair
		var spawn_pos = _get_crosshair_spawn_position()
		stalker.global_position = spawn_pos
		command_executed.emit("Spawned stalker at crosshair")

	player.get_parent().add_child(stalker)

func _get_natural_spawn_position(min_distance: float, max_distance: float) -> Vector3:
	# Get random angle
	var angle = randf() * TAU
	var distance = randf_range(min_distance, max_distance)

	# Calculate spawn position
	var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	var spawn_pos = player.global_position + offset

	# Get terrain height if TerrainGenerator exists
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if forest and forest.has_method("get_terrain"):
		var terrain = forest.get_terrain()
		if terrain:
			spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)

	return spawn_pos

func _get_crosshair_spawn_position() -> Vector3:
	# Raycast from camera to get spawn position
	var camera = player.get_node_or_null("Camera3D")
	if not camera:
		return player.global_position + player.global_transform.basis.z * -5.0

	var space_state = player.get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 100.0)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Layer 1 (world)

	var result = space_state.intersect_ray(query)
	if result:
		return result.position
	else:
		# No hit, spawn 10m in front
		return player.global_position + player.global_transform.basis.z * -10.0
