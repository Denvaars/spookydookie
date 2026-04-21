extends CharacterBody3D

## Player character - lightweight coordinator for player components
## Delegates all functionality to specialized components

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Component references
var player_audio: PlayerAudio
var player_health: PlayerHealth
var player_ui: PlayerUI
var player_inventory: PlayerInventory
var player_camera: PlayerCamera
var player_movement: PlayerMovement

# Perk system
var perk_manager: PerkManager = null

# Node references
@onready var camera: Camera3D = $Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight
@onready var interact_raycast: RayCast3D = $Camera3D/InteractRaycast
@onready var inventory_ui: Control = $UI/InventoryUI


func _ready() -> void:
	# Add player to group so enemies can find it
	add_to_group("player")

	# Initialize perk manager first (needed by components)
	perk_manager = PerkManager.new()
	perk_manager.name = "PerkManager"
	add_child(perk_manager)

	# Set process mode to pause when game is paused
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# Capture the mouse cursor for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Create all player components
	_create_components()

	# Wire up component dependencies
	_wire_components()

	# Connect component signals
	_connect_signals()

	# Initialize components
	_initialize_components()

	# Set flashlight off by default
	if flashlight:
		flashlight.visible = false

	print("Player: initialized with all components")


func _create_components() -> void:
	# Create components in dependency order
	player_audio = PlayerAudio.new()
	player_audio.name = "PlayerAudio"
	add_child(player_audio)

	player_health = PlayerHealth.new()
	player_health.name = "PlayerHealth"
	add_child(player_health)

	player_ui = PlayerUI.new()
	player_ui.name = "PlayerUI"
	add_child(player_ui)

	player_inventory = PlayerInventory.new()
	player_inventory.name = "PlayerInventory"
	add_child(player_inventory)

	player_camera = PlayerCamera.new()
	player_camera.name = "PlayerCamera"
	add_child(player_camera)

	player_movement = PlayerMovement.new()
	player_movement.name = "PlayerMovement"
	add_child(player_movement)


func _wire_components() -> void:
	# Wire up PlayerHealth dependencies
	player_health.perk_manager = perk_manager

	# Wire up PlayerInventory dependencies
	player_inventory.player_health = player_health
	player_inventory.player_audio = player_audio
	player_inventory.interact_raycast = interact_raycast
	player_inventory.flashlight = flashlight
	player_inventory.inventory_ui = inventory_ui
	player_inventory.ui_container = get_node_or_null("UI")

	# Wire up PlayerCamera dependencies
	player_camera.player_inventory = player_inventory

	# Wire up PlayerMovement dependencies
	player_movement.collision_shape = collision_shape
	player_movement.player_inventory = player_inventory
	player_movement.player_health = player_health
	player_movement.player_ui = player_ui
	player_movement.perk_manager = perk_manager

	# Get alert system reference for PlayerMovement
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")
	if forest and "alert_system" in forest:
		player_movement.alert_system = forest.alert_system
		print("Player: connected to alert system")


func _connect_signals() -> void:
	# Connect PlayerHealth signals to PlayerUI
	player_health.health_changed.connect(_on_health_changed)
	player_health.sanity_changed.connect(_on_sanity_changed)
	player_health.bleed_changed.connect(_on_bleed_changed)
	player_health.died.connect(_on_player_died)

	# Connect PlayerUI signals
	player_ui.pause_toggled.connect(_on_pause_toggled)
	player_ui.inventory_toggled.connect(_on_inventory_toggled)
	player_ui.quit_requested.connect(_on_quit_requested)


func _initialize_components() -> void:
	# Initialize PlayerHealth
	# (Health component initializes itself in _ready)

	# Initialize PlayerUI bars
	player_ui.initialize_health_bars(player_health.max_health, player_health.current_health)
	player_ui.initialize_sanity_bar(player_health.max_sanity, player_health.current_sanity)

	# Initialize PlayerMovement stamina UI
	player_movement.initialize_stamina_ui()


