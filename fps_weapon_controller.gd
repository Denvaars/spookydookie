extends Node3D

## FPS Weapon Animation Controller
## Manages weapon models and animations for first-person view

@onready var animation_player: AnimationPlayer = $animations_fps/AnimationPlayer
@onready var weapon_rig: Node3D = $animations_fps
var shotgun_mesh: MeshInstance3D = null
var flashlight_mesh: MeshInstance3D = null
var arms_mesh: MeshInstance3D = null

# Track current weapon
var current_weapon: String = ""

# Animation State Machine
enum AnimState {
	IDLE_HIP,
	WALK_HIP,
	AIMING_IN,
	IDLE_AIMED,
	WALK_AIMED,
	AIMING_OUT,
	SHOOTING,
	COCKING,
	RELOADING,
	EQUIPPING,
	SPRINTING_IN,
	SPRINTING,
	SPRINTING_OUT
}

var current_state: AnimState = AnimState.IDLE_HIP
var is_aiming: bool = false
var is_walking: bool = false
var is_sprinting: bool = false

# FOV compensation - adjust this to match your Blender camera
@export var weapon_scale: float = 1.0
@export var weapon_offset: Vector3 = Vector3.ZERO

# Weapon Sway Settings
@export_group("Weapon Sway")
@export var sway_enabled: bool = true
@export var view_sway_intensity: float = -2.0  # Looking around tilt intensity
@export var movement_sway_horizontal_intensity: float = 1.5  # Horizontal movement position sway (strafe/forward)
@export var movement_sway_vertical_intensity: float = 5  # Vertical movement position sway (jump/fall)
@export var movement_roll_intensity: float = 15.0  # Movement-based roll intensity
@export var ads_sway_multiplier: float = 0.25  # Sway intensity when aiming (0.0 - 1.0)
@export var sway_smoothness: float = 2.5  # How fast sway responds
@export var max_sway_pitch: float = 10.0  # Max pitch rotation in degrees
@export var max_sway_yaw: float = 10.0  # Max yaw rotation in degrees
@export var max_sway_roll: float = 5.0  # Max roll rotation in degrees

# Sway state
var camera_prev_rotation: Vector2 = Vector2.ZERO  # x = camera pitch, y = player yaw
var sway_rotation_offset: Vector3 = Vector3.ZERO
var sway_position_offset: Vector3 = Vector3.ZERO
var base_rotation: Vector3 = Vector3.ZERO  # Store the original rotation of FPSArms node
var prev_vertical_velocity: float = 0.0  # Track previous vertical velocity for landing detection
var landing_bounce_offset: float = 0.0  # Bounce offset when landing
var landing_bounce_velocity: float = 0.0  # Velocity for bounce spring effect

func _ready() -> void:
	# Store base rotation of FPSArms node (before sway is applied)
	base_rotation = rotation_degrees
	print("FPSArms base_rotation: ", base_rotation)

	# Find meshes (they might be nested deeper in the hierarchy)
	shotgun_mesh = find_child("Shotgun", true, false)
	flashlight_mesh = find_child("flashlight", true, false)
	arms_mesh = find_child("arms", true, false)

	# Apply scale and offset to compensate for FOV difference
	if weapon_rig:
		weapon_rig.scale = Vector3.ONE * weapon_scale
		weapon_rig.position = weapon_offset

	# Connect to animation finished signal
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	# Initialize rotation tracking for sway system
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var main_camera = player.get_node_or_null("Camera3D")
		if main_camera:
			# Track camera pitch (X) and player yaw (Y)
			camera_prev_rotation = Vector2(main_camera.rotation.x, player.rotation.y)

	# Hide all weapons by default
	hide_all_weapons()

