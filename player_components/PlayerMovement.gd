class_name PlayerMovement
extends Node

## Handles all player movement (walk/sprint/crouch/jump), stamina, weight penalties, and footstep alerts
## Core system with many dependencies

# Movement settings
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.0
@export var crouch_speed: float = 1.5

# Weight system
@export var weight_penalty_per_lb: float = 0.2
@export var max_weight_penalty: float = 50.0
@export var acceleration: float = 10.0
@export var deceleration: float = 8.0
@export var jump_velocity: float = 4.5

# Stamina settings
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 15.0
@export var stamina_regen_rate: float = 30.0
@export var min_stamina_to_sprint: float = 10.0
@export var stamina_regen_delay: float = 1.0

# Crouch settings
@export var crouch_height: float = 0.9
@export var stand_height: float = 1.8

# Debug mode (toggle with H key)
var debug_speed_enabled: bool = false
const DEBUG_SPRINT_SPEED: float = 30.0
const DEBUG_STAMINA_DRAIN: float = 1.0

# Movement state
var speed: float
var current_stamina: float
var is_sprinting: bool = false
var is_crouching: bool = false
var is_stamina_depleted: bool = false
var time_since_stopped_sprinting: float = 0.0

# Footstep alerts
var footstep_timer: float = 0.0
var footstep_interval: float = 0.5

# Danger zone tracking
var current_danger_level: float = 1.0
var current_danger_zone: int = 1

# Spawn frequency tracking
var spawn_frequency: float = 0.0

# External dependencies (set by player)
var player_node: CharacterBody3D = null
var collision_shape: CollisionShape3D = null
var player_inventory: PlayerInventory = null
var player_health: PlayerHealth = null
var player_ui: PlayerUI = null
var perk_manager: PerkManager = null
var alert_system: AlertSystem = null


func _ready() -> void:
	player_node = get_parent()
	speed = walk_speed

	# Apply perk multipliers to max stamina
	var stamina_multiplier = 1.0
	if perk_manager:
		stamina_multiplier = perk_manager.get_total_multiplier("stamina")
	current_stamina = max_stamina * stamina_multiplier

	print("PlayerMovement: initialized with max stamina %.1f" % (max_stamina * stamina_multiplier))


## Handle physics and movement each frame
func physics_process(delta: float, gravity: float) -> void:
	if not player_node:
		return

	var velocity = player_node.velocity

	# Apply gravity
	if not player_node.is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump (can't jump while crouching)
	if Input.is_action_just_pressed("ui_accept") and player_node.is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	# Handle crouch
	is_crouching = Input.is_action_pressed("crouch")

	# Adjust collision shape for crouching
	_update_collision_shape(delta)

	# Update adrenaline (from PlayerHealth)
	var adrenaline_active = player_health and player_health.adrenaline_active

	# Handle sprint with stamina
	_handle_sprint(delta, adrenaline_active)

	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (player_node.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Apply movement with acceleration/deceleration
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta * speed)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta * speed)
	else:
		velocity.x = move_toward(velocity.x, 0, deceleration * delta * speed)
		velocity.z = move_toward(velocity.z, 0, deceleration * delta * speed)

	# Update player velocity
	player_node.velocity = velocity
	player_node.move_and_slide()

	# Update danger zone tracking
	_update_danger_zone()

	# Emit footstep alerts
	_emit_footstep_alerts(delta)


func _update_collision_shape(delta: float) -> void:
	if not collision_shape:
		return

	var target_height = crouch_height if is_crouching else stand_height

	if collision_shape.shape is CapsuleShape3D:
		var capsule = collision_shape.shape as CapsuleShape3D
		capsule.height = _smooth_lerp(capsule.height, target_height, 10.0, delta)
		collision_shape.position.y = _smooth_lerp(collision_shape.position.y, target_height / 2.0, 10.0, delta)


func _handle_sprint(delta: float, adrenaline_active: bool) -> void:
	# Check if player wants to sprint
	var is_moving_forward = Input.is_action_pressed("move_forward")
	var is_moving_backward = Input.is_action_pressed("move_backward")
	var is_aiming = player_inventory and player_inventory.is_weapon_aiming()
	var is_reloading = player_inventory and player_inventory.is_weapon_reloading()
	var wants_to_sprint = Input.is_action_pressed("sprint") and player_node.is_on_floor() and not is_crouching and is_moving_forward and not is_moving_backward and not is_aiming and not is_reloading
	var can_sprint = (current_stamina > 0.0 and not is_stamina_depleted) or adrenaline_active

	if wants_to_sprint and can_sprint:
		is_sprinting = true

		# Get weight multiplier (affects all speeds except debug mode)
		var weight_multiplier = _get_weight_speed_multiplier()

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
		var weight_multiplier = _get_weight_speed_multiplier()

		if is_crouching:
			speed = crouch_speed * weight_multiplier
		else:
			speed = walk_speed * weight_multiplier
		time_since_stopped_sprinting += delta

		# Regenerate stamina only after delay
		if time_since_stopped_sprinting >= stamina_regen_delay:
			current_stamina += stamina_regen_rate * delta

			# Apply perk multiplier to max stamina
			var stamina_multiplier = 1.0
			if perk_manager:
				stamina_multiplier = perk_manager.get_total_multiplier("stamina")
			var effective_max_stamina = max_stamina * stamina_multiplier

			current_stamina = min(current_stamina, effective_max_stamina)

			# Reset depleted flag when fully recharged
			if current_stamina >= effective_max_stamina:
				is_stamina_depleted = false

	# Update stamina bar in UI
	if player_ui:
		player_ui.update_stamina_bar(current_stamina, is_stamina_depleted)