# ── Input Handling ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Handle mouse look via PlayerCamera
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player_camera.handle_mouse_motion(event)

	# Toggle flashlight
	if event.is_action_pressed("flashlight"):
		if flashlight:
			flashlight.visible = not flashlight.visible
			player_audio.play_flashlight_toggle(flashlight.visible)

	# DEBUG: Toggle super speed with H key
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		player_movement.toggle_debug_speed()

	# Interact with items
	if event.is_action_pressed("interact") and not player_ui.is_inventory_open:
		player_inventory.try_pickup_item()

	# DEBUG: Spawn bear with P key
	if event.is_action_pressed("ui_text_backspace") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
		_spawn_test_bear()

	# DEBUG: Spawn deer group with O key
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:
		_spawn_test_deer_group()

	# Use equipped item with left click (when not in inventory)
	if event.is_action_pressed("shoot") and not player_ui.is_inventory_open:
		player_inventory.use_equipped_item()

	# Toggle inventory
	if event.is_action_pressed("toggle_inventory"):
		player_ui.toggle_inventory(inventory_ui)

	# Press ESC to pause/unpause (or close inventory/settings/console)
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if player_ui.is_inventory_open:
			player_ui.toggle_inventory(inventory_ui)
		elif player_ui.is_console_open():
			player_ui.hide_console()
		elif player_ui.is_settings_open():
			player_ui.hide_settings_menu()
		elif player_ui.is_paused:
			player_ui.toggle_pause()
		else:
			player_ui.toggle_pause()

	# Test damage with K key
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		player_health.take_damage(10.0)
		print("Test damage: -10 HP (Current: %.1f/%.1f)" % [player_health.current_health, player_health.max_health])

	# Adjust frequency with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			player_movement.adjust_frequency(0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			player_movement.adjust_frequency(-0.5)


# ── Physics Processing ───────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Update movement (handles physics, stamina, sprinting, crouching)
	player_movement.physics_process(delta, gravity)

	# Update camera with current movement state
	player_camera.is_sprinting = player_movement.is_sprinting
	player_camera.is_crouching = player_movement.is_crouching
	player_camera.is_on_floor = is_on_floor()
	player_camera.horizontal_velocity = player_movement.get_horizontal_velocity()
	player_camera.vertical_velocity = player_movement.get_vertical_velocity()
	player_camera.update_camera(delta)

	# Update UI elements
	player_ui.update_coordinate_label(global_position)
	player_ui.update_fps_label(Engine.get_frames_per_second())
	player_ui.update_vignette(player_health.current_health, player_health.max_health)

	# Update sanity based on danger zone
	player_health.update_sanity_from_zone(player_movement.current_danger_zone, delta)


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_health_changed(current: float, max_value: float) -> void:
	player_ui.update_health_bars(current, player_health.current_bleed_damage)
	player_audio.update_heartbeat(current, max_value)


func _on_sanity_changed(current: float, max_value: float) -> void:
	player_ui.update_sanity_bar(current)


func _on_bleed_changed(current_bleed: float, bleed_dps: float) -> void:
	player_ui.update_health_bars(player_health.current_health, current_bleed)


func _on_player_died() -> void:
	player_audio.stop_all_audio()
	print("Player died!")
	# TODO: Implement death screen, respawn, etc.


func _on_pause_toggled(is_paused: bool) -> void:
	# Pause/unpause the game
	get_tree().paused = is_paused

	# Switch mouse mode
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_inventory_toggled(is_open: bool) -> void:
	# Pause/unpause the game
	get_tree().paused = is_open

	# Switch mouse mode
	if is_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_quit_requested() -> void:
	get_tree().quit()


# ── Public API (called by weapons, enemies, etc.) ────────────────────────────

## Apply camera recoil (called by weapons)
func apply_recoil(amount: float = 1.0) -> void:
	player_camera.apply_recoil(amount)


## Equip an item (called by inventory UI)
func equip_item(item: InventoryItem) -> void:
	player_inventory.equip_item(item)


## Unequip an item (called by inventory UI)
func unequip_item(item: InventoryItem) -> void:
	player_inventory.unequip_item(item)


# ── Property Accessors (forward to components) ───────────────────────────────