func _process(_delta: float) -> void:
	# Weapon Sway - react to camera movement
	if sway_enabled:
		apply_weapon_sway(_delta)

	# Update walking and sprinting state based on player movement
	var player = get_tree().get_first_node_in_group("player")
	if player and player is CharacterBody3D:
		var velocity_2d = Vector2(player.velocity.x, player.velocity.z)
		var was_walking = is_walking
		var was_sprinting = is_sprinting

		is_walking = velocity_2d.length() > 0.1

		# Check if player is sprinting (has is_sprinting property)
		if "is_sprinting" in player:
			is_sprinting = player.is_sprinting
		else:
			is_sprinting = false

		# Handle sprint state changes
		if was_sprinting != is_sprinting:
			if is_sprinting:
				# Started sprinting - transition to sprint
				match current_state:
					AnimState.IDLE_HIP, AnimState.WALK_HIP:
						transition_to(AnimState.SPRINTING_IN)
					AnimState.SPRINTING_OUT:
						# Interrupt sprint out with sprint in (player changed mind)
						transition_to(AnimState.SPRINTING_IN)
					# Can't sprint while aiming
					_:
						pass
			else:
				# Stopped sprinting - exit sprint
				match current_state:
					AnimState.SPRINTING, AnimState.SPRINTING_IN:
						transition_to(AnimState.SPRINTING_OUT)

		# If walking state changed, transition to appropriate state
		# But DON'T interrupt aim transitions, sprint transitions, etc.
		elif was_walking != is_walking and not is_sprinting:
			match current_state:
				AnimState.IDLE_HIP:
					if is_walking:
						transition_to(AnimState.WALK_HIP)
				AnimState.WALK_HIP:
					if not is_walking:
						transition_to(AnimState.IDLE_HIP)
				AnimState.IDLE_AIMED:
					if is_walking:
						transition_to(AnimState.WALK_AIMED)
				AnimState.WALK_AIMED:
					if not is_walking:
						transition_to(AnimState.IDLE_AIMED)

				AnimState.AIMING_IN, AnimState.AIMING_OUT:
					# Don't interrupt aim transitions with walk state changes
					pass

				AnimState.RELOADING:
					# Don't interrupt reload with walk state changes
					pass

# Soft clamp function - smoothly approaches limit instead of hard stopping
func soft_clamp(value: float, min_val: float, max_val: float) -> float:
	if value > max_val:
		# Smooth curve as it approaches max
		var excess = value - max_val
		return max_val + excess / (1.0 + abs(excess))
	elif value < min_val:
		# Smooth curve as it approaches min
		var excess = value - min_val
		return min_val + excess / (1.0 + abs(excess))
	else:
		return value

