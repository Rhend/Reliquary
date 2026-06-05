# ============================================================
# Translations.gd — Autoload de traduction FR/EN.
#
# Usage :  Translations.T("key")
# Langue : GameSettings.language ("fr" ou "en")
#
# Fallback : EN → FR → clé brute
# ============================================================
extends Node

const STRINGS: Dictionary = {
	"fr": {
		# ── Paliers ──────────────────────────────────────────
		"tier.0":        "Commun",
		"tier.1":        "Peu Commun",
		"tier.2":        "Rare",
		"tier.3":        "Épique",
		"tier.4":        "Légendaire",
		"tier.5":        "Unique",
		"tier.unknown":  "Inconnu",
		"tier.max_rank": "RANG MAX",
		"tier.max_level":"▲ NIVEAU MAXIMUM",

		# ── Zones ────────────────────────────────────────────
		"zone.0": "Surface",
		"zone.1": "Profondeur",
		"zone.2": "Abysse",
		"zone.tt.0": "Première zone du biome.\n70 % combats · 15 % bénédictions · 15 % pièges\nCréature de Surface uniquement.\nPièges : 8 % de vos PV max.",
		"zone.tt.1": "Zone intermédiaire. Les dangers s'intensifient.\n70 % combats · 15 % bénédictions · 15 % pièges\nCréatures de Surface et de Profondeur.\nPièges : 15 % de vos PV max.",
		"zone.tt.2": "Zone finale. Aucun combat automatique.\n50 % bénédictions · 50 % pièges\nPièges : 30 % de vos PV max.\nLa créature Unique peut être affrontée ici.",

		# ── Panel titres (PANEL_TITLES) ───────────────────────
		"panel.hero":      "HÉRO",
		"panel.adventure": "EXPÉDITIONS",
		"panel.forge":     "FORGE",
		"panel.sanctuary": "SANCTUAIRE",
		"panel.relic":     "RELIQUE",
		"panel.tbd":       "?",

		# ── Menu items (MENU_ITEMS labels) ────────────────────
		"menu.hero":      "HÉRO",
		"menu.adventure": "EXPÉDITIONS",
		"menu.forge":     "FORGE",
		"menu.sanctuary": "SANCTUAIRE",
		"menu.relic":     "RELIQUE",
		"menu.tbd":       "?",

		# ── Tooltips hexagones ────────────────────────────────
		"hex_tt.hero":      "Votre héros et ses passifs.\nConsultez ses équipements et sa progression.",
		"hex_tt.adventure": "Partez en expédition.\nChoisissez un biome et affrontez ses créatures.",
		"hex_tt.forge":     "Le Forgeron.\nAméliorez vos équipements avec les ingrédients récoltés.",
		"hex_tt.sanctuary": "Sanctuaire des Évolutions.\nFaites évoluer vos entités au rang supérieur.",
		"hex_tt.relic":     "Reliques anciennes.\nDébloquez des pouvoirs permanents rares.",
		"hex_tt.tbd":       "Mystère à venir...",

		# ── Éclosion ─────────────────────────────────────────
		"birth.phrase_25":  "Un battement…  puis un autre.  Quelque chose remue dans le noir.",
		"birth.phrase_50":  "Le long sommeil se déchire.  Mes souvenirs fuient comme l'eau entre mes doigts.",
		"birth.phrase_75":  "Un village, tout proche…  et des fragments de rêve épars, alentour.",
		"birth.phrase_100": "Je ne sais plus qui je suis…\nmais je m'éveille.",
		"birth.flavor":     "Ranimez l'étincelle…  réveillez l'âme endormie.",

		# ── Hints contextuels ────────────────────────────────
		"hint.start":        "Partez en expédition pour gagner de l'XP et faire progresser vos entités",
		"hint.reach_rare":   "Faites atteindre Rare à un biome pour libérer un Fragment de Mémoire",
		"hint.fragment_ok":  "Fragment collecté — continuez à progresser pour faire évoluer le Village",
		"hint.forge_ready":  "La Forge est disponible — partez en expédition pour remplir les barres XP de vos équipements",

		# ── Conditions Village ────────────────────────────────
		"village.cond.fragments": "Fragments",
		"village.cond.xp":        "XP Village",
		"village.cond.hero_xp":   "Héros à XP max",
		"village.evolve_btn":     "Faire évoluer le Village",
		"village.tier_label":     "Village",
		"village.soon":           "✦  %s  ✦\n\nBientôt disponible",

		# ── Bouton Évoluer ────────────────────────────────────
		"btn.evolve":  "ÉVOLUER ▲",

		# ── HeroPanel ────────────────────────────────────────
		"hero.section.stats":       "◆  STATISTIQUES",
		"hero.section.equip":       "◆  ÉQUIPEMENT",
		"hero.section.passives":    "◆  PASSIFS",
		"hero.section.ingredients": "◆  INGRÉDIENTS",
		"hero.stat.atk":            "ATK",
		"hero.stat.def":            "DEF",
		"hero.stat.hp":             "PV",
		"hero.no_passive":          "Aucun passif débloqué",
		"hero.no_ingredient":       "Aucun ingrédient en stock",
		"hero.equip.slot.arme":     "Arme",
		"hero.equip.slot.anneau":   "Anneau",
		"hero.equip.slot.armure":   "Armure",
		"hero.equip.slot.ceinture": "Ceinture",
		"hero.equip.slot.bouclier": "Bouclier",
		"hero.equip.slot.talisman": "Talisman",
		"hero.forge_required":      "🔨  Forge Requise",
		"hero.forge_ready":         "🔨  Prêt à forger :",
		"hero.passive.unlock_hdr":  "— À DÉBLOQUER —",
		"hero.passive.tt_mastery":  "Maîtrise : %s",
		"hero.passive.tt_effect":   "\nEffet : %s",
		"hero.equip.tt_slot":       "Slot : %s  ·  Rang : %s",

		# ── ForgePanel ───────────────────────────────────────
		"forge.smith_locked":    "🔨  Le Forgeron\n\n« Je ne peux pas encore\nvous aider. »\n\nLibérez un Fragment pour\nfaire évoluer le Village.",
		"forge.section.ingr":   "◆  INGRÉDIENTS",
		"forge.section.equip":  "◆  ÉQUIPEMENT",
		"forge.ingr.unique":    "Ingrédient unique — une seule obtention.",
		"forge.ingr.tt_stock":  "Biome : %s\nEn stock : %d",
		"forge.equip.locked":   "🔒  %s  —  Biome non découvert",
		"forge.equip.max_rank": "▲ RANG MAX",
		"forge.equip.low_xp":  "⧖  XP insuffisante — continuez l'aventure",
		"forge.equip.no_recipe":"Recette non définie",
		"forge.equip.forge_btn":"Forger → %s",
		"forge.equip.tt_slot":  "Slot : %s  ·  Rang : %s",
		"forge.equip.tt_next":  "\n→ %s : %s",
		"forge.ingr.x_of_y":        "%d / %d",
		"forge.locked.title":       "LE FORGERON",
		"forge.locked.quote":       "« Je ne peux pas encore vous aider. »",
		"forge.locked.hint":        "Libérez un Fragment de Mémoire\npour faire évoluer le Village.",
		"forge.recipe.tt_stock":    "En stock : %d\nRequis : %d",
		"forge.equip.low_xp_pct":   "⧖  XP — %d %%  (continuez l'aventure)",
		"forge.equip.forge_unavail":      "Forge indisponible",
		"forge.equip.forge_tt_unavail":   "Remplissez la barre XP et réunissez les ingrédients.",

		# ── AdventurePanel ───────────────────────────────────
		"adv.running.expedition": "Expédition en cours",
		"adv.biome_placeholder":  "Choisir un biome pour partir en expédition",
		"adv.start_btn":          "⚔   PARTIR EN EXPÉDITION",
		"adv.start_btn_named":    "⚔   PARTIR EN EXPÉDITION — %s",
		"adv.section.biomes":     "◆  BIOMES DISPONIBLES",
		"adv.section.creatures":  "CRÉATURES",
		"adv.section.traps":      "PIÈGES",
		"adv.section.blessings":  "BÉNÉDICTIONS",
		"adv.section.ingredients":"INGRÉDIENTS",
		"adv.zone_max":           "Zone max : %s",
		"adv.mechanic_label":     "Mécanique : %s",
		"adv.mechanic_tt_title":  "Mécanique — %s",
		"adv.mechanic_locked":    "%s  —  Débloquée à Rare",
		"adv.mechanic_tt_locked": "Atteins Rare pour débloquer cette mécanique.",
		"adv.ingr.tooltip":       "Biome : %s\nEn stock : %d",
		"adv.trap.dmg_zones":     "Surface : 8 %% PV  ·  Profondeur : 15 %% PV  ·  Abysse : 30 %% PV",
		"adv.trap.mastery_note":  "\nMaîtrise réduit les dégâts subis.",
		"adv.bless.desc":         "Bonus XP et soins selon la zone.\nMaîtrise augmente l'effet reçu.",
		"adv.creature.tt":        "Zone : %s\nMaîtrise : %s",

		# ── Mécaniques fortes ─────────────────────────────────
		"mech.ambush.name":       "Embuscade",
		"mech.ambush.desc":       "La créature attaque en premier.",
		"mech.poison.name":       "Empoisonnement",
		"mech.poison.desc":       "Chaque frappe du héros empoisonne l'ennemi (3 max).",
		"mech.endurcissement.name": "Endurcissement",
		"mech.endurcissement.desc": "Dégâts du héros réduits de 20 % contre les créatures du biome.",

		# ── CombatScene ──────────────────────────────────────
		"combat.end_btn":         "Mettre fin à l'expédition",
		"combat.xp_label":        "XP ce cycle — 0",
		"combat.victory":         "— Victoire —",
		"combat.defeat":          "— Défaite —",
		"combat.log.all":         "Tout",
		"combat.log.hero":        "Héros",
		"combat.log.monster":     "Monstre",
		"combat.log.attack":      "Attaque",
		"combat.log.defense":     "Défense",
		"combat.log.heal":        "Soin",
		"combat.log.status":      "État",
		"combat.xp_label_fmt":    "XP ce cycle — %d",
		"combat.bless.heal":      "+%d PV",
		"combat.bless.atk":       "+%d ATK (temporaire)",
		"combat.bless.def":       "+%d DEF (temporaire)",
		"combat.bless.xp":        "+%d%% XP ce cycle",
		"combat.bless.unknown":   "Effet inconnu",
		"combat.action.crit":     "Critique !",
		"combat.action.attack":   "Attaque",
		"combat.poison":          "Poison",
		"combat.venom":           "Venin",
		"combat.venom_contact":   "Contact Venimeux",
		"combat.shield_absorb":   "Bouclier absorbe %d",
		"combat.shield_proc":     "Bouclier d'urgence activé",
		"combat.shield_pill":     "Bouclier +%d",
		"combat.regen":           "Régénération +%d",
		"combat.unique_slain":    "Créature Unique vaincue — %s, %s",
		"combat.venom_pill":      "☠ Venin",
		"combat.ready_evolve":    "⬆ %s prêt à évoluer",

		# ── CycleSummaryScreen ───────────────────────────────
		"cycle.title":            "CYCLE TERMINÉ  —  %s",
		"cycle.victory":          "Victoire",
		"cycle.interrupted":      "Interruption",
		"cycle.defeat":           "Défaite",
		"cycle.back_village":     "🏠  RETOUR AU VILLAGE",
		"cycle.section.discoveries": "◆  DÉCOUVERTES",
		"cycle.section.resources":   "◆  RESSOURCES COLLECTÉES",
		"cycle.section.xp":          "◆  RÉPARTITION XP",
		"cycle.discovery.fragment":  "Fragment de Mémoire",
		"cycle.discovery.unique":    "Créature Unique",
		"cycle.no_evolution":        "Aucune évolution disponible",
		"cycle.encounters":          "Créatures rencontrées",
		"cycle.traps":               "Pièges identifiés",
		"cycle.blessings":           "Bénédictions trouvées",
		"cycle.section.evolutions":  "◆  ÉVOLUTIONS DISPONIBLES",
		"cycle.xp_total":            "XP total — %d",
		"cycle.hero_label":          "Héros",

		# ── Settings ─────────────────────────────────────────
		"settings.title":         "⚙  PARAMÈTRES",
		"settings.audio":         "◆  AUDIO",
		"settings.music":         "Musique",
		"settings.sfx":           "Bruitage",
		"settings.display":       "◆  AFFICHAGE",
		"settings.fullscreen":    "Plein Écran",
		"settings.save":          "◆  SAUVEGARDE",
		"settings.export":        "📤  Exporter la sauvegarde",
		"settings.import":        "📥  Importer une sauvegarde",
		"settings.language":      "◆  LANGUE",
		"settings.lang.fr":       "Français",
		"settings.lang.en":       "English",

		# ── Général ──────────────────────────────────────────
		"nav.back":               "← Village",
		"nav.back_tt":            "Revenir au hub principal.",
	},

	"en": {
		# ── Paliers ──────────────────────────────────────────
		"tier.0":        "Common",
		"tier.1":        "Uncommon",
		"tier.2":        "Rare",
		"tier.3":        "Epic",
		"tier.4":        "Legendary",
		"tier.5":        "Unique",
		"tier.unknown":  "Unknown",
		"tier.max_rank": "MAX RANK",
		"tier.max_level":"▲ MAXIMUM LEVEL",

		# ── Zones ────────────────────────────────────────────
		"zone.0": "Surface",
		"zone.1": "Depths",
		"zone.2": "Abyss",
		"zone.tt.0": "First zone of the biome.\n70% fights · 15% blessings · 15% traps\nSurface creature only.\nTraps: 8% of your max HP.",
		"zone.tt.1": "Intermediate zone. Dangers intensify.\n70% fights · 15% blessings · 15% traps\nSurface and Depths creatures.\nTraps: 15% of your max HP.",
		"zone.tt.2": "Final zone. No automatic fights.\n50% blessings · 50% traps\nTraps: 30% of your max HP.\nThe Unique creature can be fought here.",

		# ── Panel titres ──────────────────────────────────────
		"panel.hero":      "HERO",
		"panel.adventure": "EXPEDITIONS",
		"panel.forge":     "FORGE",
		"panel.sanctuary": "SANCTUARY",
		"panel.relic":     "RELIC",
		"panel.tbd":       "?",

		# ── Menu items ────────────────────────────────────────
		"menu.hero":      "HERO",
		"menu.adventure": "EXPEDITIONS",
		"menu.forge":     "FORGE",
		"menu.sanctuary": "SANCTUARY",
		"menu.relic":     "RELIC",
		"menu.tbd":       "?",

		# ── Tooltips hexagones ────────────────────────────────
		"hex_tt.hero":      "Your hero and their passives.\nCheck equipment and progression.",
		"hex_tt.adventure": "Go on an expedition.\nChoose a biome and face its creatures.",
		"hex_tt.forge":     "The Blacksmith.\nUpgrade your gear using collected ingredients.",
		"hex_tt.sanctuary": "Evolution Sanctuary.\nEvolve your entities to the next rank.",
		"hex_tt.relic":     "Ancient Relics.\nUnlock rare permanent powers.",
		"hex_tt.tbd":       "Mystery ahead...",

		# ── Éclosion ─────────────────────────────────────────
		"birth.phrase_25":  "A heartbeat… then another.  Something stirs in the dark.",
		"birth.phrase_50":  "The long sleep tears apart.  My memories slip like water through my fingers.",
		"birth.phrase_75":  "A village, close by…  and scattered dream fragments all around.",
		"birth.phrase_100": "I no longer know who I am…\nbut I am waking.",
		"birth.flavor":     "Rekindle the spark…  awaken the sleeping soul.",

		# ── Hints contextuels ────────────────────────────────
		"hint.start":        "Go on an expedition to gain XP and progress your entities",
		"hint.reach_rare":   "Bring a biome to Rare rank to free a Memory Fragment",
		"hint.fragment_ok":  "Fragment collected — keep progressing to evolve the Village",
		"hint.forge_ready":  "The Forge is available — go on expeditions to fill your equipment XP bars",

		# ── Conditions Village ────────────────────────────────
		"village.cond.fragments": "Fragments",
		"village.cond.xp":        "Village XP",
		"village.cond.hero_xp":   "Hero at max XP",
		"village.evolve_btn":     "Evolve the Village",
		"village.tier_label":     "Village",
		"village.soon":           "✦  %s  ✦\n\nComing soon",

		# ── Bouton Évoluer ────────────────────────────────────
		"btn.evolve":  "EVOLVE ▲",

		# ── HeroPanel ────────────────────────────────────────
		"hero.section.stats":       "◆  STATISTICS",
		"hero.section.equip":       "◆  EQUIPMENT",
		"hero.section.passives":    "◆  PASSIVES",
		"hero.section.ingredients": "◆  INGREDIENTS",
		"hero.stat.atk":            "ATK",
		"hero.stat.def":            "DEF",
		"hero.stat.hp":             "HP",
		"hero.no_passive":          "No passive unlocked",
		"hero.no_ingredient":       "No ingredient in stock",
		"hero.equip.slot.arme":     "Weapon",
		"hero.equip.slot.anneau":   "Ring",
		"hero.equip.slot.armure":   "Armor",
		"hero.equip.slot.ceinture": "Belt",
		"hero.equip.slot.bouclier": "Shield",
		"hero.equip.slot.talisman": "Talisman",
		"hero.forge_required":      "🔨  Forge Required",
		"hero.forge_ready":         "🔨  Ready to forge:",
		"hero.passive.unlock_hdr":  "— TO UNLOCK —",
		"hero.passive.tt_mastery":  "Mastery: %s",
		"hero.passive.tt_effect":   "\nEffect: %s",
		"hero.equip.tt_slot":       "Slot: %s  ·  Rank: %s",

		# ── ForgePanel ───────────────────────────────────────
		"forge.smith_locked":    "🔨  The Blacksmith\n\n« I can't help you\njust yet. »\n\nFree a Fragment to\nevolve the Village.",
		"forge.section.ingr":   "◆  INGREDIENTS",
		"forge.section.equip":  "◆  EQUIPMENT",
		"forge.ingr.unique":    "Unique ingredient — only one obtainable.",
		"forge.ingr.tt_stock":  "Biome: %s\nIn stock: %d",
		"forge.equip.locked":   "🔒  %s  —  Biome not discovered",
		"forge.equip.max_rank": "▲ MAX RANK",
		"forge.equip.low_xp":  "⧖  Insufficient XP — continue adventuring",
		"forge.equip.no_recipe":"Recipe not defined",
		"forge.equip.forge_btn":"Forge → %s",
		"forge.equip.tt_slot":  "Slot: %s  ·  Rank: %s",
		"forge.equip.tt_next":  "\n→ %s: %s",
		"forge.ingr.x_of_y":        "%d / %d",
		"forge.locked.title":       "THE BLACKSMITH",
		"forge.locked.quote":       "« I can't help you just yet. »",
		"forge.locked.hint":        "Free a Memory Fragment\nto evolve the Village.",
		"forge.recipe.tt_stock":    "In stock: %d\nRequired: %d",
		"forge.equip.low_xp_pct":   "⧖  XP — %d%%  (keep adventuring)",
		"forge.equip.forge_unavail":      "Forge unavailable",
		"forge.equip.forge_tt_unavail":   "Fill the XP bar and gather the required ingredients.",

		# ── AdventurePanel ───────────────────────────────────
		"adv.running.expedition": "Expedition in progress",
		"adv.biome_placeholder":  "Choose a biome to start an expedition",
		"adv.start_btn":          "⚔   START EXPEDITION",
		"adv.start_btn_named":    "⚔   START EXPEDITION — %s",
		"adv.section.biomes":     "◆  AVAILABLE BIOMES",
		"adv.section.creatures":  "CREATURES",
		"adv.section.traps":      "TRAPS",
		"adv.section.blessings":  "BLESSINGS",
		"adv.section.ingredients":"INGREDIENTS",
		"adv.zone_max":           "Max zone: %s",
		"adv.mechanic_label":     "Mechanic: %s",
		"adv.mechanic_tt_title":  "Mechanic — %s",
		"adv.mechanic_locked":    "%s  —  Unlocked at Rare",
		"adv.mechanic_tt_locked": "Reach Rare to unlock this mechanic.",
		"adv.ingr.tooltip":       "Biome: %s\nIn stock: %d",
		"adv.trap.dmg_zones":     "Surface: 8%% HP  ·  Depths: 15%% HP  ·  Abyss: 30%% HP",
		"adv.trap.mastery_note":  "\nMastery reduces damage taken.",
		"adv.bless.desc":         "XP bonus and healing based on zone.\nMastery increases the effect.",
		"adv.creature.tt":        "Zone: %s\nMastery: %s",

		# ── Mécaniques fortes ─────────────────────────────────
		"mech.ambush.name":       "Ambush",
		"mech.ambush.desc":       "The creature strikes first.",
		"mech.poison.name":       "Poisoning",
		"mech.poison.desc":       "Each hero hit poisons the enemy (max 3).",
		"mech.endurcissement.name": "Hardening",
		"mech.endurcissement.desc": "Hero's damage reduced by 20% against biome creatures.",

		# ── CombatScene ──────────────────────────────────────
		"combat.end_btn":         "End expedition",
		"combat.xp_label":        "XP this cycle — 0",
		"combat.victory":         "— Victory —",
		"combat.defeat":          "— Defeat —",
		"combat.log.all":         "All",
		"combat.log.hero":        "Hero",
		"combat.log.monster":     "Monster",
		"combat.log.attack":      "Attack",
		"combat.log.defense":     "Defense",
		"combat.log.heal":        "Heal",
		"combat.log.status":      "Status",
		"combat.xp_label_fmt":    "XP this cycle — %d",
		"combat.bless.heal":      "+%d HP",
		"combat.bless.atk":       "+%d ATK (temporary)",
		"combat.bless.def":       "+%d DEF (temporary)",
		"combat.bless.xp":        "+%d%% XP this cycle",
		"combat.bless.unknown":   "Unknown effect",
		"combat.action.crit":     "Critical!",
		"combat.action.attack":   "Attack",
		"combat.poison":          "Poison",
		"combat.venom":           "Venom",
		"combat.venom_contact":   "Venom Contact",
		"combat.shield_absorb":   "Shield absorbs %d",
		"combat.shield_proc":     "Emergency shield activated",
		"combat.shield_pill":     "Shield +%d",
		"combat.regen":           "Regeneration +%d",
		"combat.unique_slain":    "Unique Creature slain — %s, %s",
		"combat.venom_pill":      "☠ Venom",
		"combat.ready_evolve":    "⬆ %s ready to evolve",

		# ── CycleSummaryScreen ───────────────────────────────
		"cycle.title":            "CYCLE ENDED  —  %s",
		"cycle.victory":          "Victory",
		"cycle.interrupted":      "Interrupted",
		"cycle.defeat":           "Defeat",
		"cycle.back_village":     "🏠  BACK TO VILLAGE",
		"cycle.section.discoveries": "◆  DISCOVERIES",
		"cycle.section.resources":   "◆  COLLECTED RESOURCES",
		"cycle.section.xp":          "◆  XP BREAKDOWN",
		"cycle.discovery.fragment":  "Memory Fragment",
		"cycle.discovery.unique":    "Unique Creature",
		"cycle.no_evolution":        "No evolution available",
		"cycle.encounters":          "Creatures encountered",
		"cycle.traps":               "Traps identified",
		"cycle.blessings":           "Blessings found",
		"cycle.section.evolutions":  "◆  AVAILABLE EVOLUTIONS",
		"cycle.xp_total":            "Total XP — %d",
		"cycle.hero_label":          "Hero",

		# ── Settings ─────────────────────────────────────────
		"settings.title":         "⚙  SETTINGS",
		"settings.audio":         "◆  AUDIO",
		"settings.music":         "Music",
		"settings.sfx":           "Sound FX",
		"settings.display":       "◆  DISPLAY",
		"settings.fullscreen":    "Fullscreen",
		"settings.save":          "◆  SAVE",
		"settings.export":        "📤  Export save",
		"settings.import":        "📥  Import save",
		"settings.language":      "◆  LANGUAGE",
		"settings.lang.fr":       "Français",
		"settings.lang.en":       "English",

		# ── Général ──────────────────────────────────────────
		"nav.back":               "← Village",
		"nav.back_tt":            "Return to the hub.",
	},
}

