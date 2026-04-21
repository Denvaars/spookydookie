extends LootTable

## Survival Gear Loot Table
## Contains weapons, ammo, flares, and tools

func _init():
	table_name = "Survival Gear"

func get_loot_entries() -> Array[LootEntry]:
	var entries: Array[LootEntry] = []

	# Pistol Ammo - Very Common (90% chance, 1-2 boxes)
	entries.append(LootEntry.new("res://pickup_pistol_ammo.tscn", 0.9, 1, 2))

	# Shotgun Shells - Common (60% chance, 1 box)
	entries.append(LootEntry.new("res://pickup_shotgun_shells.tscn", 0.6, 1, 1))

	# Flares - Common (70% chance, 1-2 flares)
	entries.append(LootEntry.new("res://pickup_flare.tscn", 0.7, 1, 2))

	# Flare Gun - Rare (20% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_flare_gun.tscn", 0.2, 1, 1))

	# Flare Ammo - Uncommon (50% chance, 1-2 items)
	entries.append(LootEntry.new("res://pickup_flare_ammo.tscn", 0.5, 1, 2))

	# Axe - Rare (25% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_axe.tscn", 0.25, 1, 1))

	# Knife - Uncommon (40% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_knife.tscn", 0.4, 1, 1))

	return entries
