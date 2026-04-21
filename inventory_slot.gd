extends Panel

## Individual inventory grid slot
## Handles hover effects and drag/drop events

const SLOT_SIZE: int = 64

var grid_x: int = 0
var grid_y: int = 0
var inventory_ui: Control = null
var click_start_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false

@onready var background: ColorRect = $Background
@onready var item_icon: TextureRect = $ItemIcon
@onready var highlight: ColorRect = $Highlight
@onready var item_label: Label = $ItemLabel
var quantity_label: Label = null
var weight_label: Label = null

func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	background.color = Color(0.15, 0.15, 0.17, 0.8)
	highlight.color = Color(0, 0, 0, 0)  # Transparent by default
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create quantity label for stackable items (top-right)
	quantity_label = Label.new()
	quantity_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	quantity_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	quantity_label.add_theme_constant_override("outline_size", 2)
	quantity_label.add_theme_font_size_override("font_size", 12)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.anchor_right = 1.0
	quantity_label.anchor_bottom = 1.0
	quantity_label.offset_right = -2
	quantity_label.offset_top = 2
	quantity_label.visible = false
	add_child(quantity_label)

	# Create weight label (bottom-left)
	weight_label = Label.new()
	weight_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	weight_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	weight_label.add_theme_constant_override("outline_size", 2)
	weight_label.add_theme_font_size_override("font_size", 10)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weight_label.anchor_right = 1.0
	weight_label.anchor_bottom = 1.0
	weight_label.offset_left = 2
	weight_label.offset_bottom = -2
	weight_label.visible = false
	add_child(weight_label)

func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y

func set_inventory_ui(ui: Control) -> void:
	inventory_ui = ui

func update_display() -> void:
	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return

	var item = manager.get_item_at(grid_x, grid_y)

	# Only show icon if this is the top-left cell of an item
	if item and item.grid_x == grid_x and item.grid_y == grid_y:
		if item.icon:
			item_icon.texture = item.icon
			item_icon.visible = true
			# Show green background if equipped
			if item.is_equipped:
				background.color = Color(0.2, 0.6, 0.3, 0.9)  # Green for equipped
			else:
				background.color = Color(0.15, 0.15, 0.17, 0.8)
			item_label.visible = false

			# Show quantity for stackable items
			if item.stackable and item.max_stack > 1:
				quantity_label.text = str(item.current_stack) + "x"
				quantity_label.visible = true
			else:
				quantity_label.visible = false

			# Show weight
			if weight_label:
				var total_weight = item.weight
				if item.stackable:
					total_weight = item.weight * item.current_stack
				weight_label.text = "%.1f" % total_weight
				weight_label.visible = true
		else:
			# No icon, show colored placeholder based on item
			item_icon.visible = false
			# Color the background to show an item is here
			var item_color = get_item_color(item.item_id)
			# Brighten if equipped
			if item.is_equipped:
				item_color = item_color.lightened(0.3)
			background.color = item_color
			# Show item name
			item_label.text = item.item_name
			item_label.visible = true

			# Show quantity for stackable items
			if item.stackable and item.max_stack > 1:
				quantity_label.text = str(item.current_stack) + "x"
				quantity_label.visible = true
			else:
				quantity_label.visible = false

			# Show weight
			if weight_label:
				var total_weight = item.weight
				if item.stackable:
					total_weight = item.weight * item.current_stack
				weight_label.text = "%.1f" % total_weight
				weight_label.visible = true
	else:
		item_icon.visible = false
		item_label.visible = false
		if quantity_label:
			quantity_label.visible = false
		if weight_label:
			weight_label.visible = false
		# Check if this cell is occupied by a multi-cell item
		if item:
			# This is part of a larger item, show semi-transparent version
			var item_color = get_item_color(item.item_id)
			# Brighten if equipped
			if item.is_equipped:
				item_color = item_color.lightened(0.3)
			background.color = item_color.darkened(0.3)
		else:
			# Empty cell
			background.color = Color(0.15, 0.15, 0.17, 0.8)

		# Make sure weight label is hidden for non-origin cells
		if weight_label:
			weight_label.visible = false

