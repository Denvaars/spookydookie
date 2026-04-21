extends CharacterBody3D

# Movement settings
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.0
@export var crouch_speed: float = 1.5

# Weight system
@export var weight_penalty_per_lb: float = 0.2  # % slowdown per 1 lb (0.25% per lb = 25% at 100 lbs)
@export var max_weight_penalty: float = 50.0  # Maximum % speed reduction
@export var acceleration: float = 10.0
@export var deceleration: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

# Stamina settings
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 15.0
@export var stamina_regen_rate: float = 30.0
@export var min_stamina_to_sprint: float = 10.0
@export var stamina_regen_delay: float = 1.0

# Debug mode (toggle with H key)
var debug_speed_enabled: bool = false
const DEBUG_SPRINT_SPEED: float = 30.0
const DEBUG_STAMINA_DRAIN: float = 1.0

# FOV settings
@export var normal_fov: float = 75.0
@export var sprint_fov: float = 85.0
@export var fov_transition_speed: float = 8.0

# Crouch settings
@export var crouch_height: float = 0.9
@export var stand_height: float = 1.8
@export var crouch_transition_speed: float = 10.0
@export var crouch_camera_height: float = 1.0
@export var stand_camera_height: float = 1.6
@export var crouch_camera_tilt: float = 0.1  # ~8.6 degrees downward tilt
@export var crouch_dip_duration: float = 0.5  # Duration of crouch camera dip in seconds

# Head bob settings (rotation-based in radians)
@export var bob_freq_walk: float = 1.5
@export var bob_freq_sprint: float = 2.0
@export var bob_amp_walk: float = 0.015  # ~4.6 degrees
@export var bob_amp_sprint: float = 0.017  # ~6.9 degrees
@export var bob_sway_walk: float = 0.012  # Left-to-right head sway when walking
@export var bob_sway_sprint: float = 0.02  # Left-to-right head sway when sprinting
@export var bob_randomness: float = 0.15  # Amount of randomness in head bob (0-1)

# Idle breathing settings (rotation-based in radians)
@export var breathing_freq: float = 0.5
@export var breathing_amp: float = 0.02  # ~1.1 degrees

# Camera roll settings (looking left/right)
@export var camera_roll_amount: float = 1.0  # ~2.9 degrees max roll
@export var camera_roll_speed: float = 6.5  # How fast roll responds

# Landing camera tilt settings
@export var landing_tilt_intensity: float = 0.05  # How much camera tilts per unit of fall velocity
@export var landing_fall_time_multiplier: float = 0.5  # Additional tilt per second of falling
@export var landing_dip_speed: float = 5.0  # How fast camera dips down on landing (reduced for smoother dip)
@export var landing_recovery_speed: float = 5.0  # How fast camera returns to normal

# Weapon recoil camera settings
@export var recoil_intensity: float = 0.05  # How much camera kicks up when shooting
@export var recoil_kick_speed: float = 12.0  # How fast camera kicks up (smoother)
@export var recoil_recovery_speed: float = 6.0  # How fast camera returns to normal (smoother recovery)

# Vertical velocity camera pitch
@export var vertical_velocity_pitch_intensity: float = 0.01  # How much camera tilts with vertical movement
@export var vertical_velocity_pitch_speed: float = 8.0  # How fast camera responds to vertical movement

# Health settings
@export var max_health: float = 100.0
@export var health_regen_rate: float = 0.0  # HP per second (0 = no regen)
@export var health_regen_delay: float = 5.0  # Delay before regen starts

# Movement variables
var speed: float = walk_speed
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_stamina: float = max_stamina
var is_sprinting: bool = false
var is_crouching: bool = false
var was_crouching: bool = false
var previous_y_velocity: float = 0.0
var time_since_stopped_sprinting: float = 0.0
var is_stamina_depleted: bool = false

# Health variables
var current_health: float = max_health
var time_since_damaged: float = 0.0
var is_dead: bool = false

# Bleed variables
var current_bleed_damage: float = 0.0  # Total bleed damage remaining
var bleed_dps: float = 0.0  # Damage per second from bleed

# Sanity variables
@export var max_sanity: float = 100.0
var current_sanity: float = max_sanity
@export var sanity_zone_rate: float = 0.2  # Sanity change per second (1.0 per 5 seconds)

# Adrenaline variables
var adrenaline_active: bool = false
var adrenaline_timer: float = 0.0
var adrenaline_duration: float = 5.0

# Item usage variables
var is_using_item: bool = false
var item_use_timer: float = 0.0
var item_use_duration: float = 0.0
var item_being_used: InventoryItem = null

# Camera movement variables
var head_bob_time: float = 0.0
var base_camera_y: float = stand_camera_height
var mouse_look_rotation: float = 0.0  # Stores the vertical mouse look rotation
var current_bob_rotation: Vector3 = Vector3.ZERO  # Current smoothed rotation
var crouch_dip_time: float = 0.0  # Timer for crouch dip animation
var current_crouch_tilt: float = 0.0  # Current smoothed crouch tilt value
var bob_random_offset: float = 0.0  # Random offset for head bob variation
var bob_random_time: float = 0.0  # Timer for random offset changes
var movement_blend: float = 0.0  # Smooth blend between idle and moving (0-1)
var mouse_velocity: float = 0.0  # Horizontal mouse velocity for camera roll
var current_camera_roll: float = 0.0  # Current smoothed camera roll
var target_landing_tilt: float = 0.0  # Target landing tilt value
var current_landing_tilt: float = 0.0  # Current smoothed landing tilt
var target_recoil: float = 0.0  # Target recoil tilt value
var current_recoil: float = 0.0  # Current smoothed recoil tilt
var fall_time: float = 0.0  # How long player has been falling
var target_vertical_pitch: float = 0.0  # Target vertical velocity pitch
var current_vertical_pitch: float = 0.0  # Current smoothed vertical velocity pitch

