extends Node3D

## Lantern system
## Toggleable warm light that can be aimed slightly

# Lantern settings
@export var light_intensity: float = 3.0
@export var light_range: float = 12.0
@export var aim_fov: float = 65.0
@export var normal_fov: float = 75.0

# Lantern state
var is_lit: bool = false
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var mesh_instance: MeshInstance3D
var lantern_light: OmniLight3D

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Create visual model (box placeholder for lantern)
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.08, 0.12, 0.08)
	mesh_instance.mesh = box_mesh

	# Create material for the lantern
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 0.2)  # Bronze/brass
	material.metallic = 0.7
	material.roughness = 0.4
	material.emission_enabled = false  # Will enable when lit
	material.emission = Color(1.0, 0.7, 0.3)  # Warm orange
	material.emission_energy_multiplier = 1.5
	mesh_instance.material_override = material

	# Position it in front of camera (held in hand)
	if camera:
		camera.add_child(mesh_instance)
		mesh_instance.position = Vector3(0.25, -0.25, -0.35)

	# Create omni light (starts disabled)
	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(1.0, 0.7, 0.3)  # Warm orange/yellow
	lantern_light.omni_range = light_range
	lantern_light.light_energy = light_intensity
	lantern_light.shadow_enabled = true
	lantern_light.visible = false
	if camera:
		camera.add_child(lantern_light)
		lantern_light.position = Vector3(0.25, -0.25, -0.35)

	print("Lantern equipped!")

func _process(delta: float) -> void:
	# Handle aiming position
	if mesh_instance:
		var target_pos = Vector3(0.1, -0.15, -0.3) if is_aiming else Vector3(0.25, -0.25, -0.35)
		mesh_instance.position = mesh_instance.position.lerp(target_pos, 8.0 * delta)
		if lantern_light:
			lantern_light.position = mesh_instance.position

	# Flicker effect when lit
	if is_lit and lantern_light:
		# Add subtle flickering like a flame
		var flicker = randf_range(0.95, 1.05)
		lantern_light.light_energy = light_intensity * flicker

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
	if lantern_light:
		lantern_light.visible = is_lit

	if is_lit:
		print("Lantern lit!")
	else:
		print("Lantern extinguished!")

func _exit_tree() -> void:
	# Clean up visual mesh and light
	if mesh_instance:
		mesh_instance.queue_free()
	if lantern_light:
		lantern_light.queue_free()
