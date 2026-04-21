extends Node3D

## Binoculars system
## Right-click to aim in, left-click to cycle between 3 zoom levels: 2x, 5x, 8x

# Zoom settings
const ZOOM_LEVELS: Array[float] = [2.0, 5.0, 8.0]
const NORMAL_FOV: float = 75.0

var current_zoom_index: int = 0
var is_aiming: bool = false

# This property is read by player.gd to control FOV
var aim_fov: float = 37.5  # 75 / 2.0 = 2x zoom by default

# References
var player: CharacterBody3D
var camera: Camera3D
var zoom_label: Label

func _ready() -> void:
	player = get_parent()
	camera = player.get_node_or_null("Camera3D")

	# Create zoom level UI label
	var ui = player.get_node_or_null("UI")
	if ui:
		zoom_label = Label.new()
		zoom_label.add_theme_font_size_override("font_size", 24)
		zoom_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		zoom_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		zoom_label.add_theme_constant_override("outline_size", 4)
		zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		zoom_label.anchor_left = 0.5
		zoom_label.anchor_right = 0.5
		zoom_label.anchor_top = 0.0
		zoom_label.offset_left = -50
		zoom_label.offset_right = 50
		zoom_label.offset_top = 20
		zoom_label.visible = false
		ui.add_child(zoom_label)

	print("Binoculars equipped!")

func _process(_delta: float) -> void:
	# Update zoom label visibility
	if zoom_label:
		if is_aiming:
			zoom_label.text = str(ZOOM_LEVELS[current_zoom_index]) + "x"
			zoom_label.visible = true
		else:
			zoom_label.visible = false

func _input(event: InputEvent) -> void:
	if not player or player.is_inventory_open:
		return

	# Track aim state (same as weapons)
	if event.is_action_pressed("aim"):
		is_aiming = true
	elif event.is_action_released("aim"):
		is_aiming = false

	# Left-click to cycle zoom level (only when aiming)
	if event.is_action_pressed("shoot") and is_aiming:
		cycle_zoom()
		# Consume the event so weapons don't fire
		get_viewport().set_input_as_handled()

func cycle_zoom() -> void:
	# Cycle to next zoom level
	current_zoom_index = (current_zoom_index + 1) % ZOOM_LEVELS.size()

	# Update aim_fov which is read by player.gd
	var zoom_multiplier = ZOOM_LEVELS[current_zoom_index]
	aim_fov = NORMAL_FOV / zoom_multiplier

	print("Binoculars: Cycled to ", ZOOM_LEVELS[current_zoom_index], "x (FOV: ", aim_fov, ")")

func _exit_tree() -> void:
	# Clean up zoom label
	if zoom_label:
		zoom_label.queue_free()