# Camera reference
@onready var camera: Camera3D = $Camera3D
@onready var stamina_bar: ProgressBar = $UI/StaminaBar
@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var bleed_bar: ProgressBar = $UI/BleedBar
@onready var sanity_bar: ProgressBar = $UI/SanityBar
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight
@onready var inventory_ui: Control = $UI/InventoryUI
@onready var interact_raycast: RayCast3D = $Camera3D/InteractRaycast
@onready var crosshair: Control = $UI/Crosshair

# Perk system
var perk_manager: PerkManager = null

# Audio players
var flashlight_on_sound: AudioStreamPlayer
var flashlight_off_sound: AudioStreamPlayer
var heartbeat_sound: AudioStreamPlayer
var bandage_use_sound: AudioStreamPlayer

# Low health effects
var vignette_overlay: TextureRect
var low_health_threshold: float = 50.0  # HP threshold for low health effects

# Danger zone tracking
var current_danger_level: float = 1.0
var current_danger_zone: int = 1
var danger_label: Label

# Frequency/spawn tracking
var spawn_frequency: float = 0.0
var frequency_label: Label

# Coordinate display
var coordinate_label: Label

# FPS display
var fps_label: Label

# Alert system
var alert_system: AlertSystem = null
var footstep_timer: float = 0.0
var footstep_interval: float = 0.5  # Emit footstep alert every 0.5 seconds while moving

# Inventory state
var is_inventory_open: bool = false

# Pause menu state
var is_paused: bool = false
var pause_menu: Control = null
var settings_menu: Control = null
var console_ui: Control = null
var pause_menu_scene: PackedScene = preload("res://pause_menu.tscn")
var settings_menu_scene: PackedScene = preload("res://settings_menu.tscn")
var console_ui_scene: PackedScene = preload("res://console_ui.tscn")

# Equipped item state (for non-weapon items)
var equipped_item: InventoryItem = null

# Weapon state
var equipped_weapon: Node3D = null
var current_weapon_type: String = ""
var equipped_weapon_item: InventoryItem = null

func _ready() -> void:
	# Add player to group so enemies can find it
	add_to_group("player")

	# Initialize perk manager
	perk_manager = PerkManager.new()
	perk_manager.name = "PerkManager"
	add_child(perk_manager)

	# Set process mode to pause when game is paused
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# Capture the mouse cursor for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Set initial FOV
	camera.fov = normal_fov

	# Apply perk multipliers to max stamina
	var stamina_multiplier = 1.0
	if perk_manager:
		stamina_multiplier = perk_manager.get_total_multiplier("stamina")
	var effective_max_stamina = max_stamina * stamina_multiplier

	# Update stamina bar
	if stamina_bar:
		stamina_bar.max_value = effective_max_stamina
		stamina_bar.value = current_stamina

	# Update bleed bar (yellow background layer)
	if bleed_bar:
		bleed_bar.max_value = max_health
		bleed_bar.value = current_health

	# Update health bar (red foreground layer)
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health  # No bleed at start

	# Update sanity bar
	if sanity_bar:
		sanity_bar.max_value = max_sanity
		sanity_bar.value = current_sanity

	# Set flashlight off by default
	if flashlight:
		flashlight.visible = false

	# Setup flashlight sounds
	flashlight_on_sound = AudioStreamPlayer.new()
	flashlight_on_sound.stream = load("res://audio/flashlight_on.wav")
	add_child(flashlight_on_sound)

	flashlight_off_sound = AudioStreamPlayer.new()
	flashlight_off_sound.stream = load("res://audio/flashlight_off.wav")
	add_child(flashlight_off_sound)

	# Setup bandage use sound
	bandage_use_sound = AudioStreamPlayer.new()
	bandage_use_sound.stream = load("res://audio/bandage_use.wav")
	add_child(bandage_use_sound)

	# Setup heartbeat sound
	heartbeat_sound = AudioStreamPlayer.new()
	heartbeat_sound.stream = load("res://audio/heartbeat.wav")
	heartbeat_sound.bus = "Master"
	add_child(heartbeat_sound)

	# Setup vignette overlay
	var ui = get_node_or_null("UI")
	if ui:
		vignette_overlay = TextureRect.new()
		vignette_overlay.name = "VignetteOverlay"
		var vignette_texture = load("res://assets/vignette.png")
		if vignette_texture:
			vignette_overlay.texture = vignette_texture
			print("Vignette texture loaded successfully")
		else:
			push_error("Failed to load vignette texture")
		vignette_overlay.stretch_mode = TextureRect.STRETCH_SCALE
		vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette_overlay.modulate = Color(1, 1, 1, 0)  # Start invisible
		# Make it cover the entire screen using offsets
		vignette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		vignette_overlay.offset_left = 0
		vignette_overlay.offset_top = 0
		vignette_overlay.offset_right = 0
		vignette_overlay.offset_bottom = 0
		ui.add_child(vignette_overlay)
		# Ensure it's on top by moving it to the last position
		ui.move_child(vignette_overlay, ui.get_child_count() - 1)
		print("Vignette overlay created and added to UI")

		# Setup danger level display
		danger_label = Label.new()
		danger_label.name = "DangerLabel"
		danger_label.add_theme_font_size_override("font_size", 24)
		danger_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		danger_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		danger_label.add_theme_constant_override("outline_size", 4)
		danger_label.text = "Danger Zone: 1 (1.0)"
		# Position at top-left
		danger_label.position = Vector2(10, 10)
		ui.add_child(danger_label)
		print("Danger label created")

		# Setup frequency display
		frequency_label = Label.new()
		frequency_label.name = "FrequencyLabel"
		frequency_label.add_theme_font_size_override("font_size", 24)
		frequency_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1))
		frequency_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		frequency_label.add_theme_constant_override("outline_size", 4)
		frequency_label.text = "Frequency: 0.0"
		# Position below danger label
		frequency_label.position = Vector2(10, 45)
		ui.add_child(frequency_label)
		print("Frequency label created")

		# Setup coordinate display
		coordinate_label = Label.new()
		coordinate_label.name = "CoordinateLabel"
		coordinate_label.add_theme_font_size_override("font_size", 20)
		coordinate_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		coordinate_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		coordinate_label.add_theme_constant_override("outline_size", 4)
		coordinate_label.text = "Position: (0, 0, 0)"
		# Position below frequency label
		coordinate_label.position = Vector2(10, 80)
		ui.add_child(coordinate_label)
		print("Coordinate label created")

		# Setup FPS display
		fps_label = Label.new()
		fps_label.name = "FPSLabel"
		fps_label.add_theme_font_size_override("font_size", 24)
		fps_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
		fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		fps_label.add_theme_constant_override("outline_size", 4)
		fps_label.text = "FPS: 0"
		# Position below coordinate label
		fps_label.position = Vector2(10, 115)
		ui.add_child(fps_label)
		print("FPS label created")

	# Get alert system reference
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")
	if forest and "alert_system" in forest:
		alert_system = forest.alert_system
		print("Player: connected to alert system")

