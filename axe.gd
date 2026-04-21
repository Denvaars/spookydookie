extends Node3D

## Axe melee weapon system
## Heavy melee weapon with slow but powerful swings

# Axe settings
@export var damage: float = 50.0
@export var attack_range: float = 2.5
@export var attack_rate: float = 1.0  # Slow swing
@export var swing_duration: float = 0.3

# Attack variables
var can_attack: bool = true
var is_swinging: bool = false
var swing_time: float = 0.0
var time_since_attack: float = 0.0

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var initial_position: Vector3
var initial_rotation: Vector3

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Create visual model (box for axe head and handle)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.3, 0.6, 0.08)  # Axe shape
	mesh_instance.mesh = box_mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.3, 0.1)  # Brown
	mesh_instance.material_override = material

	# Position it in front of camera
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.4, -0.3, -0.5)
		mesh_instance.rotation_degrees = Vector3(45, -20, 0)
		initial_position = mesh_instance.position
		initial_rotation = mesh_instance.rotation

func _process(delta: float) -> void:
	# Update attack cooldown
	if not can_attack:
		time_since_attack += delta
		if time_since_attack >= attack_rate:
			can_attack = true
			time_since_attack = 0.0

	# Handle swing animation
	if is_swinging:
		swing_time += delta
		var progress = swing_time / swing_duration

		if progress >= 1.0:
			is_swinging = false
			swing_time = 0.0
			if mesh_instance:
				mesh_instance.position = initial_position
				mesh_instance.rotation = initial_rotation
		elif mesh_instance:
			# Swing animation (arc from right to left)
			var swing_offset = sin(progress * PI) * 0.5
			mesh_instance.rotation.z = initial_rotation.z + swing_offset * 2.0

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Attack (left click)
	if event.is_action_pressed("shoot") and can_attack and not is_swinging:
		attack()

func attack() -> void:
	can_attack = false
	is_swinging = true
	swing_time = 0.0

	print("Axe swing!")

	# Perform attack detection after a short delay (mid-swing)
	await get_tree().create_timer(swing_duration * 0.5).timeout
	check_hit()

func check_hit() -> void:
	if not camera:
		return

	# Check for hits in an arc in front of the player
	for i in range(5):  # Check multiple angles
		var angle_offset = (i - 2) * 0.2  # -0.4 to 0.4 radians
		var direction = camera.global_transform.basis.z * -1.0
		direction = direction.rotated(camera.global_transform.basis.y, angle_offset)

		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(
			camera.global_position,
			camera.global_position + direction * attack_range
		)
		query.collision_mask = 1

		var result = space_state.intersect_ray(query)
		if result:
			var hit_object = result.collider
			print("Axe hit: ", hit_object.name)

			if hit_object.has_method("take_damage"):
				hit_object.take_damage(damage)
			break  # Only hit one target
