extends CharacterBody3D

## The Stalker - patience predator that teleports closer while unwatched
## Never moves while observed, charges after building up escalation

# Stalker settings
@export var watch_timer_threshold: float = 10.0  # Seconds of not being watched to trigger reposition
@export var hidden_wait_min: float = 10.0
@export var hidden_wait_max: float = 20.0
@export var reposition_distance: float = 5.0  # How much closer each reposition
@export var escalation_threshold_min: int = 5  # Cycles before charging
@export var escalation_threshold_max: int = 7
@export var charge_speed: float = 8.0  # Faster than player sprint
@export var charge_duration: float = 17.5  # Average 15-20 seconds
@export var charge_spawn_distance: float = 20.0  # Distance from player when charging starts
@export var retreat_speed: float = 4.0
@export var retreat_distance: float = 30.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 40.0
@export var damage_threshold_retreat: float = 50.0  # Damage needed to make stalker retreat
@export var detection_fov: float = 70.0  # Player FOV cone for detection

# References
var player: CharacterBody3D = null
var player_camera: Camera3D = null
var mesh_instance: MeshInstance3D = null
var terrain: TerrainGenerator = null

# Audio
var twig_sound: AudioStream = null
var leaves_sound: AudioStream = null
var moose_sound: AudioStream = null
var laugh_sound: AudioStream = null

# State machine
enum State { WATCHING, FLEEING, HIDDEN, REPOSITIONING, CHARGING, RETREATING }
var current_state: State = State.WATCHING
var previous_state: State = State.WATCHING

# Watch timer and escalation
var watch_timer: float = 0.0  # Increments when NOT being watched
var escalation_counter: int = 0
var escalation_threshold: int = 3

# Spot counter (minigame mechanic)
var successful_spots: int = 0  # How many times player has spotted the stalker
var required_spots: int = 4  # How many spots needed to banish stalker

# Hidden state
var hidden_wait_time: float = 0.0
var hidden_timer: float = 0.0

# Fleeing state (runs to cover when spotted)
var flee_target_position: Vector3 = Vector3.ZERO
var flee_speed: float = 6.0  # Fast movement to cover
var flee_timer: float = 0.0
var flee_fade_time: float = 1.5  # Fade out after 1.5 seconds of fleeing
var is_permanent_flee: bool = false  # If true, despawn after fleeing (player won)

# Charging state
var charge_timer: float = 0.0
var can_damage: bool = true
var damage_taken_during_charge: float = 0.0  # Track damage to trigger retreat

# Detection state
var has_been_spotted: bool = false  # Prevent spam detection

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Health
var max_health: float = 300.0
var current_health: float = 300.0

func _ready() -> void:
	# Add to group for spawn tracking
	add_to_group("enemy_stalker")

	# Find player and terrain
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	if player:
		player_camera = player.get_node_or_null("Camera3D")

	# Find terrain
	terrain = get_tree().get_first_node_in_group("terrain")

	# Create visual model (tall, thin, menacing)
	mesh_instance = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.height = 2.2  # Taller than player
	capsule_mesh.radius = 0.25  # Very thin
	mesh_instance.mesh = capsule_mesh

	# Create material (bright red for testing)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.05, 0.05)  # Dark red base
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0)  # Bright red glow
	material.emission_energy_multiplier = 3.0  # Very bright for testing
	mesh_instance.material_override = material

	add_child(mesh_instance)
	mesh_instance.position.y = 1.1

	# Randomize escalation threshold
	escalation_threshold = randi_range(escalation_threshold_min, escalation_threshold_max)

	# Set required spots based on escalation threshold
	if escalation_threshold <= 5:
		required_spots = 3
	else:
		required_spots = 4

	print("Stalker spawned - will charge after %d cycles (player must spot %d times to banish)" % [escalation_threshold, required_spots])

	# Load sounds
	twig_sound = load("res://audio/twig.wav")
	leaves_sound = load("res://audio/leaves.wav")
	moose_sound = load("res://audio/moose.wav")
	laugh_sound = load("res://audio/laugh_1.wav")

	# Play initial spawn audio cue
	play_reposition_sound(global_position)

func _physics_process(delta: float) -> void:
	if not player or not player_camera:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Always look at player
	look_at_player()

	# State machine
	match current_state:
		State.WATCHING:
			handle_watching(delta)
		State.FLEEING:
			handle_fleeing(delta)
		State.HIDDEN:
			handle_hidden(delta)
		State.REPOSITIONING:
			handle_repositioning(delta)
		State.CHARGING:
			handle_charging(delta)
		State.RETREATING:
			handle_retreating(delta)

	move_and_slide()

