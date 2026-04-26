# ============================================================
# UIColors.gd — Palette de couleurs centralisée.
#
# Toutes les teintes de l'interface sont définies ici et
# référencées par nom dans Village.gd et Biome.gd.
# Modifier une valeur ici la propage dans tout le jeu.
#
# Convention :
#   • Constantes en SCREAMING_SNAKE pour les valeurs brutes
#   • Fonctions statiques pour la logique conditionnelle
# ============================================================
extends Node

# ── Arrière-plans ───────────────────────────────────────────
const BG_DARK := Color(0.06, 0.07, 0.11)   # fond principal de scène
const BG_CARD := Color(0.10, 0.11, 0.16)   # fond d'une carte PanelContainer
const BG_BAR  := Color(0.07, 0.07, 0.12)   # fond d'une ProgressBar

# ── Barres de PV — Héro (vert → jaune → rouge) ─────────────
const HP_HIGH := Color(0.18, 0.82, 0.32)   # > 60 %
const HP_MID  := Color(0.90, 0.74, 0.08)   # 30–60 %
const HP_LOW  := Color(0.88, 0.18, 0.12)   # < 30 %

# ── Barres de PV — Ennemi (rouge → orange → jaune) ─────────
# Logique inversée : rouge = fort, jaune = presque vaincu.
const ENEMY_HIGH := Color(0.88, 0.18, 0.12)
const ENEMY_MID  := Color(0.90, 0.52, 0.08)
const ENEMY_LOW  := Color(0.88, 0.82, 0.08)

# ── Labels de statistiques du héro ─────────────────────────
const STAT_ATK := Color(1.00, 0.55, 0.20)
const STAT_DEF := Color(0.30, 0.70, 1.00)
const STAT_HP  := Color(0.20, 0.85, 0.35)

# ── Hall des Évolutions — couleur par type de rencontre ────
const TYPE_CREATURE  := Color(0.95, 0.58, 0.12)
const TYPE_TRAP      := Color(0.88, 0.22, 0.22)
const TYPE_EVENT_POS := Color(0.20, 0.80, 0.42)
const TYPE_BIOME     := Color(0.22, 0.72, 0.90)

# ── Journal de combat ───────────────────────────────────────
const LOG_COMBAT   := Color(0.95, 0.58, 0.12)
const LOG_VICTORY  := Color(0.20, 0.85, 0.35)
const LOG_DEFEAT   := Color(0.88, 0.18, 0.12)
const LOG_TRAP     := Color(0.88, 0.30, 0.30)
const LOG_EVENT    := Color(0.40, 0.90, 0.55)
const LOG_LOOT     := Color(1.00, 0.85, 0.15)
const LOG_IGNORED  := Color(0.50, 0.55, 0.92)

# ── Modificateur de cycle ───────────────────────────────────
const MODIFIER_ACTIVE := Color(0.95, 0.75, 0.10)

# ── Forge / Recettes ────────────────────────────────────────
const INGREDIENT_OK      := Color(0.35, 0.85, 0.35)
const INGREDIENT_MISSING := Color(0.85, 0.35, 0.35)
const RESULT_SLOT        := Color(0.55, 0.75, 1.00)

# ── Inventaire ──────────────────────────────────────────────
const RESOURCE_QTY := Color(0.70, 1.00, 0.70)

# ── Texte UI générique ──────────────────────────────────────
const TEXT_MUTED  := Color(0.48, 0.48, 0.52)
const TEXT_HEADER := Color(0.75, 0.85, 1.00)
const TEXT_BONUS  := Color(0.55, 1.00, 0.55)
const FILTER_ON   := Color(1.00, 0.88, 0.20)

# ── Dégâts flottants ────────────────────────────────────────
const DMG_BY_HERO  := Color(1.00, 0.92, 0.05)   # dégâts infligés par le héro
const DMG_BY_ENEMY := Color(1.00, 0.30, 0.15)   # dégâts reçus par le héro

# ── Combo ────────────────────────────────────────────────────
const COMBO_COLOR := Color(1.00, 0.62, 0.05)

# ───────────────────────────────────────────────────────────
#  Fonctions utilitaires (logique conditionnelle)
# ───────────────────────────────────────────────────────────

# Couleur de la barre de PV du héro selon son pourcentage de vie (0.0–1.0).
static func hero_hp(pct: float) -> Color:
	if pct > 0.60: return HP_HIGH
	if pct > 0.30: return HP_MID
	return HP_LOW

# Couleur de la barre de PV d'un ennemi.
# (logique inversée : rouge quand il est fort, jaune quand il est presque mort)
static func enemy_hp(pct: float) -> Color:
	if pct > 0.60: return ENEMY_HIGH
	if pct > 0.30: return ENEMY_MID
	return ENEMY_LOW

# Couleur d'une entrée du Hall des Évolutions selon son type.
static func encounter(enc_type: String) -> Color:
	match enc_type:
		"Créature":  return TYPE_CREATURE
		"Piège":     return TYPE_TRAP
		"Événement": return TYPE_EVENT_POS
		"Biome":     return TYPE_BIOME
		_:           return Color.WHITE