# Smooth interpolation with easing (ease out for natural deceleration)
func smooth_lerp(current: float, target: float, speed: float, delta_time: float) -> float:
	var difference = target - current
	var change = difference * (1.0 - exp(-speed * delta_time))
	return current + change

# Smooth interpolation for Vector3 with easing
func smooth_lerp_vec3(current: Vector3, target: Vector3, speed: float, delta_time: float) -> Vector3:
	return Vector3(
		smooth_lerp(current.x, target.x, speed, delta_time),
		smooth_lerp(current.y, target.y, speed, delta_time),
		smooth_lerp(current.z, target.z, speed, delta_time)
	)

func _headbob(delta: float, velocity_length: float) -> Vector3:
	# Update random offset periodically for variation
	bob_random_time += delta
	if bob_random_time > 0.5:  # Change random offset every 0.5 seconds
		bob_random_offset = randf_range(-bob_randomness, bob_randomness)
		bob_random_time = 0.0

	# Smoothly blend between idle and moving states
	var is_moving = velocity_length > 0.1 and is_on_floor()
	var target_blend = 1.0 if is_moving else 0.0
	movement_blend = smooth_lerp(movement_blend, target_blend, 5.0, delta)

	# Blend frequency and amplitude instead of blending separate rotations
	var bob_freq = bob_freq_sprint if is_sprinting else bob_freq_walk
	var bob_amp = bob_amp_sprint if is_sprinting else bob_amp_walk
	var bob_sway = bob_sway_sprint if is_sprinting else bob_sway_walk

	# Blend between idle and movement parameters
	var blended_freq = lerp(breathing_freq, bob_freq, movement_blend)
	var blended_amp = lerp(breathing_amp, bob_amp, movement_blend)
	var blended_sway = lerp(breathing_amp * 0.2, bob_sway, movement_blend)

	# Add slight randomness to the timing
	var random_time_offset = bob_random_offset * 0.5
	var time_speed = 1.0 + lerp(0.0, velocity_length - 1.0, movement_blend)
	head_bob_time += delta * blended_freq * time_speed * (1.0 + random_time_offset)

	# Add random variation to amplitude
	var amp_variation = 1.0 + (bob_random_offset * 0.3)

	# Calculate rotation with blended parameters
	var rotation = Vector3.ZERO
	rotation.x = sin(head_bob_time * 2.0) * blended_amp * amp_variation  # Forward/back motion
	rotation.z = cos(head_bob_time) * blended_amp * 0.3 * amp_variation  # Subtle side tilt
	rotation.y = sin(head_bob_time) * blended_sway * amp_variation  # Left-to-right head sway

	return rotation

func _input(event: InputEvent) -> void:
	# Handle mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate the body horizontally
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Track horizontal mouse velocity for camera roll
		mouse_velocity = -event.relative.x * mouse_sensitivity

		# Update vertical mouse look rotation
		mouse_look_rotation -= event.relative.y * mouse_sensitivity
		mouse_look_rotation = clamp(mouse_look_rotation, deg_to_rad(-90), deg_to_rad(90))

	# Toggle flashlight
	if event.is_action_pressed("flashlight"):
		if flashlight:
			flashlight.visible = not flashlight.visible
			# Play appropriate sound
			if flashlight.visible:
				if flashlight_on_sound:
					flashlight_on_sound.play()
			else:
				if flashlight_off_sound:
					flashlight_off_sound.play()

	# DEBUG: Toggle super speed with H key
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		debug_speed_enabled = not debug_speed_enabled
		if debug_speed_enabled:
			print("DEBUG: Super speed ENABLED (sprint speed: %.1f, stamina drain: %.1f)" % [DEBUG_SPRINT_SPEED, DEBUG_STAMINA_DRAIN])
		else:
			print("DEBUG: Super speed DISABLED (normal speeds restored)")

	# Interact with items
	if event.is_action_pressed("interact") and not is_inventory_open:
		try_pickup_item()

	# DEBUG: Spawn bear with P key
	if event.is_action_pressed("ui_text_backspace") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
		spawn_test_bear()

	# DEBUG: Spawn deer group with O key
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:
		spawn_test_deer_group()

	# Use equipped item with left click (when not in inventory)
	if event.is_action_pressed("shoot") and not is_inventory_open:
		use_equipped_item()

	# Toggle inventory
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory()

	# Press ESC to pause/unpause (or close inventory/settings/console)
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if is_inventory_open:
			toggle_inventory()
		elif console_ui and console_ui.visible:
			hide_console()
		elif settings_menu and settings_menu.visible:
			hide_settings_menu()
		elif is_paused:
			# ESC closes pause menu (resumes game)
			toggle_pause()
		else:
			# ESC opens pause menu
			toggle_pause()

	# Test damage with K key
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		take_damage(10.0)
		print("Test damage: -10 HP (Current: ", current_health, "/", max_health, ")")

	# Adjust frequency with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			adjust_frequency(0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			adjust_frequency(-0.5)

