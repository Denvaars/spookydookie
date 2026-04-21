class_name AmbianceSystem
extends Node

## Manages ambient audio with seamless cross-fading between different atmospheric tracks.
## Responds to danger zones, weather, time of day, and other environmental conditions.

# Ambiance track configuration
class AmbianceTrack:
	var path: String
	var loops: bool
	var base_volume_db: float = 0.0
	var danger_zone: int = -1  # Which zone this plays in (-1 = default/any)

	func _init(p_path: String, p_loops: bool, p_volume: float = 0.0, p_zone: int = -1):
		path = p_path
		loops = p_loops
		base_volume_db = p_volume
		danger_zone = p_zone

# Audio players for cross-fading (we use 2 players and swap between them)
var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer = null  # Currently playing
var _fading_player: AudioStreamPlayer = null  # Currently fading in/out

# Ambiance configuration
var _ambiance_tracks: Dictionary = {}  # zone_id -> AmbianceTrack
var _current_zone: int = 1
var _target_track: AmbianceTrack = null
var _is_transitioning: bool = false

# Fade settings
@export var fade_duration: float = 3.0  # Seconds for cross-fade
@export var update_interval: float = 0.5  # How often to check for zone changes

var _fade_timer: float = 0.0
var _update_timer: float = 0.0
var _player_ref: CharacterBody3D = null
var _danger_manager: DangerZoneManager = null


func _ready() -> void:
	# Create audio players
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "AmbiancePlayerA"
	_player_a.bus = "Master"
	_player_a.volume_db = -80.0  # Start silent
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.name = "AmbiancePlayerB"
	_player_b.bus = "Master"
	_player_b.volume_db = -80.0  # Start silent
	add_child(_player_b)

	# Configure ambiance tracks
	_setup_ambiance_tracks()

	print("AmbianceSystem: initialized with cross-fade duration %.1fs" % fade_duration)


func initialize(player: CharacterBody3D, danger_manager: DangerZoneManager) -> void:
	_player_ref = player
	_danger_manager = danger_manager

	# Start with zone 1 ambiance
	_current_zone = 1
	_start_ambiance_immediate(_ambiance_tracks[1])

	print("AmbianceSystem: started with zone 1 ambiance")


func _setup_ambiance_tracks() -> void:
	# Configure each zone's ambiance
	# Zone 1: Safe - birds chirping
	_ambiance_tracks[1] = AmbianceTrack.new(
		"res://audio/ambiance_birds.ogg",
		true,   # loops
		-5.0,   # volume
		1       # zone
	)

	# Zone 2: Caution - wind
	_ambiance_tracks[2] = AmbianceTrack.new(
		"res://audio/ambiance_wind.ogg",
		true,   # loops
		-3.0,   # volume
		2       # zone
	)

	# Zone 3: Danger - anxiety (doesn't loop)
	_ambiance_tracks[3] = AmbianceTrack.new(
		"res://audio/ambiance_anxiety.ogg",
		false,  # doesn't loop
		0.0,    # volume
		3       # zone
	)

	print("AmbianceSystem: configured %d ambiance tracks" % _ambiance_tracks.size())


func _process(delta: float) -> void:
	# Check for zone changes periodically
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_check_zone_change()

	# Handle cross-fade transitions
	if _is_transitioning:
		_process_fade(delta)

	# Handle non-looping tracks that finish
	if _active_player and _active_player.stream:
		if not _active_player.stream.loop and not _active_player.playing:
			# Non-looping track finished, stay silent or transition back
			print("AmbianceSystem: non-looping track finished")
			_active_player.volume_db = -80.0


func _check_zone_change() -> void:
	if not _player_ref or not _danger_manager:
		return

	# Get player's current danger zone
	var player_pos = _player_ref.global_position
	var danger_level = _danger_manager.get_danger_level(player_pos)
	var new_zone = _danger_manager.get_danger_zone(danger_level)

	# Zone changed?
	if new_zone != _current_zone and not _is_transitioning:
		print("AmbianceSystem: zone changed %d -> %d (danger: %.2f)" % [_current_zone, new_zone, danger_level])
		_current_zone = new_zone

		# Start transition to new ambiance
		if _ambiance_tracks.has(new_zone):
			_start_transition(_ambiance_tracks[new_zone])


