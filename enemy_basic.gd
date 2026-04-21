extends CharacterBody3D

## Basic enemy with state machine AI
## States: IDLE, ALERTED, SEARCHING, CHASING

enum State {
	IDLE,
	ALERTED,
	SEARCHING,
	CHASING
}

# Movement settings
@export var idle_speed: float = 1.0
@export var walk_speed: float = 2.0
@export var chase_speed: float = 4.0
@export var acceleration: float = 8.0
@export var rotation_speed: float = 5.0

# Detection settings
@export var vision_range: float = 25.0
@export var vision_angle: float = 360.0  # Degrees (360 for testing - omnidirectional)
@export var alert_duration: float = 3.0  # How long to stay alerted
@export var search_duration: float = 10.0  # How long to search before giving up

# State variables
var current_state: State = State.IDLE
var player: CharacterBody3D = null
var last_known_player_position: Vector3 = Vector3.ZERO
var time_in_state: float = 0.0
var alert_level: float = 0.0  # 0.0 to 1.0, decays over time

# Debug spam prevention
var last_debug_message: String = ""
var debug_message_count: int = 0

# Navigation
var nav_agent: NavigationAgent3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Visual
var mesh_instance: MeshInstance3D

# Health
@export var max_health: float = 100.0
var current_health: float = max_health

# Damage
@export var damage_per_second: float = 20.0
var damage_cooldown: float = 0.0

func debug_print(message: String) -> void:
	if message == last_debug_message:
		debug_message_count += 1
		if debug_message_count == 2:
			print("  (message repeated, suppressing further spam...)")
		return
	else:
		if debug_message_count > 2:
			print("  (previous message repeated %d times)" % debug_message_count)
		last_debug_message = message
		debug_message_count = 1
		print(message)

func _ready() -> void:
	# Add to enemy group for alert system
	add_to_group("enemy")

	# Find player
	player = get_tree().get_first_node_in_group("player")

	if player:
		print("enemy_basic: found player at ", player.global_position)
	else:
		print("enemy_basic: ERROR - could not find player!")

	# Setup NavigationAgent3D
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 2.0
	nav_agent.path_max_distance = 3.0
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.5
	add_child(nav_agent)

	# Wait for navigation to be ready
	await get_tree().physics_frame
	print("enemy_basic: NavigationAgent3D ready")

	# Setup collision FIRST (so it's the first child)
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.5
	collision.shape = capsule
	collision.position.y = 1.25  # Half of height
	add_child(collision)

	# Create visual (placeholder cube)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 2.5, 1.0)  # Match capsule height
	mesh_instance.mesh = box_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0)  # Bright red enemy
	material.emission_enabled = true
	material.emission = Color(0.5, 0.0, 0.0)  # Glowing red
	mesh_instance.material_override = material
	mesh_instance.position.y = 1.25  # Match collision center
	add_child(mesh_instance)

	# Set collision layers
	collision_layer = 2  # Layer 2 for enemies (bit 1)
	collision_mask = 1   # Collide with world layer 1 (bit 0)

	print("enemy_basic: spawned at %v" % global_position)
	print("enemy_basic: collision setup - layer=%d, mask=%d" % [collision_layer, collision_mask])

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0  # Reset Y velocity when on floor

	# Update state timer
	time_in_state += delta

	# Decay alert level
	alert_level = max(0.0, alert_level - delta * 0.1)

	# Damage cooldown
	if damage_cooldown > 0.0:
		damage_cooldown -= delta

	# Update state machine
	match current_state:
		State.IDLE:
			process_idle(delta)
		State.ALERTED:
			process_alerted(delta)
		State.SEARCHING:
			process_searching(delta)
		State.CHASING:
			process_chasing(delta)

	# Check for player visibility
	if can_see_player():
		if current_state != State.CHASING:
			change_state(State.CHASING)
			last_known_player_position = player.global_position

	var old_pos = global_position
	move_and_slide()
	var new_pos = global_position

	# Check for collision with player
	if player and damage_cooldown <= 0.0:
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			if collision.get_collider() == player:
				# Deal damage to player
				if player.has_method("take_damage"):
					player.take_damage(damage_per_second * delta)
					damage_cooldown = 0.5  # Damage every 0.5 seconds
					print("enemy_basic: dealt %.1f damage to player!" % (damage_per_second * delta))

	# Debug movement every 0.5 seconds during chasing
	if current_state == State.CHASING and int(time_in_state * 2) % 2 == 0 and time_in_state > 0.1:
		var moved_distance = old_pos.distance_to(new_pos)
		var vel_2d = Vector2(velocity.x, velocity.z).length()
		var dist_to_player = global_position.distance_to(player.global_position) if player else 0.0
		debug_print("enemy_basic: vel=%.2f, moved=%.3fm, dist_to_player=%.1fm, on_floor=%s, vel_y=%.2f" % [vel_2d, moved_distance, dist_to_player, is_on_floor(), velocity.y])

