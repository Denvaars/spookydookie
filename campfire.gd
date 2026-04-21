extends Node3D

## Campfire that can be lit with a lighter
## Burns for 60 seconds then goes out, wood disappears

# Campfire settings
@export var campfire_scale: float = 0.35
@export var burn_duration: float = 60.0
@export var light_radius: float = 15.0
@export var light_intensity: float = 4.0
@export var interact_hold_time: float = 2.0  # How long to hold E to light

# State
var is_lit: bool = false
var has_wood: bool = true
var burn_timer: float = 0.0
var interact_progress: float = 0.0
var is_player_interacting: bool = false

# References
var stones_model: Node3D = null
var wood_model: Node3D = null
var campfire_light: OmniLight3D = null
var fire_audio: AudioStreamPlayer3D = null
var player: CharacterBody3D = null
var my_prompt_name: String = ""  # Unique prompt name for this campfire

func find_meshes_recursive(node: Node) -> Array:
	var meshes = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(find_meshes_recursive(child))
	return meshes

func _ready() -> void:
	# Add to interactable group
	add_to_group("campfire")

	# Identify this campfire with unique prompt name
	my_prompt_name = "CampfirePrompt_%s" % get_instance_id()

	# Apply scale
	scale = Vector3(campfire_scale, campfire_scale, campfire_scale)

	# Get model references from scene
	stones_model = get_node_or_null("CampfireStones")
	wood_model = get_node_or_null("CampfireWood")

	if wood_model:
		# Try to find mesh instances recursively
		var meshes = find_meshes_recursive(wood_model)
		for mesh in meshes:
			mesh.visible = true  # Force visible

	# Create light (starts disabled)
	campfire_light = OmniLight3D.new()
	campfire_light.light_color = Color(1.0, 0.5, 0.1)  # Orange fire color
	campfire_light.omni_range = light_radius
	campfire_light.light_energy = light_intensity
	campfire_light.shadow_enabled = true
	campfire_light.visible = false
	add_child(campfire_light)
	campfire_light.position.y = 0.5  # Slightly above ground

	# Create audio player
	fire_audio = AudioStreamPlayer3D.new()
	var fire_sound = load("res://audio/fire.wav")
	if fire_sound:
		fire_audio.stream = fire_sound
	fire_audio.max_distance = 20.0
	fire_audio.unit_size = 5.0
	add_child(fire_audio)

	# Check if InteractionBody already exists (from scene)
	var existing_body = get_node_or_null("InteractionBody")
	if existing_body:
		# Fix collision layers if incorrect
		if existing_body.collision_layer != 2:
			existing_body.collision_layer = 2
		if existing_body.collision_mask != 0:
			existing_body.collision_mask = 0
	else:
		# Add collision for interaction detection
		var static_body = StaticBody3D.new()
		static_body.name = "InteractionBody"
		var collision_shape = CollisionShape3D.new()
		var cylinder_shape = CylinderShape3D.new()
		cylinder_shape.radius = 0.8  # Larger radius for easier interaction
		cylinder_shape.height = 0.5
		collision_shape.shape = cylinder_shape
		collision_shape.position.y = 0.25
		static_body.add_child(collision_shape)
		static_body.collision_layer = 2  # Layer 2 for interactable objects (same as pickups)
		static_body.collision_mask = 0
		add_child(static_body)

	# Campfire ready

func _process(delta: float) -> void:
	# Handle burning
	if is_lit:
		burn_timer += delta

		# Flicker effect
		var flicker = randf_range(0.9, 1.1)
		campfire_light.light_energy = light_intensity * flicker

		# Check if burn time is up
		if burn_timer >= burn_duration:
			extinguish()

	# Check for player interaction
	check_player_interaction(delta)

