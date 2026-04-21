class_name Player
extends CharacterBody3D

## Simple first-person controller.
## No input map required — uses raw key codes.
##
## Controls:
##   WASD / Arrow keys  — move
##   Shift              — sprint
##   Space              — jump
##   Mouse              — look
##   Escape             — toggle mouse capture

const WALK_SPEED: float   = 5.0
const SPRINT_SPEED: float = 9.5
const JUMP_FORCE: float   = 5.0
const GRAVITY: float      = 20.0
const MOUSE_SENS: float   = 0.0022
const MAX_LOOK_ANGLE: float = deg_to_rad(80.0)

@onready var _head: Node3D   = $Head
@onready var _camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_head.rotate_x(-event.relative.y * MOUSE_SENS)
		_head.rotation.x = clampf(_head.rotation.x, -MAX_LOOK_ANGLE, MAX_LOOK_ANGLE)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			var mode := Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
						else Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(mode)


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = JUMP_FORCE

	# Movement
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	var speed := SPRINT_SPEED if sprint else WALK_SPEED

	var move_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_dir.x += 1.0
	move_dir = move_dir.normalized()

	var wish_dir := (transform.basis * Vector3(move_dir.x, 0.0, move_dir.y)).normalized()

	if wish_dir.length_squared() > 0.0:
		velocity.x = wish_dir.x * speed
		velocity.z = wish_dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