func get_item_color(item_id: String) -> Color:
	# Return different colors for different item types
	match item_id:
		"flashlight_01":
			return Color(0.9, 0.8, 0.3, 0.9)  # Yellow
		"medkit_01":
			return Color(0.8, 0.2, 0.2, 0.9)  # Red
		"bandage_01":
			return Color(0.9, 0.9, 0.9, 0.9)  # White
		"shotgun_01":
			return Color(0.3, 0.3, 0.3, 0.9)  # Dark gray
		"axe_01":
			return Color(0.6, 0.3, 0.1, 0.9)  # Brown
		"knife_01":
			return Color(0.7, 0.7, 0.8, 0.9)  # Steel
		"rifle_01":
			return Color(0.4, 0.3, 0.2, 0.9)  # Dark brown
		"pistol_01":
			return Color(0.2, 0.2, 0.3, 0.9)  # Dark blue
		"shotgun_shells_01":
			return Color(0.8, 0.6, 0.2, 0.9)  # Orange/brass
		"rifle_ammo_01":
			return Color(0.7, 0.5, 0.3, 0.9)  # Tan/brass
		"pistol_ammo_01":
			return Color(0.6, 0.6, 0.4, 0.9)  # Light brass
		"flare_01":
			return Color(0.9, 0.1, 0.1, 0.9)  # Bright red
		"binoculars_01":
			return Color(0.2, 0.2, 0.2, 0.9)  # Dark gray/black
		"lantern_01":
			return Color(0.7, 0.5, 0.2, 0.9)  # Bronze/brass
		"backpack_01":
			return Color(0.4, 0.3, 0.2, 0.9)  # Brown
		_:
			return Color(0.5, 0.5, 0.5, 0.9)  # Default gray

func _get_drag_data(at_position: Vector2) -> Variant:
	if not inventory_ui:
		return null

	var manager: InventoryManager = inventory_ui.inventory_manager
	var item = manager.get_item_at(grid_x, grid_y)

	if not item:
		return null

	# Mark that we're starting a drag
	is_dragging = true

	# Create drag preview
	var preview: Control
	if item.icon:
		var tex_rect = TextureRect.new()
		tex_rect.texture = item.icon
		tex_rect.custom_minimum_size = Vector2(SLOT_SIZE * item.grid_width, SLOT_SIZE * item.grid_height)
		tex_rect.modulate = Color(1, 1, 1, 0.7)
		preview = tex_rect
	else:
		# No icon, create colored rectangle preview
		var color_rect = ColorRect.new()
		color_rect.color = get_item_color(item.item_id)
		color_rect.custom_minimum_size = Vector2(SLOT_SIZE * item.grid_width, SLOT_SIZE * item.grid_height)

		# Add label to preview
		var label = Label.new()
		label.text = item.item_name
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(SLOT_SIZE * item.grid_width, SLOT_SIZE * item.grid_height)
		color_rect.add_child(label)

		preview = color_rect

	set_drag_preview(preview)

	return item

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is InventoryItem:
		return false

	if not inventory_ui:
		return false

	var dragged_item: InventoryItem = data as InventoryItem
	var manager: InventoryManager = inventory_ui.inventory_manager

	# Check if we're dropping onto a stackable item of the same type
	var target_item = manager.get_item_at(grid_x, grid_y)

	if target_item and dragged_item.stackable and target_item.stackable:
		if dragged_item.item_id == target_item.item_id and dragged_item != target_item:
			# Can combine stacks - show as valid
			highlight_cells(dragged_item, true)
			return true

	# Normal placement check
	var can_place = manager.can_place_item(dragged_item, grid_x, grid_y)

	# Show visual feedback
	highlight_cells(dragged_item, can_place)

	return can_place

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is InventoryItem:
		return

	var dragged_item: InventoryItem = data as InventoryItem
	var manager: InventoryManager = inventory_ui.inventory_manager

	# Check if item came from an equipment slot
	var from_equipment = dragged_item.has_meta("_dragging_from_equipment_slot")
	var source_equipment_slot = null
	if from_equipment:
		source_equipment_slot = dragged_item.get_meta("_dragging_from_equipment_slot")
		dragged_item.remove_meta("_dragging_from_equipment_slot")

	# Check if we're dropping onto an existing stackable item
	var target_item = manager.get_item_at(grid_x, grid_y)

	if target_item and dragged_item.stackable and target_item.stackable:
		# Check if they're the same item type
		if dragged_item.item_id == target_item.item_id and dragged_item != target_item:
			# Combine stacks
			var total = dragged_item.current_stack + target_item.current_stack

			if total <= target_item.max_stack:
				# Can fit everything into target stack
				target_item.current_stack = total
				manager.remove_item(dragged_item)

				# Clear from equipment slot if came from there
				if source_equipment_slot:
					source_equipment_slot.equipped_item = null
					source_equipment_slot.update_inventory_size()

				# Clean up drag metadata
				if dragged_item.has_meta("_equipment_slot_backup"):
					dragged_item.remove_meta("_equipment_slot_backup")
			else:
				# Overflow - fill target and keep remainder in dragged
				var overflow = total - target_item.max_stack
				target_item.current_stack = target_item.max_stack
				dragged_item.current_stack = overflow

			inventory_ui.refresh_display()
			return

	# Normal placement (no combining)
	if manager.place_item(dragged_item, grid_x, grid_y):
		# Remove from equipment slot if it came from there
		if source_equipment_slot:
			source_equipment_slot.equipped_item = null
			source_equipment_slot.update_inventory_size()

		# Clean up drag metadata (successful drop)
		if dragged_item.has_meta("_equipment_slot_backup"):
			dragged_item.remove_meta("_equipment_slot_backup")

		inventory_ui.refresh_display()

