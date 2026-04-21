# Add Item Animations Skill

This skill documents the complete process for adding first-person animations for new weapons/tools in the Godot 4.6 horror FPS game.

## System Architecture Overview

The game uses a **dual-viewport rendering system** for first-person items:
- **Main Viewport** (Layer 1): World, terrain, enemies
- **Weapon Viewport** (Layer 2): First-person item models and arms

### Key Components

1. **player.tscn** - Contains the FPSArms node hierarchy and all animation data
   - Path: `Camera3D/FPSArms/animations_fps/AnimationPlayer`
   - Contains: Arms mesh, weapon meshes, and all animations

2. **fps_weapon_controller.gd** - Animation state machine controller
   - Manages weapon switching, mesh visibility, and animation playback
   - Uses dynamic animation names: `{weapon_name}_{animation_type}`

3. **Item Scripts** (e.g., shotgun.gd, flashlight.gd) - Individual item logic
   - Calls `show_weapon()` to display correct meshes
   - Implements item-specific functionality (shooting, toggling, etc.)
   - Implements `on_unequip()` for cleanup

4. **player.gd** - Equipment system integration
   - Loads item scripts and instantiates them
   - Handles smooth FOV transitions for aiming

## Animation Naming Convention

All animations follow this pattern: `{item_name}_{animation_type}`

### Required Animations (Minimum Set)
- `{item}_hip_idle` - Standing still, weapon at hip
- `{item}_hip_walk` - Walking with weapon at hip
- `{item}_aim_idle` - Aiming down sights, standing still
- `{item}_aim_walk` - Aiming down sights, walking
- `{item}_sprinting` - Sprinting animation (looping)

