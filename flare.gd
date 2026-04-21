extends Node3D

## Handheld flare system
## Lights up area with red light, burns for 60 seconds, can be thrown

# Flare settings
@export var burn_duration: float = 60.0
@export var light_intensity: float = 5.0
@export var light_range: float = 15.0
@export var throw_force: float = 10.0
@export var aim_fov: float = 65.0
@export var normal_fov: float = 75.0

# Flare state
var is_lit: bool = false
var burn_time_remaining: float = 0.0
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var flare_light: OmniLight3D
var burn_sound: AudioStreamPlayer
var flare_item: InventoryItem = null  # Reference to the inventory item

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Get the inventory item reference to preserve state
	if player.equipped_weapon_item:
		flare_item = player.equipped_weapon_item

		# Restore state if flare was already lit
		if flare_item.flare_is_lit:
			is_lit = true
			burn_time_remaining = flare_item.flare_burn_time

	# Create visual model (cylinder for flare)
	mesh_instance = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.02
	cylinder_mesh.bottom_radius = 0.02
	cylinder_mesh.height = 0.15
	mesh_instance.mesh = cylinder_mesh

	# Create material for the flare
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.1, 0.1)  # Red
	material.emission_enabled = false  # Will enable when lit
	material.emission = Color(1.0, 0.1, 0.1)
	material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material

	# Position it in front of camera (held in hand)
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.2, -0.2, -0.3)
		mesh_instance.rotation_degrees = Vector3(0, 0, 90)  # Horizontal

	# Create omni light (starts disabled)
	flare_light = OmniLight3D.new()
	flare_light.light_color = Color(1.0, 0.2, 0.1)  # Red/orange
	flare_light.omni_range = light_range
	flare_light.light_energy = light_intensity
	flare_light.shadow_enabled = true
	flare_light.visible = false
	if camera:
		camera.add_child(flare_light)
		flare_light.position = Vector3(0.2, -0.2, -0.3)

	# Create burn sound
	burn_sound = AudioStreamPlayer.new()
	burn_sound.stream = load("res://audio/flare_burn.wav")
	burn_sound.volume_db = -5.0
	add_child(burn_sound)

	# If restoring lit state, activate visuals
	if is_lit:
		# Enable emission
		if mesh_instance:
			var mat = mesh_instance.material_override as StandardMaterial3D
			mat.emission_enabled = true
		# Turn on light
		if flare_light:
			flare_light.visible = true
		# Start sound
		if burn_sound:
			burn_sound.play()

func _process(delta: float) -> void:
	# Update burn timer if lit
	if is_lit:
		burn_time_remaining -= delta

		if burn_time_remaining <= 0.0:
			# Flare burned out
			extinguish_flare()

			# Properly unequip and remove from inventory
			if flare_item:
				flare_item.is_equipped = false

			var inventory_ui = player.get_node_or_null("UI/InventoryUI")
			if inventory_ui and inventory_ui.inventory_manager:
				# Find this flare item and remove it
				for item in inventory_ui.inventory_manager.items:
					if item.item_id == "flare_01" and item == flare_item:
						inventory_ui.inventory_manager.remove_item(item)
						break
				inventory_ui.refresh_display()

			# Clean up visual mesh and light
			if mesh_instance:
				mesh_instance.queue_free()
				mesh_instance = null
			if flare_light:
				flare_light.queue_free()
				flare_light = null

			# Stop and clean up sound
			if burn_sound:
				burn_sound.stop()

			# Clear player's equipped references
			player.equipped_item = null
			player.equipped_weapon = null
			player.equipped_weapon_item = null
			player.current_weapon_type = ""

			# Remove the weapon node
			queue_free()

	# Handle aiming position
	if mesh_instance:
		var target_pos = Vector3(0.0, -0.1, -0.25) if is_aiming else Vector3(0.2, -0.2, -0.3)
		mesh_instance.position = mesh_instance.position.lerp(target_pos, 8.0 * delta)
		if flare_light:
			flare_light.position = mesh_instance.position

	# Flicker effect when lit
	if is_lit and flare_light:
		# Add subtle flickering
		var flicker = randf_range(0.9, 1.1)
		flare_light.light_energy = light_intensity * flicker

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Light the flare on first use (left click)
	if event.is_action_pressed("shoot") and not is_lit:
		light_flare()

	# Throw the flare if already lit (left click)
	elif event.is_action_pressed("shoot") and is_lit:
		throw_flare()

	# Aim with right click (only works when lit)
	if is_lit:
		if event.is_action_pressed("aim"):
			is_aiming = true
			if camera:
				# Smoothly zoom in FOV
				var tween = create_tween()
				tween.tween_property(camera, "fov", aim_fov, 0.2)
		elif event.is_action_released("aim"):
			is_aiming = false
			if camera:
				# Smoothly zoom out FOV
				var tween = create_tween()
				tween.tween_property(camera, "fov", normal_fov, 0.2)

