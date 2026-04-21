extends CharacterBody3D

## Deer AI - Passive animal that flees when startled
## Wanders in area, flees from player when too close or hears gunshots
## Spawns in groups of 2-5

# Deer settings
@export var wander_speed: float = 2.5
@export var flee_speed: float = 7.0
@export var wander_radius: float = 15.0
@export var startle_range_walk: float = 8.0  # Distance that startles the deer when walking
@export var startle_range_crouch: float = 4.0  # Distance when crouching (closer)
@export var startle_range_sprint: float = 15.0  # Distance when sprinting (further)
@export var gunshot_startle_range: float = 30.0  # How far deer can hear gunshots

# Health
@export var max_health: float = 50.0
var current_health: float = 50.0

# State machine
enum State { IDLE, WANDERING, FLEEING }
var current_state: State = State.IDLE

# References
var player: CharacterBody3D = null
var nav_agent: NavigationAgent3D = null
var mesh_instance: MeshInstance3D = null
var terrain: TerrainGenerator = null
var alert_system: AlertSystem = null

# Spawn/wander area
var spawn_position: Vector3 = Vector3.ZERO

# Wander state
var wander_target: Vector3 = Vector3.ZERO
var wander_wait_time: float = 0.0
var wander_timer: float = 0.0

# Flee state
var flee_timer: float = 0.0
var flee_duration: float = 0.0  # How long to flee (5s or 10s)
var flee_direction: Vector3 = Vector3.ZERO  # Direction to flee in

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Add to animal group for alert system
	add_to_group("animal")

	# Find player, terrain, and alert system
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	terrain = get_tree().get_first_node_in_group("terrain")

	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")
	if forest and "alert_system" in forest:
		alert_system = forest.alert_system

	# Store spawn position
	spawn_position = global_position

	# Create NavigationAgent3D
	nav_agent = NavigationAgent3D.new()
	add_child(nav_agent)
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	nav_agent.radius = 0.4
	nav_agent.height = 1.2
	nav_agent.avoidance_enabled = true

	# Wait for navigation to be ready
	call_deferred("_setup_navigation")

	# Create visual model (smaller than bear, light brown)
	mesh_instance = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 1.2
	capsule_mesh.radius = 0.4
	mesh_instance.mesh = capsule_mesh

	# Create material (light brown deer)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 0.25)  # Light brown
	material.roughness = 0.8
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.position.y = 0.6

	# Start in idle state
	transition_to_idle()
	print("Deer spawned at %v" % spawn_position)

func _setup_navigation() -> void:
	await get_tree().physics_frame
	if current_state == State.IDLE:
		call_deferred("transition_to_wandering")

func _physics_process(delta: float) -> void:
	if not player:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Check for player proximity startle (only when not already fleeing)
	if current_state != State.FLEEING:
		var distance_to_player = global_position.distance_to(player.global_position)

		# Adjust startle range based on player movement state
		var active_startle_range = startle_range_walk
		if player.is_crouching:
			active_startle_range = startle_range_crouch  # Closer when crouching
		elif player.is_sprinting:
			active_startle_range = startle_range_sprint  # Further when sprinting

		if distance_to_player <= active_startle_range:
			transition_to_fleeing_proximity()  # Flee for 5 seconds, directly away

	# State machine
	match current_state:
		State.IDLE:
			handle_idle(delta)
		State.WANDERING:
			handle_wandering(delta)
		State.FLEEING:
			handle_fleeing(delta)

	move_and_slide()

func handle_idle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	# Wait for a bit then start wandering
	wander_timer += delta
	if wander_timer >= randf_range(2.0, 4.0):
		transition_to_wandering()

func handle_wandering(delta: float) -> void:
	# Check if we reached wander target
	var distance_to_target = global_position.distance_to(wander_target)

	if distance_to_target < 2.0 or nav_agent.is_navigation_finished():
		# Reached target - wait then pick new target
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
			look_in_direction(direction)
		else:
			var direct = (wander_target - global_position).normalized()
			direct.y = 0.0
			velocity.x = direct.x * wander_speed
			velocity.z = direct.z * wander_speed
			look_in_direction(direct)

