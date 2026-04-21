class_name ForestGenerator
extends Node3D

## Top-level orchestrator for the procedural forest.
## Run order: Terrain → Paths → POIs → Danger Zones → Trees → Rocks → Bushes → Player spawn.

@export var terrain_width: float  = 120.0   # corridor width  (X axis)
@export var terrain_length: float = 1000.0  # corridor length (Z axis)
@export var generation_seed: int  = 0       # 0 = randomise each run
@export var tree_scale_horizontal: float = 3.0  # horizontal scale (X/Z) for trees
@export var tree_scale_vertical: float = 3.0    # vertical scale (Y) for trees

var terrain: TerrainGenerator
var path_gen: PathGenerator
var poi_generator: POIGenerator
var tree_placer: TreePlacer
var rock_placer: RockPlacer
var bush_placer: BushPlacer
var danger_manager: DangerZoneManager
var spawn_manager: SpawnManager
var alert_system: AlertSystem
var ambiance_system: AmbianceSystem

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Add to group so player can find us
	add_to_group("forest_generator")

	if generation_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = generation_seed

	print("ForestGenerator: seed = %d" % _rng.seed)

	_generate()
	_spawn_player()


func _generate() -> void:
	# Terrain
	terrain = TerrainGenerator.new()
	terrain.name = "Terrain"
	add_child(terrain)
	seed(_rng.randi())
	terrain.setup(terrain_width, terrain_length, _rng.randi())

	# Paths
	path_gen = PathGenerator.new()
	path_gen.name = "Paths"
	add_child(path_gen)
	seed(_rng.randi())
	path_gen.generate(terrain)

	# Rebuild terrain with path texture blending
	terrain.set_path_generator(path_gen)

	# POIs (Points of Interest - platforms/houses)
	poi_generator = POIGenerator.new()
	poi_generator.name = "POIs"
	add_child(poi_generator)
	seed(_rng.randi())
	poi_generator.initialize(terrain, path_gen)
	poi_generator.generate()
	print("ForestGenerator: POI generation complete")

	# Danger Zones (initialize before trees so trees can use danger levels)
	danger_manager = DangerZoneManager.new()
	danger_manager.name = "DangerZones"
	add_child(danger_manager)
	danger_manager.initialize(path_gen)
	print("ForestGenerator: danger zone system initialized")

	# Trees (pass danger manager to scale trees based on danger level)
	tree_placer = TreePlacer.new()
	tree_placer.name = "Trees"
	add_child(tree_placer)
	seed(_rng.randi())
	tree_placer.place(terrain, path_gen, tree_scale_horizontal, tree_scale_vertical, poi_generator, danger_manager)

	# Rocks (after trees, with danger scaling)
	rock_placer = RockPlacer.new()
	rock_placer.name = "Rocks"
	add_child(rock_placer)
	seed(_rng.randi())
	rock_placer.place(terrain, path_gen, poi_generator, danger_manager)
	print("ForestGenerator: rock placement complete")

	# Bushes (after rocks, decorative)
	bush_placer = BushPlacer.new()
	bush_placer.name = "Bushes"
	add_child(bush_placer)
	seed(_rng.randi())
	bush_placer.place(terrain, path_gen, poi_generator)
	print("ForestGenerator: bush placement complete")

	# Spawn Manager (initialized later when player is found)
	spawn_manager = SpawnManager.new()
	spawn_manager.name = "SpawnManager"
	add_child(spawn_manager)

	# Alert System
	alert_system = AlertSystem.new()
	alert_system.name = "AlertSystem"
	add_child(alert_system)
	print("ForestGenerator: alert system initialized")

	# Ambiance System (initialized later when player is found)
	ambiance_system = AmbianceSystem.new()
	ambiance_system.name = "AmbianceSystem"
	add_child(ambiance_system)
	print("ForestGenerator: ambiance system created")



func _spawn_player() -> void:
	# Player is already placed in test_level.tscn, so we skip spawning
	print("ForestGenerator: player spawn skipped (already in scene)")

	# Find the player and initialize spawn manager
	await get_tree().process_frame  # Wait one frame to ensure everything is ready
	var player = get_tree().get_first_node_in_group("player")
	if player:
		print("ForestGenerator: found player at ", player.global_position)
		initialize_spawn_manager(player)
	else:
		print("ForestGenerator: WARNING - could not find player node!")

func initialize_spawn_manager(player: CharacterBody3D) -> void:
	if spawn_manager and danger_manager and terrain and path_gen:
		spawn_manager.initialize(danger_manager, terrain, player, path_gen)
		print("ForestGenerator: spawn manager initialized with player")

	# Initialize ambiance system with player and danger manager
	if ambiance_system and danger_manager and player:
		ambiance_system.initialize(player, danger_manager)
		print("ForestGenerator: ambiance system initialized with player")