func handle_watching(delta: float) -> void:
	# Stand completely still
	velocity.x = 0.0
	velocity.z = 0.0

	# Check if player is looking at us (only if not already spotted)
	if not has_been_spotted:
		var is_being_watched = check_if_player_looking()

		if is_being_watched:
			# Player looked at us - increment successful spots counter
			has_been_spotted = true
			successful_spots += 1
			print("Stalker: Spotted by player! (%d/%d spots)" % [successful_spots, required_spots])
			play_laugh_sound()
			watch_timer = 0.0

			# Check if player has spotted enough times to banish stalker
			if successful_spots >= required_spots:
				print("Stalker: Player won! Stalker fleeing permanently!")
				transition_to_fleeing_permanent()
				return

			# Run to cover before hiding
			transition_to_fleeing()
			return

	# Not being watched - increment timer
	watch_timer += delta

	# Check if threshold reached
	if watch_timer >= watch_timer_threshold:
		# Trigger repositioning
		print("Stalker: Watch timer reached %.1fs - repositioning" % watch_timer)
		watch_timer = 0.0
		transition_to_repositioning()

func handle_fleeing(delta: float) -> void:
	# Simple flee: run to the side and fade out after time
	flee_timer += delta

	# After flee_fade_time seconds, start fading
	if flee_timer >= flee_fade_time:
		print("Stalker: Flee timer expired, fading out")

		# If permanent flee (player won), despawn completely
		if is_permanent_flee:
			fade_out_and_despawn()
		else:
			# Normal flee - go to hidden state
			transition_to_hidden()
		return

	# Run towards flee position
	if flee_target_position == Vector3.ZERO:
		if is_permanent_flee:
			despawn_stalker()
		else:
			transition_to_hidden()
		return

	var direction = (flee_target_position - global_position)
	direction.y = 0.0
	var distance = direction.length()

	# If we reached the target, just keep running in that direction
	if distance < 2.0:
		# Keep running in the same direction
		pass
	else:
		direction = direction.normalized()
		velocity.x = direction.x * flee_speed
		velocity.z = direction.z * flee_speed

func handle_hidden(delta: float) -> void:
	# Stand still while hidden
	velocity.x = 0.0
	velocity.z = 0.0

	# Increment timer
	hidden_timer += delta

	# Check if wait time elapsed
	if hidden_timer >= hidden_wait_time:
		hidden_timer = 0.0
		transition_to_repositioning()

func handle_repositioning(delta: float) -> void:
	# This is instant (teleport), so just transition immediately
	# The actual repositioning logic is in transition_to_repositioning()
	pass

func handle_charging(delta: float) -> void:
	# Sprint at player at high speed
	var direction = (player.global_position - global_position).normalized()
	direction.y = 0.0

	velocity.x = direction.x * charge_speed
	velocity.z = direction.z * charge_speed

	# Increment charge timer
	charge_timer += delta

	# Check if reached player (attack)
	var distance = global_position.distance_to(player.global_position)
	if distance <= attack_range and can_damage:
		attack_player()

	# Check if charge duration expired
	if charge_timer >= charge_duration:
		transition_to_retreating()

func handle_retreating(delta: float) -> void:
	# Move away from player
	var direction = (global_position - player.global_position).normalized()
	direction.y = 0.0

	velocity.x = direction.x * retreat_speed
	velocity.z = direction.z * retreat_speed

	# Check if far enough away
	var distance = global_position.distance_to(player.global_position)
	if distance >= retreat_distance:
		# Reset and go back to watching
		escalation_counter = 0
		escalation_threshold = randi_range(escalation_threshold_min, escalation_threshold_max)
		transition_to_watching()

func transition_to_watching() -> void:
	if current_state == State.WATCHING:
		return

	previous_state = current_state
	current_state = State.WATCHING
	watch_timer = 0.0
	has_been_spotted = false  # Reset spotted flag for new watch cycle

	# Make visible and reset visual
	if mesh_instance:
		mesh_instance.visible = true
		if mesh_instance.material_override:
			var mat = mesh_instance.material_override as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  # Reset transparency
			mat.albedo_color.a = 1.0  # Fully opaque
			mat.emission = Color(1.0, 0.0, 0.0)  # Bright red
			mat.emission_energy_multiplier = 3.0  # Bright for testing

	print("Stalker: WATCHING")