func apply_weapon_sway(_delta: float) -> void:
	# Get the weapon camera (parent node)
	var camera = get_parent()
	if not camera or not camera is Camera3D:
		return

	# Find the player from the scene tree (since FPSArms is now in SubViewport, not under Player)
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player is CharacterBody3D:
		return

	# Get the main camera from the player
	var main_camera = player.get_node_or_null("Camera3D")
	if not main_camera:
		return

	# Get current rotation: main camera pitch (X) and player yaw (Y)
	# Player body rotates for yaw, camera only pitches up/down
	var current_rotation = Vector2(main_camera.rotation.x, player.rotation.y)

	# Calculate rotation delta (how much the view moved this frame)
	var rotation_delta = current_rotation - camera_prev_rotation

	# Normalize angle deltas to handle wrapping (-PI to PI transitions)
	rotation_delta.x = wrapf(rotation_delta.x, -PI, PI)
	rotation_delta.y = wrapf(rotation_delta.y, -PI, PI)

	# Sway multiplier (reduced when aiming)
	var sway_mult = ads_sway_multiplier if is_aiming else 1.0

	# Get camera roll from main camera for additional sway
	var camera_roll = main_camera.rotation.z

	# === VIEW SWAY (camera rotation based) ===
	var target_view_tilt = Vector3(
		-rotation_delta.x * 50.0 * view_sway_intensity * sway_mult,  # Pitch tilt (opposite of up/down look)
		rotation_delta.y * 30.0 * view_sway_intensity * sway_mult,   # Yaw tilt (opposite of left/right look)
		-rotation_delta.y * 20.0 * view_sway_intensity * sway_mult - camera_roll * rad_to_deg(1.0) * 15.0 * sway_mult   # Roll tilt (gun leans into turns + follows camera roll)
	)

	# === MOVEMENT SWAY (velocity based - position + roll) ===
	# Get player velocity in local space (relative to where player is facing)
	var velocity = player.velocity
	var velocity_local = Vector3(
		velocity.dot(player.global_transform.basis.x),  # Right/left movement
		velocity.y,  # Up/down movement (vertical)
		velocity.dot(player.global_transform.basis.z)   # Forward/back movement
	)

	# Normalize to -1 to 1 range (assume max speed ~5 units/sec for horizontal, ~10 for vertical)
	var normalized_velocity = Vector3(
		velocity_local.x / 5.0,
		velocity_local.y / 10.0,  # Vertical velocity can be higher (jumping/falling)
		velocity_local.z / 5.0
	)

	# Detect sudden vertical velocity changes (landing)
	var vertical_velocity_change = velocity_local.y - prev_vertical_velocity
	if vertical_velocity_change > 3.0:  # Landed (sudden upward velocity change)
		# Add downward bounce impulse (stronger multiplier for noticeable effect)
		landing_bounce_velocity = -vertical_velocity_change * 0.01 * movement_sway_vertical_intensity
		print("Landing detected! Velocity change: ", vertical_velocity_change, " Bounce velocity: ", landing_bounce_velocity)
	prev_vertical_velocity = velocity_local.y

	# Apply spring physics to landing bounce
	var spring_stiffness = 100.0  # Increased for snappier response
	var spring_damping = 5.0  # Reduced for more bounce
	landing_bounce_velocity += -landing_bounce_offset * spring_stiffness * _delta
	landing_bounce_velocity *= (1.0 - spring_damping * _delta)
	landing_bounce_offset += landing_bounce_velocity * _delta

	# Calculate movement-based position offset (weapon moves with movement)
	var target_movement_position = Vector3(
		-normalized_velocity.x * 0.015 * movement_sway_horizontal_intensity * sway_mult,  # Move opposite to strafe (left = weapon right)
		-normalized_velocity.y * 0.02 * movement_sway_vertical_intensity * sway_mult - abs(normalized_velocity.z) * 0.008 * movement_sway_horizontal_intensity * sway_mult - abs(normalized_velocity.x) * 0.005 * movement_sway_horizontal_intensity * sway_mult + landing_bounce_offset,  # Move opposite to vertical velocity + dip when moving + landing bounce
		normalized_velocity.z * 0.01 * movement_sway_horizontal_intensity * sway_mult  # Move back when moving forward
	)

	# Calculate movement-based roll tilt (weapon leans into strafe)
	var target_movement_tilt = Vector3(
		0.0,  # No pitch from movement
		0.0,  # No yaw from movement
		normalized_velocity.x * movement_roll_intensity * sway_mult  # Roll tilt when strafing
	)

	# === COMBINE ALL SWAY ===
	var target_sway_rotation = target_view_tilt + target_movement_tilt  # View sway + movement roll
	var target_sway_position = target_movement_position  # Only movement sway affects position

	# Smooth interpolation to targets
	sway_rotation_offset = sway_rotation_offset.lerp(target_sway_rotation, sway_smoothness * _delta)
	sway_position_offset = sway_position_offset.lerp(target_sway_position, sway_smoothness * _delta)

	# Soft clamp rotation sway to max angles (smoothly slows down as it approaches limits)
	sway_rotation_offset.x = soft_clamp(sway_rotation_offset.x, -max_sway_pitch, max_sway_pitch)
	sway_rotation_offset.y = soft_clamp(sway_rotation_offset.y, -max_sway_yaw, max_sway_yaw)
	sway_rotation_offset.z = soft_clamp(sway_rotation_offset.z, -max_sway_roll, max_sway_roll)

	# Apply sway to the weapon_rig child
	if weapon_rig:
		weapon_rig.rotation_degrees = sway_rotation_offset
		weapon_rig.position = weapon_offset + sway_position_offset

	# Store current rotation for next frame
	camera_prev_rotation = current_rotation