func get_weight_speed_multiplier() -> float:
	# Get total weight from inventory
	var total_weight: float = 0.0
	if inventory_ui:
		total_weight = inventory_ui.get_total_weight()

	# Calculate penalty - simple linear: 1 lb = 0.25% slowdown
	var penalty_percent = min(max_weight_penalty, total_weight * weight_penalty_per_lb)

	# Apply perk multiplier to weight penalty (Pack Mule reduces penalty)
	if perk_manager:
		var perk_mult = perk_manager.get_total_multiplier("weight_penalty")
		penalty_percent *= perk_mult

	var multiplier = 1.0 - (penalty_percent / 100.0)

	return clamp(multiplier, 0.5, 1.0)  # Never go below 50% speed

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump (can't jump while crouching)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	# Handle crouch
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	else:
		is_crouching = false

	# Detect crouch transition and trigger dip animation
	if is_crouching and not was_crouching:
		crouch_dip_time = 0.0  # Start the dip animation

	# Adjust collision shape and camera height for crouching
	var target_height = crouch_height if is_crouching else stand_height
	var target_camera_height = crouch_camera_height if is_crouching else stand_camera_height

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule = collision_shape.shape as CapsuleShape3D
		capsule.height = smooth_lerp(capsule.height, target_height, crouch_transition_speed, delta)
		collision_shape.position.y = smooth_lerp(collision_shape.position.y, target_height / 2.0, crouch_transition_speed, delta)

	base_camera_y = smooth_lerp(base_camera_y, target_camera_height, crouch_transition_speed, delta)

	# Animate crouch camera dip (temporary downward tilt when crouching)
	var target_crouch_tilt = 0.0
	if crouch_dip_time < crouch_dip_duration:
		crouch_dip_time += delta
		# Custom curve: medium start, speeds up in middle, slows at end
		var progress = crouch_dip_time / crouch_dip_duration

		# Blend smoothstep (slow-fast-slow) with linear for medium start
		var smoothstep_val = progress * progress * (3.0 - 2.0 * progress)
		var eased = 0.3 * progress + 0.7 * smoothstep_val

		var smoothed = sin(eased * PI)  # Creates smooth peak with custom easing
		target_crouch_tilt = smoothed * -crouch_camera_tilt  # Negative to tilt down

	# Smoothly interpolate to target tilt to prevent snapping
	current_crouch_tilt = smooth_lerp(current_crouch_tilt, target_crouch_tilt, 20.0, delta)

	# Store previous crouch state for next frame
	was_crouching = is_crouching

	# Update adrenaline timer
	if adrenaline_active:
		adrenaline_timer += delta
		if adrenaline_timer >= adrenaline_duration:
			adrenaline_active = false
			adrenaline_timer = 0.0
			print("Adrenaline wore off")

	# Update item use timer
	if is_using_item:
		item_use_timer += delta
		if item_use_timer >= item_use_duration:
			# Item use complete!
			is_using_item = false
			item_use_timer = 0.0

			# Handle completion based on item type
			if item_being_used and item_being_used.item_id == "bandage_01":
				heal(25.0)
				print("Bandage applied - healed 25 HP")

				# Handle stackable item consumption
				var ui = get_node_or_null("UI")
				if ui:
					var inventory_ui = ui.get_node_or_null("InventoryUI")
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

	# Handle sprint with stamina (can't sprint while crouching, aiming, reloading, moving backward, or not moving forward)
	var is_moving_forward = Input.is_action_pressed("move_forward")
	var is_moving_backward = Input.is_action_pressed("move_backward")
	var is_aiming = is_weapon_aiming()
	var is_reloading = is_weapon_reloading()
	var wants_to_sprint = Input.is_action_pressed("sprint") and is_on_floor() and not is_crouching and is_moving_forward and not is_moving_backward and not is_aiming and not is_reloading
	var can_sprint = (current_stamina > 0.0 and not is_stamina_depleted) or adrenaline_active  # Can always sprint with adrenaline

	if wants_to_sprint and can_sprint:
		is_sprinting = true

		# Get weight multiplier (affects all speeds except debug mode)
		var weight_multiplier = get_weight_speed_multiplier()

		# Get perk multipliers
		var sprint_perk_mult = perk_manager.get_total_multiplier("sprint_speed") if perk_manager else 1.0
		var stamina_drain_mult = perk_manager.get_total_multiplier("stamina_drain") if perk_manager else 1.0

		# Apply speed (debug mode, adrenaline, or normal)
		if debug_speed_enabled:
			speed = DEBUG_SPRINT_SPEED  # Debug mode ignores weight
		elif adrenaline_active:
			speed = sprint_speed * 1.1 * weight_multiplier * sprint_perk_mult
		else:
			speed = sprint_speed * weight_multiplier * sprint_perk_mult

		# Don't drain stamina if adrenaline is active
		if not adrenaline_active:
			var drain_rate = DEBUG_STAMINA_DRAIN if debug_speed_enabled else stamina_drain_rate
			drain_rate *= stamina_drain_mult  # Apply perk multiplier
			current_stamina -= drain_rate * delta
			current_stamina = max(current_stamina, 0.0)

		time_since_stopped_sprinting = 0.0

		# Check if stamina just depleted (only if no adrenaline)
		if current_stamina <= 0.0 and not adrenaline_active:
			is_stamina_depleted = true
			is_sprinting = false
	else:
		is_sprinting = false

		# Get weight multiplier
		var weight_multiplier = get_weight_speed_multiplier()

		if is_crouching:
			speed = crouch_speed * weight_multiplier
		else:
			speed = walk_speed * weight_multiplier
		time_since_stopped_sprinting += delta

		# Regenerate stamina only after delay
		if time_since_stopped_sprinting >= stamina_regen_delay:
			current_stamina += stamina_regen_rate * delta
			current_stamina = min(current_stamina, max_stamina)

			# Reset depleted flag when fully recharged
			if current_stamina >= max_stamina:
				is_stamina_depleted = false

	# Update stamina bar and color
	if stamina_bar:
		stamina_bar.value = current_stamina

		# Change bar color based on depletion state
		var bar_style = stamina_bar.get_theme_stylebox("fill")
		if bar_style and bar_style is StyleBoxFlat:
			if is_stamina_depleted:
				bar_style.bg_color = Color(0.8, 0.2, 0.2, 0.8)  # Red
			else:
				bar_style.bg_color = Color(0.2, 0.6, 0.8, 0.8)  # Blue

	# Smooth FOV transition with easing
	# Weapon aiming takes priority over sprint FOV
	var target_fov = normal_fov
	if is_weapon_aiming() and equipped_weapon:
		# Use weapon's aim FOV if aiming
		if "aim_fov" in equipped_weapon:
			target_fov = equipped_weapon.aim_fov
	elif is_sprinting:
		target_fov = sprint_fov

	camera.fov = smooth_lerp(camera.fov, target_fov, fov_transition_speed, delta)

	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Apply movement with acceleration/deceleration
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta * speed)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta * speed)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration * delta * speed)
		velocity.z = move_toward(velocity.z, 0, deceleration * delta * speed)

	# Apply head bob and breathing rotation
	var horizontal_velocity = Vector2(velocity.x, velocity.z).length()
	var target_bob_rotation = _headbob(delta, horizontal_velocity)

	# Smoothly interpolate to target rotation with easing to prevent jitter
	current_bob_rotation = smooth_lerp_vec3(current_bob_rotation, target_bob_rotation, 15.0, delta)

	# Calculate camera roll based on horizontal mouse movement
	var target_roll = mouse_velocity * camera_roll_amount
	current_camera_roll = smooth_lerp(current_camera_roll, target_roll, camera_roll_speed, delta)

	# Decay mouse velocity over time
	mouse_velocity = smooth_lerp(mouse_velocity, 0.0, 10.0, delta)

	# Set camera height based on crouch/stand
	camera.position.y = base_camera_y
	camera.position.x = 0.0
	camera.position.z = 0.0

	move_and_slide()

	# Track fall time
	if not is_on_floor() and velocity.y < -1.0:
		fall_time += delta
	else:
		fall_time = 0.0

	# Detect landing (was falling, now on floor) - velocity-dependent
	if is_on_floor() and previous_y_velocity < -1.0:
		# Set target downward tilt based on fall velocity AND fall duration
		var fall_speed = abs(previous_y_velocity)
		var fall_time_scale = 1.0 + (fall_time * landing_fall_time_multiplier)  # More time falling = stronger effect
		target_landing_tilt = -fall_speed * landing_tilt_intensity * fall_time_scale  # Negative = tilt down
		print("Landing! Fall speed: ", fall_speed, " Fall time: ", fall_time, " Target tilt: ", target_landing_tilt)

	# Target landing tilt smoothly returns to 0
	target_landing_tilt = smooth_lerp(target_landing_tilt, 0.0, landing_recovery_speed, delta)

	# Current landing tilt smoothly follows target (this is what gets applied to camera)
	current_landing_tilt = smooth_lerp(current_landing_tilt, target_landing_tilt, landing_dip_speed, delta)

	# Target recoil smoothly returns to 0
	target_recoil = smooth_lerp(target_recoil, 0.0, recoil_recovery_speed, delta)

	# Current recoil smoothly follows target (this is what gets applied to camera)
	current_recoil = smooth_lerp(current_recoil, target_recoil, recoil_kick_speed, delta)

	# Calculate target vertical velocity camera pitch (moving up = camera tilts down)
	target_vertical_pitch = -velocity.y * vertical_velocity_pitch_intensity

	# Smoothly interpolate current pitch to target (relative rotation)
	current_vertical_pitch = smooth_lerp(current_vertical_pitch, target_vertical_pitch, vertical_velocity_pitch_speed, delta)

	# Apply rotation: combine mouse look with head bob, crouch tilt, landing tilt, recoil, vertical velocity pitch, and camera roll
	# All values use smooth lerping for relative rotation that doesn't fight with breathing/shake
	camera.rotation.x = mouse_look_rotation + current_bob_rotation.x + current_crouch_tilt + current_landing_tilt + current_recoil + current_vertical_pitch  # Vertical look + forward/back bob + crouch tilt + landing tilt + recoil + vertical movement
	camera.rotation.z = current_bob_rotation.z + current_camera_roll  # Side tilt (roll) + mouse turn roll
	camera.rotation.y = current_bob_rotation.y  # Left-to-right head sway (yaw)

	# Store velocity for landing detection next frame
	previous_y_velocity = velocity.y

	# Process bleed damage
	if current_bleed_damage > 0.0 and bleed_dps > 0.0:
		var bleed_tick = bleed_dps * delta
		bleed_tick = min(bleed_tick, current_bleed_damage)  # Don't exceed remaining bleed damage

		current_health -= bleed_tick
		current_health = max(current_health, 0.0)
		current_bleed_damage -= bleed_tick

		# Round to zero if very small to avoid floating point issues
		if current_bleed_damage < 0.01:
			current_bleed_damage = 0.0
			bleed_dps = 0.0
			print("Bleed damage finished")

		# Check for death from bleed
		if current_health <= 0.0 and not is_dead:
			die()

	# Health regeneration
	if current_health < max_health and health_regen_rate > 0.0:
		time_since_damaged += delta
		if time_since_damaged >= health_regen_delay:
			current_health += health_regen_rate * delta
			current_health = min(current_health, max_health)

	# Update bleed bar (yellow) to show current health
	if bleed_bar:
		bleed_bar.value = current_health

	# Update health bar (red) to show health minus bleed damage
	if health_bar:
		var health_after_bleed = max(current_health - current_bleed_damage, 0.0)
		health_bar.value = health_after_bleed

	# Update sanity bar
	if sanity_bar:
		sanity_bar.value = current_sanity

	# Update coordinate display
	if coordinate_label:
		coordinate_label.text = "Position: (%.1f, %.1f, %.1f)" % [global_position.x, global_position.y, global_position.z]

	# Update FPS display
	if fps_label:
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: %d" % fps
		# Color code: green >60, yellow 30-60, red <30
		if fps >= 60:
			fps_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
		elif fps >= 30:
			fps_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
		else:
			fps_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))

	# Update low health effects
	update_low_health_effects(delta)

	# Update danger zone tracking
	update_danger_zone()

	# Update sanity based on danger zone
	update_sanity_from_zone(delta)

	# Emit footstep alerts
	if alert_system:
		if horizontal_velocity > 0.5 and is_on_floor():
			footstep_timer += delta
			if footstep_timer >= footstep_interval:
				footstep_timer = 0.0
				alert_system.alert_footstep(global_position, is_sprinting, is_crouching)