func check_player_interaction(delta: float) -> void:
	if not has_wood or is_lit:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	# Find player
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return

	# Check if player is looking directly at the campfire with raycast
	var camera = player.get_node_or_null("Camera3D")
	if not camera:
		interact_progress = 0.0
		hide_interaction_ui()
		return

	var raycast = camera.get_node_or_null("InteractRaycast")

	if not raycast:
		# Fallback to distance check
		var distance = global_position.distance_to(player.global_position)
		if distance > 3.0:
			interact_progress = 0.0
			hide_interaction_ui()
			return
	else:
		# Check if raycast is hitting this campfire or its children
		if not raycast.is_colliding():
			interact_progress = 0.0
			hide_interaction_ui()
			return

		var collider = raycast.get_collider()
		var is_looking_at_campfire = false

		# Check if collider is this campfire or a child of it
		var check_node = collider
		while check_node:
			if check_node == self:
				is_looking_at_campfire = true
				break
			check_node = check_node.get_parent()

		if not is_looking_at_campfire:
			interact_progress = 0.0
			hide_interaction_ui()
			return

	# Player is looking at campfire - check lighter
	var has_lighter = player.equipped_item and player.equipped_item.item_id == "lighter_01"
	var lighter_is_lit = false

	if has_lighter and player.equipped_weapon and "is_lit" in player.equipped_weapon:
		lighter_is_lit = player.equipped_weapon.is_lit

	# Show appropriate prompt
	if not has_lighter:
		show_interaction_prompt("Lighter Required", false)
		interact_progress = 0.0
	elif not lighter_is_lit:
		show_interaction_prompt("Light the lighter first", false)
		interact_progress = 0.0
	else:
		show_interaction_prompt("[E] Light Fire", true)

		# Check if player is holding E
		if Input.is_action_pressed("interact"):
			interact_progress += delta
			update_progress_bar(interact_progress / interact_hold_time)

			# Check if fully lit
			if interact_progress >= interact_hold_time:
				light_campfire()
				interact_progress = 0.0
				hide_interaction_ui()
		else:
			# Reset progress if they let go
			if interact_progress > 0.0:
				interact_progress = 0.0
				update_progress_bar(0.0)

func is_player_looking_at_campfire() -> bool:
	if not player:
		return false

	var camera = player.get_node_or_null("Camera3D")
	if not camera:
		return false

	# Check if camera is facing the campfire
	var to_campfire = (global_position - camera.global_position).normalized()
	var camera_forward = -camera.global_transform.basis.z
	var dot = to_campfire.dot(camera_forward)

	return dot > 0.7  # About 45 degree cone

func show_interaction_prompt(text: String, can_interact: bool) -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if not prompt:
		# Create the prompt UI
		prompt = Control.new()
		prompt.name = my_prompt_name
		prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Center it on screen
		prompt.set_anchors_preset(Control.PRESET_CENTER)
		prompt.position = Vector2(-100, 150)  # Below crosshair

		var label = Label.new()
		label.name = "PromptLabel"
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prompt.add_child(label)

		# Create progress bar
		var progress_bg = ColorRect.new()
		progress_bg.name = "ProgressBG"
		progress_bg.color = Color(0.2, 0.2, 0.2, 0.8)
		progress_bg.size = Vector2(200, 20)
		progress_bg.position = Vector2(0, 30)
		progress_bg.visible = false
		prompt.add_child(progress_bg)

		var progress_fill = ColorRect.new()
		progress_fill.name = "ProgressFill"
		progress_fill.color = Color(1, 0.6, 0.2)  # Orange like fire
		progress_fill.size = Vector2(0, 20)
		progress_fill.position = Vector2(0, 30)
		progress_fill.visible = false
		prompt.add_child(progress_fill)

		ui.add_child(prompt)

	var label = prompt.get_node("PromptLabel")
	if label:
		label.text = text

	prompt.visible = true

func update_progress_bar(progress: float) -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if not prompt:
		return

	var progress_bg = prompt.get_node_or_null("ProgressBG")
	var progress_fill = prompt.get_node_or_null("ProgressFill")

	if progress_bg and progress_fill:
		if progress > 0.0:
			progress_bg.visible = true
			progress_fill.visible = true
			progress_fill.size.x = 200 * clamp(progress, 0.0, 1.0)
		else:
			progress_bg.visible = false
			progress_fill.visible = false

func hide_interaction_ui() -> void:
	if not player:
		return

	var ui = player.get_node_or_null("UI")
	if not ui:
		return

	var prompt = ui.get_node_or_null(my_prompt_name)
	if prompt:
		prompt.visible = false

func light_campfire() -> void:
	if is_lit or not has_wood:
		return

	is_lit = true
	burn_timer = 0.0

	# Turn on light
	if campfire_light:
		campfire_light.visible = true

	# Start fire audio loop
	if fire_audio and fire_audio.stream:
		fire_audio.play()

func extinguish() -> void:
	is_lit = false
	has_wood = false

	# Turn off light
	if campfire_light:
		campfire_light.visible = false

	# Stop audio
	if fire_audio:
		fire_audio.stop()

	# Remove wood model
	if wood_model:
		wood_model.queue_free()
		wood_model = null