func _get_weight_speed_multiplier() -> float:
	# Get total weight from inventory
	var total_weight: float = 0.0
	if player_inventory and player_inventory.inventory_ui:
		total_weight = player_inventory.inventory_ui.get_total_weight()

	# Calculate penalty - simple linear: 1 lb = weight_penalty_per_lb% slowdown
	var penalty_percent = min(max_weight_penalty, total_weight * weight_penalty_per_lb)

	# Apply perk multiplier to weight penalty (Pack Mule reduces penalty)
	if perk_manager:
		var perk_mult = perk_manager.get_total_multiplier("weight_penalty")
		penalty_percent *= perk_mult

	var multiplier = 1.0 - (penalty_percent / 100.0)

	return clamp(multiplier, 0.5, 1.0)  # Never go below 50% speed


func _emit_footstep_alerts(delta: float) -> void:
	if not alert_system or not player_node:
		return

	var horizontal_velocity = Vector2(player_node.velocity.x, player_node.velocity.z).length()

	if horizontal_velocity > 0.5 and player_node.is_on_floor():
		footstep_timer += delta
		if footstep_timer >= footstep_interval:
			footstep_timer = 0.0
			alert_system.alert_footstep(player_node.global_position, is_sprinting, is_crouching)


func _update_danger_zone() -> void:
	if not player_node:
		return

	# Find the DangerZoneManager in the scene
	var forest = player_node.get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = player_node.get_node_or_null("/root/TestLevel/ForestGenerator")

	if forest and "danger_manager" in forest:
		var danger_manager = forest.danger_manager
		if danger_manager:
			# Get current danger level based on player position
			current_danger_level = danger_manager.get_danger_level(player_node.global_position)
			current_danger_zone = danger_manager.get_danger_zone(current_danger_level)

			# Check if it's night time and increase danger zone by 1
			var daylight_system = player_node.get_tree().get_first_node_in_group("daylight_system")
			if daylight_system and daylight_system.has_method("is_night_time"):
				if daylight_system.is_night_time():
					current_danger_zone = min(current_danger_zone + 1, 4)  # Cap at zone 4

			# Update UI
			if player_ui:
				player_ui.update_danger_label(current_danger_zone, current_danger_level)


## Adjust spawn frequency (called from input handling)
func adjust_frequency(delta: float) -> void:
	if not player_node:
		return

	spawn_frequency += delta
	spawn_frequency = clampf(spawn_frequency, 0.0, 10.0)

	# Update spawn manager
	var forest = player_node.get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = player_node.get_node_or_null("/root/TestLevel/ForestGenerator")

	if forest and "spawn_manager" in forest:
		var spawn_manager = forest.spawn_manager
		if spawn_manager:
			spawn_manager.set_frequency(spawn_frequency)

	# Update UI
	if player_ui:
		player_ui.update_frequency_label(spawn_frequency)


## Toggle debug speed mode
func toggle_debug_speed() -> void:
	debug_speed_enabled = not debug_speed_enabled
	if debug_speed_enabled:
		print("DEBUG: Super speed ENABLED (sprint speed: %.1f, stamina drain: %.1f)" % [DEBUG_SPRINT_SPEED, DEBUG_STAMINA_DRAIN])
	else:
		print("DEBUG: Super speed DISABLED (normal speeds restored)")


## Initialize stamina bar in UI
func initialize_stamina_ui() -> void:
	if not player_ui:
		return

	# Apply perk multipliers to max stamina
	var stamina_multiplier = 1.0
	if perk_manager:
		stamina_multiplier = perk_manager.get_total_multiplier("stamina")
	var effective_max_stamina = max_stamina * stamina_multiplier

	player_ui.initialize_stamina_bar(effective_max_stamina, current_stamina)


## Get horizontal velocity for camera effects
func get_horizontal_velocity() -> float:
	if not player_node:
		return 0.0
	return Vector2(player_node.velocity.x, player_node.velocity.z).length()


## Get vertical velocity for camera effects
func get_vertical_velocity() -> float:
	if not player_node:
		return 0.0
	return player_node.velocity.y


# Smooth interpolation with easing
func _smooth_lerp(current: float, target: float, speed: float, delta_time: float) -> float:
	var difference = target - current
	var change = difference * (1.0 - exp(-speed * delta_time))
	return current + change