func take_damage(amount: float, bleed_damage: float = 0.0, bleed_damage_per_second: float = 0.0) -> void:
	if is_dead:
		return

	# Apply direct damage
	current_health -= amount
	current_health = max(current_health, 0.0)
	time_since_damaged = 0.0

	# Apply bleed damage
	if bleed_damage > 0.0 and bleed_damage_per_second > 0.0:
		# Apply perk multiplier (Thick Skin reduces bleed)
		var bleed_mult = perk_manager.get_total_multiplier("bleed_damage") if perk_manager else 1.0
		var modified_bleed_dps = bleed_damage_per_second * bleed_mult

		current_bleed_damage += bleed_damage
		bleed_dps = modified_bleed_dps
		print("Applied %.1f bleed damage at %.1f DPS (%.0f%% from perks)" % [bleed_damage, bleed_dps, bleed_mult * 100.0])

	# Update bleed bar (yellow) to show current health
	if bleed_bar:
		bleed_bar.value = current_health

	# Update health bar (red) to show health minus bleed damage
	if health_bar:
		var health_after_bleed = max(current_health - current_bleed_damage, 0.0)
		health_bar.value = health_after_bleed

	# Check for death
	if current_health <= 0.0:
		die()

func heal(amount: float) -> void:
	if is_dead:
		return

	current_health += amount
	current_health = min(current_health, max_health)

	# Update bleed bar (yellow) to show current health
	if bleed_bar:
		bleed_bar.value = current_health

	# Update health bar (red) to show health minus bleed damage
	if health_bar:
		var health_after_bleed = max(current_health - current_bleed_damage, 0.0)
		health_bar.value = health_after_bleed

