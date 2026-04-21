extends Node3D

func _ready():
	print("=== TEST SCENE LOADED ===")
	print("Children count: ", get_child_count())
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
		if child.get_script():
			print("    Script: ", child.get_script().resource_path)
