extends Camera3D

## Weapon Camera - Mirrors main camera for separate weapon viewport rendering
## This camera renders ONLY the weapon layer (layer 2) in a separate viewport

var main_camera: Camera3D = null

func _ready() -> void:
	# Find the main camera (player's camera)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		main_camera = player.get_node_or_null("Camera3D")
		if main_camera:
			print("Weapon camera found main camera")
			# Copy initial settings
			fov = main_camera.fov
			near = main_camera.near
			far = main_camera.far
		else:
			push_error("Weapon camera could not find main Camera3D!")
	else:
		push_error("Weapon camera could not find player!")

func _process(_delta: float) -> void:
	if not main_camera:
		return

	# Copy transform (position and rotation) from main camera
	global_transform = main_camera.global_transform

	# Also copy FOV in case it changes (sprint FOV, aim FOV, etc.)
	fov = main_camera.fov
