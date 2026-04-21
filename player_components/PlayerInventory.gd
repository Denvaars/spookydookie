class_name PlayerInventory
extends Node

## Handles equipped items, weapons, item usage, and pickup interactions
## Moderate complexity - depends on PlayerHealth and PlayerAudio

# Signals
signal weapon_equipped(weapon_type: String)
signal weapon_unequipped()
signal item_equipped(item: InventoryItem)
signal item_unequipped(item: InventoryItem)

# Equipped item state
var equipped_item: InventoryItem = null
var equipped_weapon: Node3D = null
var current_weapon_type: String = ""
var equipped_weapon_item: InventoryItem = null

# Item usage state
var is_using_item: bool = false
var item_use_timer: float = 0.0
var item_use_duration: float = 0.0
var item_being_used: InventoryItem = null

# External dependencies (set by player)
var player_health: PlayerHealth = null
var player_audio: PlayerAudio = null
var interact_raycast: RayCast3D = null
var flashlight: SpotLight3D = null
var inventory_ui: Control = null

# Parent references
var player_node: CharacterBody3D = null
var ui_container: Control = null


func _ready() -> void:
	player_node = get_parent()


func _process(delta: float) -> void:
	# Update item use timer
	if is_using_item:
		item_use_timer += delta
		if item_use_timer >= item_use_duration:
			_complete_item_use()


func _complete_item_use() -> void:
	# Item use complete!
	is_using_item = false
	item_use_timer = 0.0

	# Handle completion based on item type
	if item_being_used and item_being_used.item_id == "bandage_01":
		if player_health:
			player_health.heal(25.0)
			print("Bandage applied - healed 25 HP")

		# Handle stackable item consumption
		if inventory_ui:
			var manager: InventoryManager = inventory_ui.inventory_manager
			if manager:
				item_being_used.is_equipped = false

				# Decrease stack count instead of removing entire item
				if item_being_used.stackable and item_being_used.current_stack > 1:
					item_being_used.current_stack -= 1
					print("Bandages remaining: %d" % item_being_used.current_stack)
				else:
					# Last one in stack, remove entirely
					manager.remove_item(item_being_used)
					equipped_item = null
					print("Used last bandage")

				inventory_ui.refresh_display()

	item_being_used = null


## Try to pick up an item using interact raycast
func try_pickup_item() -> void:
	if not interact_raycast:
		return

	if interact_raycast.is_colliding():
		var collider = interact_raycast.get_collider()

		# Check for pickups
		if collider and collider.is_in_group("pickup"):
			if collider.has_method("pickup"):
				collider.pickup(player_node)

		# Check for interactables (perk statue, etc)
		elif collider and collider.is_in_group("interactable"):
			if collider.has_method("interact"):
				collider.interact(player_node)


## Equip a weapon by type
func equip_weapon(weapon_type: String, item: InventoryItem = null) -> void:
	# Unequip current weapon first
	if equipped_weapon:
		# Call on_unequip to save state and hide model
		if equipped_weapon.has_method("on_unequip"):
			equipped_weapon.on_unequip()

		# Hide ammo UI
		if ui_container:
			var ammo_label = ui_container.get_node_or_null("AmmoLabel")
			if ammo_label:
				ammo_label.visible = false

		equipped_weapon.queue_free()
		equipped_weapon = null

	# Store the item reference
	equipped_weapon_item = item
	equipped_item = item  # Also store in equipped_item for consistency

	# Load the appropriate weapon script
	var weapon_script = null
	match weapon_type:
		"shotgun":
			weapon_script = load("res://shotgun.gd")
		"rifle":
			weapon_script = load("res://rifle.gd")
		"pistol":
			weapon_script = load("res://pistol.gd")
		"axe":
			weapon_script = load("res://axe.gd")
		"knife":
			weapon_script = load("res://knife.gd")
		"flare":
			weapon_script = load("res://flare.gd")
		"flare_gun":
			weapon_script = load("res://flare_gun.gd")
		"binoculars":
			weapon_script = load("res://binoculars.gd")
		"flashlight":
			weapon_script = load("res://flashlight.gd")
		"lantern":
			weapon_script = load("res://lantern.gd")
		"lighter":
			weapon_script = load("res://lighter.gd")
		_:
			print("Unknown weapon type: ", weapon_type)
			return

	# Create and equip the weapon
	equipped_weapon = Node3D.new()
	equipped_weapon.set_script(weapon_script)
	equipped_weapon.name = weapon_type.capitalize()
	player_node.add_child(equipped_weapon)
	current_weapon_type = weapon_type

	print(weapon_type.capitalize(), " equipped!")
	weapon_equipped.emit(weapon_type)


