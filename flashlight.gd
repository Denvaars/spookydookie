extends Node3D

## Flashlight tool system
## Toggleable spotlight for illumination

# Flashlight settings
@export var light_intensity: float = 5.0
@export var light_range: float = 20.0
@export var aim_fov: float = 70.0  # Less zoom than shotgun (shotgun is 60.0)

# Flashlight state
var is_on: bool = false
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D
var flashlight_light: SpotLight3D

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Show the FPS weapon model
	var fps_controller = get_tree().root.find_child("FPSArms", true, false)
	if fps_controller:
		fps_controller.show_weapon("flashlight")
	else:
		print("Warning: FPSArms controller not found!")

	# Find the flashlight SpotLight3D node
	if camera:
		flashlight_light = camera.get_node_or_null("Flashlight")
		if flashlight_light:
			flashlight_light.visible = is_on
			flashlight_light.light_energy = light_intensity
			flashlight_light.spot_range = light_range
		else:
			print("Warning: Flashlight SpotLight3D not found!")

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Toggle flashlight on/off
	if event.is_action_pressed("shoot"):
		toggle_flashlight()

	# Aim (smooth FOV transition handled automatically by player.gd)
	if event.is_action_pressed("aim"):
		is_aiming = true
		# Play aim animation
		var fps_controller = get_tree().root.find_child("FPSArms", true, false)
		if fps_controller:
			fps_controller.set_aiming(true)
	elif event.is_action_released("aim"):
		is_aiming = false
		# Play idle animation
		var fps_controller = get_tree().root.find_child("FPSArms", true, false)
		if fps_controller:
			fps_controller.set_aiming(false)

func toggle_flashlight() -> void:
	is_on = !is_on

	if flashlight_light:
		flashlight_light.visible = is_on

	print("Flashlight ", "ON" if is_on else "OFF")

# Called when tool is unequipped
func on_unequip() -> void:
	# Turn off flashlight when unequipping
	if flashlight_light:
		flashlight_light.visible = false
		is_on = false

	# Hide the FPS weapon model
	if camera:
		var fps_controller = get_tree().root.find_child("FPSArms", true, false)
		if fps_controller:
			fps_controller.hide_all_weapons()
