class_name PlayerAudio
extends Node

## Handles all player audio (heartbeat, item sounds, footsteps)
## Isolated component with minimal dependencies

# Audio players
var flashlight_on_sound: AudioStreamPlayer
var flashlight_off_sound: AudioStreamPlayer
var heartbeat_sound: AudioStreamPlayer
var bandage_use_sound: AudioStreamPlayer

# State
var low_health_threshold: float = 50.0


func _ready() -> void:
	# Load audio files
	flashlight_on_sound = AudioStreamPlayer.new()
	flashlight_on_sound.stream = load("res://audio/flashlight_on.wav")
	flashlight_on_sound.volume_db = -5
	add_child(flashlight_on_sound)

	flashlight_off_sound = AudioStreamPlayer.new()
	flashlight_off_sound.stream = load("res://audio/flashlight_off.wav")
	flashlight_off_sound.volume_db = -5
	add_child(flashlight_off_sound)

	bandage_use_sound = AudioStreamPlayer.new()
	bandage_use_sound.stream = load("res://audio/bandage_use.wav")
	add_child(bandage_use_sound)

	heartbeat_sound = AudioStreamPlayer.new()
	heartbeat_sound.stream = load("res://audio/heartbeat.wav")
	heartbeat_sound.bus = "Master"
	add_child(heartbeat_sound)


## Play flashlight toggle sound
func play_flashlight_toggle(turning_on: bool) -> void:
	if turning_on:
		flashlight_on_sound.play()
	else:
		flashlight_off_sound.play()


## Play bandage use sound
func play_bandage_use() -> void:
	bandage_use_sound.play()


## Update heartbeat audio based on health level
func update_heartbeat(current_health: float, max_health: float) -> void:
	var health_percent := current_health / max_health * 100.0

	if health_percent < low_health_threshold:
		if not heartbeat_sound.playing:
			heartbeat_sound.play()

		# Volume increases as health decreases
		var volume := remap(health_percent, 0.0, low_health_threshold, -5.0, -20.0)
		heartbeat_sound.volume_db = volume

		# Pitch increases as health decreases
		var pitch := remap(health_percent, 0.0, low_health_threshold, 1.5, 1.0)
		heartbeat_sound.pitch_scale = pitch
	else:
		# Above threshold, stop heartbeat
		if heartbeat_sound.playing:
			heartbeat_sound.stop()


## Stop all audio (e.g., on player death)
func stop_all_audio() -> void:
	flashlight_on_sound.stop()
	flashlight_off_sound.stop()
	bandage_use_sound.stop()
	heartbeat_sound.stop()