## Unequip current weapon
func unequip_weapon() -> void:
	if equipped_weapon:
		# Call on_unequip to save state and hide model
		if equipped_weapon.has_method("on_unequip"):
			equipped_weapon.on_unequip()

		# Hide ammo UI
		if ui_container:
			var ammo_label = ui_container.get_node_or_null("AmmoLabel")
			if ammo_label:
				ammo_label.visible = false

		equipped_weapon.queue_free()
		equipped_weapon = null
		current_weapon_type = ""
		equipped_weapon_item = null
		print("Weapon unequipped")
		weapon_unequipped.emit()


## Equip an item
func equip_item(item: InventoryItem) -> void:
	# Unequip any currently equipped item first
	if equipped_item:
		# Properly unequip the old item (handles flashlight turning off, etc.)
		unequip_item(equipped_item)
		equipped_item.is_equipped = false

	# Handle different item types
	match item.item_id:
		"shotgun_01":
			equip_weapon("shotgun", item)
		"rifle_01":
			equip_weapon("rifle", item)
		"pistol_01":
			equip_weapon("pistol", item)
		"axe_01":
			equip_weapon("axe", item)
		"knife_01":
			equip_weapon("knife", item)
		"flare_01":
			equip_weapon("flare", item)
		"flare_gun_01":
			equip_weapon("flare_gun", item)
		"binoculars_01":
			equip_weapon("binoculars", item)
		"flashlight_01":
			equip_weapon("flashlight", item)
		"lantern_01":
			equip_weapon("lantern", item)
		"lighter_01":
			equip_weapon("lighter", item)
		_:
			# For non-weapon items, just store the reference
			equipped_item = item
			print("Equipped: ", item.item_name)
			item_equipped.emit(item)


## Unequip an item
func unequip_item(item: InventoryItem) -> void:
	# Handle different item types
	match item.item_id:
		"shotgun_01", "rifle_01", "pistol_01", "axe_01", "knife_01", "flare_01", "flare_gun_01", "binoculars_01", "flashlight_01", "lantern_01", "lighter_01":
			# Unequip weapon
			if equipped_weapon and equipped_weapon_item == item:
				if equipped_weapon:
					# Save weapon state and hide model
					if equipped_weapon.has_method("on_unequip"):
						equipped_weapon.on_unequip()

					# Hide ammo UI
					if ui_container:
						var ammo_label = ui_container.get_node_or_null("AmmoLabel")
						if ammo_label:
							ammo_label.visible = false

					equipped_weapon.queue_free()
					equipped_weapon = null
					current_weapon_type = ""
					equipped_weapon_item = null
					print("Weapon unequipped")
					weapon_unequipped.emit()
		"flashlight_01":
			# Turn off flashlight when unequipping
			if flashlight and flashlight.visible:
				flashlight.visible = false
				if player_audio:
					player_audio.play_flashlight_toggle(false)
			if equipped_item == item:
				equipped_item = null
				print("Unequipped flashlight")
				item_unequipped.emit(item)
		_:
			# For non-weapon items
			if equipped_item == item:
				equipped_item = null
				print("Unequipped: ", item.item_name)
				item_unequipped.emit(item)