func light_flare() -> void:
	is_lit = true
	burn_time_remaining = burn_duration

	# Enable emission on mesh
	if mesh_instance:
		var material = mesh_instance.material_override as StandardMaterial3D
		material.emission_enabled = true

	# Turn on light
	if flare_light:
		flare_light.visible = true

	# Start burn sound loop
	if burn_sound:
		burn_sound.play()

	print("Flare lit! Burns for ", burn_duration, " seconds")

func extinguish_flare() -> void:
	is_lit = false
	burn_time_remaining = 0.0

	# Disable emission
	if mesh_instance:
		var mat = mesh_instance.material_override as StandardMaterial3D
		if mat:
			mat.emission_enabled = false

	# Turn off light
	if flare_light:
		flare_light.visible = false

	# Stop burn sound
	if burn_sound and burn_sound.playing:
		burn_sound.stop()

	print("Flare burned out")

func throw_flare() -> void:
	if not is_lit:
		return

	print("Throwing flare!")

	# Create thrown flare object
	var thrown_flare_scene = load("res://thrown_flare.tscn")
	if not thrown_flare_scene:
		print("ERROR: thrown_flare.tscn not found!")
		return

	var thrown_flare = thrown_flare_scene.instantiate()

	# Add to world
	player.get_parent().add_child(thrown_flare)

	# Position at camera
	if camera:
		thrown_flare.global_position = camera.global_position + camera.global_transform.basis.z * -0.5

		# Give it velocity
		var throw_direction = camera.global_transform.basis.z * -1.0
		if thrown_flare is RigidBody3D:
			thrown_flare.linear_velocity = throw_direction * throw_force

	# Transfer burn time to thrown flare
	if "burn_time_remaining" in thrown_flare:
		thrown_flare.burn_time_remaining = burn_time_remaining
		print("Transferred ", burn_time_remaining, " seconds to thrown flare")

	# Properly unequip and remove from inventory
	if flare_item:
		flare_item.is_equipped = false

	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if inventory_ui and inventory_ui.inventory_manager:
		for item in inventory_ui.inventory_manager.items:
			if item.item_id == "flare_01" and item == flare_item:
				inventory_ui.inventory_manager.remove_item(item)
				break
		inventory_ui.refresh_display()

	# Clean up visual mesh and light
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if flare_light:
		flare_light.queue_free()
		flare_light = null

	# Stop and clean up sound
	if burn_sound:
		burn_sound.stop()

	# Clear player's equipped references
	player.equipped_item = null
	player.equipped_weapon = null
	player.equipped_weapon_item = null
	player.current_weapon_type = ""

	# Remove this weapon node
	queue_free()

# Called when flare is unequipped
func on_unequip() -> void:
	# Save state to inventory item
	if flare_item:
		flare_item.flare_is_lit = is_lit
		flare_item.flare_burn_time = burn_time_remaining

	# Turn off light and sound
	if flare_light:
		flare_light.visible = false
	if burn_sound and burn_sound.playing:
		burn_sound.stop()