func transition_to_fleeing() -> void:
	if current_state == State.FLEEING:
		return

	previous_state = current_state
	current_state = State.FLEEING
	flee_timer = 0.0  # Reset timer
	is_permanent_flee = false

	# Simple flee: run to the side
	flee_target_position = find_cover_position_simple()

	if flee_target_position == Vector3.ZERO:
		print("Stalker: Failed to calculate flee position, hiding immediately")
		transition_to_hidden()
		return

	print("Stalker: FLEEING to side (will fade after %.1fs)" % flee_fade_time)

func transition_to_fleeing_permanent() -> void:
	# Player won the minigame - flee and despawn permanently
	previous_state = current_state
	current_state = State.FLEEING
	flee_timer = 0.0
	is_permanent_flee = true

	# Run to the side
	flee_target_position = find_cover_position_simple()

	if flee_target_position == Vector3.ZERO:
		# Just despawn if can't flee
		despawn_stalker()
		return

	print("Stalker: FLEEING permanently (player won minigame)")

func transition_to_hidden() -> void:
	if current_state == State.HIDDEN:
		return

	previous_state = current_state
	current_state = State.HIDDEN

	# Fade out over 0.5 seconds instead of instant disappear
	if mesh_instance:
		fade_out_stalker()

	# Set random wait time
	hidden_wait_time = randf_range(hidden_wait_min, hidden_wait_max)
	hidden_timer = 0.0

	print("Stalker: HIDDEN (waiting %.1fs)" % hidden_wait_time)

func fade_out_stalker() -> void:
	if not mesh_instance or not mesh_instance.material_override:
		return

	var mat = mesh_instance.material_override as StandardMaterial3D

	# Enable transparency
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var fade_duration = 0.5
	var elapsed = 0.0

	while elapsed < fade_duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

		var alpha = 1.0 - (elapsed / fade_duration)
		mat.albedo_color.a = alpha

		if mat.emission_enabled:
			var emission_color = mat.emission
			emission_color.a = alpha
			mat.emission = emission_color

	# Fully invisible
	mesh_instance.visible = false
	mat.albedo_color.a = 1.0  # Reset for next time

func transition_to_repositioning() -> void:
	previous_state = current_state
	current_state = State.REPOSITIONING

	# Increment escalation counter
	escalation_counter += 1
	print("Stalker: REPOSITIONING (escalation: %d/%d)" % [escalation_counter, escalation_threshold])

	# Check if we should charge this time
	if escalation_counter >= escalation_threshold:
		# Transition to charging (will find and spawn at charge position)
		transition_to_charging()
		# Play sound at charging spawn location
		if global_position != Vector3.ZERO:
			play_reposition_sound(global_position)
	else:
		# Not ready to charge yet, reposition normally - get closer
		var new_pos = find_reposition_target()
		if new_pos != Vector3.ZERO:
			global_position = new_pos
			# Play reposition sound at NEW location
			play_reposition_sound(global_position)
		transition_to_watching()

func transition_to_charging() -> void:
	if current_state == State.CHARGING:
		return

	# Try to find a valid charging position first
	var spawn_pos = Vector3.ZERO
	if player:
		spawn_pos = find_charging_position()

	# If we couldn't find a valid position, abort charge and reposition instead
	if spawn_pos == Vector3.ZERO:
		print("Stalker: Could not find valid charging position - repositioning instead")
		var reposition_pos = find_reposition_target()
		if reposition_pos != Vector3.ZERO:
			global_position = reposition_pos
			play_reposition_sound(global_position)
		transition_to_watching()
		return

	previous_state = current_state
	current_state = State.CHARGING
	charge_timer = 0.0
	can_damage = true
	damage_taken_during_charge = 0.0  # Reset damage counter

	# Move to charging position
	global_position = spawn_pos
	print("Stalker: Spawned for charge at %.1fm from player" % global_position.distance_to(player.global_position))

	# Brighten glow when charging
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(0.8, 0.3, 0.3)  # Red glow
		mat.emission_energy_multiplier = 2.0

	# Play moose sound when charging starts
	play_charge_sound()

	print("Stalker: CHARGING!")

func transition_to_retreating() -> void:
	if current_state == State.RETREATING:
		return

	previous_state = current_state
	current_state = State.RETREATING

	# Reset visual
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(1.0, 0.0, 0.0)  # Bright red
		mat.emission_energy_multiplier = 3.0  # Bright for testing

	print("Stalker: RETREATING")

