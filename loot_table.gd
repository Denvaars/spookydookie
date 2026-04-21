class_name LootTable
extends Resource

## Loot table defines what items can spawn and their probabilities
## Override get_loot_entries() in child classes to define items

var table_name: String = "Loot Table"

# Simple loot entry structure
class LootEntry:
	var item_scene_path: String = ""
	var spawn_chance: float = 1.0
	var min_quantity: int = 1
	var max_quantity: int = 1

	func _init(path: String, chance: float, min_qty: int = 1, max_qty: int = 1):
		item_scene_path = path
		spawn_chance = chance
		min_quantity = min_qty
		max_quantity = max_qty

## Override this function in child classes to define loot
func get_loot_entries() -> Array[LootEntry]:
	return []

## Roll the loot table and return an array of item scenes to spawn
func roll_loot() -> Array[PackedScene]:
	var spawned_items: Array[PackedScene] = []
	var entries = get_loot_entries()

	for entry in entries:
		# Check if this entry should spawn based on probability
		var roll = randf()
		if roll <= entry.spawn_chance:
			# Determine quantity
			var quantity = randi_range(entry.min_quantity, entry.max_quantity)

			# Load the item scene
			var item_scene = load(entry.item_scene_path)
			if item_scene:
				for i in range(quantity):
					spawned_items.append(item_scene)
			else:
				push_warning("LootTable '%s': Failed to load item at path: %s" % [table_name, entry.item_scene_path])

	return spawned_items
