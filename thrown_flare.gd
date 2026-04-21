extends RigidBody3D

## Thrown flare physics object
## Continues burning on the ground with light and sound

var burn_time_remaining: float = 60.0

var mesh_instance: MeshInstance3D
var flare_light: OmniLight3D
var burn_sound: AudioStreamPlayer3D

func _ready() -> void:
	# Set collision layers
	collision_layer = 1  # World layer
	collision_mask = 1   # Collide with world

	# Create visual mesh
	mesh_instance = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.02
	cylinder_mesh.bottom_radius = 0.02
	cylinder_mesh.height = 0.15
	mesh_instance.mesh = cylinder_mesh

	# Create glowing material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.1, 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.1, 0.1)
	material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material

	add_child(mesh_instance)

	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.02
	capsule.height = 0.15
	collision_shape.shape = capsule
	add_child(collision_shape)

	# Create omni light
	flare_light = OmniLight3D.new()
	flare_light.light_color = Color(1.0, 0.2, 0.1)
	flare_light.omni_range = 15.0
	flare_light.light_energy = 5.0
	flare_light.shadow_enabled = true
	add_child(flare_light)

	# Create 3D burn sound
	burn_sound = AudioStreamPlayer3D.new()
	burn_sound.stream = load("res://audio/flare_burn.wav")
	burn_sound.unit_size = 10.0  # Audible from 10 meters
	burn_sound.max_distance = 50.0
	burn_sound.volume_db = -5.0
	burn_sound.autoplay = true
	add_child(burn_sound)

	print("Thrown flare created with ", burn_time_remaining, " seconds remaining")

func _process(delta: float) -> void:
	# Update burn timer
	burn_time_remaining -= delta

	if burn_time_remaining <= 0.0:
		# Flare burned out
		burn_sound.stop()
		queue_free()
		return

	# Flicker effect
	if flare_light:
		var flicker = randf_range(0.9, 1.1)
		flare_light.light_energy = 5.0 * flicker