func die() -> void:
	is_dead = true
	print("Player died!")
	# TODO: Implement death screen, respawn, etc.

func try_pickup_item() -> void:
	if not interact_raycast:
		return

	if interact_raycast.is_colliding():
		var collider = interact_raycast.get_collider()

		# Check for pickups
		if collider and collider.is_in_group("pickup"):
			if collider.has_method("pickup"):
				collider.pickup(self)

		# Check for interactables (perk statue, etc)
		elif collider and collider.is_in_group("interactable"):
			if collider.has_method("interact"):
				collider.interact(self)

func toggle_inventory() -> void:
	is_inventory_open = !is_inventory_open

	if inventory_ui:
		inventory_ui.visible = is_inventory_open

	# Hide/show crosshair
	if crosshair:
		crosshair.visible = !is_inventory_open

	# Pause/unpause the game
	get_tree().paused = is_inventory_open

	# Switch mouse mode
	if is_inventory_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func toggle_pause() -> void:
	is_paused = !is_paused

	if is_paused:
		# Create and show pause menu
		if not pause_menu:
			pause_menu = pause_menu_scene.instantiate()
			pause_menu.resume_pressed.connect(_on_resume_pressed)
			pause_menu.settings_pressed.connect(_on_settings_pressed)
			pause_menu.console_pressed.connect(_on_console_pressed)
			pause_menu.quit_pressed.connect(_on_quit_pressed)

			var ui = get_node_or_null("UI")
			if ui:
				ui.add_child(pause_menu)

		if pause_menu:
			pause_menu.visible = true

		# Pause the game
		get_tree().paused = true

		# Show mouse
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Hide pause menu
		if pause_menu:
			pause_menu.visible = false

		# Unpause the game
		get_tree().paused = false

		# Capture mouse
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_resume_pressed() -> void:
	toggle_pause()


func _on_settings_pressed() -> void:
	# Hide pause menu and show settings menu
	if pause_menu:
		pause_menu.visible = false

	if not settings_menu:
		settings_menu = settings_menu_scene.instantiate()
		settings_menu.back_pressed.connect(_on_settings_back_pressed)

		var ui = get_node_or_null("UI")
		if ui:
			ui.add_child(settings_menu)

	if settings_menu:
		settings_menu.visible = true


func _on_settings_back_pressed() -> void:
	hide_settings_menu()


func hide_settings_menu() -> void:
	if settings_menu:
		settings_menu.visible = false

	if pause_menu:
		pause_menu.visible = true


func _on_console_pressed() -> void:
	# Hide pause menu and show console
	if pause_menu:
		pause_menu.visible = false

	if not console_ui:
		console_ui = console_ui_scene.instantiate()
		console_ui.close_requested.connect(_on_console_close_requested)

		var ui = get_node_or_null("UI")
		if ui:
			ui.add_child(console_ui)

	if console_ui:
		console_ui.show_console()


