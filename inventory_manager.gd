class_name InventoryManager
extends Node

## Manages the inventory grid and item placement
## Handles placement validation, collision detection, and item storage

const GRID_WIDTH: int = 8
const GRID_HEIGHT: int = 6

var current_grid_width: int = GRID_WIDTH  # Can be expanded with backpacks
var grid: Array[Array] = []
var items: Array[InventoryItem] = []

func _init() -> void:
	# Initialize grid
	_resize_grid(GRID_WIDTH, GRID_HEIGHT)

func _resize_grid(width: int, height: int) -> void:
	var old_width = current_grid_width
	var old_height = len(grid) if len(grid) > 0 else GRID_HEIGHT

	# If expanding width only, keep all items in place and just expand the grid
	if width > old_width and height == old_height:
		# Simply expand each row
		for y in range(len(grid)):
			grid[y].resize(width)
			for x in range(old_width, width):
				grid[y][x] = null

		current_grid_width = width
		print("Expanded grid from %d to %d columns, all items kept in place" % [old_width, width])
		return

	# For shrinking width, only move items that are cut off, keep others in place
	if width < old_width and height == old_height:
		# Find items that need to be moved (any part beyond new width)
		var items_to_move: Array[Dictionary] = []
		for item in items:
			if item.is_placed():
				var rightmost_column = item.grid_x + item.grid_width - 1
				if rightmost_column >= width:
					# This item extends into columns that will be removed
					items_to_move.append({
						"item": item,
						"x": item.grid_x,
						"y": item.grid_y
					})
					remove_item(item)

		# Shrink the grid
		for y in range(len(grid)):
			grid[y].resize(width)

		current_grid_width = width

		# Try to place moved items back
		for stored in items_to_move:
			var item: InventoryItem = stored["item"]
			var placed = false

			# Try to find any available space
			for try_y in range(height):
				for try_x in range(width):
					if can_place_item(item, try_x, try_y):
						place_item(item, try_x, try_y)
						placed = true
						break
				if placed:
					break

			if not placed:
				print("WARNING: Could not re-place item after grid shrink: ", item.item_name)

		print("Shrunk grid from %d to %d columns, moved %d items" % [old_width, width, items_to_move.size()])
		return

	# For height changes or other complex resizes, do full rebuild
	# Store items temporarily
	var stored_items: Array[Dictionary] = []
	for item in items:
		if item.is_placed():
			stored_items.append({
				"item": item,
				"x": item.grid_x,
				"y": item.grid_y
			})
			remove_item(item)

	# Resize grid
	grid.clear()
	grid.resize(height)
	for y in range(height):
		grid[y] = []
		grid[y].resize(width)
		for x in range(width):
			grid[y][x] = null

	current_grid_width = width

	# Try to restore items
	for stored in stored_items:
		var item: InventoryItem = stored["item"]
		var x: int = stored["x"]
		var y: int = stored["y"]

		# Try original position first
		if can_place_item(item, x, y):
			place_item(item, x, y)
		else:
			# Find any available space
			var placed = false
			for try_y in range(height):
				for try_x in range(width):
					if can_place_item(item, try_x, try_y):
						place_item(item, try_x, try_y)
						placed = true
						break
				if placed:
					break

			if not placed:
				print("WARNING: Could not re-place item after grid resize: ", item.item_name)

func set_grid_width(width: int) -> void:
	if width != current_grid_width:
		_resize_grid(width, GRID_HEIGHT)

func can_place_item(item: InventoryItem, x: int, y: int) -> bool:
	# Check bounds
	if x < 0 or y < 0:
		return false
	if x + item.grid_width > current_grid_width or y + item.grid_height > GRID_HEIGHT:
		return false

	# Check for overlapping items
	for dy in range(item.grid_height):
		for dx in range(item.grid_width):
			var cell = grid[y + dy][x + dx]
			# If cell is occupied by a different item, can't place
			if cell != null and cell != item:
				return false

	return true

func place_item(item: InventoryItem, x: int, y: int) -> bool:
	if not can_place_item(item, x, y):
		return false

	# Remove item from old position if it was placed
	if item.is_placed():
		remove_item(item)

	# Place item in new position
	item.grid_x = x
	item.grid_y = y

	# Mark all cells occupied by this item
	for dy in range(item.grid_height):
		for dx in range(item.grid_width):
			grid[y + dy][x + dx] = item

	# Add to items list if not already there
	if not items.has(item):
		items.append(item)

	return true

func remove_item(item: InventoryItem) -> void:
	if not item.is_placed():
		return

	# Clear all cells occupied by this item
	for dy in range(item.grid_height):
		for dx in range(item.grid_width):
			if grid[item.grid_y + dy][item.grid_x + dx] == item:
				grid[item.grid_y + dy][item.grid_x + dx] = null

	# Reset item position
	item.grid_x = -1
	item.grid_y = -1

	# Remove from items list
	items.erase(item)

func get_item_at(x: int, y: int) -> InventoryItem:
	if x < 0 or y < 0 or x >= current_grid_width or y >= GRID_HEIGHT:
		return null
	return grid[y][x]

func get_grid_size() -> Vector2i:
	return Vector2i(current_grid_width, GRID_HEIGHT)

func get_total_weight() -> float:
	var total_weight: float = 0.0
	for item in items:
		if item.stackable:
			total_weight += item.weight * item.current_stack
		else:
			total_weight += item.weight
	return total_weight

func clear() -> void:
	for item in items.duplicate():
		remove_item(item)
	items.clear()
