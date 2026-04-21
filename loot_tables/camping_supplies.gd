extends LootTable

## Camping Supplies Loot Table
## Contains flashlights, lanterns, binoculars, and camping gear

func _init():
	table_name = "Camping Supplies"

func get_loot_entries() -> Array[LootEntry]:
	var entries: Array[LootEntry] = []

	# Item Name - Rarity (spawn_chance, min_quantity, max_quantity)
	entries.append(LootEntry.new("res://pickup_flashlight.tscn", 0.6, 1, 1))
	entries.append(LootEntry.new("res://pickup_lighter.tscn", 0.6, 1, 1))
	entries.append(LootEntry.new("res://pickup_binoculars.tscn", 0.3, 1, 1))
	entries.append(LootEntry.new("res://pickup_lantern.tscn", 0.6, 1, 1))
	entries.append(LootEntry.new("res://pickup_knife.tscn", 0.4, 1, 1))

	return entries
