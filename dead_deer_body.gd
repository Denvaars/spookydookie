extends RigidBody3D

## Dead deer body that can be harvested for pelt, meat, and antlers
## Requires knife to harvest, takes 4 seconds

# Harvest settings
@export var harvest_time: float = 4.0
var is_harvested: bool = false
var interact_progress: float = 0.0

# References
var player: CharacterBody3D = null
var mesh_instance: MeshInstance3D = null
var my_prompt_name: String = ""

func _ready() -> void:
	# Add to interactable group
	add_to_group("harvestable")

	# Unique prompt name
	my_prompt_name = "DeerHarvestPrompt_%s" % get_instance_id()

	# Set collision
	collision_layer = 2  # Layer 2 for interactables
	collision_mask = 1   # Collide with world

	# Get mesh instance
	mesh_instance = get_node_or_null("MeshInstance3D")

	# Add collision shape if not exists
	if not get_node_or_null("CollisionShape3D"):
		var collision_shape = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.height = 1.2
		capsule.radius = 0.4
		collision_shape.shape = capsule
		collision_shape.position.y = 0.6
		add_child(collision_shape)

	print("Dead deer body ready for harvesting")

func _process(delta: float) -> void:
	# Don't process anything if already harvested
	if is_harvested:
		hide_interaction_ui()
		return

	check_player_interaction(delta)

func check_player_interaction(delta: float) -> void:
	if is_harvested:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	# Find player
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return

	# Check if player is looking at the body with raycast
	var camera = player.get_node_or_null("Camera3D")
	if not camera:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	var raycast = camera.get_node_or_null("InteractRaycast")
	if not raycast:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	# Check if raycast is hitting this body
	if not raycast.is_colliding():
		interact_progress = 0.0
		hide_interaction_ui()
		return

	var collider = raycast.get_collider()
	var is_looking_at_body = false

	# Check if collider is this body or a child of it
	var check_node = collider
	while check_node:
		if check_node == self:
			is_looking_at_body = true
			break
		check_node = check_node.get_parent()

	if not is_looking_at_body:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	# Player is looking at body - check if they have a knife equipped
	var has_knife = player.equipped_item and player.equipped_item.item_id == "knife_01"

	# Show appropriate prompt
	if not has_knife:
		show_interaction_prompt("Knife Required", false)
		interact_progress = 0.0
	else:
		show_interaction_prompt("[E] Harvest Deer", true)

		# Check if player is holding E
		if Input.is_action_pressed("interact"):
			interact_progress += delta
			update_progress_bar(interact_progress / harvest_time)

			# Check if fully harvested
			if interact_progress >= harvest_time:
				harvest_deer()
				interact_progress = 0.0
				hide_interaction_ui()
		else:
			# Reset progress if they let go
			if interact_progress > 0.0:
				interact_progress = 0.0
				update_progress_bar(0.0)

func show_interaction_prompt(text: String, can_interact: bool) -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if not prompt:
		# Create the prompt UI
		prompt = Control.new()
		prompt.name = my_prompt_name
		prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Center it on screen
		prompt.set_anchors_preset(Control.PRESET_CENTER)
		prompt.position = Vector2(-100, 150)  # Below crosshair

		var label = Label.new()
		label.name = "PromptLabel"
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prompt.add_child(label)

		# Create progress bar
		var progress_bg = ColorRect.new()
		progress_bg.name = "ProgressBG"
		progress_bg.color = Color(0.2, 0.2, 0.2, 0.8)
		progress_bg.size = Vector2(200, 20)
		progress_bg.position = Vector2(0, 30)
		progress_bg.visible = false
		prompt.add_child(progress_bg)

		var progress_fill = ColorRect.new()
		progress_fill.name = "ProgressFill"
		progress_fill.color = Color(0.8, 0.6, 0.2)  # Brown/tan for deer
		progress_fill.size = Vector2(0, 20)
		progress_fill.position = Vector2(0, 30)
		progress_fill.visible = false
		prompt.add_child(progress_fill)

		ui.add_child(prompt)

	var label = prompt.get_node("PromptLabel")
	if label:
		label.text = text

	prompt.visible = true

func update_progress_bar(progress: float) -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if not prompt:
		return

	var progress_bg = prompt.get_node_or_null("ProgressBG")
	var progress_fill = prompt.get_node_or_null("ProgressFill")

	if progress_bg and progress_fill:
		if progress > 0.0:
			progress_bg.visible = true
			progress_fill.visible = true
			progress_fill.size.x = 200 * clamp(progress, 0.0, 1.0)
		else:
			progress_bg.visible = false
			progress_fill.visible = false

func hide_interaction_ui() -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if prompt:
		prompt.visible = false

func harvest_deer() -> void:
	if is_harvested:
		return

	# Mark as harvested immediately to prevent double-harvesting
	is_harvested = true

	# Stop all processing immediately
	set_process(false)

	# Hide interaction UI immediately
	hide_interaction_ui()

	# Disable collision to prevent further interaction
	collision_layer = 0
	collision_mask = 0

	# Remove from harvestable group
	remove_from_group("harvestable")

	print("Harvesting deer...")

	# Give items directly to player inventory
	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if inventory_ui and inventory_ui.inventory_manager:
		var manager = inventory_ui.inventory_manager

		# Give 1 pelt
		var pelt_resource = load("res://items/deer_pelt.tres")
		if pelt_resource:
			var pelt_item = pelt_resource.duplicate(true)
			pelt_item.current_stack = 1
			if not try_add_to_inventory(manager, pelt_item):
				spawn_item("res://pickup_deer_pelt.tscn")

		# Give 1-2 meat
		var meat_count = randi_range(1, 2)
		var meat_resource = load("res://items/deer_meat.tres")
		if meat_resource:
			var meat_item = meat_resource.duplicate(true)
			meat_item.current_stack = meat_count
			if not try_add_to_inventory(manager, meat_item):
				for i in range(meat_count):
					spawn_item("res://pickup_deer_meat.tscn")

		# Give 0-2 antlers
		var antler_count = randi_range(0, 2)
		if antler_count > 0:
			var antler_resource = load("res://items/deer_antler.tres")
			if antler_resource:
				var antler_item = antler_resource.duplicate(true)
				antler_item.current_stack = antler_count
				if not try_add_to_inventory(manager, antler_item):
					for i in range(antler_count):
						spawn_item("res://pickup_deer_antler.tscn")

		inventory_ui.refresh_display()
		print("Harvested: 1 pelt, %d meat, %d antlers" % [meat_count, antler_count])

	# Remove body instantly
	queue_free()

func try_add_to_inventory(manager: InventoryManager, item: InventoryItem) -> bool:
	var grid_size = manager.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if manager.can_place_item(item, x, y):
				if manager.place_item(item, x, y):
					return true
	return false

func spawn_item(scene_path: String) -> void:
	var item_scene = load(scene_path)
	if not item_scene:
		print("ERROR: Could not load ", scene_path)
		return

	var item = item_scene.instantiate()
	get_tree().root.add_child(item)

	# Spawn near the body
	var offset = Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))
	item.global_position = global_position + offset

	if item is RigidBody3D:
		item.linear_velocity = Vector3(randf_range(-1, 1), 2, randf_range(-1, 1))
