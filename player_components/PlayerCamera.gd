class_name PlayerCamera
extends Node

## Handles all camera effects (head bob, FOV, recoil, landing tilt, etc.)
## Depends on player movement state and inventory state

# FOV settings
@export var normal_fov: float = 75.0
@export var sprint_fov: float = 85.0
@export var fov_transition_speed: float = 8.0

# Crouch camera settings
@export var crouch_camera_height: float = 1.0
@export var stand_camera_height: float = 1.6
@export var crouch_transition_speed: float = 10.0
@export var crouch_camera_tilt: float = 0.1
@export var crouch_dip_duration: float = 0.5

# Head bob settings (rotation-based in radians)
@export var bob_freq_walk: float = 1.5
@export var bob_freq_sprint: float = 2.0
@export var bob_amp_walk: float = 0.015
@export var bob_amp_sprint: float = 0.017
@export var bob_sway_walk: float = 0.012
@export var bob_sway_sprint: float = 0.02
@export var bob_randomness: float = 0.15

# Idle breathing settings
@export var breathing_freq: float = 0.5
@export var breathing_amp: float = 0.02

# Camera roll settings
@export var camera_roll_amount: float = 1.0
@export var camera_roll_speed: float = 6.5

# Landing camera tilt settings
@export var landing_tilt_intensity: float = 0.05
@export var landing_fall_time_multiplier: float = 0.5
@export var landing_dip_speed: float = 5.0
@export var landing_recovery_speed: float = 5.0

# Weapon recoil camera settings
@export var recoil_intensity: float = 0.05
@export var recoil_kick_speed: float = 12.0
@export var recoil_recovery_speed: float = 6.0

# Vertical velocity camera pitch
@export var vertical_velocity_pitch_intensity: float = 0.01
@export var vertical_velocity_pitch_speed: float = 8.0

# Mouse sensitivity
@export var mouse_sensitivity: float = 0.003

# Camera state variables
var head_bob_time: float = 0.0
var base_camera_y: float
var mouse_look_rotation: float = 0.0
var current_bob_rotation: Vector3 = Vector3.ZERO
var crouch_dip_time: float = 0.0
var current_crouch_tilt: float = 0.0
var bob_random_offset: float = 0.0
var bob_random_time: float = 0.0
var movement_blend: float = 0.0
var mouse_velocity: float = 0.0
var current_camera_roll: float = 0.0
var target_landing_tilt: float = 0.0
var current_landing_tilt: float = 0.0
var target_recoil: float = 0.0
var current_recoil: float = 0.0
var fall_time: float = 0.0
var target_vertical_pitch: float = 0.0
var current_vertical_pitch: float = 0.0

# External state (set by player)
var camera: Camera3D = null
var is_sprinting: bool = false
var is_crouching: bool = false
var was_crouching: bool = false
var is_on_floor: bool = false
var horizontal_velocity: float = 0.0
var vertical_velocity: float = 0.0
var previous_y_velocity: float = 0.0
var player_inventory: PlayerInventory = null


func _ready() -> void:
	# Get camera from parent
	var player = get_parent()
	if player:
		camera = player.get_node_or_null("Camera3D")

	if not camera:
		push_error("PlayerCamera: Could not find Camera3D")
		return

	# Set initial FOV and camera height
	camera.fov = normal_fov
	base_camera_y = stand_camera_height
	print("PlayerCamera: initialized with FOV %.1f" % normal_fov)


## Handle mouse input for camera look
func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not camera:
		return

	var player = get_parent()
	if not player:
		return

	# Rotate the body horizontally
	player.rotate_y(-event.relative.x * mouse_sensitivity)

	# Track horizontal mouse velocity for camera roll
	mouse_velocity = -event.relative.x * mouse_sensitivity

	# Update vertical mouse look rotation
	mouse_look_rotation -= event.relative.y * mouse_sensitivity
	mouse_look_rotation = clamp(mouse_look_rotation, deg_to_rad(-90), deg_to_rad(90))


## Update camera effects each frame
func update_camera(delta: float) -> void:
	if not camera:
		return

	# Update crouch camera height transition
	_update_crouch_camera(delta)

	# Update FOV transition
	_update_fov(delta)

	# Apply head bob and breathing rotation
	var target_bob_rotation = _calculate_headbob(delta)
	current_bob_rotation = _smooth_lerp_vec3(current_bob_rotation, target_bob_rotation, 15.0, delta)

	# Calculate camera roll based on horizontal mouse movement
	var target_roll = mouse_velocity * camera_roll_amount
	current_camera_roll = _smooth_lerp(current_camera_roll, target_roll, camera_roll_speed, delta)

	# Decay mouse velocity over time
	mouse_velocity = _smooth_lerp(mouse_velocity, 0.0, 10.0, delta)

	# Update landing tilt
	_update_landing_tilt(delta)

	# Update recoil
	_update_recoil(delta)

	# Update vertical velocity pitch
	target_vertical_pitch = -vertical_velocity * vertical_velocity_pitch_intensity
	current_vertical_pitch = _smooth_lerp(current_vertical_pitch, target_vertical_pitch, vertical_velocity_pitch_speed, delta)

	# Set camera position
	camera.position.y = base_camera_y
	camera.position.x = 0.0
	camera.position.z = 0.0

	# Apply all camera rotations
	camera.rotation.x = mouse_look_rotation + current_bob_rotation.x + current_crouch_tilt + current_landing_tilt + current_recoil + current_vertical_pitch
	camera.rotation.z = current_bob_rotation.z + current_camera_roll
	camera.rotation.y = current_bob_rotation.y

	# Store previous velocity for landing detection
	previous_y_velocity = vertical_velocity


