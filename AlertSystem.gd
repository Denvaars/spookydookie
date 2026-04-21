class_name AlertSystem
extends Node

## Global alert system for notifying enemies of player actions
## Enemies subscribe to alerts and react based on proximity

# Alert noise levels (in meters)
const NOISE_WALKING: float = 5.0
const NOISE_RUNNING: float = 15.0
const NOISE_CROUCHING: float = 2.0
const NOISE_JUMPING: float = 8.0
const NOISE_LANDING: float = 10.0
const NOISE_FLASHLIGHT: float = 3.0
const NOISE_ITEM_USE: float = 5.0
const NOISE_SHOTGUN: float = 60.0
const NOISE_RIFLE: float = 70.0
const NOISE_PISTOL: float = 50.0
const NOISE_FLAREGUN: float = 40.0
const NOISE_MELEE: float = 8.0

func _ready() -> void:
	print("AlertSystem: initialized")

func emit_alert(position: Vector3, radius: float, alert_type: String) -> void:
	print("AlertSystem: %s alert at %v (radius: %.1fm)" % [alert_type, position, radius])

	# Find all enemies in the scene
	var enemies = get_tree().get_nodes_in_group("enemy")

	var alerted_count = 0
	for enemy in enemies:
		if enemy.has_method("on_alert"):
			# Check if enemy is in range
			var distance = enemy.global_position.distance_to(position)
			if distance <= radius:
				enemy.on_alert(position, radius, alert_type)
				alerted_count += 1

	if alerted_count > 0:
		print("AlertSystem: alerted %d enemies" % alerted_count)

	# Also notify animals (deer, etc.) of gunshots
	if alert_type.begins_with("gunshot_"):
		var animals = get_tree().get_nodes_in_group("animal")
		var startled_count = 0
		for animal in animals:
			if animal.has_method("on_gunshot_alert"):
				var distance = animal.global_position.distance_to(position)
				if distance <= radius:
					animal.on_gunshot_alert(position)
					startled_count += 1
		if startled_count > 0:
			print("AlertSystem: startled %d animals" % startled_count)

# Helper functions for common alerts
func alert_footstep(position: Vector3, is_running: bool, is_crouching: bool) -> void:
	var radius = NOISE_WALKING
	var type = "footstep"

	if is_crouching:
		radius = NOISE_CROUCHING
		type = "crouch_step"
	elif is_running:
		radius = NOISE_RUNNING
		type = "running"

	emit_alert(position, radius, type)

func alert_jump(position: Vector3) -> void:
	emit_alert(position, NOISE_JUMPING, "jump")

func alert_landing(position: Vector3) -> void:
	emit_alert(position, NOISE_LANDING, "landing")

func alert_flashlight(position: Vector3) -> void:
	emit_alert(position, NOISE_FLASHLIGHT, "flashlight")

func alert_weapon_fire(position: Vector3, weapon_type: String) -> void:
	var radius = NOISE_PISTOL
	match weapon_type:
		"shotgun":
			radius = NOISE_SHOTGUN
		"rifle":
			radius = NOISE_RIFLE
		"pistol":
			radius = NOISE_PISTOL
		"flare_gun":
			radius = NOISE_FLAREGUN
		"axe", "knife":
			radius = NOISE_MELEE

	emit_alert(position, radius, "gunshot_" + weapon_type)

func alert_item_use(position: Vector3) -> void:
	emit_alert(position, NOISE_ITEM_USE, "item_use")