func transition_to(new_state: AnimState) -> void:
	print("TRANSITION: ", AnimState.keys()[current_state], " -> ", AnimState.keys()[new_state])
	current_state = new_state

	# Play the appropriate animation for this state
	match current_state:
		AnimState.IDLE_HIP:
			play_animation(current_weapon + "_hip_idle", true, 0.2)      # slow, floaty blend
		AnimState.WALK_HIP:
			play_animation(current_weapon + "_hip_walk", true, 0.2)       # slow, floaty blend
		AnimState.AIMING_IN:
			print("  -> Playing ", current_weapon, "_aim")
			# Flashlight doesn't have aim-in transition, go straight to aim_idle
			if current_weapon == "flashlight":
				transition_to(AnimState.IDLE_AIMED)
			else:
				play_animation(current_weapon + "_aim", false, 0.1)           # snappy aim-in
		AnimState.IDLE_AIMED:
			print("  -> Playing ", current_weapon, "_aim_idle (loop)")
			play_animation(current_weapon + "_aim_idle", true, 0.15)
		AnimState.WALK_AIMED:
			print("  -> Playing ", current_weapon, "_aim_walk (loop)")
			play_animation(current_weapon + "_aim_walk", true, 0.2)
		AnimState.AIMING_OUT:
			print("  -> Playing ", current_weapon, "_aim backwards")
			# Flashlight doesn't have aim-out transition, go straight to hip
			if current_weapon == "flashlight":
				if is_sprinting:
					transition_to(AnimState.SPRINTING_IN)
				elif is_walking:
					transition_to(AnimState.WALK_HIP)
				else:
					transition_to(AnimState.IDLE_HIP)
			else:
				if animation_player:
					# Make sure aim animation isn't looping before playing backwards
					var anim = animation_player.get_animation(current_weapon + "_aim")
					if anim:
						anim.loop_mode = Animation.LOOP_NONE
					animation_player.play_backwards(current_weapon + "_aim", 0.1)  # snappy aim-out
		AnimState.SHOOTING:
			# Handled by play_shoot()
			pass
		AnimState.COCKING:
			# Handled by shotgun.gd timing
			pass
		AnimState.RELOADING:
			play_animation(current_weapon + "_reload", false, 0.1)        # quick snap into reload
		AnimState.EQUIPPING:
			var equip_anim = current_weapon + "_equip"
			if animation_player and animation_player.has_animation(equip_anim):
				play_animation(equip_anim, false, 0.0)     # no blend, clean cut on equip
			else:
				# No equip animation, go straight to idle
				transition_to(AnimState.IDLE_HIP)
		AnimState.SPRINTING_IN:
			print("  -> Playing ", current_weapon, "_sprint (transition)")
			# Flashlight only has sprinting loop, no sprint-in transition
			if current_weapon == "flashlight":
				transition_to(AnimState.SPRINTING)
			else:
				play_animation(current_weapon + "_sprint", false, 0.1)        # quick blend into sprint
		AnimState.SPRINTING:
			print("  -> Playing ", current_weapon, "_sprinting (loop)")
			play_animation(current_weapon + "_sprinting", true, 0.2)      # looping sprint
		AnimState.SPRINTING_OUT:
			print("  -> Playing ", current_weapon, "_sprint backwards")
			# Flashlight doesn't have sprint-out transition, go straight to hip
			if current_weapon == "flashlight":
				if is_aiming:
					transition_to(AnimState.AIMING_IN)
				elif is_walking:
					transition_to(AnimState.WALK_HIP)
				else:
					transition_to(AnimState.IDLE_HIP)
			else:
				if animation_player:
					# Play sprint animation backwards to return to hip
					var anim = animation_player.get_animation(current_weapon + "_sprint")
					if anim:
						anim.loop_mode = Animation.LOOP_NONE
					animation_player.play_backwards(current_weapon + "_sprint", 0.1)

func _on_animation_finished(anim_name: String) -> void:
	print("Animation finished: ", anim_name, " | State: ", AnimState.keys()[current_state], " | pending_cock: ", pending_cock)

	# Only handle transitions for states that are controlled by animation finishing
	# SHOOTING and COCKING are controlled by timing in shotgun.gd
	match current_state:
		AnimState.AIMING_IN:
			# Aim in finished - check if we need to play cock before going to idle
			if pending_cock:
				print("  -> Aim in finished, playing pending cock with force=true")
				play_cock(true)  # Force play, ignore state check
			else:
				# Check if player stopped aiming during transition
				if not is_aiming:
					# Player unaimed during aim-in, go back out
					transition_to(AnimState.AIMING_OUT)
				# Go to aimed idle/walk
				elif is_walking:
					transition_to(AnimState.WALK_AIMED)
				else:
					transition_to(AnimState.IDLE_AIMED)

		AnimState.AIMING_OUT:
			# Aim out finished - check if we need to play cock before going to idle
			if pending_cock:
				print("  -> Aim out finished, playing pending cock with force=true")
				play_cock(true)  # Force play, ignore state check
			else:
				# Check if player started aiming again during unaim
				if is_aiming:
					# Player re-aimed during aim-out, go back in
					transition_to(AnimState.AIMING_IN)
				# Check if we should go into sprint instead of idle/walk
				elif is_sprinting:
					transition_to(AnimState.SPRINTING_IN)
				# Go to hip idle/walk
				elif is_walking:
					transition_to(AnimState.WALK_HIP)
				else:
					transition_to(AnimState.IDLE_HIP)

		AnimState.RELOADING:
			# Don't transition on animation finished - reload has multiple sub-animations
			# The weapon script (shotgun.gd) will call finish_reload() when truly done
			pass

		AnimState.EQUIPPING:
			# Equip finished, transition to appropriate state based on player state
			if is_sprinting:
				transition_to(AnimState.SPRINTING_IN)
			elif is_aiming:
				transition_to(AnimState.AIMING_IN)
			elif is_walking:
				transition_to(AnimState.WALK_HIP)
			else:
				transition_to(AnimState.IDLE_HIP)

		AnimState.SPRINTING_IN:
			# Sprint in finished - check if still sprinting
			if not is_sprinting:
				# Player stopped sprinting during transition
				transition_to(AnimState.SPRINTING_OUT)
			else:
				# Go to looping sprint
				transition_to(AnimState.SPRINTING)

		AnimState.SPRINTING_OUT:
			# Sprint out finished - check if player changed state during transition
			if is_sprinting:
				# Player started sprinting again during sprint-out
				transition_to(AnimState.SPRINTING_IN)
			elif is_aiming:
				# Player was trying to aim, transition to aiming now
				transition_to(AnimState.AIMING_IN)
			elif is_walking:
				transition_to(AnimState.WALK_HIP)
			else:
				transition_to(AnimState.IDLE_HIP)

		AnimState.SHOOTING, AnimState.COCKING:
			# These are controlled by timing, not animation finishing
			# Do nothing - timing system will call finish_cocking()
			pass

