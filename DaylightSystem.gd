extends Node3D

## Controls the day/night cycle animation
## Press N to pause/unpause for testing

@onready var animation_player: AnimationPlayer = $DayAndNightCycle

func _ready() -> void:
	# Add to group so other systems can find us
	add_to_group("daylight_system")

	# Start at time 3.0 (middle of the day)
	if animation_player:
		animation_player.seek(2.0, true)

# Get current time of day (0-8 scale based on animation position)
func get_time_of_day() -> float:
	if not animation_player:
		return 3.0  # Default to day time

	# Animation position maps to time (0-8)
	# Animation length is 4.0 seconds, each second = 2 hours
	var anim_position = animation_player.current_animation_position
	var anim_length = animation_player.current_animation_length

	# Map animation position (0-4) to time (0-8)
	var time = (anim_position / anim_length) * 8.0
	return time

# Check if it's currently night time (5-8 on the time scale)
func is_night_time() -> bool:
	var time = get_time_of_day()
	return time >= 4.5 and time <= 8.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_N:
		if not animation_player:
			print("DaylightSystem: ERROR - animation_player is null!")
			return

		if animation_player.is_playing():
			animation_player.pause()
			print("DaylightSystem: animation PAUSED")
		else:
			animation_player.play()
			print("DaylightSystem: animation RESUMED")
