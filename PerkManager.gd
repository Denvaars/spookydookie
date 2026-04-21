class_name PerkManager
extends Node

## Manages player perks and their effects

const MAX_PERKS: int = 3

var active_perks: Array[Perk] = []
var available_perks: Array[Perk] = []

signal perks_changed()

func _ready() -> void:
	# Load all available perks
	available_perks = [
		load("res://perks/pack_mule.tres"),
		load("res://perks/marathon.tres"),
		load("res://perks/dead_sprint.tres"),
		load("res://perks/thick_skin.tres"),
		load("res://perks/sharp_shooter.tres"),
		load("res://perks/fast_hands.tres")
	]
	print("PerkManager: loaded %d available perks" % available_perks.size())

func has_perk(perk_id: String) -> bool:
	for perk in active_perks:
		if perk.perk_id == perk_id:
			return true
	return false

func add_perk(perk: Perk) -> bool:
	# Check if already have this perk
	if has_perk(perk.perk_id):
		print("PerkManager: already have perk '%s'" % perk.perk_name)
		return false

	# Check if at max capacity
	if active_perks.size() >= MAX_PERKS:
		print("PerkManager: cannot add perk, already at max (%d)" % MAX_PERKS)
		return false

	# Add perk
	active_perks.append(perk)
	print("PerkManager: added perk '%s' (%d/%d)" % [perk.perk_name, active_perks.size(), MAX_PERKS])
	perks_changed.emit()
	return true

func remove_perk(perk_id: String) -> bool:
	for i in range(active_perks.size()):
		if active_perks[i].perk_id == perk_id:
			var perk = active_perks[i]
			active_perks.remove_at(i)
			print("PerkManager: removed perk '%s'" % perk.perk_name)
			perks_changed.emit()
			return true
	return false

func clear_perks() -> void:
	active_perks.clear()
	print("PerkManager: cleared all perks")
	perks_changed.emit()

func get_total_multiplier(stat_name: String) -> float:
	var multiplier: float = 1.0
	for perk in active_perks:
		match stat_name:
			"weight_penalty":
				multiplier *= perk.weight_penalty_multiplier
			"stamina":
				multiplier *= perk.stamina_multiplier
			"sprint_speed":
				multiplier *= perk.sprint_speed_multiplier
			"stamina_drain":
				multiplier *= perk.stamina_drain_multiplier
			"bleed_damage":
				multiplier *= perk.bleed_damage_multiplier
			"weapon_fire_rate":
				multiplier *= perk.weapon_fire_rate_multiplier
			"reload_speed":
				multiplier *= perk.reload_speed_multiplier
	return multiplier

func get_stat_bonus(stat_name: String) -> float:
	var bonus: float = 0.0
	for perk in active_perks:
		match stat_name:
			"max_stamina":
				bonus += perk.max_stamina_bonus
	return bonus

func can_add_perk() -> bool:
	return active_perks.size() < MAX_PERKS

func get_slots_remaining() -> int:
	return MAX_PERKS - active_perks.size()
