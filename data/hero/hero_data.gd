# ============================================================
# HeroData — Resource décrivant le Héro unique du jeu.
#
# Le Héro n'a pas de Maîtrise ni de Rareté.
# Sa puissance vient exclusivement de :
#   • l'équipement porté (weapon / armor / accessory)
#   • les passifs permanents débloqués par les entités du jeu
# ============================================================
class_name HeroData extends Resource

@export var base_hp:  int = 110
@export var base_atk: int = 15
@export var base_def: int = 7

# Slots d'équipement : weapon | armor | accessory
@export var equipment: Dictionary = {
	"weapon":    "",
	"armor":     "",
	"accessory": ""
}

func get_effective_atk(passive_bonus: float = 0.0, equip_bonus: float = 0.0,
		atk_mult: float = 1.0) -> float:
	return (float(base_atk) + passive_bonus + equip_bonus) * atk_mult

func get_effective_def(passive_bonus: float = 0.0, def_mult: float = 1.0) -> float:
	return (float(base_def) + passive_bonus) * def_mult

func get_effective_hp(passive_bonus: float = 0.0, equip_bonus: float = 0.0) -> float:
	return float(base_hp) + passive_bonus + equip_bonus

func equip(slot: String, item_id: String) -> void:
	if slot in ["weapon", "armor", "accessory"]:
		equipment[slot] = item_id
