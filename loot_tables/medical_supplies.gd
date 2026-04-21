extends LootTable

## Medical Supplies Loot Table
## Contains bandages, medkits, and batteries

func _init():
	table_name = "Medical Supplies"

func get_loot_entries() -> Array[LootEntry]:
	var entries: Array[LootEntry] = []

	# Bandages - Common (80% chance, 1-2 items)
	entries.append(LootEntry.new("res://pickup_bandage.tscn", 0.8, 1, 2))

	# Medkit - Uncommon (40% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_medkit.tscn", 0.4, 1, 1))

	# Batteries - Common (70% chance, 1-3 items)
	entries.append(LootEntry.new("res://pickup_battery.tscn", 0.7, 1, 3))

	# Pain Killers - Common (60% chance, 1-2 items)
	entries.append(LootEntry.new("res://pickup_pain_killers.tscn", 0.6, 1, 2))

	# Antiseptic - Uncommon (40% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_antiseptic.tscn", 0.4, 1, 1))

	# Adrenaline Syringe - Rare (20% chance, 1 item)
	entries.append(LootEntry.new("res://pickup_adrenaline_syringe.tscn", 0.2, 1, 1))

	return entries