### Optional Animations (Full Set)
- `{item}_aim` - Transition from hip to aim (shotgun has this, flashlight doesn't)
- `{item}_sprint` - Transition into sprint (shotgun has this, flashlight doesn't)
- `{item}_equip` - Equip/draw animation
- `{item}_hip_shoot` - Shooting from hip
- `{item}_aim_shoot` - Shooting while aiming
- `{item}_hip_cock` - Cocking/pump animation (shotgun-specific)
- `{item}_aim_cock` - Cocking while aiming (shotgun-specific)
- `{item}_reload_start` - Start reload sequence
- `{item}_reload_shell` - Insert ammo (looping)
- `{item}_reload_end` - Finish reload sequence

### Animation State Flow

```
EQUIPPING → IDLE_HIP ⇄ WALK_HIP
                ↓           ↓
          AIMING_IN → IDLE_AIMED ⇄ WALK_AIMED
                          ↓
                    AIMING_OUT
                          ↓
            SPRINTING_IN → SPRINTING → SPRINTING_OUT
```

## Step-by-Step Guide: Adding a New Item

### Step 1: Create Animations in Blender/Godot

1. Export your item model + arms from Blender as `.glb`
2. Place in `res://assets/` directory
3. Create animations in Blender with proper naming
4. Import into Godot

### Step 2: Add Mesh Node to player.tscn

**Important Location**: `Camera3D/FPSArms/animations_fps/arms_armature/Skeleton3D/`

**Example (for "knife" item)**:
```gdscript
[node name="knife" type="MeshInstance3D" parent="Camera3D/FPSArms/animations_fps/arms_armature/Skeleton3D"]
visible = false
layers = 2
mesh = SubResource("ArrayMesh_xyz123")
skin = SubResource("Skin_e0psv")
skeleton = NodePath("..")
```

**Critical Settings**:
- `visible = false` - Must start hidden
- `layers = 2` - Required for weapon viewport rendering
- Name must be **lowercase** (e.g., "knife", "flashlight", not "Knife")

### Step 3: Add Animations to AnimationPlayer

1. Open `player.tscn` in Godot
2. Navigate to: `Camera3D/FPSArms/animations_fps/AnimationPlayer`
3. Create animations following naming convention
4. Each animation should modify:
   - Skeleton3D bone transforms (for arm movement)
   - Item mesh transform (for item movement)
   - **Do NOT animate visibility** - handled by code

### Step 4: Update fps_weapon_controller.gd

**Add mesh variable** (around line 8):
```gdscript
var knife_mesh: MeshInstance3D = null
```

**Find mesh in _ready()** (around line 69):
```gdscript
knife_mesh = find_child("knife", true, false)
```

**Hide mesh in hide_all_weapons()** (around line 417):
```gdscript
if knife_mesh:
    knife_mesh.visible = false
```

**Show mesh in show_weapon()** (around line 433):
```gdscript
"knife":
    if knife_mesh:
        knife_mesh.visible = true
    if arms_mesh:
        arms_mesh.visible = true
    play_equip()
```

**Special Animation Handling** (if needed):

If your item doesn't have transition animations (like flashlight), add special cases in `transition_to()` (around line 279):

```gdscript
AnimState.AIMING_IN:
    if current_weapon == "knife":
        transition_to(AnimState.IDLE_AIMED)  # Skip transition
    else:
        play_animation(current_weapon + "_aim", false, 0.1)
```

### Step 5: Create Item Script (e.g., knife.gd)

**Template**:
```gdscript
extends Node3D

## [Item Name] system
## [Description of what it does]

# Settings
@export var aim_fov: float = 70.0  # FOV when aiming (optional)

# State
var is_aiming: bool = false

# References
var player: CharacterBody3D
var camera: Camera3D

func _ready() -> void:
    player = get_parent()
    camera = player.get_node_or_null("Camera3D")

    # Show the FPS weapon model
    var fps_controller = get_tree().root.find_child("FPSArms", true, false)
    if fps_controller:
        fps_controller.show_weapon("knife")
    else:
        print("Warning: FPSArms controller not found!")

func _input(event: InputEvent) -> void:
    if not player or player.is_inventory_open:
        return

    # Primary action (shoot/use)
    if event.is_action_pressed("shoot"):
        use_item()

    # Aim (optional)
    if event.is_action_pressed("aim"):
        is_aiming = true
        var fps_controller = get_tree().root.find_child("FPSArms", true, false)
        if fps_controller:
            fps_controller.set_aiming(true)
    elif event.is_action_released("aim"):
        is_aiming = false
        var fps_controller = get_tree().root.find_child("FPSArms", true, false)
        if fps_controller:
            fps_controller.set_aiming(false)

func use_item() -> void:
    # Item-specific logic here
    print("Knife used!")

# Called when item is unequipped
func on_unequip() -> void:
    # Cleanup logic here

    # Hide the FPS weapon model
    if camera:
        var fps_controller = get_tree().root.find_child("FPSArms", true, false)
        if fps_controller:
            fps_controller.hide_all_weapons()
```

**Key Points**:
- Always call `show_weapon()` in `_ready()`
- Always implement `on_unequip()` for cleanup
- Use `fps_controller.set_aiming()` for aim state
- Check `player.is_inventory_open` before accepting input
- **FOV transition is automatic** - just define `aim_fov` export variable

### Step 6: Integrate into player.gd Equipment System

**Add to weapon script loading** (around line 1040):
```gdscript
match weapon_type:
    "shotgun":
        weapon_script = load("res://shotgun.gd")
    "knife":
        weapon_script = load("res://knife.gd")
    # ... other items
```

**Add to equip_item()** (around line 1104):
```gdscript
match item.item_id:
    "shotgun_01":
        equip_weapon("shotgun", item)
    "knife_01":
        equip_weapon("knife", item)
    # ... other items
```

**Add to unequip_item()** (around line 1133):
```gdscript
match item.item_id:
    "shotgun_01", "rifle_01", "knife_01", "flashlight_01":
        # Unequip weapon
        # ... existing logic
```

## Common Patterns & Examples

### Example 1: Simple Tool (Flashlight)
- **Animations**: 7 total (no transitions, no shooting)
- **Functionality**: Toggle on/off, aim for FOV change
- **Special Handling**: Skips AIMING_IN/OUT and SPRINTING_IN/OUT transitions

### Example 2: Firearm (Shotgun)
- **Animations**: 15+ total (full set with transitions)
- **Functionality**: Shooting, reloading, aiming, cocking
- **Special Handling**: Shoot → Cock timing system, reload state machine

### Example 3: Melee Weapon (Knife - hypothetical)
- **Animations**: 8-10 total (attack animations, no reload)
- **Functionality**: Attack, quick attack, heavy attack
- **Special Handling**: Attack cooldown, hit detection

## Important Gotchas

### Mesh Visibility Issues
✅ **Always set in scene**:
- `visible = false`
- `layers = 2`

❌ **Never**:
- Leave visible by default
- Use layer 1 (main viewport)

### Node Naming
✅ **Use lowercase**: "flashlight", "knife", "shotgun"
❌ **Don't use capital**: "Flashlight", "Knife", "Shotgun"

### Animation Transitions
- If your item has simple animations (like flashlight), add special cases in `transition_to()`
- Don't try to play non-existent animations
- Use direct state changes: `transition_to(AnimState.IDLE_AIMED)` instead of playing missing transition

### FOV Handling
✅ **Let player.gd handle it**: Just define `@export var aim_fov: float`
❌ **Don't set manually**: `camera.fov = aim_fov` creates instant transition

### State Machine
- Only ONE animation state can be active at a time
- Transitions must be explicit (call `transition_to()`)
- Some states like SHOOTING and COCKING are timing-based, not animation-based

## Testing Checklist

After implementing a new item:

- [ ] Mesh is hidden by default (not visible in scene)
- [ ] Equipping shows correct meshes (arms + item, others hidden)
- [ ] Unequipping hides all meshes
- [ ] All animations play correctly:
  - [ ] Hip idle/walk
  - [ ] Aim idle/walk (if applicable)
  - [ ] Sprint (if applicable)
  - [ ] Item-specific actions (shoot, attack, etc.)
- [ ] FOV transitions smoothly when aiming
- [ ] No console errors about missing animations
- [ ] Item can be equipped/unequipped multiple times without issues
- [ ] Switching between items works correctly

## File Reference Quick List

**Scene Files**:
- `player.tscn` - Contains all meshes and animations

**Scripts to Modify**:
1. `fps_weapon_controller.gd` - Add mesh handling
2. `{item_name}.gd` - Create new item script
3. `player.gd` - Add to equipment system

**Key Line Numbers** (approximate, may drift):
- fps_weapon_controller.gd:8 - Mesh variables
- fps_weapon_controller.gd:69 - Find meshes
- fps_weapon_controller.gd:417 - Hide meshes
- fps_weapon_controller.gd:433 - Show weapon cases
- fps_weapon_controller.gd:279 - Animation transitions
- player.gd:1040 - Script loading
- player.gd:1104 - Equip item IDs
- player.gd:1133 - Unequip item IDs

## Animation Export Settings (Blender)

When exporting from Blender:
1. Format: `.glb` (GLB 2.0)
2. Include: Selected Objects, Animations
3. Transform: Apply Transform
4. Animation: Export all actions, NLA Strips
5. Skinning: Include armature/bones
6. Compression: Enabled for smaller file size

## Future Improvements

Ideas for extending the system:
- Add attachment system (scopes, flashlights on weapons)
- Add procedural recoil for each weapon type
- Add customizable crosshairs per weapon
- Add weapon durability/condition
- Add weapon inspection animations (Y key)
