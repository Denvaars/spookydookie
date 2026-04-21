extends Node3D

## Lighter system
## Toggleable dim flame light that can be aimed slightly

# Lighter settings
@export var light_intensity: float = 1.0  # Much dimmer than lantern
@export var light_range: float = 6.0  # Smaller range than lantern
@export var aim_fov: float = 65.0
@export var normal_fov: float = 75.0

# Lighter state
var is_lit: bool = false
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var lighter_light: OmniLight3D

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Create visual model (small box placeholder for lighter)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.04, 0.08, 0.02)  # Smaller than lantern
	mesh_instance.mesh = box_mesh

	# Create material for the lighter
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.75)  # Chrome/silver
	material.metallic = 0.9
	material.roughness = 0.3
	material.emission_enabled = false  # Will enable when lit
	material.emission = Color(1.0, 0.6, 0.2)  # Warm orange flame
	material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material

	# Position it in front of camera (held in hand)
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.2, -0.3, -0.3)

	# Create omni light (starts disabled)
	lighter_light = OmniLight3D.new()
	lighter_light.light_color = Color(1.0, 0.6, 0.2)  # Warm flame color
	lighter_light.omni_range = light_range
	lighter_light.light_energy = light_intensity
	lighter_light.shadow_enabled = true
	lighter_light.visible = false
	if camera:
		camera.add_child(lighter_light)
		lighter_light.position = Vector3(0.2, -0.3, -0.3)

	print("Lighter equipped!")

func _process(delta: float) -> void:
	# Handle aiming position
	if mesh_instance:
		var target_pos = Vector3(0.1, -0.15, -0.25) if is_aiming else Vector3(0.2, -0.3, -0.3)
		mesh_instance.position = mesh_instance.position.lerp(target_pos, 8.0 * delta)
		if lighter_light:
			lighter_light.position = mesh_instance.position

	# Flicker effect when lit (more pronounced than lantern)
	if is_lit and lighter_light:
		# Add more noticeable flickering like a small flame
		var flicker = randf_range(0.85, 1.15)
		lighter_light.light_energy = light_intensity * flicker

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Left-click to toggle light on/off
	if event.is_action_pressed("shoot"):
		toggle_light()

	# Aim with right click
	if event.is_action_pressed("aim"):
		is_aiming = true
	elif event.is_action_released("aim"):
		is_aiming = false

func toggle_light() -> void:
	is_lit = not is_lit

	# Enable/disable emission on mesh
	if mesh_instance:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission_enabled = is_lit

	# Turn on/off light
	if lighter_light:
		lighter_light.visible = is_lit

	if is_lit:
		print("Lighter lit!")
	else:
		print("Lighter extinguished!")

func _exit_tree() -> void:
	# Clean up visual mesh and light
	if mesh_instance:
		mesh_instance.queue_free()
	if lighter_light:
		lighter_light.queue_free()
