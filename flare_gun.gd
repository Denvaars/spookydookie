extends Node3D

## Flare Gun weapon system
## Single-shot flare gun that shoots projectile flares

# Flare gun settings
@export var fire_rate: float = 1.0
@export var reload_time: float = 2.5
@export var max_ammo: int = 1  # Single shot
@export var projectile_speed: float = 30.0
@export var aim_fov: float = 65.0
@export var normal_fov: float = 75.0

# Ammo variables
var current_ammo: int = 1
var is_reloading: bool = false
var can_shoot: bool = true
var time_since_shot: float = 0.0
var ammo_item_id: String = "flare_ammo_01"
var ammo_per_stack: int = 1  # Matches magazine size

# Aiming
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var ammo_label: Label

# Audio
var shoot_sound: AudioStreamPlayer
var equip_sound: AudioStreamPlayer

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Restore ammo from inventory item if available
	if player.equipped_weapon_item and player.equipped_weapon_item.weapon_current_ammo >= 0:
		current_ammo = player.equipped_weapon_item.weapon_current_ammo
		print("Restored flare gun ammo: %d/%d" % [current_ammo, max_ammo])

	# Create visual model (flare gun shape)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.08, 0.15, 0.25)  # Flare gun shape
	mesh_instance.mesh = box_mesh

	# Create material (orange/red plastic)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.3, 0.1)  # Orange/red
	material.roughness = 0.6
	mesh_instance.material_override = material

	# Position it in front of camera (lower right)
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.35, -0.3, -0.4)
		mesh_instance.rotation_degrees = Vector3(-5, 0, 0)

	# Setup shoot sound
	shoot_sound = AudioStreamPlayer.new()
	shoot_sound.stream = load("res://audio/flaregun_shoot.wav")
	add_child(shoot_sound)

	# Setup equip sound and play it
	equip_sound = AudioStreamPlayer.new()
	equip_sound.stream = load("res://audio/flaregun_equip.wav")
	add_child(equip_sound)
	equip_sound.play()

	# Get ammo UI reference
	var ui = player.get_node_or_null("UI")
	if ui:
		ammo_label = ui.get_node_or_null("AmmoLabel")
		update_ammo_ui()

func _process(delta: float) -> void:
	# Update fire rate cooldown
	if not can_shoot:
		time_since_shot += delta
		if time_since_shot >= fire_rate:
			can_shoot = true
			time_since_shot = 0.0

	# Handle aiming weapon position
	if mesh_instance:
		var target_pos = Vector3(0.0, -0.1, -0.35) if is_aiming else Vector3(0.35, -0.3, -0.4)
		mesh_instance.position = mesh_instance.position.lerp(target_pos, 10.0 * delta)

	# Update ammo UI
	update_ammo_ui()

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Shoot
	if event.is_action_pressed("shoot") and can_shoot and not is_reloading:
		shoot()

	# Reload
	if event.is_action_pressed("reload") and current_ammo < max_ammo and not is_reloading:
		reload()

	# Aim down sights
	if event.is_action_pressed("aim"):
		is_aiming = true
	elif event.is_action_released("aim"):
		is_aiming = false

func shoot() -> void:
	if current_ammo <= 0:
		print("Out of flare ammo! Press R to reload")
		return

	current_ammo -= 1
	can_shoot = false
	print("Flare gun shot! Ammo: ", current_ammo, "/", max_ammo)

	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

	# Alert enemies to gunshot
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if forest and "alert_system" in forest:
		var alert_system = forest.alert_system
		if alert_system:
			alert_system.alert_weapon_fire(player.global_position, "flare_gun")

	# Fire projectile
	fire_projectile()

	# Update ammo UI
	update_ammo_ui()

func fire_projectile() -> void:
	if not camera:
		return

	# Load flare projectile scene
	var projectile_scene = load("res://flare_projectile.tscn")
	if not projectile_scene:
		print("ERROR: flare_projectile.tscn not found!")
		return

	var projectile = projectile_scene.instantiate()

	# Add to world
	get_tree().root.add_child(projectile)

	# Position at camera
	projectile.global_position = camera.global_position + camera.global_transform.basis.z * -0.5

	# Give it velocity
	var direction = camera.global_transform.basis.z * -1.0
	if projectile is RigidBody3D:
		projectile.linear_velocity = direction * projectile_speed

	print("Flare projectile fired at speed ", projectile_speed)

func reload() -> void:
	if is_reloading:
		return

	# Check if we have ammo in inventory
	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if not inventory_ui:
		print("No inventory UI found")
		return

	var inventory_manager = inventory_ui.inventory_manager
	if not inventory_manager:
		print("No inventory manager found")
		return

	# Count how many ammo items we have
	var ammo_in_inventory: int = 0
	var ammo_items: Array[InventoryItem] = []
	for item in inventory_manager.items:
		if item.item_id == ammo_item_id:
			ammo_items.append(item)
			ammo_in_inventory += item.current_stack

	if ammo_in_inventory == 0:
		print("No flare ammo in inventory!")
		return

	is_reloading = true
	print("Reloading flare gun...")
	update_ammo_ui()

	# Calculate ammo to reload
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_reload = min(ammo_needed, ammo_in_inventory)

	# Wait for reload time
	await get_tree().create_timer(reload_time).timeout

	# Consume ammo from inventory
	var ammo_still_needed: int = ammo_to_reload

	for item in ammo_items:
		if ammo_still_needed <= 0:
			break

		# Take ammo from this stack
		var ammo_from_stack = min(ammo_still_needed, item.current_stack)
		item.current_stack -= ammo_from_stack
		ammo_still_needed -= ammo_from_stack

		# If stack is empty, remove it
		if item.current_stack <= 0:
			inventory_manager.remove_item(item)

	# Add the reloaded ammo to magazine
	current_ammo += ammo_to_reload

	is_reloading = false
	print("Reload complete! Ammo: ", current_ammo, "/", max_ammo)

	# Update ammo UI and refresh inventory display
	update_ammo_ui()
	var inv_ui = player.get_node_or_null("UI/InventoryUI")
	if inv_ui:
		inv_ui.refresh_display()

func update_ammo_ui() -> void:
	if ammo_label:
		# Count ammo in inventory
		var ammo_in_inventory: int = 0
		var inventory_ui = player.get_node_or_null("UI/InventoryUI")
		if inventory_ui and inventory_ui.inventory_manager:
			for item in inventory_ui.inventory_manager.items:
				if item.item_id == ammo_item_id:
					ammo_in_inventory += item.current_stack

		var reload_text = " [RELOADING]" if is_reloading else ""
		ammo_label.text = str(current_ammo) + " / " + str(ammo_in_inventory) + reload_text
		ammo_label.visible = true

# Called when weapon is unequipped to save state
func on_unequip() -> void:
	if player and player.equipped_weapon_item:
		player.equipped_weapon_item.weapon_current_ammo = current_ammo
		print("Saved flare gun ammo: %d/%d" % [current_ammo, max_ammo])