# Retourne la chaîne traduite pour la langue courante.
# Fallback : EN → FR → clé brute.
func T(key: String) -> String:
	var lang: String = GameSettings.language if GameSettings else "fr"
	var lang_dict: Dictionary = STRINGS.get(lang, {})
	if lang_dict.has(key):
		return lang_dict[key]
	var fr_dict: Dictionary = STRINGS.get("fr", {})
	if fr_dict.has(key):
		return fr_dict[key]
	return key

# Retourne la liste des tabs du journal de combat dans la langue courante.
func log_tabs() -> PackedStringArray:
	return PackedStringArray([
		T("combat.log.all"),   T("combat.log.hero"),   T("combat.log.monster"),
		T("combat.log.attack"),T("combat.log.defense"),T("combat.log.heal"),
		T("combat.log.status"),
	])

# Retourne le titre d'un panel (clé "hero", "adventure", etc.).
func panel_title(panel_id: String) -> String:
	return T("panel." + panel_id)

# Retourne le nom d'une mécanique forte traduit.
func mech_name(mech_id: String) -> String:
	return T("mech." + mech_id + ".name")

# Retourne la description d'une mécanique forte traduite.
func mech_desc(mech_id: String) -> String:
	return T("mech." + mech_id + ".desc")

# Retourne le nom d'une zone (0=Surface, 1=Profondeur/Depths, 2=Abysse/Abyss).
func zone_name(idx: int) -> String:
	return T("zone." + str(clampi(idx, 0, 2)))

# Retourne la description tooltip d'une zone.
func zone_tooltip(idx: int) -> String:
	return T("zone.tt." + str(clampi(idx, 0, 2)))

# Retourne le nom d'un slot d'équipement traduit (clé = slot_key: "arme", "anneau"…).
func equip_slot_name(slot_key: String) -> String:
	return T("hero.equip.slot." + slot_key)
