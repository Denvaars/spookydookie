extends Panel

## Equipment slot for armor, clothing, and accessories
## Only accepts items with matching equipment_slot type

const SLOT_SIZE: int = 80

var slot_type: InventoryItem.EquipmentSlot
var slot_name: String = ""
var inventory_ui: Control = null
var equipped_item: InventoryItem = null

@onready var background: ColorRect = $Background
@onready var item_icon: TextureRect = $ItemIcon
@onready var highlight: ColorRect = $Highlight
@onready var slot_label: Label = $SlotLabel

func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	background.color = Color(0.12, 0.12, 0.14, 0.9)
	highlight.color = Color(0, 0, 0, 0)  # Transparent by default
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_slot_type: InventoryItem.EquipmentSlot, p_slot_name: String, p_inventory_ui: Control) -> void:
	slot_type = p_slot_type
	slot_name = p_slot_name
	inventory_ui = p_inventory_ui
	slot_label.text = p_slot_name

func update_display() -> void:
	if equipped_item:
		if equipped_item.icon:
			item_icon.texture = equipped_item.icon
			item_icon.visible = true
			slot_label.visible = false
			background.color = Color(0.2, 0.5, 0.7, 0.9)  # Blue when equipped
		else:
			item_icon.visible = false
			slot_label.text = equipped_item.item_name
			slot_label.visible = true
			background.color = Color(0.2, 0.5, 0.7, 0.9)  # Blue when equipped
	else:
		item_icon.visible = false
		slot_label.text = slot_name
		slot_label.visible = true
		background.color = Color(0.12, 0.12, 0.14, 0.9)  # Dark when empty

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is InventoryItem:
		return false

	var item: InventoryItem = data as InventoryItem

	# Check if item matches this slot type
	if item.equipment_slot != slot_type:
		highlight.color = Color(0.8, 0.2, 0.2, 0.5)  # Red for invalid
		return false

	# Valid equipment
	highlight.color = Color(0.2, 0.8, 0.4, 0.5)  # Green for valid
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is InventoryItem:
		return

	var item: InventoryItem = data as InventoryItem

	# Verify it's the right slot type
	if item.equipment_slot != slot_type:
		return

	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager

	# Check if item came from another equipment slot
	var from_equipment = item.has_meta("_dragging_from_equipment_slot")
	var source_equipment_slot = null
	if from_equipment:
		source_equipment_slot = item.get_meta("_dragging_from_equipment_slot")
		item.remove_meta("_dragging_from_equipment_slot")

	# If there's already an item equipped, swap them
	if equipped_item:
		# Remove from equipment slot first
		var old_item = equipped_item
		equipped_item = null

		# Try to place the old item in the inventory grid
		# Find the position where the dragged item came from
		var placed = false
		if item.is_placed():
			# Try to place at the dragged item's old position
			if manager.place_item(old_item, item.grid_x, item.grid_y):
				placed = true

		if not placed:
			# Find any available space
			placed = try_place_anywhere(manager, old_item)

		if not placed:
			# No space - can't swap, put old item back
			equipped_item = old_item
			inventory_ui.refresh_display()
			print("No space to swap equipment!")
			return

	# Remove new item from inventory grid if it was there
	if item.is_placed():
		manager.remove_item(item)

	# Remove from source equipment slot if it came from there
	if source_equipment_slot and source_equipment_slot != self:
		source_equipment_slot.equipped_item = null
		source_equipment_slot.update_inventory_size()

	# Equip the new item in this slot
	equipped_item = item

	# Clean up drag metadata (successful drop)
	if item.has_meta("_equipment_slot_backup"):
		item.remove_meta("_equipment_slot_backup")

	# Handle backpack inventory expansion
	update_inventory_size()

	inventory_ui.refresh_display()
	print("Equipped %s in %s slot" % [item.item_name, slot_name])

func try_place_anywhere(manager: InventoryManager, item: InventoryItem) -> bool:
	# Try to find any available space for the item
	var grid_size = manager.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if manager.can_place_item(item, x, y):
				return manager.place_item(item, x, y)
	return false

func update_inventory_size() -> void:
	# Update inventory columns based on equipped chest item
	if inventory_ui and inventory_ui.has_method("update_grid_width"):
		var old_item = equipped_item
		var success = inventory_ui.update_grid_width()

		# If grid resize failed (would lose items), restore the equipment
		if not success and old_item and slot_type == InventoryItem.EquipmentSlot.CHEST:
			equipped_item = old_item
			print("Cannot remove backpack - items would be lost! Clear column 9 first.")
			inventory_ui.refresh_display()

func _get_drag_data(at_position: Vector2) -> Variant:
	if not equipped_item:
		return null

	# Store reference to item being dragged (in case drag fails)
	var dragged_item = equipped_item

	# Create drag preview
	var preview: Control
	if dragged_item.icon:
		var tex_rect = TextureRect.new()
		tex_rect.texture = dragged_item.icon
		tex_rect.custom_minimum_size = Vector2(SLOT_SIZE * dragged_item.grid_width, SLOT_SIZE * dragged_item.grid_height)
		tex_rect.modulate = Color(1, 1, 1, 0.7)
		preview = tex_rect
	else:
		var color_rect = ColorRect.new()
		color_rect.color = Color(0.2, 0.5, 0.7, 0.9)
		color_rect.custom_minimum_size = Vector2(SLOT_SIZE * dragged_item.grid_width, SLOT_SIZE * dragged_item.grid_height)

		var label = Label.new()
		label.text = dragged_item.item_name
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(SLOT_SIZE * dragged_item.grid_width, SLOT_SIZE * dragged_item.grid_height)
		color_rect.add_child(label)

		preview = color_rect

	set_drag_preview(preview)

	# Mark that we're dragging from an equipment slot (store original slot)
	dragged_item.set_meta("_dragging_from_equipment_slot", self)
	dragged_item.set_meta("_equipment_slot_backup", self)

	# Return the item as drag data
	return dragged_item

func clear_highlight() -> void:
	highlight.color = Color(0, 0, 0, 0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_highlight()

		# Check if we had an item being dragged from this slot
		# If it still has the backup metadata, the drag failed - restore it
		if inventory_ui and inventory_ui.inventory_manager:
			for item in inventory_ui.inventory_manager.items:
				if item.has_meta("_equipment_slot_backup"):
					var backup_slot = item.get_meta("_equipment_slot_backup")
					if backup_slot == self:
						# Drag failed, item wasn't placed anywhere - restore it
						if not item.is_placed():  # Only restore if not in grid
							equipped_item = item
							print("EquipmentSlot: drag failed, restored item to equipment slot")
						item.remove_meta("_equipment_slot_backup")

		# Clean up any remaining metadata
		if equipped_item and equipped_item.has_meta("_equipment_slot_backup"):
			equipped_item.remove_meta("_equipment_slot_backup")

		# Refresh display
		if inventory_ui:
			inventory_ui.refresh_display()