func _on_console_close_requested() -> void:
	hide_console()


func hide_console() -> void:
	if console_ui:
		console_ui.hide_console()

	if pause_menu:
		pause_menu.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func equip_weapon(weapon_type: String, item: InventoryItem = null) -> void:
	# Unequip current weapon first
	if equipped_weapon:
		# Call on_unequip to save state and hide model
		if equipped_weapon.has_method("on_unequip"):
			equipped_weapon.on_unequip()

		# Just remove the weapon node, don't return to inventory
		var ui = get_node_or_null("UI")
		if ui:
			var ammo_label = ui.get_node_or_null("AmmoLabel")
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
	add_child(equipped_weapon)
	current_weapon_type = weapon_type

	print(weapon_type.capitalize(), " equipped!")

func unequip_weapon() -> void:
	if equipped_weapon:
		# Call on_unequip to save state and hide model
		if equipped_weapon.has_method("on_unequip"):
			equipped_weapon.on_unequip()

		# Hide ammo UI
		var ui = get_node_or_null("UI")
		if ui:
			var ammo_label = ui.get_node_or_null("AmmoLabel")
			if ammo_label:
				ammo_label.visible = false

		equipped_weapon.queue_free()
		equipped_weapon = null
		current_weapon_type = ""
		equipped_weapon_item = null
		print("Weapon unequipped")


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

func unequip_item(item: InventoryItem) -> void:
	# Handle different item types
	match item.item_id:
		"shotgun_01", "rifle_01", "pistol_01", "axe_01", "knife_01", "flare_01", "flare_gun_01", "binoculars_01", "flashlight_01", "lantern_01", "lighter_01":
			# Unequip weapon
			if equipped_weapon and equipped_weapon_item == item:
				# Don't return to inventory - it's already there
				# Just remove the weapon node and its visual components
				if equipped_weapon:
					# Save weapon state and hide model
					if equipped_weapon.has_method("on_unequip"):
						equipped_weapon.on_unequip()

					# Hide ammo UI
					var ui = get_node_or_null("UI")
					if ui:
						var ammo_label = ui.get_node_or_null("AmmoLabel")
						if ammo_label:
							ammo_label.visible = false

					equipped_weapon.queue_free()
					equipped_weapon = null
					current_weapon_type = ""
					equipped_weapon_item = null
					print("Weapon unequipped")
		"flashlight_01":
			# Turn off flashlight when unequipping
			if flashlight and flashlight.visible:
				flashlight.visible = false
				if flashlight_off_sound:
					flashlight_off_sound.play()
			if equipped_item == item:
				equipped_item = null
				print("Unequipped flashlight")
		_:
			# For non-weapon items
			if equipped_item == item:
				equipped_item = null
				print("Unequipped: ", item.item_name)

func use_equipped_item() -> void:
	if not equipped_item:
		return

	# Get inventory manager to remove items after use
	var ui = get_node_or_null("UI")
	if not ui:
		return

	var inventory_ui = ui.get_node_or_null("InventoryUI")
	if not inventory_ui:
		return

	var manager: InventoryManager = inventory_ui.inventory_manager
	if not manager:
		return

	# Handle different item types
	match equipped_item.item_id:
		"medkit_01":
			# Heal player
			heal(75.0)
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
				if bandage_use_sound:
					bandage_use_sound.play()
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
				if flashlight.visible:
					if flashlight_on_sound:
						flashlight_on_sound.play()
					print("Flashlight turned on")
				else:
					if flashlight_off_sound:
						flashlight_off_sound.play()
					print("Flashlight turned off")

		"adrenaline_syringe_01":
			# Activate adrenaline (infinite stamina + 10% speed boost for 10 seconds)
			adrenaline_active = true
			adrenaline_timer = 0.0
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
			if current_bleed_damage > 0.0:
				current_bleed_damage = 0.0
				bleed_dps = 0.0
				print("Used antiseptic - bleeding stopped!")
				# Update both bars (bleed cleared, so red bar catches up to yellow)
				if bleed_bar:
					bleed_bar.value = current_health
				if health_bar:
					health_bar.value = current_health
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
			current_sanity += 30.0
			current_sanity = min(current_sanity, max_sanity)
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

func adjust_frequency(delta: float) -> void:
	spawn_frequency += delta
	spawn_frequency = clampf(spawn_frequency, 0.0, 10.0)

	# Update spawn manager
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")

	if forest and "spawn_manager" in forest:
		var spawn_manager = forest.spawn_manager
		if spawn_manager:
			spawn_manager.set_frequency(spawn_frequency)

	# Update UI
	if frequency_label:
		frequency_label.text = "Frequency: %.1f" % spawn_frequency

func update_danger_zone() -> void:
	# Find the DangerZoneManager in the scene
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		# Try to find it by path
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")

	if forest and "danger_manager" in forest:
		var danger_manager = forest.danger_manager
		if danger_manager:
			# Get current danger level based on player position
			current_danger_level = danger_manager.get_danger_level(global_position)
			current_danger_zone = danger_manager.get_danger_zone(current_danger_level)

			# Check if it's night time and increase danger zone by 1
			var daylight_system = get_tree().get_first_node_in_group("daylight_system")
			if daylight_system and daylight_system.has_method("is_night_time"):
				if daylight_system.is_night_time():
					current_danger_zone = min(current_danger_zone + 1, 4)  # Cap at zone 4

			# Update UI
			if danger_label:
				danger_label.text = "Danger Zone: %d (%.2f)" % [current_danger_zone, current_danger_level]

				# Change color based on danger zone
				match current_danger_zone:
					1:
						danger_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))  # Green
					2:
						danger_label.add_theme_color_override("font_color", Color(1, 1, 0.3))  # Yellow
					3:
						danger_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))  # Red
					4:
						danger_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.8))  # Dark Red/Purple

