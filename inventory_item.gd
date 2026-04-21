class_name InventoryItem
extends Resource

## An item that can be placed in the inventory grid
## Represents items like keys, medkits, batteries, etc.

@export var item_name: String = "Item"
@export var item_id: String = "item_00"
@export var icon: Texture2D
@export var grid_width: int = 1
@export var grid_height: int = 1
@export var description: String = "An item."
@export var stackable: bool = false
@export var max_stack: int = 1
@export var can_be_equipped: bool = true  # Most items can be equipped

# Equipment slot type (for armor/clothing/backpacks)
enum EquipmentSlot { NONE, HEAD, CHEST, FEET }
@export var equipment_slot: EquipmentSlot = EquipmentSlot.NONE
@export var inventory_bonus_columns: int = 0  # How many extra columns this item adds when worn

# Weight system
@export var weight: float = 1.0  # Weight in pounds (lbs)

# Grid position (top-left corner when placed)
# -1, -1 means not placed in grid
var grid_x: int = -1
var grid_y: int = -1

# Equipment state
var is_equipped: bool = false

# Stack quantity (for stackable items like ammo)
var current_stack: int = 1

# Flare state (for flares)
var flare_is_lit: bool = false
var flare_burn_time: float = 0.0

# Weapon state (for guns)
var weapon_current_ammo: int = -1  # -1 means use default from weapon script

func is_placed() -> bool:
	return grid_x >= 0 and grid_y >= 0

func get_size() -> Vector2i:
	return Vector2i(grid_width, grid_height)
