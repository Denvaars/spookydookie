extends Control

## Main inventory UI controller
## Manages the grid display and communicates with InventoryManager

const InventorySlotScene = preload("res://inventory_slot.tscn")
const EquipmentSlotScene = preload("res://equipment_slot.tscn")

var inventory_manager: InventoryManager
var slots: Array[Array] = []

# Equipment slots
var equipment_slots: Array = []  # [head_slot, chest_slot, feet_slot]

@onready var grid_container: GridContainer = $Panel/MainHBox/GridContainer
@onready var equipment_container: VBoxContainer = $Panel/MainHBox/EquipmentContainer
@onready var weight_label: Label = $Panel/WeightLabel

func _ready() -> void:
	# Initialize inventory manager
	inventory_manager = InventoryManager.new()
	add_child(inventory_manager)

	# Set up grid container
	grid_container.columns = inventory_manager.GRID_WIDTH

	# Create equipment slots
	create_equipment_slots()

	# Create all inventory slots
	create_slots()

	# Initial display update
	refresh_display()

func create_equipment_slots() -> void:
	# Clear existing equipment slots
	for child in equipment_container.get_children():
		if child.name.begins_with("EquipmentSlot"):
			child.queue_free()
	equipment_slots.clear()

	# Create 3 equipment slots: Head, Chest, Feet
	var slot_types = [
		{"type": InventoryItem.EquipmentSlot.HEAD, "name": "HEAD"},
		{"type": InventoryItem.EquipmentSlot.CHEST, "name": "CHEST"},
		{"type": InventoryItem.EquipmentSlot.FEET, "name": "FEET"}
	]

	for slot_data in slot_types:
		var slot = EquipmentSlotScene.instantiate()
		equipment_container.add_child(slot)
		slot.setup(slot_data["type"], slot_data["name"], self)
		equipment_slots.append(slot)

	print("Created %d equipment slots" % equipment_slots.size())

func create_slots() -> void:
	# Clear existing slots first
	for child in grid_container.get_children():
		child.queue_free()
	slots.clear()

	var grid_size = inventory_manager.get_grid_size()

	slots.resize(grid_size.y)
	for y in range(grid_size.y):
		slots[y] = []
		slots[y].resize(grid_size.x)

		for x in range(grid_size.x):
			var slot = InventorySlotScene.instantiate()
			slot.set_grid_position(x, y)
			slot.set_inventory_ui(self)
			grid_container.add_child(slot)
			slots[y][x] = slot

func refresh_display() -> void:
	# Update all inventory grid slots
	for y in range(len(slots)):
		for x in range(len(slots[y])):
			slots[y][x].update_display()

	# Update equipment slots
	for equipment_slot in equipment_slots:
		equipment_slot.update_display()

	# Update weight display
	update_weight_display()

func update_weight_display() -> void:
	if not weight_label:
		return

	var total_weight = get_total_weight()

	# Calculate speed penalty
	var player = get_parent().get_parent()
	var penalty_percent = 0.0
	if player and player.has_method("get_weight_speed_multiplier"):
		var weight_multiplier = player.get_weight_speed_multiplier()
		penalty_percent = (1.0 - weight_multiplier) * 100.0

	# Update label with color coding
	weight_label.text = "Weight: %.1f lbs (%.0f%% slow)" % [total_weight, penalty_percent]

	# Color based on weight
	if penalty_percent >= 40.0:
		weight_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))  # Red - very heavy
	elif penalty_percent >= 20.0:
		weight_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))  # Yellow - heavy
	else:
		weight_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))  # Green - light

func get_slot_at(x: int, y: int) -> Panel:
	if x < 0 or y < 0 or y >= len(slots) or x >= len(slots[0]):
		return null
	return slots[y][x]

func clear_all_highlights() -> void:
	for y in range(len(slots)):
		for x in range(len(slots[y])):
			slots[y][x].clear_highlight()

