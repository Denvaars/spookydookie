extends CharacterBody3D

## Bear AI - Passive animal that becomes aggressive when provoked
## Wanders in area, attacks if player gets too close or attacks it
## Flees when health drops below 35%

# Bear settings
@export var wander_speed: float = 2.0
@export var chase_speed: float = 4.5
@export var flee_speed: float = 5.5
@export var wander_radius: float = 10.0  # How far from spawn to wander
@export var aggro_range: float = 8.0  # Distance player triggers aggression
@export var attack_range: float = 2.5
@export var attack_damage: float = 40.0  # Base damage
@export var bleed_damage: float = 30.0  # Total bleed damage
@export var bleed_dps: float = 3.0  # Bleed damage per second
@export var attack_cooldown: float = 2.5

# Health
@export var max_health: float = 150.0
var current_health: float = 150.0
var flee_health_threshold: float = 52.5  # 35% of max health

# State machine
enum State { IDLE, WANDERING, AGGRESSIVE, FLEEING }
var current_state: State = State.IDLE

# References
var player: CharacterBody3D = null
var nav_agent: NavigationAgent3D = null
var mesh_instance: MeshInstance3D = null
var terrain: TerrainGenerator = null

# Spawn/wander area
var spawn_position: Vector3 = Vector3.ZERO

# Wander state
var wander_target: Vector3 = Vector3.ZERO
var wander_wait_time: float = 0.0
var wander_timer: float = 0.0

# Attack state
var can_attack: bool = true
var attack_timer: float = 0.0

# Flee state
var flee_target: Vector3 = Vector3.ZERO

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Find player and terrain
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	terrain = get_tree().get_first_node_in_group("terrain")

	# Store spawn position
	spawn_position = global_position

	# Create NavigationAgent3D
	nav_agent = NavigationAgent3D.new()
	add_child(nav_agent)
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	nav_agent.radius = 0.6
	nav_agent.height = 1.5
	nav_agent.avoidance_enabled = true

	# Wait for navigation to be ready
	call_deferred("_setup_navigation")

	# Create visual model (large brown bear)
	mesh_instance = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 1.5
	capsule_mesh.radius = 0.6
	mesh_instance.mesh = capsule_mesh

	# Create material (brown bear)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.25, 0.15)  # Brown
	material.roughness = 0.8
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.position.y = 0.75

	# Start in idle state
	transition_to_idle()
	print("Bear spawned at %v" % spawn_position)

func _setup_navigation() -> void:
	# Called after tree is ready to ensure navigation works
	await get_tree().physics_frame
	if current_state == State.IDLE:
		# Start wandering after setup
		call_deferred("transition_to_wandering")

func _physics_process(delta: float) -> void:
	if not player:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Update attack cooldown
	if not can_attack:
		attack_timer += delta
		if attack_timer >= attack_cooldown:
			can_attack = true
			attack_timer = 0.0

	# Check health for flee state
	if current_health <= flee_health_threshold and current_state != State.FLEEING:
		transition_to_fleeing()

	# State machine
	match current_state:
		State.IDLE:
			handle_idle(delta)
		State.WANDERING:
			handle_wandering(delta)
		State.AGGRESSIVE:
			handle_aggressive(delta)
		State.FLEEING:
			handle_fleeing(delta)

	move_and_slide()

func handle_idle(delta: float) -> void:
	# Stand still and check for player proximity
	velocity.x = 0.0
	velocity.z = 0.0

	# Check if player is too close
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= aggro_range:
		transition_to_aggressive()
		return

	# Wait for a bit then start wandering
	wander_timer += delta
	if wander_timer >= randf_range(2.0, 4.0):
		transition_to_wandering()

func handle_wandering(delta: float) -> void:
	# Wander around spawn area
	var distance_to_player = global_position.distance_to(player.global_position)

	# Check if player gets too close
	if distance_to_player <= aggro_range:
		transition_to_aggressive()
		return

	# Check if we reached wander target
	var distance_to_target = global_position.distance_to(wander_target)

	if distance_to_target < 2.0 or nav_agent.is_navigation_finished():
		# Reached target or navigation finished - wait then pick new target
		wander_timer += delta
		if wander_timer >= wander_wait_time:
			pick_new_wander_target()
			wander_timer = 0.0

		velocity.x = 0.0
		velocity.z = 0.0
	else:
		# Move toward wander target
		var next_position = nav_agent.get_next_path_position()
		var direction = (next_position - global_position).normalized()
		direction.y = 0.0

		if direction.length() > 0.01:
			velocity.x = direction.x * wander_speed
			velocity.z = direction.z * wander_speed
			# Look in movement direction
			look_in_direction(direction)
		else:
			# No valid direction, try direct movement
			var direct = (wander_target - global_position).normalized()
			direct.y = 0.0
			velocity.x = direct.x * wander_speed
			velocity.z = direct.z * wander_speed
			look_in_direction(direct)

