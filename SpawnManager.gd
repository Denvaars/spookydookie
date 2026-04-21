class_name SpawnManager
extends Node

## Manages enemy spawning based on frequency and danger zones
## Spawns enemies out of line of sight and at least 15m away

@export var min_spawn_distance: float = 35.0
@export var max_spawn_distance: float = 45.0
@export var spawn_check_interval: float = 2.0  # Check for spawn every N seconds

var frequency: float = 0.0  # 0.0 to 10.0, controls spawn rate
var danger_manager: DangerZoneManager = null
var terrain: TerrainGenerator = null
var player: CharacterBody3D = null
var path_generator: PathGenerator = null

var time_since_last_check: float = 0.0
var spawn_sound: AudioStreamPlayer
var has_logged_no_player: bool = false

# Enemy scenes
var enemy_scenes: Array[PackedScene] = []

func _ready() -> void:
	print("SpawnManager: _ready() called")

	# Load enemy scenes
	# Enemy basic disabled for now
	# var basic_scene = load("res://enemy_basic.tscn")
	# if basic_scene:
	# 	enemy_scenes.append(basic_scene)
	# 	print("SpawnManager: loaded enemy_basic.tscn")

	# Load enemy_stalker
	var stalker_scene = load("res://enemy_stalker.tscn")
	if stalker_scene:
		enemy_scenes.append(stalker_scene)
		print("SpawnManager: loaded enemy_stalker.tscn")
	else:
		print("SpawnManager: ERROR - failed to load enemy_stalker.tscn")

	print("SpawnManager: total enemy types loaded: %d" % enemy_scenes.size())

	# Setup spawn sound
	spawn_sound = AudioStreamPlayer.new()
	var behindyou_audio = load("res://audio/behindyou.wav")
	if behindyou_audio:
		spawn_sound.stream = behindyou_audio
		print("SpawnManager: loaded behindyou.wav")
	else:
		print("SpawnManager: ERROR - failed to load behindyou.wav")
	spawn_sound.bus = "Master"
	add_child(spawn_sound)

func initialize(p_danger_manager: DangerZoneManager, p_terrain: TerrainGenerator, p_player: CharacterBody3D, p_path: PathGenerator) -> void:
	danger_manager = p_danger_manager
	terrain = p_terrain
	player = p_player
	path_generator = p_path
	print("SpawnManager: initialized with:")
	print("  - danger_manager: ", danger_manager != null)
	print("  - terrain: ", terrain != null)
	print("  - player: ", player != null)
	print("  - path_generator: ", path_generator != null)
	if player:
		print("  - player position: ", player.global_position)

func _process(delta: float) -> void:
	if not player:
		return

	if frequency <= 0.0:
		return

	time_since_last_check += delta

	if time_since_last_check >= spawn_check_interval:
		time_since_last_check = 0.0
		attempt_spawn()

func attempt_spawn() -> void:
	# Calculate spawn chance based on frequency and danger
	var player_danger = 1.0
	if danger_manager:
		player_danger = danger_manager.get_danger_level(player.global_position)
	else:
		print("SpawnManager: WARNING - no danger_manager!")

	# Don't spawn in safe areas (danger < 2.0)
	if player_danger < 2.0:
		return

	# Spawn chance increases with frequency and danger
	# Frequency 1.0 + Danger 1.0 = 5% chance per check
	# Frequency 10.0 + Danger 3.0 = 65% chance per check
	var spawn_chance = (frequency * 0.05) * (player_danger * 0.5)
	spawn_chance = clampf(spawn_chance, 0.0, 0.8)  # Max 80% chance

	var roll = randf()

	if roll < spawn_chance:
		print("SpawnManager: SPAWN TRIGGERED! (freq: %.1f, danger: %.2f, chance: %.1f%%)" % [frequency, player_danger, spawn_chance * 100])
		spawn_enemy()

func spawn_enemy() -> void:
	# Check if a stalker already exists (only one at a time)
	var existing_stalker = get_tree().get_first_node_in_group("enemy_stalker")
	if existing_stalker:
		print("SpawnManager: stalker already active, skipping spawn")
		return

	# Find valid spawn position around player (not necessarily on path)
	var spawn_pos = find_valid_spawn_position()

	if spawn_pos == Vector3.ZERO:
		print("SpawnManager: could not find valid spawn position")
		return

	# Check if we have enemy scenes
	if enemy_scenes.is_empty():
		print("SpawnManager: ERROR - no enemy scenes loaded!")
		return

	# Pick random enemy type
	var enemy_scene = enemy_scenes[randi() % enemy_scenes.size()]
	var enemy = enemy_scene.instantiate()

	# Add to scene
	get_tree().root.add_child(enemy)
	enemy.global_position = spawn_pos

	# Play spawn sound
	if spawn_sound:
		spawn_sound.play()

	print("SpawnManager: ✓ Spawned enemy at %v" % spawn_pos)

