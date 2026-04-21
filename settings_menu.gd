extends Control

signal back_pressed

@onready var render_distance_slider = $Panel/VBoxContainer/RenderDistance/HSlider
@onready var render_distance_label = $Panel/VBoxContainer/RenderDistance/ValueLabel
@onready var max_fps_slider = $Panel/VBoxContainer/MaxFPS/HSlider
@onready var max_fps_label = $Panel/VBoxContainer/MaxFPS/ValueLabel
@onready var back_button = $Panel/VBoxContainer/BackButton

func _ready() -> void:
	# Set initial values from SettingsManager
	render_distance_slider.value = SettingsManager.render_distance_chunks
	max_fps_slider.value = SettingsManager.max_fps

	# Update labels
	_update_labels()

	# Connect signals
	render_distance_slider.value_changed.connect(_on_render_distance_changed)
	max_fps_slider.value_changed.connect(_on_max_fps_changed)
	back_button.pressed.connect(_on_back_pressed)

func _update_labels() -> void:
	render_distance_label.text = "%d chunks (%dm)" % [render_distance_slider.value, int(render_distance_slider.value * 100)]
	max_fps_label.text = str(int(max_fps_slider.value))

func _on_render_distance_changed(value: float) -> void:
	SettingsManager.set_render_distance(int(value))
	render_distance_label.text = "%d chunks (%dm)" % [int(value), int(value * 100)]

func _on_max_fps_changed(value: float) -> void:
	SettingsManager.set_max_fps(int(value))
	max_fps_label.text = str(int(value))

func _on_back_pressed() -> void:
	back_pressed.emit()