func update_grid_width() -> bool:
	# Calculate bonus columns from equipped chest item (backpack)
	var bonus_columns = 0
	if equipment_slots.size() > 1:  # Chest slot is index 1
		var chest_slot = equipment_slots[1]
		if chest_slot.equipped_item and chest_slot.equipped_item.inventory_bonus_columns > 0:
			bonus_columns = chest_slot.equipped_item.inventory_bonus_columns

	var new_width = inventory_manager.GRID_WIDTH + bonus_columns
	var old_width = grid_container.columns

	print("DEBUG update_grid_width: old_width=%d, new_width=%d, bonus_columns=%d" % [old_width, new_width, bonus_columns])

	# Only rebuild if width changed
	if old_width != new_width:
		# If shrinking, drop items that would be cut off
		if new_width < old_width:
			print("DEBUG: Grid shrinking from %d to %d" % [old_width, new_width])
			var items_to_drop: Array[InventoryItem] = []

			# Find items in columns that will be removed
			for item in inventory_manager.items:
				if item.is_placed():
					var rightmost_column = item.grid_x + item.grid_width - 1
					print("DEBUG: Checking item %s at column %d (rightmost: %d)" % [item.item_name, item.grid_x, rightmost_column])
					if rightmost_column >= new_width:
						print("DEBUG: Item %s will be dropped (column %d >= %d)" % [item.item_name, rightmost_column, new_width])
						items_to_drop.append(item)

			# Drop these items on the ground
			print("DEBUG: Dropping %d items" % items_to_drop.size())
			for item in items_to_drop:
				inventory_manager.remove_item(item)
				drop_item_on_ground(item)

			if items_to_drop.size() > 0:
				print("Dropped %d items on ground from inventory" % items_to_drop.size())

		print("Updating inventory width: %d -> %d" % [old_width, new_width])
		inventory_manager.set_grid_width(new_width)
		grid_container.columns = new_width
		create_slots()
		refresh_display()
		return true

	print("DEBUG: No width change needed")
	return true  # No change needed, success

func get_equipped_item_in_slot(slot_type: InventoryItem.EquipmentSlot) -> InventoryItem:
	for equipment_slot in equipment_slots:
		if equipment_slot.slot_type == slot_type:
			return equipment_slot.equipped_item
	return null

func get_total_weight() -> float:
	# Get weight from inventory items
	var total_weight = inventory_manager.get_total_weight()

	# Add weight from equipped items
	for equipment_slot in equipment_slots:
		if equipment_slot.equipped_item:
			var item = equipment_slot.equipped_item
			if item.stackable:
				total_weight += item.weight * item.current_stack
			else:
				total_weight += item.weight

	return total_weight

func drop_item_on_ground(item: InventoryItem) -> void:
	# Get player position
	var player = get_parent().get_parent()
	if not player:
		return

	# Convert item name to pickup scene name
	# e.g., "Pain Killers" -> "pickup_pain_killers.tscn"
	var item_name_lower = item.item_name.to_lower().replace(" ", "_")
	var pickup_scene_path = "res://pickup_%s.tscn" % item_name_lower

	print("DEBUG: Item name: '%s' -> Pickup scene: '%s'" % [item.item_name, pickup_scene_path])

	# Try to load the pickup scene
	var pickup_scene = load(pickup_scene_path)
	if not pickup_scene:
		print("Warning: Could not find pickup scene for item: %s (tried: %s)" % [item.item_name, pickup_scene_path])
		return

	# Instantiate the pickup
	var pickup = pickup_scene.instantiate()
	if not pickup:
		print("Warning: Could not instantiate pickup for: %s" % item.item_name)
		return

	# Set the item resource and mark as dropped
	pickup.item_resource = item
	pickup.is_dropped = true  # Preserves stack size

	# Add to scene
	var root = get_tree().root
	root.add_child(pickup)

	# Position in front of player and slightly up
	var drop_position = player.global_position + player.global_transform.basis.z * -1.0 + Vector3(0, 1.5, 0)
	pickup.global_position = drop_position

	# Add forward velocity if it's a RigidBody
	if pickup is RigidBody3D:
		pickup.linear_velocity = player.global_transform.basis.z * -2.0 + Vector3(0, 1.0, 0)

	print("Dropped item on ground: %s" % item.item_name)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close inventory when toggle key or ESC is pressed
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
		# Get the player and toggle inventory
		var player = get_parent().get_parent()
		if player and player.has_method("toggle_inventory"):
			player.toggle_inventory()
		get_viewport().set_input_as_handled()