func highlight_cells(item: InventoryItem, is_valid: bool) -> void:
	if not inventory_ui:
		return

	var color = Color(0.2, 0.8, 0.4, 0.4) if is_valid else Color(0.8, 0.2, 0.2, 0.4)

	# Highlight all cells this item would occupy
	for dy in range(item.grid_height):
		for dx in range(item.grid_width):
			var slot = inventory_ui.get_slot_at(grid_x + dx, grid_y + dy)
			if slot:
				slot.highlight.color = color

func clear_highlight() -> void:
	highlight.color = Color(0, 0, 0, 0)

func _gui_input(event: InputEvent) -> void:
	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return

	var item = manager.get_item_at(grid_x, grid_y)
	if not item:
		return

	# Right click to drop item
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		drop_item_in_world(item)
		accept_event()

	# Left click to equip item (track press and release)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			click_start_position = event.position
			is_dragging = false
		elif not event.pressed and not is_dragging:
			# Left click released without dragging - equip the item
			if click_start_position.distance_to(event.position) < 5.0:  # Small threshold for click detection
				equip_item(item)
				accept_event()

func drop_item_in_world(item: InventoryItem) -> void:
	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return

	# Get the player
	var player = inventory_ui.get_parent().get_parent()
	if not player:
		return

	# Unequip the item if it's currently equipped
	if item.is_equipped:
		item.is_equipped = false
		# Clear player's equipped references
		if player.equipped_item == item:
			player.equipped_item = null
		if player.equipped_weapon_item == item:
			# Call on_unequip for weapons to save state
			if player.equipped_weapon and player.equipped_weapon.has_method("on_unequip"):
				player.equipped_weapon.on_unequip()
			# Remove the weapon node
			if player.equipped_weapon:
				player.equipped_weapon.queue_free()
				player.equipped_weapon = null
			player.equipped_weapon_item = null
		print("Unequipped item before dropping: ", item.item_name)

	# Remove item from inventory
	manager.remove_item(item)
	inventory_ui.refresh_display()

	# Spawn the item in the world in front of the player
	var item_scene: PackedScene = null
	match item.item_id:
		"flashlight_01":
			item_scene = load("res://pickup_flashlight.tscn")
		"medkit_01":
			item_scene = load("res://pickup_medkit.tscn")
		"bandage_01":
			item_scene = load("res://pickup_bandage.tscn")
		"shotgun_01":
			item_scene = load("res://pickup_shotgun.tscn")
		"axe_01":
			item_scene = load("res://pickup_axe.tscn")
		"knife_01":
			item_scene = load("res://pickup_knife.tscn")
		"rifle_01":
			item_scene = load("res://pickup_rifle.tscn")
		"pistol_01":
			item_scene = load("res://pickup_pistol.tscn")
		"shotgun_shells_01":
			item_scene = load("res://pickup_shotgun_shells.tscn")
		"rifle_ammo_01":
			item_scene = load("res://pickup_rifle_ammo.tscn")
		"pistol_ammo_01":
			item_scene = load("res://pickup_pistol_ammo.tscn")
		"flare_01":
			item_scene = load("res://pickup_flare.tscn")
		"flare_gun_01":
			item_scene = load("res://pickup_flare_gun.tscn")
		"flare_ammo_01":
			item_scene = load("res://pickup_flare_ammo.tscn")
		"binoculars_01":
			item_scene = load("res://pickup_binoculars.tscn")
		"lantern_01":
			item_scene = load("res://pickup_lantern.tscn")
		"bear_pelt_01":
			item_scene = load("res://pickup_bear_pelt.tscn")
		"bear_meat_01":
			item_scene = load("res://pickup_bear_meat.tscn")
		"deer_pelt_01":
			item_scene = load("res://pickup_deer_pelt.tscn")
		"deer_meat_01":
			item_scene = load("res://pickup_deer_meat.tscn")
		"deer_antler_01":
			item_scene = load("res://pickup_deer_antler.tscn")
		"adrenaline_syringe_01":
			item_scene = load("res://pickup_adrenaline_syringe.tscn")
		"antiseptic_01":
			item_scene = load("res://pickup_antiseptic.tscn")
		"pain_killers_01":
			item_scene = load("res://pickup_pain_killers.tscn")
		"battery_01":
			item_scene = load("res://pickup_battery.tscn")
		"lighter_01":
			item_scene = load("res://pickup_lighter.tscn")
		"backpack_01":
			item_scene = load("res://pickup_backpack.tscn")

	if item_scene:
		var item_instance = item_scene.instantiate()

		print("Instantiated pickup scene for: ", item.item_name, " inventory stack: ", item.current_stack)

		# Mark this as dropped from inventory
		if "is_dropped" in item_instance:
			item_instance.is_dropped = true
			print("Marked pickup as dropped from inventory")

		# Preserve stack quantity for stackable items
		if "item_resource" in item_instance and item_instance.item_resource:
			print("Found item_resource in pickup, duplicating and setting stack to: ", item.current_stack)
			# Duplicate the resource so we don't modify the shared .tres file (deep copy)
			item_instance.item_resource = item_instance.item_resource.duplicate(true)
			item_instance.item_resource.current_stack = item.current_stack
			print("Pickup's item_resource.current_stack is now: ", item_instance.item_resource.current_stack)

			# Preserve weapon ammo for guns
			if item.weapon_current_ammo >= 0:
				item_instance.item_resource.weapon_current_ammo = item.weapon_current_ammo
				print("Preserved weapon ammo: ", item.weapon_current_ammo)
		else:
			print("ERROR: No item_resource found in pickup instance!")

		# Add to the world first (required for RigidBody3D to work)
		player.get_parent().add_child(item_instance)

		# Position it in front of the player
		var camera = player.get_node_or_null("Camera3D")
		var drop_position: Vector3
		var drop_velocity: Vector3

		if camera:
			# Drop position in front and slightly below camera
			drop_position = camera.global_position + camera.global_transform.basis.z * -1.5 + Vector3(0, -0.3, 0)
			# Give it a toss forward and slightly down
			drop_velocity = camera.global_transform.basis.z * -3.0 + Vector3(0, -1.0, 0)
		else:
			drop_position = player.global_position + player.global_transform.basis.z * -1.5
			drop_velocity = player.global_transform.basis.z * -3.0 + Vector3(0, -1.0, 0)

		item_instance.global_position = drop_position

		# Apply the velocity to the RigidBody3D
		if item_instance is RigidBody3D:
			item_instance.linear_velocity = drop_velocity
			# Add a slight random rotation for realism
			item_instance.angular_velocity = Vector3(
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0)
			)