func find_reposition_target() -> Vector3:
	# Find a position that is:
	# 1. At specific distance based on escalation progress
	# 2. Has line of sight to player
	# 3. Outside player's current FOV
	# 4. Preferably has partial occlusion (but not required)

	# Calculate target distance based on escalation progress
	# If threshold is 5: starts at 35m, then 30m, 25m, 20m, 15m
	# If threshold is 7: starts at 45m, then 40m, 35m, 30m, 25m, 20m, 15m
	var max_distance = 45.0  # Maximum starting distance
	var min_distance = 15.0  # Minimum distance before charging
	var distance_per_step = (max_distance - min_distance) / float(escalation_threshold - 1)
	var target_distance = max_distance - (distance_per_step * (escalation_counter - 1))
	target_distance = clampf(target_distance, min_distance, max_distance)

	print("Stalker: Targeting distance %.1fm (escalation %d/%d)" % [target_distance, escalation_counter, escalation_threshold])

	var max_attempts = 50
	var best_fallback_pos = Vector3.ZERO

	for attempt in range(max_attempts):
		# Random angle around player
		var angle = randf() * TAU

		# Position at target distance
		var offset = Vector3(cos(angle) * target_distance, 0, sin(angle) * target_distance)
		var candidate_pos = player.global_position + offset

		# Get terrain height
		if terrain:
			candidate_pos.y = terrain.get_height(candidate_pos.x, candidate_pos.z) + 1.1
		else:
			candidate_pos.y = player.global_position.y

		# Check basic requirements
		if not has_line_of_sight_to_player(candidate_pos):
			continue

		if is_in_player_fov(candidate_pos):
			continue

		# IMPORTANT: Check if player can actually see this position
		# This prevents spawning behind terrain/trees that fully block view
		if not player_can_see_position(candidate_pos):
			continue

		# Position is valid (bidirectional LOS + outside FOV)
		# Check if it's in the open (NO occlusion - preferred for dense forest)
		var has_good_occlusion = has_partial_occlusion(candidate_pos)

		if not has_good_occlusion:
			# Open position - preferred in dense forest
			print("Stalker: Found open position (fully visible) at %.1fm" % target_distance)
			return candidate_pos

		# Save as fallback - this position has cover (not preferred)
		if best_fallback_pos == Vector3.ZERO:
			best_fallback_pos = candidate_pos

	# Return fallback position if we found one (position with cover)
	if best_fallback_pos != Vector3.ZERO:
		print("Stalker: Using covered position (fallback) at %.1fm" % target_distance)
		return best_fallback_pos

	# Couldn't find valid position at all
	print("Stalker: Failed to find reposition target at %.1fm" % target_distance)
	return Vector3.ZERO

func find_cover_position_simple() -> Vector3:
	# Simple approach: run to the side of where player is looking
	# Avoid fleeing toward the path
	if not player or not player_camera:
		return Vector3.ZERO

	# Get camera forward direction
	var cam_forward = -player_camera.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	# Get perpendicular direction (left or right)
	var perpendicular = Vector3(-cam_forward.z, 0, cam_forward.x)

	# Try to pick direction that goes AWAY from the path
	var path_generator = get_tree().get_first_node_in_group("path")
	if path_generator and path_generator.has_method("get_nearest_path_point"):
		var nearest_path_point = path_generator.get_nearest_path_point(global_position)
		if nearest_path_point != Vector3.ZERO:
			# Direction from stalker to path
			var to_path = (nearest_path_point - global_position).normalized()
			to_path.y = 0.0

			# Pick the perpendicular direction that goes AWAY from path
			var dot_left = perpendicular.dot(to_path)
			var dot_right = (-perpendicular).dot(to_path)

			# Choose direction with smaller dot (goes away from path)
			if dot_left < dot_right:
				# Left goes away from path
				pass
			else:
				# Right goes away from path
				perpendicular = -perpendicular
		else:
			# No path found, randomly choose
			if randf() > 0.5:
				perpendicular = -perpendicular
	else:
		# Randomly choose left or right
		if randf() > 0.5:
			perpendicular = -perpendicular

	# Run 10-15m to the side
	var flee_distance = randf_range(10.0, 15.0)
	var flee_pos = global_position + (perpendicular * flee_distance)

	# Get terrain height
	if terrain:
		flee_pos.y = terrain.get_height(flee_pos.x, flee_pos.z) + 1.1
	else:
		flee_pos.y = global_position.y

	print("Stalker: Fleeing to the side (%.1fm away from path)" % flee_distance)
	return flee_pos

