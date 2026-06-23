# ============================================================
# UIColors.gd — Palette de couleurs centralisée.
#
# Toutes les teintes de l'interface sont définies ici.
# Modifier une valeur ici la propage dans tout le jeu.
#
# Convention :
#   • Constantes SCREAMING_SNAKE pour les valeurs brutes
#   • Fonctions statiques pour la logique conditionnelle
# ============================================================
extends Node

# ── Arrière-plans ───────────────────────────────────────────
const BG_DARK := Color(0.06, 0.07, 0.11)
const BG_CARD := Color(0.10, 0.11, 0.16)
const BG_BAR  := Color(0.07, 0.07, 0.12)
const PANEL_BG_DARK := Color(0.05, 0.06, 0.10)   # fond de panneau quasi noir (combat, rituel) — alpha posé au site

# ── Barres de PV — Héros (vert → jaune → rouge → rouge vif) ─
const HP_HIGH     := Color(0.18, 0.82, 0.32)   # > 60 %
const HP_MID      := Color(0.90, 0.74, 0.08)   # 30–60 %
const HP_LOW      := Color(0.88, 0.18, 0.12)   # 15–30 %
const HP_CRITICAL := Color(1.00, 0.05, 0.05)   # < 15 % — danger immédiat

# ── Barres de PV — Ennemi (rouge → orange → jaune) ─────────
# Logique inversée : rouge = fort, jaune = presque vaincu.
const ENEMY_HIGH := Color(0.88, 0.18, 0.12)
const ENEMY_MID  := Color(0.90, 0.52, 0.08)
const ENEMY_LOW  := Color(0.88, 0.82, 0.08)

# ── Labels de statistiques du héros ─────────────────────────
const STAT_ATK := Color(1.00, 0.55, 0.20)
const STAT_DEF := Color(0.30, 0.70, 1.00)
const STAT_HP  := Color(0.20, 0.85, 0.35)

# ── Hall des Évolutions — couleur par type de rencontre ────
const TYPE_CREATURE   := Color(0.95, 0.58, 0.12)
const TYPE_TRAP       := Color(0.88, 0.22, 0.22)
const TYPE_BENEDICTION := Color(0.20, 0.80, 0.42)
const TYPE_BIOME      := Color(0.22, 0.72, 0.90)

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

# ── Effets visuels ──────────────────────────────────────────
const VICTORY_GLOW := Color(0.22, 1.00, 0.48)   # flash carte héros après victoire
const HEAL_COLOR   := Color(0.25, 0.95, 0.40)   # nombres flottants de soin
const HASTE        := Color(0.25, 0.95, 0.85)   # hâte (jauge ATB accélérée + pill « Hâte »)

# ── États de combat (pills + feedback) ──────────────────────
const SHIELD := Color(0.30, 0.70, 1.00)   # bouclier / absorption
const POISON := Color(0.62, 0.15, 0.78)   # poison / venin / saignement (DoT)

# ── Mécaniques fortes de biome (couleur unique panneau ↔ combat) ──
const MECH_AMBUSH    := Color(0.90, 0.35, 0.35)   # embuscade — rouge
const MECH_POISON    := POISON                     # poison — violet (cf. États de combat)
const MECH_ENDURANCE := Color(0.80, 0.55, 0.25)   # endurcissement — brun-orangé

# ── Forge / Recettes ────────────────────────────────────────
const INGREDIENT_OK      := Color(0.35, 0.85, 0.35)
const INGREDIENT_MISSING := Color(0.85, 0.35, 0.35)
const RESULT_SLOT        := Color(0.55, 0.75, 1.00)

# ── Inventaire ──────────────────────────────────────────────
const RESOURCE_QTY := Color(0.70, 1.00, 0.70)

# ── Rareté / tiers de maîtrise ──────────────────────────────
const TIER_COMMUN     := Color(0.62, 0.62, 0.65)   # 0 — Commun
const TIER_PEU_COMMUN := Color(0.22, 0.82, 0.38)   # 1 — Peu Commun
const TIER_RARE       := Color(0.22, 0.58, 1.00)   # 2 — Rare
const TIER_EPIQUE     := Color(0.72, 0.28, 1.00)   # 3 — Épique
const TIER_LEGENDAIRE := Color(1.00, 0.78, 0.08)   # 4 — Légendaire
const TIER_UNIQUE     := Color(1.00, 0.10, 0.18)   # 5 — Unique

# ── Zones d'enfoncement (Surface / Profondeur / Abysse) ──────
const ZONE_SURFACE    := Color(0.30, 0.70, 1.00)   # bleu
const ZONE_PROFONDEUR := Color(0.72, 0.28, 1.00)   # violet
const ZONE_ABYSSE     := Color(0.88, 0.18, 0.12)   # rouge

# ── Village / éclosion ──────────────────────────────────────
const VILLAGE_NASCENT := Color(0.38, 0.38, 0.52)   # teinte du village naissant (palier 0)
const ENERGY_ACCENT   := Color(0.70, 0.85, 1.0)    # accent bleu clair des liens/boules d'énergie

