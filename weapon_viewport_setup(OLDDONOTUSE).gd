extends SubViewportContainer

## Weapon Viewport System
## Renders weapons in a separate viewport with different FOV

@onready var viewport: SubViewport = $WeaponViewport
@onready var weapon_camera: Camera3D = $WeaponViewport/WeaponCamera3D

var main_camera: Camera3D

func _ready() -> void:
	# Make the container fill the screen
	anchors_preset = Control.PRESET_FULL_RECT

	# Make viewport size match screen
	viewport.size = get_viewport().size

	# Make background transparent
	viewport.transparent_bg = true

	# Find main camera
	var player = get_node("/root").get_node("Player") # Adjust path as needed
	if player:
		main_camera = player.get_node_or_null("Camera3D")

	# Configure weapon camera
	if weapon_camera:
		weapon_camera.cull_mask = 512  # Only layer 10
		weapon_camera.fov = 50.0  # Adjust to match Blender

func _process(_delta: float) -> void:
	# Sync weapon camera with main camera
	if main_camera and weapon_camera:
		weapon_camera.global_transform = main_camera.global_transform

	# Resize viewport if window size changes
	if viewport.size != get_viewport().size:
		viewport.size = get_viewport().size
