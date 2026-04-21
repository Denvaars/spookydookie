extends Node

## Centralized Loot Tables Registry
## Contains all loot table definitions in one place
## Access via: LootTablesRegistry.get_table("table_name")

class_name LootTablesRegistry

# Loot entry structure
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

# Define all loot tables here
static func get_table(table_name: String) -> Array[LootEntry]:
	match table_name:
		"medical_supplies":
			return get_medical_supplies()
		"survival_gear":
			return get_survival_gear()
		"camping_supplies":
			return get_camping_supplies()
		_:
			push_warning("LootTablesRegistry: Unknown loot table '%s'" % table_name)
			return []

# Roll a loot table and return spawnable items
static func roll_loot(table_name: String) -> Array[PackedScene]:
	var spawned_items: Array[PackedScene] = []
	var entries = get_table(table_name)

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
				push_warning("LootTablesRegistry: Failed to load item at path: %s" % entry.item_scene_path)

	return spawned_items

## MEDICAL SUPPLIES
## Contains bandages, medkits, and medical items
static func get_medical_supplies() -> Array[LootEntry]:
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

## SURVIVAL GEAR
## Contains weapons, ammo, flares, and tools
static func get_survival_gear() -> Array[LootEntry]:
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

## CAMPING SUPPLIES
## Contains flashlights, lanterns, binoculars, and camping gear
static func get_camping_supplies() -> Array[LootEntry]:
	var entries: Array[LootEntry] = []

	# Flashlight - Common (60% chance)
	entries.append(LootEntry.new("res://pickup_flashlight.tscn", 0.6, 1, 1))

	# Lighter - Common (60% chance)
	entries.append(LootEntry.new("res://pickup_lighter.tscn", 0.6, 1, 1))

	# Binoculars - Uncommon (30% chance)
	entries.append(LootEntry.new("res://pickup_binoculars.tscn", 0.3, 1, 1))

	# Lantern - Common (60% chance)
	entries.append(LootEntry.new("res://pickup_lantern.tscn", 0.6, 1, 1))

	# Knife - Uncommon (40% chance)
	entries.append(LootEntry.new("res://pickup_knife.tscn", 0.4, 1, 1))

	return entries
