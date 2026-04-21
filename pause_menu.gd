extends Control

signal resume_pressed
signal settings_pressed
signal console_pressed
signal quit_pressed

func _ready() -> void:
	# Connect button signals
	$Panel/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$Panel/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$Panel/VBoxContainer/ConsoleButton.pressed.connect(_on_console_pressed)
	$Panel/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_resume_pressed() -> void:
	resume_pressed.emit()

func _on_settings_pressed() -> void:
	settings_pressed.emit()

func _on_console_pressed() -> void:
	console_pressed.emit()

func _on_quit_pressed() -> void:
	quit_pressed.emit()
