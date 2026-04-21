extends Node3D

## Helper script to select which meat model to show
## The meat pack GLB contains two meat models: "meat_1" and "meat_2"

@export_enum("meat_1", "meat_2") var meat_type: String = "meat_1"

func _ready() -> void:
	# Wait a frame for the GLB to fully load
	await get_tree().process_frame

	# Find all child nodes
	for child in get_children():
		if child.name == "meat_1":
			child.visible = (meat_type == "meat_1")
		elif child.name == "meat_2":
			child.visible = (meat_type == "meat_2")
