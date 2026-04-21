extends Node3D

## Knife melee weapon system
## Fast melee weapon with quick stabs

# Knife settings
@export var damage: float = 30.0
@export var attack_range: float = 1.5
@export var attack_rate: float = 0.5  # Fast attacks
@export var stab_duration: float = 0.15

# Attack variables
var can_attack: bool = true
var is_stabbing: bool = false
var stab_time: float = 0.0
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

	# Create visual model (thin box for knife blade)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.03, 0.25, 0.05)  # Thin knife
	mesh_instance.mesh = box_mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.8)  # Steel gray
	mesh_instance.material_override = material

	# Position it in front of camera (close and to the right)
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.3, -0.2, -0.35)
		mesh_instance.rotation_degrees = Vector3(0, 45, 15)
		initial_position = mesh_instance.position
		initial_rotation = mesh_instance.rotation

func _process(delta: float) -> void:
	# Update attack cooldown
	if not can_attack:
		time_since_attack += delta
		if time_since_attack >= attack_rate:
			can_attack = true
			time_since_attack = 0.0

	# Handle stab animation
	if is_stabbing:
		stab_time += delta
		var progress = stab_time / stab_duration

		if progress >= 1.0:
			is_stabbing = false
			stab_time = 0.0
			if mesh_instance:
				mesh_instance.position = initial_position
				mesh_instance.rotation = initial_rotation
		elif mesh_instance:
			# Stab animation (forward thrust)
			var thrust = sin(progress * PI) * 0.3
			mesh_instance.position.z = initial_position.z - thrust

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Attack (left click)
	if event.is_action_pressed("shoot") and can_attack and not is_stabbing:
		attack()

func attack() -> void:
	can_attack = false
	is_stabbing = true
	stab_time = 0.0

	print("Knife stab!")

	# Perform attack detection at mid-stab
	await get_tree().create_timer(stab_duration * 0.5).timeout
	check_hit()

func check_hit() -> void:
	if not camera:
		return

	# Check for hits directly in front
	var direction = camera.global_transform.basis.z * -1.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position + direction * attack_range
	)
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)
	if result:
		var hit_object = result.collider
		print("Knife hit: ", hit_object.name)

		if hit_object.has_method("take_damage"):
			hit_object.take_damage(damage)
