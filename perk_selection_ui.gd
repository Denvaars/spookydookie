extends Control

## UI for selecting perks from the perk statue

var perk_manager: PerkManager = null
var perk_buttons: Array = []

@onready var panel: Panel = $Panel
@onready var perk_grid: GridContainer = $Panel/VBox/PerkGrid
@onready var active_perks_label: Label = $Panel/VBox/ActivePerksLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

const PerkButtonScene = preload("res://perk_button.tscn")

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_pressed)

func open_perk_menu(p_perk_manager: PerkManager) -> void:
	perk_manager = p_perk_manager
	refresh_display()
	visible = true

	# Pause game and capture mouse
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_perk_menu() -> void:
	visible = false

	# Resume game
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh_display() -> void:
	if not perk_manager:
		return

	# Clear existing buttons
	for child in perk_grid.get_children():
		child.queue_free()
	perk_buttons.clear()

	# Update active perks display
	var slots_text = "Perks: %d / %d" % [perk_manager.active_perks.size(), perk_manager.MAX_PERKS]
	active_perks_label.text = slots_text

	# Create button for each available perk
	for perk in perk_manager.available_perks:
		var button = PerkButtonScene.instantiate()
		perk_grid.add_child(button)
		button.setup(perk, perk_manager)
		button.perk_selected.connect(_on_perk_selected)
		perk_buttons.append(button)

func _on_perk_selected(perk: Perk) -> void:
	# Refresh all buttons to update their states
	refresh_display()

func _on_close_pressed() -> void:
	close_perk_menu()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on ESC
	if event.is_action_pressed("ui_cancel"):
		close_perk_menu()
		get_viewport().set_input_as_handled()
