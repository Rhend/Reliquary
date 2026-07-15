# ============================================================
# ProgressionHeros — NIVEAU et XP du héros (système RPG classique, acté
# 06/07/2026) + crédit d'Euren. Rework Combat, chantier 6.
#
# class_name statique (pattern Balance : PAS un autoload). L'état vit dans
# GameData.player ("heros_xp", "euren" — persisté automatiquement, cf.
# SaveManager) ; les valeurs de courbe/gains vivent dans
# data/progression/heros_progression.tres (ProgressionHerosData) et le
# niveau est DÉRIVÉ de l'XP totale (source unique, aucun champ redondant).
#
# Crédit d'XP : IMMÉDIAT à la victoire de chaque combat (appelé par ExpeRun) —
# la montée de niveau en cours de run est possible et voulue ; les stats du
# combattant CTB déjà construit ne changent pas à chaud (le nouveau niveau
# compte au prochain combat, cf. CtbPont).
# Crédit d'Euren : à la SORTIE d'expédition uniquement (extraction ou
# complétion ; défaite = rien) — appelé par ExpeRun._terminer.
# ============================================================
class_name ProgressionHeros

const CONFIG: ProgressionHerosData = preload("res://data/progression/heros_progression.tres")

# ─── Lecture ─────────────────────────────────────────────────

static func xp_totale() -> float:
	return float(GameData.player.get("heros_xp", 0.0))

static func niveau() -> int:
	return CONFIG.niveau_pour_xp(xp_totale())

# Seuil d'XP totale du prochain niveau (pour l'affichage « XP x / y »).
static func seuil_prochain_niveau() -> float:
	return CONFIG.seuil_xp(niveau() + 1)

# Bonus plats du niveau courant : {hp, atk, def, vit} — consommés par
# CtbPont.combattant_depuis_heros (injectés AVANT les %, additif universel).
static func bonus_plats() -> Dictionary:
	return CONFIG.bonus_plats(niveau())

# ─── Écriture ────────────────────────────────────────────────

# Crédite de l'XP de niveau (jamais négative, jamais perdue). Retourne
# {avant, apres} (niveaux) ; émet heros_xp_gagnee, et heros_niveau_change
# si le niveau monte (possiblement de plusieurs niveaux en un gain).
static func gagner_xp(montant: float) -> Dictionary:
	var avant := niveau()
	if montant > 0.0:
		GameData.player["heros_xp"] = xp_totale() + montant
		EventBus.heros_xp_gagnee.emit(montant, xp_totale())
	var apres := niveau()
	if apres > avant:
		EventBus.heros_niveau_change.emit(avant, apres)
	return {"avant": avant, "apres": apres}

# ─── Euren ───────────────────────────────────────────────────

static func euren() -> float:
	return float(GameData.player.get("euren", 0.0))

# Crédite de l'Euren (à la sortie d'expédition uniquement — l'appelant
# décide ; aucun puits de dépense à ce chantier).
static func crediter_euren(montant: float) -> void:
	if montant <= 0.0:
		return
	GameData.player["euren"] = euren() + montant
	EventBus.euren_change.emit(euren())