# ── Carte neutre (sans rareté native) ───────────────────────
const CARD_NEUTRAL := Color(0.42, 0.52, 0.68)   # acier-bleu sobre, ni tier ni catégorie

# ── Butin (pastilles placeholder, en attendant les icônes) ──
const LOOT_NEUTRAL := Color(0.55, 0.62, 0.72)   # ingrédient sans teinte propre

# ── XP flottante par type d'entité réceptrice (combat) ──────
# Créature → TYPE_CREATURE, Biome → TYPE_BIOME (déjà définis plus haut).
const XP_HERO      := Color(0.55, 0.36, 0.97)   # violet (cohérent avec ⚔ du héros)
const XP_PASSIVE   := Color(0.45, 0.90, 0.75)   # vert d'eau
const XP_EQUIPMENT := Color(0.55, 0.75, 1.00)   # bleu clair (cf. RESULT_SLOT)

# ── Sélection (panneau Expéditions) ─────────────────────────
const SELECTION_GOLD := Color(1.00, 0.84, 0.30)   # liseré or du biome sélectionné

# ── Texte UI générique ──────────────────────────────────────
const TEXT_MUTED  := Color(0.48, 0.48, 0.52)
const TEXT_HEADER := Color(0.75, 0.85, 1.00)
const TEXT_BONUS  := Color(0.55, 1.00, 0.55)
const TOOLTIP_BODY := Color(0.80, 0.82, 0.88)   # corps de tooltip — clair, lisible sur BG_DARK
const FILTER_ON   := Color(1.00, 0.88, 0.20)

# ── Dégâts flottants ────────────────────────────────────────
const DMG_BY_HERO   := Color(1.00, 0.92, 0.05)   # dégâts infligés par le héros (faible/moyen)
const DMG_BY_ENEMY  := Color(1.00, 0.30, 0.15)   # dégâts reçus par le héros (faible)
const DMG_HEAVY_HERO  := Color(1.00, 0.50, 0.08)   # orange éclatant — dégâts forts par le héros
const DMG_HEAVY_ENEMY := Color(1.00, 0.08, 0.08)   # rouge vif — dégâts forts par l'ennemi

# ───────────────────────────────────────────────────────────
#  Fonctions utilitaires (logique conditionnelle)
# ───────────────────────────────────────────────────────────

# Couleur de la barre de PV du héros — 4 niveaux de danger.
func hero_hp(pct: float) -> Color:
	if pct > 0.60: return HP_HIGH
	if pct > 0.30: return HP_MID
	if pct > 0.15: return HP_LOW
	return HP_CRITICAL

# Couleur de la barre de PV d'un ennemi.
# Logique inversée : rouge quand il est fort, jaune quand il faiblit.
func enemy_hp(pct: float) -> Color:
	if pct > 0.60: return ENEMY_HIGH
	if pct > 0.30: return ENEMY_MID
	return ENEMY_LOW

# Couleur d'un tier de maîtrise (0 = Commun … 5 = Unique).
func tier_color(tier: int) -> Color:
	match tier:
		Enums.Maitrise.COMMUN:     return TIER_COMMUN
		Enums.Maitrise.PEU_COMMUN: return TIER_PEU_COMMUN
		Enums.Maitrise.RARE:       return TIER_RARE
		Enums.Maitrise.EPIQUE:     return TIER_EPIQUE
		Enums.Maitrise.LEGENDAIRE: return TIER_LEGENDAIRE
		Enums.Maitrise.UNIQUE:     return TIER_UNIQUE
		_:                         return Color.WHITE

# Couleur d'XP flottante selon le type d'entité réceptrice (combat).
func entity_type_color(entity_type: String) -> Color:
	match entity_type:
		Enums.EntityType.HERO:      return XP_HERO
		Enums.EntityType.CREATURE:  return TYPE_CREATURE
		Enums.EntityType.BIOME:     return TYPE_BIOME
		Enums.EntityType.PASSIVE, Enums.EntityType.PASSIF_UNIQUE: return XP_PASSIVE
		Enums.EntityType.EQUIPMENT: return XP_EQUIPMENT
		_:                          return TEXT_HEADER

# Couleur placeholder d'une pastille de butin : teinte stable dérivée de
# l'item_id (variété visuelle en attendant les icônes), neutre si vide.
func loot_color(item_id: String) -> Color:
	if item_id == "":
		return LOOT_NEUTRAL
	var hue := float(absi(item_id.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.50, 0.92)

# Couleur d'une zone d'enfoncement (0 = Surface, 1 = Profondeur, 2 = Abysse).
func zone_color(zone: int) -> Color:
	match zone:
		Enums.Zone.SURFACE:    return ZONE_SURFACE
		Enums.Zone.PROFONDEUR: return ZONE_PROFONDEUR
		Enums.Zone.ABYSSE:     return ZONE_ABYSSE
		_:                     return ZONE_SURFACE