func find_cover_position() -> Vector3:
	# Find nearby objects (trees, rocks) and hide behind them

	if not player or not player_camera:
		return Vector3.ZERO

	var space_state = get_world_3d().direct_space_state

	print("\n=== FINDING COVER ===")
	print("Stalker position: %v" % global_position)
	print("Player position: %v" % player.global_position)

	# Use a sphere cast to find all nearby objects
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 20.0  # Search 20m around stalker
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.exclude = [self, player]
	query.collision_mask = 0xFFFFFFFF  # Check ALL collision layers
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var nearby_objects = space_state.intersect_shape(query, 100)  # Find up to 100 objects

	print("Sphere query found %d nearby objects" % nearby_objects.size())

	# If sphere query found nothing, try raycasts in a circle
	if nearby_objects.is_empty():
		print("Sphere query empty - trying raycast sweep")
		nearby_objects = find_objects_with_raycasts()
		print("Raycast sweep found %d objects" % nearby_objects.size())

	# Get direction away from player
	var away_from_player = (global_position - player.global_position).normalized()

	# Check each object to see if we can hide behind it
	var best_cover_pos = Vector3.ZERO
	var best_cover_score = -1.0

	for collision in nearby_objects:
		var collider = collision.collider if collision.has("collider") else collision.get("collider")

		# Get the object's position
		var object_pos = Vector3.ZERO

		# Handle both sphere query results and raycast results
		if collision.has("position"):
			# From raycast
			object_pos = collision.position
		elif collider is Node3D:
			# From sphere query
			object_pos = collider.global_position
		else:
			continue

		# Position ourselves on the opposite side of the object from the player
		# Calculate direction from player through object
		var player_to_object = (object_pos - player.global_position).normalized()

		# Place stalker 3-5m behind the object (farther to ensure it blocks LOS)
		var hide_distance = randf_range(3.0, 5.0)
		var hide_pos = object_pos + (player_to_object * hide_distance)

		print("Checking object at %v, hide pos: %v (%.1fm behind)" % [object_pos, hide_pos, hide_distance])

		# Get terrain height
		if terrain:
			hide_pos.y = terrain.get_height(hide_pos.x, hide_pos.z) + 1.1
		else:
			hide_pos.y = global_position.y

		# Only consider positions within reasonable range (not too close, not too far)
		var distance_to_hide_pos = global_position.distance_to(hide_pos)
		if distance_to_hide_pos < 3.0:  # Too close - probably not valid cover
			print("  REJECTED: Too close (%.1fm)" % distance_to_hide_pos)
			continue
		if distance_to_hide_pos > 20.0:  # Too far
			print("  REJECTED: Too far (%.1fm)" % distance_to_hide_pos)
			continue

		# CRITICAL: Verify the object is actually between player and hide position
		# Shoot ray from player to hide pos - should hit the object
		var verification_query = PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3(0, 1.0, 0),
			hide_pos + Vector3(0, 1.0, 0)
		)
		verification_query.exclude = [player, self]
		verification_query.collision_mask = 0xFFFFFFFF

		var verification_result = space_state.intersect_ray(verification_query)

		# If the ray DOESN'T hit anything, or hits something past the object, skip this
		if not verification_result:
			print("  REJECTED: No obstruction between player and hide pos")
			continue

		# Check if hit point is near the object (within 2m)
		var hit_to_object_dist = verification_result.position.distance_to(object_pos)
		if hit_to_object_dist > 3.0:
			print("  REJECTED: Hit point %.1fm from object (object not blocking)" % hit_to_object_dist)
			continue

		print("  VALID: Object blocks LOS (hit within %.1fm of object)" % hit_to_object_dist)

		# Test if this position actually blocks LOS from player
		var is_fully_hidden = true
		var blocked_count = 0
		for height_offset in [0.5, 1.0, 1.8]:  # Test feet, chest, head
			var test_point = hide_pos + Vector3(0, height_offset, 0)

			var los_query = PhysicsRayQueryParameters3D.create(
				player_camera.global_position,
				test_point
			)
			los_query.exclude = [player, self]
			los_query.collision_mask = 0xFFFFFFFF  # Check all layers

			var los_result = space_state.intersect_ray(los_query)

			# If raycast hits something = blocked (good)
			# If raycast hits nothing = reaches hide_pos = visible (bad)
			if los_result:
				blocked_count += 1
				var hit_distance = player_camera.global_position.distance_to(los_result.position)
				var target_distance = player_camera.global_position.distance_to(test_point)
				print("  Height %.1fm BLOCKED by: %s (hit at %.1fm, target at %.1fm)" % [height_offset, los_result.collider.name if los_result.collider else "unknown", hit_distance, target_distance])
			else:
				print("  Height %.1fm VISIBLE (ray reached target, no obstruction)" % height_offset)
				is_fully_hidden = false
				break

		if is_fully_hidden:
			# Prioritize CLOSEST valid cover (simplest and most reliable)
			if best_cover_pos == Vector3.ZERO or distance_to_hide_pos < global_position.distance_to(best_cover_pos):
				best_cover_pos = hide_pos
				print("  NEW BEST: Closest cover at %.1fm" % distance_to_hide_pos)

	if best_cover_pos != Vector3.ZERO:
		var distance = global_position.distance_to(best_cover_pos)
		print("✓ FOUND VALID COVER at %.1fm away: %v" % [distance, best_cover_pos])
		print("===================\n")
		return best_cover_pos

	# Fallback: just run away from player
	var fallback_pos = global_position + (away_from_player * 12.0)
	if terrain:
		fallback_pos.y = terrain.get_height(fallback_pos.x, fallback_pos.z) + 1.1

	print("✗ NO VALID COVER FOUND - using fallback position")
	print("Fallback position: %v (12m away from player)" % fallback_pos)
	print("===================\n")
	return fallback_pos

