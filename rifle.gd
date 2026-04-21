extends Node3D

## Hunting rifle weapon system
## Bolt-action rifle with high damage and accuracy

# Rifle settings
@export var damage: float = 60.0
@export var max_range: float = 100.0
@export var fire_rate: float = 1.2  # Time between shots (bolt action)
@export var reload_time: float = 2.0
@export var max_ammo: int = 5
@export var aim_fov: float = 50.0  # More zoom for rifle
@export var normal_fov: float = 75.0

# Ammo variables
var current_ammo: int = 5
var is_reloading: bool = false
var can_shoot: bool = true
var time_since_shot: float = 0.0
var ammo_item_id: String = "rifle_ammo_01"
var ammo_per_stack: int = 5  # Matches magazine size

# Aiming
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var ammo_label: Label

# Audio
var shoot_sound: AudioStreamPlayer

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Restore ammo from inventory item if available
	if player.equipped_weapon_item and player.equipped_weapon_item.weapon_current_ammo >= 0:
		current_ammo = player.equipped_weapon_item.weapon_current_ammo
		print("Restored rifle ammo: %d/%d" % [current_ammo, max_ammo])

	# Create visual model (long thin box for rifle)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.08, 0.12, 1.0)  # Long rifle
	mesh_instance.mesh = box_mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.2, 0.1)  # Dark brown
	mesh_instance.material_override = material

	# Position it in front of camera
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.25, -0.2, -0.6)
		mesh_instance.rotation_degrees = Vector3(-5, 0, 0)

	# Setup shoot sound
	shoot_sound = AudioStreamPlayer.new()
	shoot_sound.stream = load("res://audio/rifle_shoot.wav")
	add_child(shoot_sound)

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

	# Handle aiming weapon position (FOV is controlled by player)
	if mesh_instance:
		# Move weapon when aiming
		var target_pos = Vector3(0.1, -0.1, -0.5) if is_aiming else Vector3(0.25, -0.2, -0.6)
		mesh_instance.position = mesh_instance.position.lerp(target_pos, 6.0 * delta)

	# Update ammo UI every frame to keep reserve count accurate
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
		print("Out of ammo! Press R to reload")
		return

	current_ammo -= 1
	can_shoot = false
	print("Rifle shot! Ammo: ", current_ammo, "/", max_ammo)

	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

	# Alert enemies to gunshot
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if forest and "alert_system" in forest:
		var alert_system = forest.alert_system
		if alert_system:
			alert_system.alert_weapon_fire(player.global_position, "rifle")

	# Fire single bullet
	fire_bullet()

	# Update ammo UI
	update_ammo_ui()

func fire_bullet() -> void:
	if not camera:
		return

	# Perfectly accurate shot (no spread for rifle)
	var direction = camera.global_transform.basis.z * -1.0

	# Perform raycast
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position + direction * max_range
	)
	query.collision_mask = 3  # Hit world (layer 1) and enemies (layer 2)

	var result = space_state.intersect_ray(query)
	if result:
		# Hit something
		var hit_object = result.collider
		print("Rifle hit: ", hit_object.name, " at ", result.position)

		# Apply damage
		if hit_object.has_method("take_damage"):
			hit_object.take_damage(damage)

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
		print("No rifle ammo in inventory!")
		return

	is_reloading = true
	print("Reloading rifle...")
	update_ammo_ui()

	# Calculate ammo to reload
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_reload = min(ammo_needed, ammo_in_inventory)

	# Wait for reload time
	await get_tree().create_timer(reload_time).timeout

	# Consume ammo from inventory (individual bullets from stacks)
	var ammo_still_needed: int = ammo_to_reload

	for item in ammo_items:
		if ammo_still_needed <= 0:
			break

		# Take bullets from this stack
		var bullets_from_stack = min(ammo_still_needed, item.current_stack)
		item.current_stack -= bullets_from_stack
		ammo_still_needed -= bullets_from_stack

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
		print("Saved rifle ammo: %d/%d" % [current_ammo, max_ammo])