func _start_transition(target_track: AmbianceTrack) -> void:
	if _is_transitioning:
		return

	_target_track = target_track
	_is_transitioning = true
	_fade_timer = 0.0

	# Determine which player to use for the new track
	if _active_player == _player_a:
		_fading_player = _player_b
	else:
		_fading_player = _player_a

	# Load and configure the new track
	var stream = load(target_track.path)
	if stream:
		_fading_player.stream = stream
		_fading_player.volume_db = -80.0  # Start silent

		# Configure looping
		if stream is AudioStreamOggVorbis:
			stream.loop = target_track.loops
		elif stream is AudioStreamMP3:
			stream.loop = target_track.loops
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if target_track.loops else AudioStreamWAV.LOOP_DISABLED

		_fading_player.play()
		print("AmbianceSystem: starting cross-fade to '%s' (loops: %s)" % [target_track.path.get_file(), target_track.loops])
	else:
		push_warning("AmbianceSystem: failed to load '%s'" % target_track.path)
		_is_transitioning = false


func _process_fade(delta: float) -> void:
	_fade_timer += delta
	var fade_progress = clampf(_fade_timer / fade_duration, 0.0, 1.0)

	# Smooth S-curve for more natural fading
	var smooth_progress = smoothstep(0.0, 1.0, fade_progress)

	# Fade out old player
	if _active_player:
		var old_volume = lerp(0.0, -80.0, smooth_progress)
		_active_player.volume_db = old_volume

	# Fade in new player
	if _fading_player and _target_track:
		var new_volume = lerp(-80.0, _target_track.base_volume_db, smooth_progress)
		_fading_player.volume_db = new_volume

	# Transition complete?
	if fade_progress >= 1.0:
		# Stop and cleanup old player
		if _active_player:
			_active_player.stop()
			_active_player.volume_db = -80.0

		# New player is now active
		_active_player = _fading_player
		_fading_player = null
		_target_track = null
		_is_transitioning = false

		print("AmbianceSystem: cross-fade complete, now playing zone %d ambiance" % _current_zone)


func _start_ambiance_immediate(track: AmbianceTrack) -> void:
	# Start playing immediately without fade (used for initial ambiance)
	_active_player = _player_a

	var stream = load(track.path)
	if stream:
		_active_player.stream = stream

		# Configure looping
		if stream is AudioStreamOggVorbis:
			stream.loop = track.loops
		elif stream is AudioStreamMP3:
			stream.loop = track.loops
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if track.loops else AudioStreamWAV.LOOP_DISABLED

		_active_player.volume_db = track.base_volume_db
		_active_player.play()

		print("AmbianceSystem: started immediate playback of '%s'" % track.path.get_file())
	else:
		push_warning("AmbianceSystem: failed to load '%s'" % track.path)


# Manual control functions for future use (weather, time of day, etc.)

func force_ambiance(zone: int, fade: bool = true) -> void:
	"""Force a specific ambiance to play, optionally with fade."""
	if not _ambiance_tracks.has(zone):
		push_warning("AmbianceSystem: no ambiance configured for zone %d" % zone)
		return

	if fade:
		_start_transition(_ambiance_tracks[zone])
	else:
		_start_ambiance_immediate(_ambiance_tracks[zone])


func stop_ambiance(fade_out: bool = true) -> void:
	"""Stop all ambiance, optionally with fade out."""
	if fade_out and _active_player:
		# TODO: Implement fade-to-silence
		_active_player.stop()
	elif _active_player:
		_active_player.stop()
		_active_player.volume_db = -80.0


func set_volume(volume_db: float) -> void:
	"""Adjust master volume for ambiance system."""
	if _active_player:
		_active_player.volume_db = volume_db