func _update_crouch_camera(delta: float) -> void:
	# Detect crouch transition and trigger dip animation
	if is_crouching and not was_crouching:
		crouch_dip_time = 0.0  # Start the dip animation

	# Adjust camera height for crouching
	var target_camera_height = crouch_camera_height if is_crouching else stand_camera_height
	base_camera_y = _smooth_lerp(base_camera_y, target_camera_height, crouch_transition_speed, delta)

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
	current_crouch_tilt = _smooth_lerp(current_crouch_tilt, target_crouch_tilt, 20.0, delta)

	# Store previous crouch state for next frame
	was_crouching = is_crouching


func _update_fov(delta: float) -> void:
	# Weapon aiming takes priority over sprint FOV
	var target_fov = normal_fov
	if player_inventory and player_inventory.is_weapon_aiming():
		# Use weapon's aim FOV if aiming
		var weapon_fov = player_inventory.get_weapon_aim_fov()
		if weapon_fov > 0.0:
			target_fov = weapon_fov
	elif is_sprinting:
		target_fov = sprint_fov

	camera.fov = _smooth_lerp(camera.fov, target_fov, fov_transition_speed, delta)


func _update_landing_tilt(delta: float) -> void:
	# Track fall time
	if not is_on_floor and vertical_velocity < -1.0:
		fall_time += delta
	else:
		fall_time = 0.0

	# Detect landing (was falling, now on floor) - velocity-dependent
	if is_on_floor and previous_y_velocity < -1.0:
		# Set target downward tilt based on fall velocity AND fall duration
		var fall_speed = abs(previous_y_velocity)
		var fall_time_scale = 1.0 + (fall_time * landing_fall_time_multiplier)
		target_landing_tilt = -fall_speed * landing_tilt_intensity * fall_time_scale
		print("Landing! Fall speed: ", fall_speed, " Fall time: ", fall_time, " Target tilt: ", target_landing_tilt)

	# Target landing tilt smoothly returns to 0
	target_landing_tilt = _smooth_lerp(target_landing_tilt, 0.0, landing_recovery_speed, delta)

	# Current landing tilt smoothly follows target
	current_landing_tilt = _smooth_lerp(current_landing_tilt, target_landing_tilt, landing_dip_speed, delta)


func _update_recoil(delta: float) -> void:
	# Target recoil smoothly returns to 0
	target_recoil = _smooth_lerp(target_recoil, 0.0, recoil_recovery_speed, delta)

	# Current recoil smoothly follows target
	current_recoil = _smooth_lerp(current_recoil, target_recoil, recoil_kick_speed, delta)


func _calculate_headbob(delta: float) -> Vector3:
	# Update random offset periodically for variation
	bob_random_time += delta
	if bob_random_time > 0.5:
		bob_random_offset = randf_range(-bob_randomness, bob_randomness)
		bob_random_time = 0.0

	# Smoothly blend between idle and moving states
	var is_moving = horizontal_velocity > 0.1 and is_on_floor
	var target_blend = 1.0 if is_moving else 0.0
	movement_blend = _smooth_lerp(movement_blend, target_blend, 5.0, delta)

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
	var time_speed = 1.0 + lerp(0.0, horizontal_velocity - 1.0, movement_blend)
	head_bob_time += delta * blended_freq * time_speed * (1.0 + random_time_offset)

	# Add random variation to amplitude
	var amp_variation = 1.0 + (bob_random_offset * 0.3)

	# Calculate rotation with blended parameters
	var rotation = Vector3.ZERO
	rotation.x = sin(head_bob_time * 2.0) * blended_amp * amp_variation  # Forward/back motion
	rotation.z = cos(head_bob_time) * blended_amp * 0.3 * amp_variation  # Subtle side tilt
	rotation.y = sin(head_bob_time) * blended_sway * amp_variation  # Left-to-right head sway

	return rotation


## Apply recoil effect to camera (called by weapons)
func apply_recoil(amount: float = 1.0) -> void:
	# Set target recoil to kick up (positive pitch = look up)
	target_recoil = amount * recoil_intensity
	print("Recoil applied! Amount: ", target_recoil)


# Smooth interpolation with easing (ease out for natural deceleration)
func _smooth_lerp(current: float, target: float, speed: float, delta_time: float) -> float:
	var difference = target - current
	var change = difference * (1.0 - exp(-speed * delta_time))
	return current + change


# Smooth interpolation for Vector3 with easing
func _smooth_lerp_vec3(current: Vector3, target: Vector3, speed: float, delta_time: float) -> Vector3:
	return Vector3(
		_smooth_lerp(current.x, target.x, speed, delta_time),
		_smooth_lerp(current.y, target.y, speed, delta_time),
		_smooth_lerp(current.z, target.z, speed, delta_time)
	)
