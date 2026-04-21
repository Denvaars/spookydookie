class_name Perk
extends Resource

## Represents a single perk that modifies player stats

@export var perk_name: String = "Perk"
@export var perk_id: String = "perk_00"
@export var description: String = "A perk that does something."
@export var icon: Texture2D = null

# Perk effects (multipliers and bonuses)
@export var weight_penalty_multiplier: float = 1.0  # 0.8 = 20% less weight penalty
@export var max_stamina_bonus: float = 0.0  # 20.0 = +20 stamina
@export var stamina_multiplier: float = 1.0  # 1.2 = 20% more stamina
@export var sprint_speed_multiplier: float = 1.0  # 1.1 = 10% faster
@export var stamina_drain_multiplier: float = 1.0  # 1.1 = 10% faster drain
@export var bleed_damage_multiplier: float = 1.0  # 0.5 = 50% slower bleed
@export var weapon_fire_rate_multiplier: float = 1.0  # 1.35 = 35% faster
@export var reload_speed_multiplier: float = 1.0  # 1.4 = 40% faster