func hide_all_weapons() -> void:
	if shotgun_mesh:
		shotgun_mesh.visible = false
	if flashlight_mesh:
		flashlight_mesh.visible = false
	if arms_mesh:
		arms_mesh.visible = false

	# Reset state
	current_state = AnimState.IDLE_HIP
	is_aiming = false
	is_walking = false
	is_sprinting = false

func show_weapon(weapon_name: String) -> void:
	hide_all_weapons()
	current_weapon = weapon_name
	is_aiming = false
	is_walking = false
	is_sprinting = false

	match weapon_name:
		"shotgun":
			if shotgun_mesh:
				shotgun_mesh.visible = true
			if arms_mesh:
				arms_mesh.visible = true
			play_equip()
		"flashlight":
			if flashlight_mesh:
				flashlight_mesh.visible = true
			if arms_mesh:
				arms_mesh.visible = true
			play_equip()
		_:
			print("Unknown weapon: ", weapon_name)

func set_aiming(aiming: bool) -> void:
	var old_aiming = is_aiming
	is_aiming = aiming

	# Don't transition if aim state didn't actually change
	if old_aiming == is_aiming:
		return

	print("set_aiming called: ", is_aiming, " | Current state: ", AnimState.keys()[current_state], " | Current anim: ", animation_player.current_animation if animation_player else "none")

	# Aim transitions can interrupt ANYTHING except reloading/equipping
	match current_state:
		AnimState.RELOADING, AnimState.EQUIPPING:
			# Can't aim during these states
			return

		AnimState.SPRINTING_IN, AnimState.SPRINTING:
			# Aiming cancels sprint - transition out of sprint first
			# When sprint out finishes, it will check is_aiming and go to aim
			if is_aiming:
				print(">>> Aiming cancels sprint, transitioning to SPRINTING_OUT")
				transition_to(AnimState.SPRINTING_OUT)
			return

		AnimState.SPRINTING_OUT:
			# Already exiting sprint, the animation_finished handler will check is_aiming
			return

		_:
			# Everything else can be interrupted by aim transitions
			if is_aiming:
				print(">>> Transitioning to AIMING_IN")
				transition_to(AnimState.AIMING_IN)
			else:
				print(">>> Transitioning to AIMING_OUT")
				transition_to(AnimState.AIMING_OUT)

func play_animation(anim_name: String, loop: bool = false, blend: float = 0.15) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		# Get the animation
		var anim = animation_player.get_animation(anim_name)
		if anim:
			# Set loop mode directly on the animation
			if loop:
				anim.loop_mode = Animation.LOOP_LINEAR
			else:
				anim.loop_mode = Animation.LOOP_NONE

		# Play the animation with blend time
		animation_player.play(anim_name, blend)
	else:
		print("Animation not found: ", anim_name)

func stop_animation() -> void:
	if animation_player:
		animation_player.stop()

