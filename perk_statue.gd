extends StaticBody3D

## Perk statue that allows players to select perks

@onready var interaction_area: Area3D = $InteractionArea
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var player_nearby: bool = false
var player_ref: CharacterBody3D = null

func _ready() -> void:
	# Connect area signals
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	# Add to interaction group
	add_to_group("interactable")

	print("PerkStatue: ready for interaction")

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		player_ref = body as CharacterBody3D
		print("PerkStatue: player nearby - press E to select perks")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		player_ref = null

func interact(player: Node) -> void:
	if not player_nearby:
		return

	print("PerkStatue: opening perk selection menu")

	# Find the perk selection UI
	var ui = player.get_node_or_null("UI")
	if not ui:
		print("PerkStatue: ERROR - no UI node found on player")
		return

	var perk_ui = ui.get_node_or_null("PerkSelectionUI")
	if not perk_ui:
		print("PerkStatue: ERROR - no PerkSelectionUI found")
		return

	# Find perk manager
	var perk_manager = player.get_node_or_null("PerkManager")
	if not perk_manager:
		print("PerkStatue: ERROR - no PerkManager found on player")
		return

	# Open the perk menu
	perk_ui.open_perk_menu(perk_manager)

func get_interaction_prompt() -> String:
	return "Select Perks"
