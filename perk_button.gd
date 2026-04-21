extends Panel

## Individual perk button in the selection UI

signal perk_selected(perk: Perk)

var perk: Perk = null
var perk_manager: PerkManager = null
var is_active: bool = false

@onready var perk_name_label: Label = $VBox/NameLabel
@onready var description_label: Label = $VBox/DescriptionLabel
@onready var select_button: Button = $VBox/SelectButton

func setup(p_perk: Perk, p_perk_manager: PerkManager) -> void:
	perk = p_perk
	perk_manager = p_perk_manager

	# Set labels
	perk_name_label.text = perk.perk_name
	description_label.text = perk.description

	# Check if this perk is active
	is_active = perk_manager.has_perk(perk.perk_id)

	# Update button state
	update_button()

	# Connect button signal
	if not select_button.pressed.is_connected(_on_select_pressed):
		select_button.pressed.connect(_on_select_pressed)

func update_button() -> void:
	if is_active:
		# Perk is equipped
		select_button.text = "REMOVE"
		select_button.disabled = false
		# Highlight as active
		self_modulate = Color(0.3, 0.8, 0.3, 1.0)  # Green
	elif perk_manager.can_add_perk():
		# Can equip this perk
		select_button.text = "SELECT"
		select_button.disabled = false
		self_modulate = Color(1, 1, 1, 1)  # Normal
	else:
		# At max capacity, can't add more
		select_button.text = "FULL"
		select_button.disabled = true
		self_modulate = Color(0.5, 0.5, 0.5, 1)  # Grayed out

func _on_select_pressed() -> void:
	if is_active:
		# Remove perk
		if perk_manager.remove_perk(perk.perk_id):
			is_active = false
			perk_selected.emit(perk)
	else:
		# Add perk
		if perk_manager.add_perk(perk):
			is_active = true
			perk_selected.emit(perk)
