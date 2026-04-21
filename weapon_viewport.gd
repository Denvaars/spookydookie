extends SubViewport

func _ready() -> void:
	# Use fixed smaller resolution for weapon viewport (512x512 is plenty for weapon models)
	size = Vector2i(512, 512)

	# Create separate World3D for weapons only (don't render the entire game world)
	world_3d = World3D.new()

	# Add simple environment for weapons
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)  # Transparent
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.4)  # Subtle ambient light
	world_3d.environment = env

	# Add directional light for weapons
	var light = DirectionalLight3D.new()
	light.light_energy = 1.0
	light.shadow_enabled = false  # No shadows needed for weapons
	light.rotation_degrees = Vector3(-45, 30, 0)  # Angle the light nicely
	add_child(light)

	# Disable expensive features
	positional_shadow_atlas_size = 0  # Disable shadow atlas
	use_hdr_2d = false  # Disable HDR

	print("Weapon viewport configured: 512x512, separate World3D, simple lighting, shadows disabled")