func find_valid_spawn_position_ahead_on_path() -> Vector3:
	if not path_generator or not player:
		return Vector3.ZERO

	var camera = player.get_node_or_null("Camera3D")
	if not camera:
		return Vector3.ZERO

	var main_path = path_generator.main_path
	if main_path.is_empty():
		return Vector3.ZERO

	# Find player's current position along path
	var player_path_index = find_nearest_path_index(player.global_position, main_path)

	# Spawn 30-80 meters ahead on the path
	var spawn_distance_ahead = randf_range(30.0, 80.0)
	var accumulated_distance = 0.0
	var spawn_index = player_path_index

	# Walk forward along path until we've gone far enough
	for i in range(player_path_index, main_path.size() - 1):
		var segment_length = main_path[i].distance_to(main_path[i + 1])
		accumulated_distance += segment_length

		if accumulated_distance >= spawn_distance_ahead:
			spawn_index = i + 1
			break

	# Make sure we have a valid index
	if spawn_index >= main_path.size():
		spawn_index = main_path.size() - 1

	# Get position on path
	var path_position = main_path[spawn_index]

	# Offset slightly to the side (±5m from path)
	var offset = randf_range(-5.0, 5.0)
	var spawn_pos = path_position + Vector3(offset, 0, 0)

	# Get terrain height
	if terrain:
		spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)

	# Check if in camera view
	if is_in_camera_view(spawn_pos, camera):
		# Try once more with different offset
		offset = randf_range(-5.0, 5.0)
		spawn_pos = path_position + Vector3(offset, 0, 0)
		if terrain:
			spawn_pos.y = terrain.get_height(spawn_pos.x, spawn_pos.z)

		if is_in_camera_view(spawn_pos, camera):
			return Vector3.ZERO

	return spawn_pos

func find_nearest_path_index(position: Vector3, path: Array) -> int:
	var nearest_index = 0
	var nearest_distance = INF

	for i in range(path.size()):
		var dist = Vector2(position.x, position.z).distance_to(Vector2(path[i].x, path[i].z))
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_index = i

	return nearest_index

func find_valid_spawn_position() -> Vector3:
	var max_attempts = 20
	var camera = player.get_node_or_null("Camera3D")

	if not camera:
		return Vector3.ZERO

	for attempt in range(max_attempts):
		# Random angle around player
		var angle = randf() * TAU

		# Random distance from player
		var distance = randf_range(min_spawn_distance, max_spawn_distance)

		# Calculate position
		var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		var potential_pos = player.global_position + offset

		# Get terrain height
		if terrain:
			potential_pos.y = terrain.get_height(potential_pos.x, potential_pos.z)
		else:
			potential_pos.y = player.global_position.y

		# Check if position is outside camera view
		var in_view = is_in_camera_view(potential_pos, camera)
		var dist = player.global_position.distance_to(potential_pos)

		if not in_view and dist >= min_spawn_distance:
			return potential_pos

	return Vector3.ZERO

func is_in_camera_view(world_pos: Vector3, camera: Camera3D) -> bool:
	# Get position relative to camera
	var local_pos = world_pos - camera.global_position

	# Get camera forward direction
	var cam_forward = -camera.global_transform.basis.z

	# Check if point is behind camera
	var dot = local_pos.normalized().dot(cam_forward)
	if dot < 0.1:  # Behind or too far to the side
		return false

	# Project to screen space
	var screen_pos = camera.unproject_position(world_pos)
	var viewport_size = camera.get_viewport().get_visible_rect().size

	# Check if on screen (with margin for safety)
	var margin = 100.0
	if screen_pos.x < -margin or screen_pos.x > viewport_size.x + margin:
		return false
	if screen_pos.y < -margin or screen_pos.y > viewport_size.y + margin:
		return false

	return true

func set_frequency(new_frequency: float) -> void:
	var old_frequency = frequency
	frequency = clampf(new_frequency, 0.0, 10.0)
	print("SpawnManager: frequency changed from %.1f to %.1f" % [old_frequency, frequency])
	if frequency > 0.0 and player:
		print("SpawnManager: spawning is ACTIVE (next check in %.1fs)" % (spawn_check_interval - time_since_last_check))