func find_objects_with_raycasts() -> Array:
	# Fallback method: shoot rays in all directions to find nearby objects
	var space_state = get_world_3d().direct_space_state
	var found_objects = []
	var unique_colliders = {}

	# Shoot rays in a circle around stalker
	for i in range(16):  # 16 directions
		var angle = (TAU / 16.0) * i
		var direction = Vector3(cos(angle), 0, sin(angle))

		for distance in [5.0, 10.0, 15.0, 20.0]:  # Multiple distances
			var target = global_position + (direction * distance)

			var query = PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0, 1.0, 0),
				target + Vector3(0, 1.0, 0)
			)
			query.exclude = [self, player]
			query.collision_mask = 0xFFFFFFFF

			var result = space_state.intersect_ray(query)

			if result and result.collider:
				var collider = result.collider
				# Avoid duplicates
				if not unique_colliders.has(collider):
					unique_colliders[collider] = true
					found_objects.append({"collider": collider, "position": result.position})

	return found_objects

func find_charging_position() -> Vector3:
	# Find position exactly charge_spawn_distance away for charging
	var max_attempts = 50

	for attempt in range(max_attempts):
		var angle = randf() * TAU
		var offset = Vector3(cos(angle) * charge_spawn_distance, 0, sin(angle) * charge_spawn_distance)
		var candidate_pos = player.global_position + offset

		# Get terrain height
		if terrain:
			candidate_pos.y = terrain.get_height(candidate_pos.x, candidate_pos.z) + 1.1
		else:
			candidate_pos.y = player.global_position.y

		# Check FOV and bidirectional LOS (player must be able to see stalker)
		if has_line_of_sight_to_player(candidate_pos) and not is_in_player_fov(candidate_pos) and player_can_see_position(candidate_pos):
			return candidate_pos

	print("Stalker: Failed to find charging position")
	return Vector3.ZERO

func has_line_of_sight_to_player(from_pos: Vector3) -> bool:
	if not player:
		return false

	# Raycast from position to player
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		from_pos,
		player.global_position + Vector3(0, 1.0, 0)  # Aim at player center
	)
	query.exclude = [self]
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)

	# If we hit the player or nothing, we have LOS
	if not result or result.collider == player:
		return true

	return false

func player_can_see_position(pos: Vector3) -> bool:
	# Check if player has clear LOS to this position (terrain + trees)
	if not player or not player_camera:
		return false

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player_camera.global_position,
		pos + Vector3(0, 1.0, 0)  # Aim at stalker center height
	)
	query.exclude = [player, self]
	query.collision_mask = 1  # World geometry (terrain + tree collision)

	var result = space_state.intersect_ray(query)

	# If ray reaches position without hitting anything, player can see it
	return not result

func is_in_player_fov(pos: Vector3) -> bool:
	if not player_camera:
		return false

	# Get direction from camera to position
	var to_pos = (pos - player_camera.global_position).normalized()

	# Get camera forward direction
	var cam_forward = -player_camera.global_transform.basis.z

	# Calculate dot product
	var dot = cam_forward.dot(to_pos)

	# If dot > threshold, position is in FOV
	# FOV of 70 degrees means threshold is cos(70) ≈ 0.34
	var threshold = cos(deg_to_rad(detection_fov))

	return dot > threshold