## Use the currently equipped item
func use_equipped_item() -> void:
	if not equipped_item:
		return

	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return

	# Handle different item types
	match equipped_item.item_id:
		"medkit_01":
			# Heal player
			if player_health:
				player_health.heal(75.0)
				print("Used medkit - healed 75 HP")
			# Unequip and handle stack
			equipped_item.is_equipped = false

			# Decrease stack count or remove entirely
			if equipped_item.stackable and equipped_item.current_stack > 1:
				equipped_item.current_stack -= 1
				print("Medkits remaining: %d" % equipped_item.current_stack)
			else:
				manager.remove_item(equipped_item)
				equipped_item = null
				print("Used last medkit")

			inventory_ui.refresh_display()

		"bandage_01":
			# Start using bandage (2.5 second delay)
			if not is_using_item:
				is_using_item = true
				item_use_timer = 0.0
				item_use_duration = 2.5
				item_being_used = equipped_item
				print("Using bandage... (2.5 seconds)")
				# Play bandage use sound
				if player_audio:
					player_audio.play_bandage_use()
			else:
				print("Already using an item!")

		"shotgun_shells_01", "rifle_ammo_01", "pistol_ammo_01":
			# Ammo is no longer consumed on use - it stays in inventory
			# Weapons will consume it directly when reloading
			print("Ammo is ready to use - reload your weapon when needed!")
			equipped_item.is_equipped = false
			equipped_item = null

		"flashlight_01":
			# Toggle flashlight
			if flashlight:
				flashlight.visible = not flashlight.visible
				if player_audio:
					player_audio.play_flashlight_toggle(flashlight.visible)
				if flashlight.visible:
					print("Flashlight turned on")
				else:
					print("Flashlight turned off")

		"adrenaline_syringe_01":
			# Activate adrenaline (infinite stamina + 10% speed boost for 10 seconds)
			if player_health:
				player_health.activate_adrenaline(10.0)
				print("Used adrenaline syringe - infinite stamina and speed boost for 10 seconds!")
			# Unequip and handle stack
			equipped_item.is_equipped = false

			# Decrease stack count or remove entirely
			if equipped_item.stackable and equipped_item.current_stack > 1:
				equipped_item.current_stack -= 1
				print("Adrenaline syringes remaining: %d" % equipped_item.current_stack)
			else:
				manager.remove_item(equipped_item)
				equipped_item = null
				print("Used last adrenaline syringe")

			inventory_ui.refresh_display()

		"antiseptic_01":
			# Stop bleeding
			if player_health:
				if player_health.current_bleed_damage > 0.0:
					player_health.reduce_bleed(player_health.current_bleed_damage)  # Clear all bleed
					print("Used antiseptic - bleeding stopped!")
				else:
					print("Used antiseptic - no bleeding to stop")
			# Unequip and handle stack
			equipped_item.is_equipped = false

			# Decrease stack count or remove entirely
			if equipped_item.stackable and equipped_item.current_stack > 1:
				equipped_item.current_stack -= 1
				print("Antiseptic bottles remaining: %d" % equipped_item.current_stack)
			else:
				manager.remove_item(equipped_item)
				equipped_item = null
				print("Used last antiseptic")

			inventory_ui.refresh_display()

		"pain_killers_01":
			# Restore 30 sanity
			if player_health:
				player_health.change_sanity(30.0)
				print("Used pain killers - restored 30 sanity")
			# Unequip and handle stack
			equipped_item.is_equipped = false

			# Decrease stack count or remove entirely
			if equipped_item.stackable and equipped_item.current_stack > 1:
				equipped_item.current_stack -= 1
				print("Pain killer bottles remaining: %d" % equipped_item.current_stack)
			else:
				manager.remove_item(equipped_item)
				equipped_item = null
				print("Used last pain killers")

			inventory_ui.refresh_display()

		_:
			print("Used item: ", equipped_item.item_name)


## Check if weapon is currently aiming
func is_weapon_aiming() -> bool:
	if equipped_weapon and "is_aiming" in equipped_weapon:
		return equipped_weapon.is_aiming
	return false


## Check if weapon is currently reloading
func is_weapon_reloading() -> bool:
	if equipped_weapon and "is_reloading" in equipped_weapon:
		return equipped_weapon.is_reloading
	return false


## Get the equipped weapon's aim FOV (for camera)
func get_weapon_aim_fov() -> float:
	if equipped_weapon and "aim_fov" in equipped_weapon:
		return equipped_weapon.aim_fov
	return 0.0
