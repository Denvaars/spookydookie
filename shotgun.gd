extends Node3D

## Shotgun weapon system
## Handles shooting, reloading, and aiming

# Shotgun settings
@export var damage_per_pellet: float = 8.0
@export var pellet_count: int = 8
@export var spread_angle: float = 0.1  # Spread in radians
@export var max_range: float = 50.0
@export var shoot_duration: float = 0.3  # Time before cock animation plays
@export var cock_duration: float = 0.5  # Time cock animation takes before can shoot again
@export var reload_start_time: float = 0.6  # Time for reload start animation (slowed down for animation)
@export var reload_shell_time: float = 0.8  # Time to insert one shell (slowed down for animation)
@export var reload_end_time: float = 0.5  # Time for reload end animation (slowed down for animation)
@export var max_ammo: int = 8
@export var aim_fov: float = 60.0  # FOV when aiming down sights
@export var normal_fov: float = 75.0

# Ammo variables
var current_ammo: int = 8
var is_reloading: bool = false
var can_shoot: bool = true
var ammo_item_id: String = "shotgun_shells_01"
var ammo_per_stack: int = 8  # Matches magazine size

# Shooting state machine
enum ShootState { IDLE, SHOOTING, COCKING }
var shoot_state: ShootState = ShootState.IDLE
var shoot_timer: float = 0.0

# Reload state machine
enum ReloadState { NONE, START, INSERTING_SHELL, END }
var reload_state: ReloadState = ReloadState.NONE
var reload_timer: float = 0.0
var pending_action_after_reload: String = ""  # "shoot", "aim", "unaim", or ""

# Aiming
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var raycast: RayCast3D

# Audio
var shoot_sound: AudioStreamPlayer
var reload_start_sound: AudioStreamPlayer
var reload_shell_sound: AudioStreamPlayer
var reload_end_sound: AudioStreamPlayer
var ammo_label: Label

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Restore ammo from inventory item if available
	if player.equipped_weapon_item and player.equipped_weapon_item.weapon_current_ammo >= 0:
		current_ammo = player.equipped_weapon_item.weapon_current_ammo
		print("Restored shotgun ammo: %d/%d" % [current_ammo, max_ammo])

	# Show the FPS weapon model
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.show_weapon("shotgun")
	else:
		print("Warning: FPSArms controller not found!")

	# Setup shoot sound
	shoot_sound = AudioStreamPlayer.new()
	shoot_sound.stream = load("res://audio/shotgun_shoot.wav")
	add_child(shoot_sound)

	# Setup reload sounds
	reload_start_sound = AudioStreamPlayer.new()
	reload_start_sound.stream = load("res://audio/shotgun_reload_start.wav")
	add_child(reload_start_sound)

	reload_shell_sound = AudioStreamPlayer.new()
	reload_shell_sound.stream = load("res://audio/shotgun_reload_shell.wav")
	add_child(reload_shell_sound)

	reload_end_sound = AudioStreamPlayer.new()
	reload_end_sound.stream = load("res://audio/shotgun_reload_end.wav")
	add_child(reload_end_sound)

	# Create raycast for shooting
	raycast = RayCast3D.new()
	raycast.enabled = true
	raycast.target_position = Vector3(0, 0, -max_range)
	raycast.collision_mask = 1  # Collide with world
	if camera:
		camera.add_child(raycast)

	# Get ammo UI reference
	var ui = player.get_node_or_null("UI")
	if ui:
		ammo_label = ui.get_node_or_null("AmmoLabel")
		update_ammo_ui()

