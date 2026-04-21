class_name PlayerUI
extends Node

## Handles all player UI elements (bars, labels, menus, overlays)
## Passive display component - no game logic, only UI updates

# Progress bars
var stamina_bar: ProgressBar
var health_bar: ProgressBar
var bleed_bar: ProgressBar
var sanity_bar: ProgressBar

# Visual overlays
var vignette_overlay: TextureRect
var crosshair: Control

# Labels
var danger_label: Label
var frequency_label: Label
var coordinate_label: Label
var fps_label: Label

# Menu system
var pause_menu: Control = null
var settings_menu: Control = null
var console_ui: Control = null
var pause_menu_scene: PackedScene = preload("res://pause_menu.tscn")
var settings_menu_scene: PackedScene = preload("res://settings_menu.tscn")
var console_ui_scene: PackedScene = preload("res://console_ui.tscn")

# State
var is_paused: bool = false
var is_inventory_open: bool = false
var low_health_threshold: float = 50.0

# UI parent container
var ui_container: Control = null

# Signals for menu actions
signal pause_toggled(is_paused: bool)
signal inventory_toggled(is_open: bool)
signal quit_requested()


func _ready() -> void:
	# Get UI container from parent
	var player = get_parent()
	if player:
		ui_container = player.get_node_or_null("UI")

	if not ui_container:
		push_error("PlayerUI: Could not find UI container")
		return

	# Get progress bars
	stamina_bar = ui_container.get_node_or_null("StaminaBar")
	health_bar = ui_container.get_node_or_null("HealthBar")
	bleed_bar = ui_container.get_node_or_null("BleedBar")
	sanity_bar = ui_container.get_node_or_null("SanityBar")
	crosshair = ui_container.get_node_or_null("Crosshair")

	# Create vignette overlay
	_create_vignette_overlay()

	# Create labels
	_create_labels()


func _create_vignette_overlay() -> void:
	vignette_overlay = TextureRect.new()
	vignette_overlay.name = "VignetteOverlay"
	var vignette_texture = load("res://assets/vignette.png")
	if vignette_texture:
		vignette_overlay.texture = vignette_texture
		print("PlayerUI: vignette texture loaded successfully")
	else:
		push_error("PlayerUI: failed to load vignette texture")
	vignette_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_overlay.modulate = Color(1, 1, 1, 0)  # Start invisible
	# Make it cover the entire screen
	vignette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_overlay.offset_left = 0
	vignette_overlay.offset_top = 0
	vignette_overlay.offset_right = 0
	vignette_overlay.offset_bottom = 0
	ui_container.add_child(vignette_overlay)
	# Ensure it's on top
	ui_container.move_child(vignette_overlay, ui_container.get_child_count() - 1)
	print("PlayerUI: vignette overlay created")


func _create_labels() -> void:
	# Danger level display
	danger_label = Label.new()
	danger_label.name = "DangerLabel"
	danger_label.add_theme_font_size_override("font_size", 24)
	danger_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	danger_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	danger_label.add_theme_constant_override("outline_size", 4)
	danger_label.text = "Danger Zone: 1 (1.0)"
	danger_label.position = Vector2(10, 10)
	ui_container.add_child(danger_label)

	# Frequency display
	frequency_label = Label.new()
	frequency_label.name = "FrequencyLabel"
	frequency_label.add_theme_font_size_override("font_size", 24)
	frequency_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1))
	frequency_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	frequency_label.add_theme_constant_override("outline_size", 4)
	frequency_label.text = "Frequency: 0.0"
	frequency_label.position = Vector2(10, 45)
	ui_container.add_child(frequency_label)

	# Coordinate display
	coordinate_label = Label.new()
	coordinate_label.name = "CoordinateLabel"
	coordinate_label.add_theme_font_size_override("font_size", 20)
	coordinate_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	coordinate_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	coordinate_label.add_theme_constant_override("outline_size", 4)
	coordinate_label.text = "Position: (0, 0, 0)"
	coordinate_label.position = Vector2(10, 80)
	ui_container.add_child(coordinate_label)

	# FPS display
	fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.add_theme_font_size_override("font_size", 24)
	fps_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.text = "FPS: 0"
	fps_label.position = Vector2(10, 115)
	ui_container.add_child(fps_label)

	print("PlayerUI: labels created")