func handle_aggressive(delta: float) -> void:
	# Chase and attack player - use direct movement (more reliable than pathfinding)
	var distance_to_player = global_position.distance_to(player.global_position)

	# Check if in attack range
	if distance_to_player <= attack_range and can_attack:
		attack_player()
		velocity.x = 0.0
		velocity.z = 0.0
		# Still look at player while attacking
		look_at_target(player.global_position)
		return

	# Direct movement toward player (simple and reliable)
	var direction = (player.global_position - global_position).normalized()
	direction.y = 0.0

	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed

	# Always look at player while chasing
	look_at_target(player.global_position)

	# Debug output
	if int(Time.get_ticks_msec()) % 1000 < 16:  # Print roughly once per second
		print("Bear chasing: distance %.1fm, velocity (%.1f, %.1f)" % [distance_to_player, velocity.x, velocity.z])

func handle_fleeing(delta: float) -> void:
	# Run away from player - direct movement
	var distance_to_player = global_position.distance_to(player.global_position)

	# If far enough away, stop fleeing
	if distance_to_player > 30.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Direct movement away from player
	var away_from_player = (global_position - player.global_position).normalized()
	away_from_player.y = 0.0

	velocity.x = away_from_player.x * flee_speed
	velocity.z = away_from_player.z * flee_speed

	look_in_direction(away_from_player)

func transition_to_idle() -> void:
	if current_state == State.IDLE:
		return

	current_state = State.IDLE
	wander_timer = 0.0
	print("Bear: IDLE")

func transition_to_wandering() -> void:
	if current_state == State.WANDERING:
		return

	current_state = State.WANDERING
	pick_new_wander_target()
	print("Bear: WANDERING")

func transition_to_aggressive() -> void:
	if current_state == State.AGGRESSIVE:
		return

	current_state = State.AGGRESSIVE
	print("Bear: AGGRESSIVE - attacking player!")

	# Change color to indicate aggression
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.6, 0.2, 0.1)  # Reddish-brown

func transition_to_fleeing() -> void:
	if current_state == State.FLEEING:
		return

	current_state = State.FLEEING
	print("Bear: FLEEING - health low!")

	# Change color to show injured
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.3, 0.2, 0.15)  # Darker brown

func pick_new_wander_target() -> void:
	# Pick random point within wander radius of spawn
	var angle = randf() * TAU
	var distance = randf() * wander_radius
	var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)

	wander_target = spawn_position + offset

	# Get terrain height
	if terrain:
		wander_target.y = terrain.get_height(wander_target.x, wander_target.z)

	# Set navigation target
	nav_agent.target_position = wander_target

	# Set wait time for next wander
	wander_wait_time = randf_range(3.0, 6.0)

	print("Bear: New wander target at distance %.1fm from spawn" % distance)

func attack_player() -> void:
	if not player or not can_attack:
		return

	can_attack = false
	attack_timer = 0.0

	print("Bear attacks player for %.1f damage + %.1f bleed!" % [attack_damage, bleed_damage])

	if player.has_method("take_damage"):
		player.take_damage(attack_damage, bleed_damage, bleed_dps)

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Bear took %.1f damage. Health: %.1f/%.1f" % [amount, current_health, max_health])

	# Flash red when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		var original_color = mat.albedo_color
		mat.albedo_color = Color(1.0, 0.2, 0.2)

		await get_tree().create_timer(0.1).timeout

		if mesh_instance and mesh_instance.material_override:
			mat.albedo_color = original_color

	# Become aggressive when attacked (if not fleeing)
	if current_state != State.FLEEING and current_state != State.AGGRESSIVE:
		transition_to_aggressive()

	# Check if should start fleeing
	if current_health <= flee_health_threshold:
		transition_to_fleeing()

	if current_health <= 0.0:
		die()

func die() -> void:
	print("Bear died!")

	# Create dead bear body (ragdoll)
	var dead_body = RigidBody3D.new()
	var dead_body_script = load("res://dead_bear_body.gd")
	dead_body.set_script(dead_body_script)

	# Position at bear's location
	get_tree().root.add_child(dead_body)
	dead_body.global_position = global_position

	# Transfer the mesh to the dead body
	if mesh_instance:
		mesh_instance.get_parent().remove_child(mesh_instance)
		dead_body.add_child(mesh_instance)
		mesh_instance.position = Vector3(0, 0.75, 0)

	# Add some initial velocity for ragdoll effect
	dead_body.linear_velocity = velocity * 0.5
	dead_body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))

	# Remove the living bear
	queue_free()

func look_at_target(target_pos: Vector3) -> void:
	var direction = target_pos - global_position
	direction.y = 0.0

	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = target_rotation

func look_in_direction(direction: Vector3) -> void:
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = target_rotation