func _process(delta: float) -> void:
	# Handle shooting state machine
	match shoot_state:
		ShootState.SHOOTING:
			shoot_timer += delta
			if shoot_timer >= shoot_duration:
				# Time to play cock animation
				shoot_state = ShootState.COCKING
				shoot_timer = 0.0
				play_cock_animation()

				# Play cock sounds (reload start and end)
				play_cock_sounds()

		ShootState.COCKING:
			shoot_timer += delta
			if shoot_timer >= cock_duration:
				# Ready to shoot again - tell animation controller to return to idle
				shoot_state = ShootState.IDLE
				shoot_timer = 0.0
				can_shoot = true

				# Tell FPS controller to return to idle/walk
				var fps_controller = get_tree().root.find_child("FPSArms", true, false)
				if fps_controller:
					fps_controller.finish_cocking()

	# Handle reload state machine
	match reload_state:
		ReloadState.START:
			reload_timer += delta
			if reload_timer >= reload_start_time:
				# Start finished, begin inserting shells
				reload_state = ReloadState.INSERTING_SHELL
				reload_timer = 0.0
				insert_shell()

		ReloadState.INSERTING_SHELL:
			reload_timer += delta
			if reload_timer >= reload_shell_time:
				# Shell inserted, check if we need more
				reload_timer = 0.0
				if current_ammo < max_ammo and has_ammo_in_inventory():
					insert_shell()
				else:
					# Done inserting, play end animation
					reload_state = ReloadState.END
					reload_timer = 0.0
					play_reload_end()

		ReloadState.END:
			reload_timer += delta
			if reload_timer >= reload_end_time:
				# Reload complete
				finish_reload()

	# Update ammo UI every frame to keep reserve count accurate
	update_ammo_ui()

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Shoot (can interrupt reload)
	if event.is_action_pressed("shoot"):
		if is_reloading:
			# Cancel reload and queue shoot action
			cancel_reload_with_action("shoot")
		elif can_shoot:
			shoot()

	# Reload
	if event.is_action_pressed("reload") and current_ammo < max_ammo and not is_reloading:
		reload()

	# Aim down sights (can interrupt reload)
	if event.is_action_pressed("aim"):
		if is_reloading:
			# Cancel reload and queue aim action
			cancel_reload_with_action("aim")
		else:
			is_aiming = true
			# Play aim animation
			var fps_controller = get_tree().root.find_child("FPSArms", true, false)
			if fps_controller:
				fps_controller.set_aiming(true)
	elif event.is_action_released("aim"):
		if is_reloading:
			# Cancel reload and queue un-aim action
			cancel_reload_with_action("unaim")
		else:
			is_aiming = false
			# Play idle animation
			var fps_controller = get_tree().root.find_child("FPSArms", true, false)
			if fps_controller:
				fps_controller.set_aiming(false)

func shoot() -> void:
	if current_ammo <= 0:
		print("Out of ammo! Press R to reload")
		return

	current_ammo -= 1
	can_shoot = false
	shoot_state = ShootState.SHOOTING
	shoot_timer = 0.0
	print("Shot fired! Ammo: ", current_ammo, "/", max_ammo)

	# Play shoot animation
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.play_shoot()

	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

	# Spawn muzzle flash particle effect
	spawn_muzzle_flash()

	# Apply camera recoil (doubled when aiming)
	if player and player.has_method("apply_recoil"):
		var recoil_amount = 5.0
		if is_aiming:
			recoil_amount *= 2.0  # Double recoil when aiming down sights
		player.apply_recoil(recoil_amount)

	# Alert enemies to gunshot
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if forest and "alert_system" in forest:
		var alert_system = forest.alert_system
		if alert_system:
			alert_system.alert_weapon_fire(player.global_position, "shotgun")

	# Fire multiple pellets (shotgun spread)
	for i in range(pellet_count):
		fire_pellet()

	# Update ammo UI
	update_ammo_ui()

func fire_pellet() -> void:
	if not raycast or not camera:
		return

	# Random spread
	var spread_x = randf_range(-spread_angle, spread_angle)
	var spread_y = randf_range(-spread_angle, spread_angle)

	# Calculate direction with spread
	var direction = camera.global_transform.basis.z * -1.0
	direction = direction.rotated(camera.global_transform.basis.x, spread_y)
	direction = direction.rotated(camera.global_transform.basis.y, spread_x)
	direction = direction.normalized()

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
		print("Pellet hit: ", hit_object.name, " at ", result.position)

		# Apply damage if it has a damage method
		if hit_object.has_method("take_damage"):
			hit_object.take_damage(damage_per_pellet)

func play_cock_animation() -> void:
	# Play the cock animation through the state machine
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.play_cock()

func play_cock_sounds() -> void:
	# Play cock start sound immediately
	if reload_start_sound:
		reload_start_sound.play()

	# Play cock end sound shortly after (0.15 seconds)
	await get_tree().create_timer(0.15).timeout
	if reload_end_sound:
		reload_end_sound.play()

func spawn_muzzle_flash() -> void:
	# Find the skeleton and muzzle bone
	if not camera:
		return

	var fps_arms = camera.get_node_or_null("FPSArms")
	if not fps_arms:
		print("Warning: FPSArms not found!")
		return

	var skeleton = fps_arms.get_node_or_null("animations_fps/arms_armature/Skeleton3D")
	if not skeleton:
		print("Warning: Skeleton3D not found!")
		return

	# Find the muzzle bone index
	var bone_idx = skeleton.find_bone("muzzle")
	if bone_idx == -1:
		print("Warning: 'muzzle' bone not found in skeleton!")
		return

	# Get the global transform of the muzzle bone
	var bone_global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)

	# Load and instantiate muzzle flash particle
	var muzzle_flash_scene = load("res://assets/muzzle_flash.tscn")
	if not muzzle_flash_scene:
		print("Warning: assets/muzzle_flash.tscn not found!")
		return

	var muzzle_flash = muzzle_flash_scene.instantiate()

	# Add to scene at muzzle bone position
	get_tree().root.add_child(muzzle_flash)
	muzzle_flash.global_transform = bone_global_transform

	# Auto-delete after particles finish (adjust time as needed)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(muzzle_flash):
		muzzle_flash.queue_free()