func handle_fleeing(delta: float) -> void:
	# Update flee timer
	flee_timer += delta

	# Stop fleeing after duration
	if flee_timer >= flee_duration:
		transition_to_idle()
		return

	# Run in flee direction (set when fleeing starts)
	if flee_direction.length() > 0.01:
		velocity.x = flee_direction.x * flee_speed
		velocity.z = flee_direction.z * flee_speed
		look_in_direction(flee_direction)
	else:
		# Fallback: run directly away from player
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
	print("Deer: IDLE")

func transition_to_wandering() -> void:
	if current_state == State.WANDERING:
		return

	current_state = State.WANDERING
	pick_new_wander_target()
	print("Deer: WANDERING")

func transition_to_fleeing_proximity() -> void:
	# Flee directly away from player when startled by proximity
	if current_state == State.FLEEING:
		return

	current_state = State.FLEEING
	flee_timer = 0.0
	flee_duration = 5.0

	# Run directly away from player
	flee_direction = (global_position - player.global_position).normalized()
	flee_direction.y = 0.0

	print("Deer: FLEEING from player for 5s!")
	update_flee_appearance()

func transition_to_fleeing_gunshot() -> void:
	# Flee in random direction away from gunshot
	if current_state == State.FLEEING:
		# Already fleeing, extend duration
		flee_duration = max(flee_duration, 10.0)
		flee_timer = 0.0
		return

	current_state = State.FLEEING
	flee_timer = 0.0
	flee_duration = 10.0

	# Calculate base "away from player" direction
	var away_from_player = (global_position - player.global_position).normalized()
	away_from_player.y = 0.0

	# Add random angle within 180-degree cone (±90 degrees)
	var random_angle = randf_range(-PI/2, PI/2)  # -90 to +90 degrees
	var base_angle = atan2(away_from_player.x, away_from_player.z)
	var final_angle = base_angle + random_angle

	# Calculate flee direction
	flee_direction = Vector3(sin(final_angle), 0, cos(final_angle)).normalized()

	print("Deer: FLEEING from gunshot for 10s!")
	update_flee_appearance()

func update_flee_appearance() -> void:
	# Change color to show fear
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.5, 0.35, 0.2)  # Darker when scared

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

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Deer took %.1f damage. Health: %.1f/%.1f" % [amount, current_health, max_health])

	# Flash red when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		var original_color = mat.albedo_color
		mat.albedo_color = Color(1.0, 0.2, 0.2)

		await get_tree().create_timer(0.1).timeout

		if mesh_instance and mesh_instance.material_override:
			mat.albedo_color = original_color

	# Flee for 10 seconds when shot (random direction)
	transition_to_fleeing_gunshot()

	if current_health <= 0.0:
		die()

func die() -> void:
	print("Deer died!")

	# Create dead deer body (ragdoll)
	var dead_body = RigidBody3D.new()
	var dead_body_script = load("res://dead_deer_body.gd")
	dead_body.set_script(dead_body_script)

	# Position at deer's location
	get_tree().root.add_child(dead_body)
	dead_body.global_position = global_position

	# Transfer the mesh to the dead body
	if mesh_instance:
		mesh_instance.get_parent().remove_child(mesh_instance)
		dead_body.add_child(mesh_instance)
		mesh_instance.position = Vector3(0, 0.6, 0)

	# Add some initial velocity for ragdoll effect
	dead_body.linear_velocity = velocity * 0.5
	dead_body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))

	# Remove the living deer
	queue_free()

func look_in_direction(direction: Vector3) -> void:
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = target_rotation

# Called by alert system when gunshot is fired
func on_gunshot_alert(gunshot_position: Vector3) -> void:
	var distance = global_position.distance_to(gunshot_position)
	if distance <= gunshot_startle_range:
		print("Deer heard gunshot %.1fm away - fleeing!" % distance)
		transition_to_fleeing_gunshot()  # Flee for 10 seconds in random direction
