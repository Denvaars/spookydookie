extends Control

signal close_requested

@onready var output_log = $Panel/VBoxContainer/ScrollContainer/OutputLog
@onready var input_field = $Panel/VBoxContainer/InputField
@onready var close_button = $Panel/VBoxContainer/CloseButton
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer

var console_manager: Node = null
var command_history: Array[String] = []
var history_index: int = -1

func _ready() -> void:
	# Get console manager
	console_manager = get_node("/root/ConsoleManager")

	# Connect signals
	input_field.text_submitted.connect(_on_command_submitted)
	close_button.pressed.connect(_on_close_pressed)

	if console_manager:
		console_manager.command_executed.connect(_on_command_executed)
		console_manager.command_error.connect(_on_command_error)

	# Focus input field
	input_field.grab_focus()

	# Add welcome message
	add_output("Console ready. Type /give or /summon for help.", Color.GRAY)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle command history with up/down arrows
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_history_previous()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_history_next()
			get_viewport().set_input_as_handled()

func _on_command_submitted(command: String) -> void:
	if command.is_empty():
		return

	# Add to output log
	add_output("> " + command, Color.WHITE)

	# Add to history
	command_history.append(command)
	history_index = command_history.size()

	# Execute command
	if console_manager:
		console_manager.execute_command(command)

	# Clear input
	input_field.clear()

func _on_command_executed(result: String) -> void:
	add_output(result, Color.GREEN)

func _on_command_error(error: String) -> void:
	add_output("ERROR: " + error, Color.RED)

func add_output(text: String, color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_log.add_child(label)

	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _history_previous() -> void:
	if command_history.is_empty():
		return

	history_index = maxi(0, history_index - 1)
	if history_index < command_history.size():
		input_field.text = command_history[history_index]
		input_field.caret_column = input_field.text.length()

func _history_next() -> void:
	if command_history.is_empty():
		return

	history_index = mini(command_history.size(), history_index + 1)

	if history_index < command_history.size():
		input_field.text = command_history[history_index]
		input_field.caret_column = input_field.text.length()
	else:
		input_field.clear()

func _on_close_pressed() -> void:
	close_requested.emit()

func show_console() -> void:
	visible = true
	input_field.grab_focus()

func hide_console() -> void:
	visible = false
	input_field.clear()
