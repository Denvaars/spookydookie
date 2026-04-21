extends Node

## Singleton that manages game settings and applies them

signal settings_changed

# Settings with defaults
var render_distance_chunks: int = 3  # Default 3, max 6
var max_fps: int = 144  # Frame rate cap

const SETTINGS_FILE = "user://settings.cfg"

func _ready() -> void:
	load_settings()
	apply_all_settings()

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)

	if err == OK:
		render_distance_chunks = config.get_value("graphics", "render_distance", 3)
		max_fps = config.get_value("graphics", "max_fps", 144)
		print("Settings loaded from ", SETTINGS_FILE)
	else:
		print("No settings file found, using defaults")

func save_settings() -> void:
	var config = ConfigFile.new()

	config.set_value("graphics", "render_distance", render_distance_chunks)
	config.set_value("graphics", "max_fps", max_fps)

	var err = config.save(SETTINGS_FILE)
	if err == OK:
		print("Settings saved to ", SETTINGS_FILE)
	else:
		push_error("Failed to save settings: ", err)

func apply_all_settings() -> void:
	apply_max_fps()
	apply_render_distance()
	settings_changed.emit()

func apply_max_fps() -> void:
	Engine.max_fps = max_fps
	print("Max FPS set to: ", max_fps)

func apply_render_distance() -> void:
	# Update cull distance on all tree/rock/bush chunks
	var tree_placer = get_tree().get_first_node_in_group("tree_placer")
	if tree_placer:
		var new_distance = render_distance_chunks * 100.0  # 100m per chunk
		tree_placer.set_cull_distance(new_distance)

	var rock_placer = get_tree().get_first_node_in_group("rock_placer")
	if rock_placer:
		var new_distance = render_distance_chunks * 100.0
		rock_placer.set_cull_distance(new_distance)

	var bush_placer = get_tree().get_first_node_in_group("bush_placer")
	if bush_placer:
		var new_distance = render_distance_chunks * 100.0
		bush_placer.set_cull_distance(new_distance)

	print("Render distance set to: ", render_distance_chunks, " chunks (", render_distance_chunks * 100, "m)")

func set_render_distance(chunks: int) -> void:
	render_distance_chunks = clampi(chunks, 1, 6)
	apply_render_distance()
	save_settings()

func set_max_fps(fps: int) -> void:
	max_fps = clampi(fps, 30, 300)
	apply_max_fps()
	save_settings()