## Get equipped weapon item (accessed by weapon scripts)
var equipped_weapon_item: InventoryItem:
	get:
		return player_inventory.equipped_weapon_item if player_inventory else null

## Get equipped weapon node (accessed by weapon scripts)
var equipped_weapon: Node3D:
	get:
		return player_inventory.equipped_weapon if player_inventory else null

## Get current weapon type (accessed by weapon scripts)
var current_weapon_type: String:
	get:
		return player_inventory.current_weapon_type if player_inventory else ""

## Get equipped item (accessed by inventory UI)
var equipped_item: InventoryItem:
	get:
		return player_inventory.equipped_item if player_inventory else null

## Get current health (accessed by enemies)
var current_health: float:
	get:
		return player_health.current_health if player_health else 0.0

## Get max health (accessed by UI)
var max_health: float:
	get:
		return player_health.max_health if player_health else 100.0

## Check if player is dead (accessed by enemies)
var is_dead: bool:
	get:
		return player_health.is_dead if player_health else false


# ── Debug Spawn Functions ────────────────────────────────────────────────────

func _spawn_test_bear() -> void:
	# DEBUG: Spawn a bear in the forest like natural spawning
	var bear_scene = load("res://animal_bear.tscn")
	if not bear_scene:
		print("Failed to load bear scene!")
		return

	var bear = bear_scene.instantiate()

	# Spawn in forest, off the path, 20-40m away
	var angle = randf() * TAU
	var distance = randf_range(20.0, 40.0)
	var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	var spawn_pos = global_position + offset

	# Get terrain height
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("get_height"):
		spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)
	else:
		spawn_pos.y = global_position.y

	get_tree().root.add_child(bear)
	bear.global_position = spawn_pos

	print("DEBUG: Spawned bear at %v (%.1fm away)" % [spawn_pos, distance])


func _spawn_test_deer_group() -> void:
	# DEBUG: Spawn a group of 2-5 deer
	var deer_scene = load("res://animal_deer.tscn")
	if not deer_scene:
		print("Failed to load deer scene!")
		return

	# Spawn 2-5 deer
	var deer_count = randi_range(2, 5)

	# Get terrain and path references
	var terrain = get_tree().get_first_node_in_group("terrain")
	var forest = get_tree().get_first_node_in_group("forest_generator")
	if not forest:
		forest = get_node_or_null("/root/TestLevel/ForestGenerator")

	var path_generator = null
	if forest and "path_generator" in forest:
		path_generator = forest.path_generator

	# Find base position NOT on path (try up to 10 times)
	var base_pos = Vector3.ZERO
	var base_distance = 0.0
	var found_valid_position = false

	for attempt in range(10):
		var base_angle = randf() * TAU
		base_distance = randf_range(15.0, 30.0)
		var base_offset = Vector3(cos(base_angle) * base_distance, 0, sin(base_angle) * base_distance)
		base_pos = global_position + base_offset

		# Check if on path
		if path_generator and path_generator.has_method("is_on_path"):
			if not path_generator.is_on_path(base_pos.x, base_pos.z):
				found_valid_position = true
				break
		else:
			# No path generator, position is valid
			found_valid_position = true
			break

	if not found_valid_position:
		print("DEBUG: Could not find valid deer spawn position off path")
		return

	# Spawn each deer in a small cluster around base position
	for i in range(deer_count):
		var deer = deer_scene.instantiate()

		# Scatter deer within 3-5 meters of base position
		var cluster_angle = randf() * TAU
		var cluster_distance = randf_range(3.0, 5.0)
		var cluster_offset = Vector3(cos(cluster_angle) * cluster_distance, 0, sin(cluster_angle) * cluster_distance)
		var spawn_pos = base_pos + cluster_offset

		# Get terrain height
		if terrain and terrain.has_method("get_height"):
			spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)
		else:
			spawn_pos.y = global_position.y

		get_tree().root.add_child(deer)
		deer.global_position = spawn_pos

	print("DEBUG: Spawned %d deer at base position %v (%.1fm away, OFF PATH)" % [deer_count, base_pos, base_distance])
