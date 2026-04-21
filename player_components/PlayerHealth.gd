class_name PlayerHealth
extends Node

## Handles player health, bleed, sanity, adrenaline, and death

# Signals for other components to listen to
signal health_changed(current: float, max: float)
signal sanity_changed(current: float, max: float)
signal bleed_changed(current_bleed: float, bleed_dps: float)
signal died()
signal adrenaline_changed(active: bool)

# Health settings
@export var max_health: float = 100.0
@export var health_regen_rate: float = 0.0  # HP per second (0 = no regen)
@export var health_regen_delay: float = 5.0  # Delay before regen starts

# Sanity settings
@export var max_sanity: float = 100.0
@export var sanity_zone_rate: float = 0.2  # Sanity change per second

# State
var current_health: float = max_health
var time_since_damaged: float = 0.0
var is_dead: bool = false
var low_health_threshold: float = 50.0

# Bleed
var current_bleed_damage: float = 0.0  # Total bleed damage remaining
var bleed_dps: float = 0.0  # Damage per second from bleed

# Sanity
var current_sanity: float = max_sanity

# Adrenaline
var adrenaline_active: bool = false
var adrenaline_timer: float = 0.0
var adrenaline_duration: float = 5.0

# External dependencies
var perk_manager = null  # Set by player


func _ready() -> void:
	# Initialize at full health
	health_changed.emit(current_health, max_health)
	sanity_changed.emit(current_sanity, max_sanity)


func _process(delta: float) -> void:
	if is_dead:
		return

	# Health regeneration
	if health_regen_rate > 0.0:
		time_since_damaged += delta
		if time_since_damaged >= health_regen_delay:
			current_health += health_regen_rate * delta
			current_health = min(current_health, max_health)
			health_changed.emit(current_health, max_health)

	# Bleed damage over time
	if current_bleed_damage > 0.0 and bleed_dps > 0.0:
		var damage_this_frame = bleed_dps * delta
		current_health -= damage_this_frame
		current_bleed_damage -= damage_this_frame

		# Clamp values
		current_health = max(current_health, 0.0)
		current_bleed_damage = max(current_bleed_damage, 0.0)

		# If bleed damage depleted, reset DPS
		if current_bleed_damage <= 0.0:
			bleed_dps = 0.0

		health_changed.emit(current_health, max_health)
		bleed_changed.emit(current_bleed_damage, bleed_dps)

		# Check for death
		if current_health <= 0.0:
			die()

	# Adrenaline timer
	if adrenaline_active:
		adrenaline_timer -= delta
		if adrenaline_timer <= 0.0:
			adrenaline_active = false
			adrenaline_changed.emit(false)


## Apply damage to the player
func take_damage(amount: float, bleed_damage: float = 0.0, bleed_damage_per_second: float = 0.0) -> void:
	if is_dead:
		return

	# Apply direct damage
	current_health -= amount
	current_health = max(current_health, 0.0)
	time_since_damaged = 0.0

	# Apply bleed damage
	if bleed_damage > 0.0 and bleed_damage_per_second > 0.0:
		# Apply perk multiplier (Thick Skin reduces bleed)
		var bleed_mult = perk_manager.get_total_multiplier("bleed_damage") if perk_manager else 1.0
		var modified_bleed_dps = bleed_damage_per_second * bleed_mult

		current_bleed_damage += bleed_damage
		bleed_dps = modified_bleed_dps
		print("Applied %.1f bleed damage at %.1f DPS (%.0f%% from perks)" % [bleed_damage, bleed_dps, bleed_mult * 100.0])

	# Emit signals
	health_changed.emit(current_health, max_health)
	bleed_changed.emit(current_bleed_damage, bleed_dps)

	# Check for death
	if current_health <= 0.0:
		die()


## Heal the player
func heal(amount: float) -> void:
	if is_dead:
		return

	current_health += amount
	current_health = min(current_health, max_health)

	health_changed.emit(current_health, max_health)


## Reduce bleed damage
func reduce_bleed(amount: float) -> void:
	current_bleed_damage -= amount
	current_bleed_damage = max(current_bleed_damage, 0.0)

	# If bleed is gone, reset DPS
	if current_bleed_damage <= 0.0:
		bleed_dps = 0.0

	bleed_changed.emit(current_bleed_damage, bleed_dps)


## Modify sanity based on danger zone
func update_sanity_from_zone(danger_zone: int, delta: float) -> void:
	match danger_zone:
		1:
			# Zone 1 (safe) - restore sanity smoothly
			current_sanity += sanity_zone_rate * delta
			current_sanity = min(current_sanity, max_sanity)
		2:
			# Zone 2 (medium danger) - no change
			pass
		3:
			# Zone 3 (high danger) - lose sanity smoothly
			current_sanity -= sanity_zone_rate * delta
			current_sanity = max(current_sanity, 0.0)
		4:
			# Zone 4 (extreme danger - night time) - lose sanity faster
			current_sanity -= sanity_zone_rate * 2.0 * delta  # Double drain rate
			current_sanity = max(current_sanity, 0.0)

	sanity_changed.emit(current_sanity, max_sanity)


## Modify sanity directly (e.g., from pain killers)
func change_sanity(amount: float) -> void:
	current_sanity += amount
	current_sanity = clamp(current_sanity, 0.0, max_sanity)
	sanity_changed.emit(current_sanity, max_sanity)


## Activate adrenaline effect
func activate_adrenaline(duration: float) -> void:
	adrenaline_active = true
	adrenaline_timer = duration
	adrenaline_changed.emit(true)


## Get current health as percentage (0.0 to 1.0)
func get_health_percent() -> float:
	return current_health / max_health


## Check if health is below threshold
func is_low_health() -> bool:
	return current_health <= low_health_threshold


## Handle player death
func die() -> void:
	is_dead = true
	died.emit()
	print("Player died!")
	# TODO: Implement death screen, respawn, etc.
