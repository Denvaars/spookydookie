extends CharacterBody3D

## Enemy AI that only moves when not being looked at
## Classic "Weeping Angel" / SCP-173 mechanic

# Enemy settings
@export var move_speed: float = 2.5
@export var detection_angle: float = 60.0  # FOV cone angle in degrees
@export var max_detection_range: float = 50.0
@export var attack_range: float = 1.5
@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 1.0

# References
var player: CharacterBody3D = null
var player_camera: Camera3D = null
var mesh_instance: MeshInstance3D = null

# State
var is_being_watched: bool = false
var can_attack: bool = true
var time_since_attack: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Health
var max_health: float = 100.0
var current_health: float = 100.0

func _ready() -> void:
	# Find player in scene
	await get_tree().process_frame  # Wait for scene to be ready
	player = get_tree().get_first_node_in_group("player")

	if player:
		player_camera = player.get_node_or_null("Camera3D")

	# Create visual model (tall creepy figure)
	mesh_instance = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 2.0
	capsule_mesh.radius = 0.4
	mesh_instance.mesh = capsule_mesh

	# Create material (dark shadowy appearance)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.1)  # Very dark
	material.emission_enabled = true
	material.emission = Color(0.2, 0.0, 0.0)  # Slight red glow
	material.emission_energy_multiplier = 0.3
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.position.y = 1.0  # Center the capsule

func _physics_process(delta: float) -> void:
	if not player or not player_camera:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Update attack cooldown
	if not can_attack:
		time_since_attack += delta
		if time_since_attack >= attack_cooldown:
			can_attack = true
			time_since_attack = 0.0

	# Check if player is looking at us
	is_being_watched = check_if_being_watched()

	# Only move if not being watched
	if not is_being_watched:
		move_towards_player(delta)
	else:
		# Stop moving when being watched
		velocity.x = 0.0
		velocity.z = 0.0

	# Check if we can attack the player
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= attack_range and can_attack:
		attack_player()

	move_and_slide()

func check_if_being_watched() -> bool:
	if not player_camera:
		return false

	# Vector from camera to enemy
	var to_enemy = global_position - player_camera.global_position
	var distance = to_enemy.length()

	# Too far away to be seen clearly
	if distance > max_detection_range:
		return false

	# Direction camera is facing
	var camera_forward = -player_camera.global_transform.basis.z

	# Angle between camera forward and direction to enemy
	var angle = rad_to_deg(camera_forward.angle_to(to_enemy))

	# Check if enemy is within camera's FOV cone
	if angle > detection_angle:
		return false

	# Perform raycast to check if there's a clear line of sight
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player_camera.global_position,
		global_position + Vector3(0, 1.0, 0)  # Aim at center of enemy
	)
	query.exclude = [player]  # Don't hit the player
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)
	if result:
		# Check if the raycast hit this enemy
		if result.collider == self:
			return true  # Player has clear line of sight to enemy

	return false

func move_towards_player(delta: float) -> void:
	if not player:
		return

	# Calculate direction to player (only on XZ plane)
	var direction = Vector3.ZERO
	direction.x = player.global_position.x - global_position.x
	direction.z = player.global_position.z - global_position.z
	direction.y = 0.0
	direction = direction.normalized()

	# Move towards player
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Look at player
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = target_rotation

func attack_player() -> void:
	if not player or not can_attack:
		return

	can_attack = false
	print("Enemy attacks player!")

	# Damage the player
	if player.has_method("take_damage"):
		player.take_damage(attack_damage)

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Enemy took ", amount, " damage. Health: ", current_health, "/", max_health)

	# Flash red when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(1.0, 0.0, 0.0)
		mat.emission_energy_multiplier = 2.0

		# Reset color after a short delay
		await get_tree().create_timer(0.1).timeout
		if mesh_instance and mesh_instance.material_override:
			mat.emission = Color(0.2, 0.0, 0.0)
			mat.emission_energy_multiplier = 0.3

	if current_health <= 0.0:
		die()

func die() -> void:
	print("Enemy died!")
	queue_free()