func update_sanity_from_zone(delta: float) -> void:
	# Apply smooth sanity changes based on danger zone
	match current_danger_zone:
		1:
			# Zone 1 (safe) - restore sanity smoothly
			current_sanity += sanity_zone_rate * delta
			current_sanity = min(current_sanity, max_sanity)
		2:
			# Zone 2 (medium danger) - no change
			pass
		3:
			# Zone 3 (high danger) - lose sanity smoothly
			current_sanity -= sanity_zone_rate * delta
			current_sanity = max(current_sanity, 0.0)
		4:
			# Zone 4 (extreme danger - night time) - lose sanity faster
			current_sanity -= sanity_zone_rate * 2.0 * delta  # Double drain rate
			current_sanity = max(current_sanity, 0.0)

func update_low_health_effects(delta: float) -> void:
	# Calculate health percentage (0.0 to 1.0)
	var health_percent = current_health / max_health

	# Update vignette overlay
	if vignette_overlay:
		if current_health <= low_health_threshold:
			# Calculate vignette opacity based on health (0 HP = 1.0 opacity, 50 HP = 0.0 opacity)
			var vignette_alpha = 1.0 - (current_health / low_health_threshold)
			vignette_alpha = clamp(vignette_alpha, 0.0, 1.0)
			vignette_overlay.modulate = Color(1, 1, 1, vignette_alpha)
		else:
			# Above threshold, fade out
			vignette_overlay.modulate = Color(1, 1, 1, 0)

	# Update heartbeat sound
	if heartbeat_sound:
		if current_health <= low_health_threshold:
			# Calculate intensity based on health (lower health = higher intensity)
			var intensity = 1.0 - (current_health / low_health_threshold)
			intensity = clamp(intensity, 0.0, 1.0)

			# Volume increases as health decreases (-20 dB to 0 dB)
			var volume_db = lerp(-20.0, 0.0, intensity)
			heartbeat_sound.volume_db = volume_db

			# Speed increases as health decreases (0.8x to 1.5x speed)
			var pitch_scale = lerp(0.8, 1.5, intensity)
			heartbeat_sound.pitch_scale = pitch_scale

			# Start playing if not already
			if not heartbeat_sound.playing:
				heartbeat_sound.play()
		else:
			# Above threshold, stop heartbeat
			if heartbeat_sound.playing:
				heartbeat_sound.stop()

func is_weapon_aiming() -> bool:
	# Check if the equipped weapon is currently aiming
	if equipped_weapon and "is_aiming" in equipped_weapon:
		return equipped_weapon.is_aiming
	return false

func is_weapon_reloading() -> bool:
	# Check if the equipped weapon is currently reloading
	if equipped_weapon and "is_reloading" in equipped_weapon:
		return equipped_weapon.is_reloading
	return false

func spawn_test_bear() -> void:
	# DEBUG: Spawn a bear in the forest like natural spawning
	var bear_scene = load("res://animal_bear.tscn")
	if not bear_scene:
		print("Failed to load bear scene!")
		return

	var bear = bear_scene.instantiate()

	# Spawn in forest, off the path, 20-40m away
	var angle = randf() * TAU
	var distance = randf_range(20.0, 40.0)
	var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	var spawn_pos = global_position + offset

	# Get terrain height
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("get_height"):
		spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)
	else:
		spawn_pos.y = global_position.y

	get_tree().root.add_child(bear)
	bear.global_position = spawn_pos

	print("DEBUG: Spawned bear at %v (%.1fm away)" % [spawn_pos, distance])

func spawn_test_deer_group() -> void:
	# DEBUG: Spawn a group of 2-5 deer
	var deer_scene = load("res://animal_deer.tscn")
	if not deer_scene:
		print("Failed to load deer scene!")
		return

	# Spawn 2-5 deer
	var deer_count = randi_range(2, 5)

	# Get terrain and path references
	var terrain = get_tree().get_first_node_in_group("terrain")
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")

	var path_generator = null
	if forest and "path_generator" in forest:
		path_generator = forest.path_generator

	# Find base position NOT on path (try up to 10 times)
	var base_pos = Vector3.ZERO
	var base_distance = 0.0
	var found_valid_position = false

	for attempt in range(10):
		var base_angle = randf() * TAU
		base_distance = randf_range(15.0, 30.0)
		var base_offset = Vector3(cos(base_angle) * base_distance, 0, sin(base_angle) * base_distance)
		base_pos = global_position + base_offset

		# Check if on path
		if path_generator and path_generator.has_method("is_on_path"):
			if not path_generator.is_on_path(base_pos.x, base_pos.z):
				found_valid_position = true
				break
		else:
			# No path generator, position is valid
			found_valid_position = true
			break

	if not found_valid_position:
		print("DEBUG: Could not find valid deer spawn position off path")
		return

	# Spawn each deer in a small cluster around base position
	for i in range(deer_count):
		var deer = deer_scene.instantiate()

		# Scatter deer within 3-5 meters of base position
		var cluster_angle = randf() * TAU
		var cluster_distance = randf_range(3.0, 5.0)
		var cluster_offset = Vector3(cos(cluster_angle) * cluster_distance, 0, sin(cluster_angle) * cluster_distance)
		var spawn_pos = base_pos + cluster_offset

		# Get terrain height
		if terrain and terrain.has_method("get_height"):
			spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)
		else:
			spawn_pos.y = global_position.y

		get_tree().root.add_child(deer)
		deer.global_position = spawn_pos

	print("DEBUG: Spawned %d deer at base position %v (%.1fm away, OFF PATH)" % [deer_count, base_pos, base_distance])

# Called by weapons to apply camera recoil
func apply_recoil(amount: float = 1.0) -> void:
	# Set target recoil to kick up (positive pitch = look up)
	target_recoil = amount * recoil_intensity
	print("Recoil applied! Amount: ", target_recoil)