## Initialize stamina bar with max value
func initialize_stamina_bar(max_value: float, current_value: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = max_value
		stamina_bar.value = current_value


## Update stamina bar value and color
func update_stamina_bar(value: float, is_depleted: bool) -> void:
	if stamina_bar:
		stamina_bar.value = value

		# Change bar color based on depletion state
		var bar_style = stamina_bar.get_theme_stylebox("fill")
		if bar_style and bar_style is StyleBoxFlat:
			if is_depleted:
				bar_style.bg_color = Color(0.8, 0.2, 0.2, 0.8)  # Red
			else:
				bar_style.bg_color = Color(0.2, 0.6, 0.8, 0.8)  # Blue


## Initialize health bars with max value
func initialize_health_bars(max_health: float, current_health: float) -> void:
	# Bleed bar (yellow background layer)
	if bleed_bar:
		bleed_bar.max_value = max_health
		bleed_bar.value = current_health

	# Health bar (red foreground layer)
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health


## Update health bars (yellow = current health, red = health minus bleed)
func update_health_bars(current_health: float, current_bleed_damage: float) -> void:
	# Update bleed bar (yellow) to show current health
	if bleed_bar:
		bleed_bar.value = current_health

	# Update health bar (red) to show health minus bleed damage
	if health_bar:
		var health_after_bleed = max(current_health - current_bleed_damage, 0.0)
		health_bar.value = health_after_bleed


## Initialize sanity bar with max value
func initialize_sanity_bar(max_value: float, current_value: float) -> void:
	if sanity_bar:
		sanity_bar.max_value = max_value
		sanity_bar.value = current_value


## Update sanity bar value
func update_sanity_bar(value: float) -> void:
	if sanity_bar:
		sanity_bar.value = value


## Update vignette overlay based on health
func update_vignette(current_health: float, max_health: float) -> void:
	if not vignette_overlay:
		return

	if current_health <= low_health_threshold:
		# Calculate vignette opacity (0 HP = 1.0 opacity, 50 HP = 0.0 opacity)
		var vignette_alpha = 1.0 - (current_health / low_health_threshold)
		vignette_alpha = clamp(vignette_alpha, 0.0, 1.0)
		vignette_overlay.modulate = Color(1, 1, 1, vignette_alpha)
	else:
		# Above threshold, fade out
		vignette_overlay.modulate = Color(1, 1, 1, 0)


## Update danger zone label
func update_danger_label(zone: int, level: float) -> void:
	if not danger_label:
		return

	danger_label.text = "Danger Zone: %d (%.2f)" % [zone, level]

	# Change color based on danger zone
	match zone:
		1:
			danger_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))  # Green
		2:
			danger_label.add_theme_color_override("font_color", Color(1, 1, 0.3))  # Yellow
		3:
			danger_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))  # Red
		4:
			danger_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.8))  # Dark Red/Purple


## Update frequency label
func update_frequency_label(frequency: float) -> void:
	if frequency_label:
		frequency_label.text = "Frequency: %.1f" % frequency


## Update coordinate label
func update_coordinate_label(position: Vector3) -> void:
	if coordinate_label:
		coordinate_label.text = "Position: (%.1f, %.1f, %.1f)" % [position.x, position.y, position.z]


## Update FPS label with color coding
func update_fps_label(fps: int) -> void:
	if not fps_label:
		return

	fps_label.text = "FPS: %d" % fps

	# Color code: green >60, yellow 30-60, red <30
	if fps >= 60:
		fps_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	else:
		fps_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))


## Toggle inventory visibility
func toggle_inventory(inventory_ui: Control) -> void:
	is_inventory_open = !is_inventory_open

	if inventory_ui:
		inventory_ui.visible = is_inventory_open

	# Hide/show crosshair
	if crosshair:
		crosshair.visible = !is_inventory_open

	inventory_toggled.emit(is_inventory_open)


## Toggle pause menu
func toggle_pause() -> void:
	is_paused = !is_paused

	if is_paused:
		_show_pause_menu()
	else:
		_hide_pause_menu()

	pause_toggled.emit(is_paused)


func _show_pause_menu() -> void:
	# Create pause menu if it doesn't exist
	if not pause_menu:
		pause_menu = pause_menu_scene.instantiate()
		pause_menu.resume_pressed.connect(_on_resume_pressed)
		pause_menu.settings_pressed.connect(_on_settings_pressed)
		pause_menu.console_pressed.connect(_on_console_pressed)
		pause_menu.quit_pressed.connect(_on_quit_pressed)
		ui_container.add_child(pause_menu)

	if pause_menu:
		pause_menu.visible = true


func _hide_pause_menu() -> void:
	if pause_menu:
		pause_menu.visible = false


func _on_resume_pressed() -> void:
	toggle_pause()


func _on_settings_pressed() -> void:
	# Hide pause menu and show settings menu
	if pause_menu:
		pause_menu.visible = false

	if not settings_menu:
		settings_menu = settings_menu_scene.instantiate()
		settings_menu.back_pressed.connect(_on_settings_back_pressed)
		ui_container.add_child(settings_menu)

	if settings_menu:
		settings_menu.visible = true


func _on_settings_back_pressed() -> void:
	hide_settings_menu()


func hide_settings_menu() -> void:
	if settings_menu:
		settings_menu.visible = false

	if pause_menu:
		pause_menu.visible = true


func _on_console_pressed() -> void:
	# Hide pause menu and show console
	if pause_menu:
		pause_menu.visible = false

	if not console_ui:
		console_ui = console_ui_scene.instantiate()
		console_ui.close_requested.connect(_on_console_close_requested)
		ui_container.add_child(console_ui)

	if console_ui:
		console_ui.show_console()


func _on_console_close_requested() -> void:
	hide_console()


func hide_console() -> void:
	if console_ui:
		console_ui.hide_console()

	if pause_menu:
		pause_menu.visible = true


func _on_quit_pressed() -> void:
	quit_requested.emit()


## Check if settings menu is open
func is_settings_open() -> bool:
	return settings_menu != null and settings_menu.visible


## Check if console is open
func is_console_open() -> bool:
	return console_ui != null and console_ui.visible