func has_partial_occlusion(pos: Vector3) -> bool:
	# Check if there's something between position and player camera
	# BUT make sure the stalker is still somewhat visible

	if not player_camera:
		return false

	var space_state = get_world_3d().direct_space_state

	# Cast multiple rays to check if stalker would be partially visible
	# Center ray (chest level)
	var center_query = PhysicsRayQueryParameters3D.create(
		player_camera.global_position,
		pos + Vector3(0, 1.0, 0)  # Aim at center
	)
	center_query.exclude = [player, self]
	center_query.collision_mask = 1

	var center_result = space_state.intersect_ray(center_query)

	# Top ray (head level)
	var top_query = PhysicsRayQueryParameters3D.create(
		player_camera.global_position,
		pos + Vector3(0, 1.8, 0)  # Aim at top of stalker
	)
	top_query.exclude = [player, self]
	top_query.collision_mask = 1

	var top_result = space_state.intersect_ray(top_query)

	# If BOTH center and top are blocked, stalker is completely hidden - reject
	if center_result and top_result:
		return false  # Too much occlusion - stalker would be invisible

	# If at least one ray is clear, stalker is partially visible - good position
	return true

func check_if_player_can_see_stalker() -> bool:
	# Check if player has unobstructed LOS to stalker (for fleeing logic)
	if not player_camera:
		return false

	var space_state = get_world_3d().direct_space_state

	# Test multiple heights on stalker
	for height_offset in [0.5, 1.0, 1.8]:
		var test_point = global_position + Vector3(0, height_offset, 0)

		var query = PhysicsRayQueryParameters3D.create(
			player_camera.global_position,
			test_point
		)
		query.exclude = [player, self]
		query.collision_mask = 0xFFFFFFFF

		var result = space_state.intersect_ray(query)

		# If result is NULL = ray reached stalker = VISIBLE
		# If result exists = ray hit obstacle = BLOCKED
		if not result:
			print("  Height %.1fm VISIBLE to player" % height_offset)
			return true  # Player can see this part
		else:
			print("  Height %.1fm BLOCKED by %s" % [height_offset, result.collider.name if result.collider else "unknown"])

	# All parts blocked - player cannot see us
	print("Stalker: Fully hidden from player")
	return false

func check_if_player_looking() -> bool:
	# Check if player is looking DIRECTLY at stalker with tight detection
	if not player_camera:
		return false

	var space_state = get_world_3d().direct_space_state

	# Cast ray from camera straight forward through crosshair
	var from = player_camera.global_position
	var forward = -player_camera.global_transform.basis.z
	var to = from + (forward * 150.0)  # 150m forward

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)

	# Player must be looking DIRECTLY at the stalker (raycast hits it)
	if result and result.collider == self:
		print("Stalker: PLAYER IS LOOKING DIRECTLY AT ME!")
		return true

	return false

func look_at_player() -> void:
	if not player:
		return

	var direction = Vector3.ZERO
	direction.x = player.global_position.x - global_position.x
	direction.z = player.global_position.z - global_position.z
	direction.y = 0.0

	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = target_rotation

func attack_player() -> void:
	if not player or not can_damage:
		return

	# FAIRNESS CHECK: Only allow attack if player can actually see the stalker
	# This prevents invisible/behind-terrain attacks
	if not player_can_see_position(global_position):
		print("Stalker: Attack BLOCKED - player can't see me (behind terrain)")
		# Don't damage, but still retreat (failed attack)
		can_damage = false
		transition_to_retreating()
		return

	can_damage = false
	print("Stalker ATTACK!")

	# Visual/audio feedback for attack
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(1.0, 0.0, 0.0)  # Bright red flash
		mat.emission_energy_multiplier = 5.0

	# Play attack sound (laugh)
	if laugh_sound:
		var audio_player = AudioStreamPlayer3D.new()
		audio_player.stream = laugh_sound
		audio_player.max_distance = 100.0
		audio_player.unit_size = 20.0
		get_tree().root.add_child(audio_player)
		audio_player.global_position = global_position
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)

	if player.has_method("take_damage"):
		player.take_damage(attack_damage)

	# Reset successful spots counter - player failed to banish stalker
	print("Stalker: Attack successful! Spot counter reset (%d → 0)" % successful_spots)
	successful_spots = 0

	# After hitting player, retreat
	transition_to_retreating()

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Stalker took %.1f damage. Health: %.1f/%.1f" % [amount, current_health, max_health])

	# Track damage during charge
	if current_state == State.CHARGING:
		damage_taken_during_charge += amount
		print("Stalker took %.1f damage while charging (%.1f/%.1f total)" % [amount, damage_taken_during_charge, damage_threshold_retreat])

	# Flash red when hit
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.emission = Color(1.0, 0.2, 0.2)
		mat.emission_energy_multiplier = 3.0

		await get_tree().create_timer(0.15).timeout

		if mesh_instance and mesh_instance.material_override:
			# Restore appropriate color based on state
			if current_state == State.CHARGING:
				mat.emission = Color(0.8, 0.3, 0.3)
				mat.emission_energy_multiplier = 2.0
			else:
				mat.emission = Color(0.3, 0.3, 0.5)
				mat.emission_energy_multiplier = 0.3

	# Being hit while charging causes retreat if damage threshold reached
	if current_state == State.CHARGING and damage_taken_during_charge >= damage_threshold_retreat:
		print("Stalker interrupted by %1.f damage - retreating!" % damage_taken_during_charge)
		transition_to_retreating()

	if current_health <= 0.0:
		die()