func process_idle(delta: float) -> void:
	# Stand still or wander
	velocity.x = move_toward(velocity.x, 0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	# If alert level high enough, become alerted
	if alert_level > 0.3:
		change_state(State.ALERTED)

func process_alerted(delta: float) -> void:
	# Turn toward alert source, then search
	velocity.x = move_toward(velocity.x, 0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	# Look toward last known position
	look_toward_position(last_known_player_position, delta)

	# After alert duration, start searching
	if time_in_state >= alert_duration:
		change_state(State.SEARCHING)

func process_searching(delta: float) -> void:
	# Move toward last known player position
	if nav_agent.is_navigation_finished():
		# Reached search point, give up after duration
		if time_in_state >= search_duration:
			change_state(State.IDLE)
	else:
		# Navigate to target
		var next_position = nav_agent.get_next_path_position()
		var direction = (next_position - global_position).normalized()

		# Move toward next waypoint
		velocity.x = move_toward(velocity.x, direction.x * walk_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * walk_speed, acceleration * delta)

		# Rotate toward movement direction
		look_toward_direction(direction, delta)

func process_chasing(delta: float) -> void:
	if not player:
		change_state(State.IDLE)
		return

	# Update target position
	nav_agent.target_position = player.global_position
	last_known_player_position = player.global_position

	# Debug navigation ONCE at start
	if time_in_state < 0.1:
		print("========================================")
		print("enemy_basic: CHASING started")
		print("  Distance to player: %.1fm" % global_position.distance_to(player.global_position))
		print("  Nav target: %v" % nav_agent.target_position)
		print("  Nav finished: %s" % nav_agent.is_navigation_finished())
		print("  Chase speed: %.1f" % chase_speed)
		print("  Current velocity: %v" % velocity)
		print("========================================")

	# Just move directly toward player (ignore navigation for now)
	var direction = (player.global_position - global_position).normalized()

	# Force velocity to move toward player
	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed

	look_toward_direction(direction, delta)

	# Debug velocity being set
	if time_in_state < 0.2:
		print("enemy_basic: SET velocity to %v (direction=%v, speed=%.1f)" % [velocity, direction, chase_speed])

	# If lost sight for too long, start searching
	if not can_see_player() and time_in_state > 2.0:
		change_state(State.SEARCHING)

func change_state(new_state: State) -> void:
	if new_state == current_state:
		return

	var state_names = ["IDLE", "ALERTED", "SEARCHING", "CHASING"]
	print("enemy_basic: %s -> %s" % [state_names[current_state], state_names[new_state]])

	current_state = new_state
	time_in_state = 0.0

	# Set navigation target for searching
	if new_state == State.SEARCHING:
		nav_agent.target_position = last_known_player_position

func can_see_player() -> bool:
	if not player:
		return false

	var to_player = player.global_position - global_position
	var distance = to_player.length()

	# Check range
	if distance > vision_range:
		return false

	# Check angle (360 degrees for now = always true)
	var forward = -global_transform.basis.z
	var angle = rad_to_deg(forward.angle_to(to_player.normalized()))

	if angle > vision_angle / 2.0:
		return false

	# Raycast for line of sight
	var space_state = get_world_3d().direct_space_state
	var eye_pos = global_position + Vector3(0, 1.5, 0)  # Eye height
	var player_eye_pos = player.global_position + Vector3(0, 1.5, 0)  # Player eye height

	var query = PhysicsRayQueryParameters3D.create(eye_pos, player_eye_pos)
	query.exclude = [self]
	query.collision_mask = 1  # World geometry only (don't check other enemies)

	var result = space_state.intersect_ray(query)

	# Can see if nothing blocking OR hit player directly
	var can_see = result.is_empty() or result.collider == player

	if can_see:
		debug_print("enemy_basic: CAN SEE PLAYER! Distance: %.1fm" % distance)

	return can_see

func look_toward_position(target_pos: Vector3, delta: float) -> void:
	var direction = (target_pos - global_position).normalized()
	look_toward_direction(direction, delta)

func look_toward_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return

	var target_rotation = atan2(direction.x, direction.z)
	var current_rotation = rotation.y

	# Smooth rotation
	rotation.y = lerp_angle(current_rotation, target_rotation, rotation_speed * delta)

func on_alert(alert_position: Vector3, alert_radius: float, alert_type: String) -> void:
	# Check if alert is in range
	var distance = global_position.distance_to(alert_position)

	if distance <= alert_radius:
		# Increase alert level based on proximity
		var proximity = 1.0 - (distance / alert_radius)
		alert_level = min(1.0, alert_level + proximity * 0.5)

		# Store last known position
		last_known_player_position = alert_position

		# If very close alert, immediately become alerted
		if proximity > 0.7:
			change_state(State.ALERTED)

		print("enemy_basic: heard %s at distance %.1f (alert level: %.2f)" % [alert_type, distance, alert_level])

func take_damage(amount: float) -> void:
	current_health -= amount

	# Flash white when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.albedo_color = Color(1, 1, 1)  # White flash
		await get_tree().create_timer(0.1).timeout
		mat.albedo_color = Color(1, 0, 0)  # Back to red

	print("enemy_basic: ✗ HIT! Took %.1f damage (%.1f/%.1f HP)" % [amount, current_health, max_health])

	if current_health <= 0:
		die()
	else:
		# Being damaged alerts the enemy
		alert_level = 1.0
		if player:
			last_known_player_position = player.global_position
			if current_state != State.CHASING:
				change_state(State.CHASING)

func die() -> void:
	print("========================================")
	print("enemy_basic: ☠ ENEMY KILLED!")
	print("========================================")

	# Death effect - flash and fall
	if mesh_instance:
		mesh_instance.material_override.albedo_color = Color(0.2, 0.2, 0.2)

	# Remove from scene after short delay
	await get_tree().create_timer(0.5).timeout
	queue_free()
