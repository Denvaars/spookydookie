extends RigidBody3D

## Pickup item in the world
## Can be picked up by the player looking at it and pressing E

@export var item_resource: InventoryItem

# Track if this pickup was dropped from inventory (vs spawned in world)
var is_dropped: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Add to pickup group so player can detect it
	add_to_group("pickup")

	# Set up collision layers
	collision_layer = 2  # Layer 2 for pickups
	collision_mask = 1  # Collide with world (layer 1)

func pickup(player) -> bool:
	if not item_resource:
		return false

	# Try to add to player's inventory
	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if not inventory_ui:
		return false

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return false

	# Duplicate the resource so each pickup is unique (deep copy to preserve runtime values)
	var item_copy = item_resource.duplicate(true)

	# Manually preserve runtime variables that don't get copied by duplicate()
	item_copy.current_stack = item_resource.current_stack
	item_copy.weapon_current_ammo = item_resource.weapon_current_ammo
	item_copy.flare_is_lit = item_resource.flare_is_lit
	item_copy.flare_burn_time = item_resource.flare_burn_time

	# Initialize stackable items to their max stack unless this was dropped from inventory
	if item_copy.stackable and item_copy.max_stack > 1:
		if not is_dropped:
			# Fresh world spawn - set to max stack
			item_copy.current_stack = item_copy.max_stack

	# Try to find a spot in the inventory
	var grid_size = manager.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if manager.can_place_item(item_copy, x, y):
				if manager.place_item(item_copy, x, y):
					inventory_ui.refresh_display()
					queue_free()  # Remove from world
					return true

	# No space in inventory
	return false