func reload() -> void:
	if is_reloading:
		return

	# Check if we have ammo in inventory
	if not has_ammo_in_inventory():
		print("No shotgun shells in inventory!")
		return

	is_reloading = true
	reload_state = ReloadState.START
	reload_timer = 0.0
	print("Starting reload...")
	update_ammo_ui()

	# Play reload start animation
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.play_reload_start()

	# Play reload start sound
	if reload_start_sound:
		reload_start_sound.play()

func has_ammo_in_inventory() -> bool:
	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if not inventory_ui:
		return false

	var inventory_manager = inventory_ui.inventory_manager
	if not inventory_manager:
		return false

	for item in inventory_manager.items:
		if item.item_id == ammo_item_id and item.current_stack > 0:
			return true

	return false

func insert_shell() -> void:
	# Take one shell from inventory
	var inventory_ui = player.get_node_or_null("UI/InventoryUI")
	if not inventory_ui:
		return

	var inventory_manager = inventory_ui.inventory_manager
	if not inventory_manager:
		return

	# Find an ammo item and take one shell
	for item in inventory_manager.items:
		if item.item_id == ammo_item_id and item.current_stack > 0:
			item.current_stack -= 1

			# If stack is empty, remove it
			if item.current_stack <= 0:
				inventory_manager.remove_item(item)

			# Add one shell to magazine
			current_ammo += 1
			print("Inserted shell. Ammo: ", current_ammo, "/", max_ammo)

			# Play shell insert animation
			var fps_controller_shell = get_tree().root.find_child("FPSArms", true, false)
			if fps_controller_shell:
				fps_controller_shell.play_reload_shell()

			# Play shell insert sound
			if reload_shell_sound:
				reload_shell_sound.play()

			update_ammo_ui()

			# Refresh inventory display
			var inv_ui = player.get_node_or_null("UI/InventoryUI")
			if inv_ui:
				inv_ui.refresh_display()

			break

func play_reload_end() -> void:
	print("Ending reload...")

	# Play reload end animation
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.play_reload_end()

	# Play reload end sound
	if reload_end_sound:
		reload_end_sound.play()

func finish_reload() -> void:
	is_reloading = false
	reload_state = ReloadState.NONE
	reload_timer = 0.0
	print("Reload complete! Ammo: ", current_ammo, "/", max_ammo)

	# Check if there's a pending action to execute
	var action_to_execute = pending_action_after_reload
	pending_action_after_reload = ""

	# Return to appropriate animation state
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		# Tell FPS controller reload is completely done
		fps_controller.finish_reload()

	update_ammo_ui()

	# Execute pending action after reload is fully finished
	if action_to_execute == "shoot":
		# Wait one frame to ensure reload is fully cleaned up
		await get_tree().process_frame
		# Check if shoot button is still held
		if can_shoot and Input.is_action_pressed("shoot"):
			shoot()
	elif action_to_execute == "aim":
		# Wait one frame to ensure reload is fully cleaned up
		await get_tree().process_frame
		# Check if aim button is still held
		if Input.is_action_pressed("aim"):
			is_aiming = true
			if fps_controller:
				fps_controller.set_aiming(true)
	elif action_to_execute == "unaim":
		# Wait one frame to ensure reload is fully cleaned up
		await get_tree().process_frame
		# Check if aim button is NOT held (still released)
		if not Input.is_action_pressed("aim"):
			is_aiming = false
			if fps_controller:
				fps_controller.set_aiming(false)

func cancel_reload() -> void:
	if not is_reloading:
		return

	is_reloading = false
	reload_state = ReloadState.NONE
	reload_timer = 0.0
	print("Reload canceled! Ammo: ", current_ammo, "/", max_ammo)

	update_ammo_ui()

func cancel_reload_with_action(action: String) -> void:
	if not is_reloading:
		return

	print("Canceling reload with pending action: ", action)

	# Store the pending action
	pending_action_after_reload = action

	# Skip to reload end phase
	reload_state = ReloadState.END
	reload_timer = 0.0
	play_reload_end()

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
		print("Saved shotgun ammo: %d/%d" % [current_ammo, max_ammo])

	# Hide the FPS weapon model
	if camera:
		var fps_controller = get_tree().root.find_child("FPSArms", true, false)
		if fps_controller:
			fps_controller.hide_all_weapons()
