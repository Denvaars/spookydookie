extends CharacterBody3D

## Enemy AI that constantly follows the player
## Slow but relentless pursuit

# Enemy settings
@export var move_speed: float = 1.5  # Slower than statue
@export var attack_range: float = 1.5
@export var attack_damage: float = 20.0
@export var attack_cooldown: float = 1.5

# References
var player: CharacterBody3D = null
var mesh_instance: MeshInstance3D = null

# State
var can_attack: bool = true
var time_since_attack: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Health
var max_health: float = 80.0
var current_health: float = 80.0

func _ready() -> void:
	# Find player in scene
	await get_tree().process_frame  # Wait for scene to be ready
	player = get_tree().get_first_node_in_group("player")

	# Create visual model (shorter, hunched figure)
	mesh_instance = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 1.5
	capsule_mesh.radius = 0.35
	mesh_instance.mesh = capsule_mesh

	# Create material (different appearance - greenish glow)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.2, 0.15)  # Dark greenish
	material.emission_enabled = true
	material.emission = Color(0.0, 0.3, 0.1)  # Green glow
	material.emission_energy_multiplier = 0.4
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.position.y = 0.75  # Center the capsule

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
		time_since_attack += delta
		if time_since_attack >= attack_cooldown:
			can_attack = true
			time_since_attack = 0.0

	# Always move towards player
	move_towards_player(delta)

	# Check if we can attack the player
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= attack_range and can_attack:
		attack_player()

	move_and_slide()

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
	print("Follower attacks player!")

	# Damage the player
	if player.has_method("take_damage"):
		player.take_damage(attack_damage)

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Follower took ", amount, " damage. Health: ", current_health, "/", max_health)

	# Flash green when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(0.0, 1.0, 0.2)
		mat.emission_energy_multiplier = 3.0

		# Reset color after a short delay
		await get_tree().create_timer(0.1).timeout
		if mesh_instance and mesh_instance.material_override:
			mat.emission = Color(0.0, 0.3, 0.1)
			mat.emission_energy_multiplier = 0.4

	if current_health <= 0.0:
		die()

func die() -> void:
	print("Follower died!")
	queue_free()