func play_reposition_sound(sound_position: Vector3) -> void:
	# Randomly choose between twig and leaves sound
	var sound_to_play = twig_sound if randf() > 0.5 else leaves_sound

	if not sound_to_play:
		print("Stalker: ERROR - No reposition sound loaded!")
		return

	print("Stalker: Playing reposition sound at position: %v" % sound_position)

	# Create a temporary AudioStreamPlayer3D at the position
	var sound_player = AudioStreamPlayer3D.new()
	sound_player.stream = sound_to_play
	sound_player.max_distance = 80.0  # Max range player can hear it
	sound_player.unit_size = 40.0  # Large radius where sound is at full volume
	sound_player.volume_db = 3.0  # Base volume
	sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE  # Better for gameplay
	sound_player.attenuation_filter_cutoff_hz = 8000.0  # Less aggressive filter
	sound_player.attenuation_filter_db = -12.0  # Gentler filtering
	sound_player.max_db = 6.0  # Higher cap
	sound_player.panning_strength = 1.2  # Moderate panning for directionality
	sound_player.autoplay = true

	# Add to scene at position
	get_tree().root.add_child(sound_player)
	sound_player.global_position = sound_position

	# Remove after sound finishes
	await sound_player.finished
	sound_player.queue_free()

func play_charge_sound() -> void:
	if not moose_sound:
		return

	# Create a temporary AudioStreamPlayer3D at stalker's position
	var sound_player = AudioStreamPlayer3D.new()
	sound_player.stream = moose_sound
	sound_player.max_distance = 100.0  # Warning sound range
	sound_player.unit_size = 50.0  # Very large radius - this is a warning!
	sound_player.volume_db = 6.0  # Loud but not deafening
	sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sound_player.attenuation_filter_cutoff_hz = 8000.0
	sound_player.attenuation_filter_db = -12.0
	sound_player.max_db = 9.0  # Allow it to be quite loud
	sound_player.panning_strength = 1.2
	sound_player.autoplay = true

	# Add to scene at stalker position
	get_tree().root.add_child(sound_player)
	sound_player.global_position = global_position

	# Remove after sound finishes
	await sound_player.finished
	sound_player.queue_free()

func play_laugh_sound() -> void:
	if not laugh_sound:
		return

	# Create a temporary AudioStreamPlayer3D at stalker's position
	var sound_player = AudioStreamPlayer3D.new()
	sound_player.stream = laugh_sound
	sound_player.max_distance = 80.0  # Moderate range
	sound_player.unit_size = 35.0  # Medium-large radius
	sound_player.volume_db = 3.0
	sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sound_player.attenuation_filter_cutoff_hz = 8000.0
	sound_player.attenuation_filter_db = -12.0
	sound_player.max_db = 6.0
	sound_player.panning_strength = 1.2
	sound_player.autoplay = true

	# Add to scene at stalker position
	get_tree().root.add_child(sound_player)
	sound_player.global_position = global_position

	# Remove after sound finishes
	await sound_player.finished
	sound_player.queue_free()

func fade_out_and_despawn() -> void:
	# Fade out then remove from game permanently
	if mesh_instance:
		await fade_out_stalker()

	print("Stalker despawning - player won!")
	queue_free()

func despawn_stalker() -> void:
	# Instant despawn (fallback)
	print("Stalker despawning!")
	queue_free()

func die() -> void:
	print("Stalker died!")
	queue_free()