func equip_item(item: InventoryItem) -> void:
	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	var player = inventory_ui.get_parent().get_parent()

	if not player:
		return

	# Check if item can be equipped
	if not item.can_be_equipped:
		print("This item cannot be equipped")
		return

	# Check if weapon is currently equipping - prevent rapid clicks during animation
	if player.has_node("Camera3D/FPSArms"):
		var fps_arms = player.get_node("Camera3D/FPSArms")
		if fps_arms and "current_state" in fps_arms:
			# AnimState.EQUIPPING = 9
			if fps_arms.current_state == 9:
				print("Cannot equip/unequip while weapon is equipping")
				return

	# If item is already equipped, unequip it
	if item.is_equipped:
		item.is_equipped = false
		if player.has_method("unequip_item"):
			player.unequip_item(item)
		inventory_ui.refresh_display()
		print("Unequipped: ", item.item_name)
		return

	# Unequip any currently equipped item
	for inv_item in manager.items:
		if inv_item.is_equipped:
			inv_item.is_equipped = false
			if player.has_method("unequip_item"):
				player.unequip_item(inv_item)

	# Equip this item
	item.is_equipped = true
	if player.has_method("equip_item"):
		player.equip_item(item)
	inventory_ui.refresh_display()
	print("Equipped: ", item.item_name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Clear all highlights when drag ends
		if inventory_ui:
			inventory_ui.clear_all_highlights()
		# Reset drag flag
		is_dragging = false

		# Clean up any equipment slot metadata if drag failed
		if inventory_ui and inventory_ui.inventory_manager:
			for item in inventory_ui.inventory_manager.items:
				if item.has_meta("_dragging_from_equipment_slot"):
					item.remove_meta("_dragging_from_equipment_slot")