func play_shoot() -> void:
	# If we're in an aim transition, don't interrupt it with the shoot animation
	# The pending_cock system will handle playing cock after aim finishes
	if current_state == AnimState.AIMING_IN or current_state == AnimState.AIMING_OUT:
		print("Shot during aim transition - skipping shoot animation, will cock after aim finishes")
		return

	current_state = AnimState.SHOOTING
	if is_aiming:
		play_animation(current_weapon + "_aim_shoot", false, 0.05)    # fast snap for shooting
	else:
		play_animation(current_weapon + "_hip_shoot", false, 0.05)    # fast snap for shooting

var pending_cock: bool = false  # Flag to play cock after aim transition finishes

func play_cock(force: bool = false) -> void:
	print("play_cock called (force: ", force, ") | Current state: ", AnimState.keys()[current_state])
	print("play_cock called at: ", animation_player.current_animation, 
		  " position: ", animation_player.current_animation_position,
		  " length: ", animation_player.current_animation_length)
	# If we're in an aim transition, wait for it to finish before playing cock
	# UNLESS force = true (called from animation finished handler)
	if not force and (current_state == AnimState.AIMING_IN or current_state == AnimState.AIMING_OUT):
		print("  -> In aim transition, delaying cock until aim finishes")
		pending_cock = true
		return

	# Clear pending flag
	pending_cock = false

	# Play cock animation for the CURRENT aim state
	current_state = AnimState.COCKING

	var cock_anim = current_weapon + "_aim_cock" if is_aiming else current_weapon + "_hip_cock"

	# Make absolutely sure cock animations don't loop
	if animation_player and animation_player.has_animation(cock_anim):
		var anim = animation_player.get_animation(cock_anim)
		if anim:
			anim.loop_mode = Animation.LOOP_NONE
		animation_player.advance(0)
		animation_player.play(cock_anim, 0.0)          # very short blend, feels snappy
		print("  -> Playing cock: ", cock_anim)

func finish_cocking() -> void:
	# Called by shotgun.gd timing system when cock duration is complete
	print("finish_cocking called | Current state: ", AnimState.keys()[current_state])

	# Don't interrupt aim transitions! Let them finish naturally
	if current_state == AnimState.AIMING_IN or current_state == AnimState.AIMING_OUT:
		print("  -> In aim transition, not interrupting")
		return

	# Only transition to idle/walk if we're still in COCKING state
	if current_state == AnimState.COCKING:
		# Transition to appropriate idle/walk state immediately
		if is_aiming:
			if is_walking:
				transition_to(AnimState.WALK_AIMED)
			else:
				transition_to(AnimState.IDLE_AIMED)
		else:
			# Check if sprinting after cocking
			if is_sprinting:
				transition_to(AnimState.SPRINTING_IN)
			elif is_walking:
				transition_to(AnimState.WALK_HIP)
			else:
				transition_to(AnimState.IDLE_HIP)
	else:
		print("  -> Not in COCKING state, ignoring")

func play_reload() -> void:
	# Legacy method - just plays reload start
	play_reload_start()

func play_reload_start() -> void:
	transition_to(AnimState.RELOADING)
	# Play the start animation specifically
	var reload_start_anim = current_weapon + "_reload_start"
	if animation_player and animation_player.has_animation(reload_start_anim):
		play_animation(reload_start_anim, false, 0.1)
	else:
		# Fallback to old single reload animation
		play_animation(current_weapon + "_reload", false, 0.0)

func play_reload_shell() -> void:
	# Play shell insertion animation (can be called multiple times during reload loop)
	var reload_shell_anim = current_weapon + "_reload_shell"
	if animation_player and animation_player.has_animation(reload_shell_anim):
		play_animation(reload_shell_anim, false, 0.0)  # Quick blend for shell insert

func play_reload_end() -> void:
	# Play reload end animation
	var reload_end_anim = current_weapon + "_reload_end"
	if animation_player and animation_player.has_animation(reload_end_anim):
		play_animation(reload_end_anim, false, 0.1)

func finish_reload() -> void:
	# Called by weapon when reload is completely finished
	# Transition back to appropriate state
	if is_aiming:
		if is_walking:
			transition_to(AnimState.WALK_AIMED)
		else:
			transition_to(AnimState.IDLE_AIMED)
	else:
		# Check if sprinting after reload
		if is_sprinting:
			transition_to(AnimState.SPRINTING_IN)
		elif is_walking:
			transition_to(AnimState.WALK_HIP)
		else:
			transition_to(AnimState.IDLE_HIP)

func play_equip() -> void:
	transition_to(AnimState.EQUIPPING)
