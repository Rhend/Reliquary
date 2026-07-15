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
		"tier.max_rank": "Palier Max atteint",
		"tier.max_level":"▲ Palier Max atteint",

		# ── Zones ────────────────────────────────────────────
		"zone.0": "Surface",
		"zone.1": "Profondeur",
		"zone.2": "Abysse",
		"zone.tt.0": "Première zone du biome.\n70 % combats · 15 % bénédictions · 15 % pièges\nCréature de Surface uniquement.\nPièges : 8 % de vos PV max.",
		"zone.tt.1": "Zone intermédiaire. Les dangers s'intensifient.\n70 % combats · 15 % bénédictions · 15 % pièges\nCréatures de Surface et de Profondeur.\nPièges : 15 % de vos PV max.",
		"zone.tt.2": "Zone finale. Aucun combat automatique.\n50 % bénédictions · 50 % pièges\nPièges : 30 % de vos PV max.\nLa créature Unique peut être affrontée ici.",

		# ── Panel titres (PANEL_TITLES) ───────────────────────
		"panel.hero":      "HÉROS",
		"panel.adventure": "EXPÉDITIONS",
		"panel.forge":     "FORGE",
		"panel.sanctuary": "SANCTUAIRE",
		"panel.relic":     "RELIQUE",
		"panel.tbd":       "?",

		# ── Menu items (MENU_ITEMS labels) ────────────────────
		"menu.hero":      "HÉROS",
		"menu.adventure": "EXPÉDITIONS",
		"menu.map":       "CARTE",
		"menu.forge":     "FORGE",
		"menu.sanctuary": "SANCTUAIRE",
		"menu.relic":     "RELIQUE",
		"menu.tbd":       "?",

		# ── Tooltips hexagones ────────────────────────────────
		"hex_tt.hero":      "Votre héros et ses passifs.\nConsultez ses équipements et sa progression.",
		"hex_tt.adventure": "Partez en expédition.\nChoisissez un biome et affrontez ses créatures.",
		"hex_tt.map":       "Carte holographique 3D.\nExplorez le secteur et sélectionnez un biome découvert.",
		"hex_tt.forge":     "Le Forgeron.\nAméliorez vos équipements avec les ingrédients récoltés.",
		"hex_tt.sanctuary": "Sanctuaire des Évolutions.\nFaites évoluer vos entités au rang supérieur.",
		"hex_tt.relic":     "Reliques anciennes.\nDébloquez des pouvoirs permanents rares.",
		"hex_tt.tbd":       "Mystère à venir...",

		# ── Éclosion ─────────────────────────────────────────
		"birth.phrase_25":  "Un battement…  puis un autre.  Quelque chose remue dans le noir.",
		"birth.phrase_50":  "Le long sommeil se déchire.  Mes souvenirs fuient comme l'eau entre mes doigts.",
		"birth.phrase_75":  "Un village, tout proche…  et des fragments de mémoire épars, alentour.",
		"birth.phrase_100": "Je ne sais plus qui je suis…\nmais je m'éveille.",
		"birth.flavor":     "Ranimez l'étincelle…  réveillez l'âme endormie.",
		"birth.whisper.1":  "Une lueur, là, tout au fond…",
		"birth.whisper.2":  "Des voix anciennes murmurent mon nom.",
		"birth.whisper.3":  "Le froid recule.  Quelque chose respire.",
		"birth.whisper.4":  "Des ombres glissent au bord du rêve.",
		"birth.whisper.5":  "Un souvenir affleure, puis se dérobe.",
		"birth.whisper.6":  "La terre frémit sous le long silence.",
		"birth.whisper.7":  "Quelqu'un m'attend tout près, je le sens.",
		"birth.whisper.8":  "Des braises rougeoient encore sous la cendre.",
		"birth.whisper.9":  "Le vide se peuple de chuchotements.",
		"birth.whisper.10": "Mes paupières pèsent comme des siècles.",

		# ── Hints contextuels ────────────────────────────────
		"hint.start":          "Partez en expédition pour gagner de l'XP et faire progresser vos entités",
		"hint.reach_rare":     "Faites atteindre le rang Rare à un biome pour libérer un Fragment de Mémoire",
		"hint.upgrade_ready":  "Le Village peut évoluer — utilisez le bouton au centre du hub",
		"hint.need_fragments": "Encore %d Fragment(s) de Mémoire — faites évoluer vos biomes (Rare, Légendaire, Unique)",

		# ── Conditions Village ────────────────────────────────
		"village.cond.fragments": "Fragments",
		"village.cond.header":    "▾  PROCHAIN PALIER  ▾",
		"village.cond.ready":     "✦  PRÊT À ÉVOLUER  ✦",
		"village.cond.kills":     "Créatures vaincues",
		"village.kills.tt_body":  "Le Village grandit TOUT SEUL. Premier palier : vaincre assez de créatures en expédition débloque la Forge (et active les drops). Aucun clic, aucun coût.\n\nVaincues : %d  ·  Requis pour le prochain palier : %d",
		"village.cond.buildings": "Bâtiments reconstruits",
		"village.buildings.tt_body": "Le Village grandit TOUT SEUL : il monte de palier dès qu'assez de bâtiments sont reconstruits (palier Commun ou plus), tous quartiers confondus. Aucun clic, aucun coût.\n\nReconstruits : %d  ·  Requis pour le prochain palier : %d",
		"village.frag.tt_title":  "Fragments de Mémoire",
		"village.frag.tt_body":   "Un biome libère un Fragment quand il atteint un nouveau jalon :\nRare, puis Légendaire, puis Unique.\nPartez en expédition pour faire gagner de l'XP à vos biomes,\npuis faites-les évoluer.\n\nCollectés : %d  ·  Requis pour le prochain palier : %d",
		"village.cond.xp":        "XP Village",
		"village.cond.hero_xp":   "Héros à XP max",
		"village.evolve_btn":     "Faire évoluer le Village",
		"village.tier_label":     "Village",
		"village.soon":           "✦  %s  ✦\n\nBientôt disponible",
		"village.fragment_freed": "🔮  Fragment libéré : %s",
		"village.biome_revealed": "✦  Nouveau biome révélé : %s  ✦",
		"village.equipment_unlocked": "⚔  Équipement obtenu : %s",

		# ── Génériques UI ────────────────────────────────────
		"ui.none": "Aucun",

		# ── Bouton Évoluer ────────────────────────────────────
		"btn.evolve":           "ÉVOLUER ▲",
		"evolve.tt_title":      "Évolution — %s",
		"evolve.tt_body":       "Rang %s  →  Rang %s\nAction définitive — déclenche le rituel d'ascension.",
		"village.evolve.tt_body": "Le Village atteint le rang %s —\nde nouvelles structures se débloquent autour de l'anneau.",
		"ritual.passive_unlocked": "Passif débloqué : %s",
		"ritual.new_tier":         "Nouveau palier atteint — Capacités améliorées",
		"ritual.eclosion_title":   "ÉCLOSION",
		"ritual.eclosion_text":    "Le Village a éclos ! Vous pouvez maintenant partir en expédition !",
		"ritual.village.2":        "Le Sanctuaire est accessible !",
		"ritual.village.3":        "La Relique est accessible !",
		"ritual.village.4":        "Le mystère ultime s'ouvre…",
		"ritual.village.default":  "Nouveau palier du Village !",

		# ── HeroPanel ────────────────────────────────────────
		"hero.section.stats":       "◆  STATISTIQUES",
		"hero.section.equip":       "◆  ÉQUIPEMENT",
		"hero.section.passives":    "◆  PASSIFS",
		"hero.section.ingredients": "◆  INGRÉDIENTS",
		"hero.stat.atk":            "ATK",
		"hero.stat.def":            "DEF",
		"hero.stat.hp":             "PV",
		"hero.stat.vit":            "VIT",
		"hero.stat.crit":           "CRIT",
		"hero.stat.atk_tt":         "Dégâts par coup : %d (normal) · %d (critique).",
		"hero.stat.def_tt":         "Réduit les dégâts subis de %d %%.",
		"hero.stat.hp_tt":          "Énergie vitale du héros. À 0, sa conscience s'éteint et se reforme au Village.",
		"hero.stat.vit_tt":         "Cadence d'attaque : %s frappes par seconde.",
		"hero.stat.crit_tt":        "Chance %d %% · Dégâts critiques ×%s\nDPS moyen +%d %%.",
		"hero.equip.placeholder":   "À débloquer",
		"hero.equip.placeholder_tt":"Équipement encore introuvable.\nFais progresser le biome %s pour le récupérer.",
		"hero.equip.slot.arme":     "Arme",
		"hero.equip.slot.anneau":   "Anneau",
		"hero.equip.slot.armure":   "Armure",
		"hero.equip.slot.ceinture": "Ceinture",
		"hero.equip.slot.bouclier": "Bouclier",
		"hero.equip.slot.talisman": "Talisman",
		"hero.forge_required":      "🔨  Forge Requise",
		"hero.forge_ready":         "🔨  Prêt à forger — rends-toi à la Forge",
		"hero.passive.unlock_hdr":  "— À DÉBLOQUER —",
		"hero.passive.tt_mastery":  "Maîtrise : %s",
		"hero.passive.tt_effect":   "\nEffet : %s",
		"hero.equip.tt_slot":       "Slot : %s  ·  Rang : %s",

		# ── ForgePanel ───────────────────────────────────────
		"forge.smith_locked":    "🔨  Le Forgeron\n\n« Je ne peux pas encore\nvous aider. »\n\nAmenez un biome au rang Rare\npour libérer un Fragment et\nfaire évoluer le Village.",
		"forge.section.ingr":   "◆  INGRÉDIENTS",
		"forge.section.equip":  "◆  ÉQUIPEMENT",
		"forge.ingr.unique":    "Ingrédient unique — une seule obtention.",
		"forge.ingr.tt_stock":  "Biome : %s\nEn stock : %d",
		"forge.equip.locked":   "🔒  %s  —  Monte %s au palier %s pour l'obtenir",
		"forge.equip.max_rank": "▲ Palier Max atteint",
		"forge.equip.low_xp":  "⧖  XP insuffisante — continuez l'aventure",
		"forge.equip.no_recipe":"Recette non définie",
		"forge.equip.forge_btn":"Forger",
		"forge.equip.tt_slot":  "Slot : %s  ·  Rang : %s",
		"forge.equip.tt_next":  "\n→ %s : %s",
		"forge.ingr.x_of_y":        "%d / %d",
		"forge.locked.title":       "LE FORGERON",
		"forge.locked.quote":       "« Je ne peux pas encore vous aider. »",
		"forge.locked.hint":        "Amenez un biome au rang Rare pour libérer\nun Fragment de Mémoire et faire évoluer le Village.",
		"forge.recipe.tt_stock":    "En stock : %d\nRequis : %d",
		"forge.equip.low_xp_pct":   "⧖  XP — %d %%  (continuez l'aventure)",
		"forge.equip.forge_unavail":      "Équipement pas encore prêt",
		"forge.equip.forge_tt_unavail":   "Remplissez la barre XP et réunissez les ingrédients.",

		# ── Forge — palier & arbre (Chantier 5) ──────────────
		"forge.points":          "Points de Forge : %d",
		"forge.evolve_btn":      "Faire évoluer",
		"forge.open_tree":       "Ouvrir l'arbre",
		"forge.tree_locked":     "L'arbre s'active au palier Peu Commun de l'équipement.",
		"forge.node.type.mineur":   "Mineur",
		"forge.node.type.notable":  "Notable",
		"forge.node.type.keystone": "Clé de voûte",
		"forge.node.strate":        "Strate %d",
		"forge.node.cost":          "Coût : %d pts",
		"forge.node.owned":         "Acquis",
		"forge.node.locked_strate":     "Requiert l'équipement au palier %d",
		"forge.node.locked_connexite":  "Nécessite un nœud voisin acquis",
		"forge.stat.atk":   "ATK",
		"forge.stat.def":   "DEF",
		"forge.stat.crit":  "critique",
		"forge.stat.atb":   "vitesse ATB",
		"forge.stat.hp":    "PV max",
		"forge.stat.regen": "régén",
		"forge.stat.drop":  "drop rare",
		"forge.effect.stat_pct":               "Bonus de stat annexe",
		"forge.effect.per_tier":               "Croît avec le palier de l'équipement",
		"forge.effect.crit_mult":              "+ multiplicateur de critique",
		"forge.effect.gauge_start":            "Jauge ATB de départ augmentée",
		"forge.effect.def_ignore":             "Ignore une part de la DEF ennemie",
		"forge.effect.cond_atk_hp_above":      "+ATK quand les PV sont hauts",
		"forge.effect.residual":               "Dégâts résiduels sur l'ennemi",
		"forge.effect.endurcissement_counter": "+dégâts contre l'Endurcissement",
		"forge.effect.ambush_negate":          "Annule le malus d'embuscade",
		"forge.effect.poison_stack_reduction": "−1 stack de venin subi",

		# ── AdventurePanel ───────────────────────────────────
		"adv.running.expedition": "Expédition en cours",
		"adv.biome_placeholder":  "Choisir un biome pour partir en expédition",
		"adv.start_btn":          "⚔   PARTIR EN EXPÉDITION",
		"adv.start_btn_named":    "⚔   PARTIR EN EXPÉDITION — %s",
		"adv.map_btn":            "🗺   CARTE",
		"adv.map_title":          "CARTE DES EXPÉDITIONS",
		"adv.map_hint":           "Sélectionnez un secteur découvert",
		"adv.combat_wip":         "⚒ Combat en refonte — expédition sans combats pour l'instant",
		"adv.section.biomes":     "◆  BIOMES DISPONIBLES",
		"adv.entities_count":     "Entités %d/%d",
		"adv.cat.creature":       "Créature",
		"adv.cat.trap":           "Piège",
		"adv.cat.blessing":       "Bénédiction",
		"adv.cat.ingredient":     "Ingrédient",
		"adv.cat.resource":       "Ressource",
		"adv.zone_max":           "Zone max : %s",
		"adv.mechanic_label":     "Mécanique : %s",
		"adv.mechanic_tt_title":  "Mécanique — %s",
		"adv.mechanic_locked":    "%s  —  Débloquée à Rare",
		"adv.mechanic_tt_locked": "Atteins Rare pour débloquer cette mécanique.",
		"adv.ingr.tooltip":       "Biome : %s\nEn stock : %d",
		"adv.next.title":         "Prochain palier — %s",
		"adv.next.fragment":      "Libère un Fragment de Mémoire",
		"adv.next.mechanic":      "Active la mécanique %s",
		"adv.next.zone":          "Débloque la zone %s",
		"adv.next.secondary":     "Révèle un nouveau biome",
		"adv.next.equipment":     "Octroie l'équipement du biome",
		"adv.next.tt":            "Gagnez de l'XP en expédition dans ce biome,\npuis utilisez le bouton ÉVOLUER quand sa barre est pleine.",
		"adv.trap.dmg_zones":     "Surface : 8 %% PV  ·  Profondeur : 15 %% PV  ·  Abysse : 30 %% PV",
		"adv.trap.mastery_note":  "\nMaîtrise réduit les dégâts subis.",
		"adv.bless.desc":         "Bonus XP et soins selon la zone.\nMaîtrise augmente l'effet reçu.",
		"adv.creature.tt":        "Zone : %s\nMaîtrise : %s",

		# ── Mécaniques fortes ─────────────────────────────────
		"mech.ambush.name":       "Embuscade",
		"mech.ambush.desc":       "La créature attaque en premier.",
		"mech.poison.name":       "Empoisonnement",
		"mech.poison.desc":       "Le marais toxique empoisonne le héros à chaque coup ennemi (3 max).",
		"mech.endurcissement.name": "Endurcissement",
		"mech.endurcissement.desc": "Dégâts du héros réduits de 20 % contre les créatures du biome.",

		# ── CombatScene ──────────────────────────────────────
		"combat.end_btn":         "Mettre fin à l'expédition",
		"combat.evolve_badge":    "▲ %d",
		"combat.evolve_tt_title": "Prêtes à évoluer (%d)",
		"combat.loot.title":      "Butin",
		"combat.loot.empty":      "rien pour l'instant",
		"combat.xp_float":        "+%d XP",
		"combat.xp_type.hero":      "Héros",
		"combat.xp_type.biome":     "Biome",
		"combat.xp_type.creature":  "Créature",
		"combat.xp_type.passive":   "Passif",
		"combat.xp_type.equipment": "Équipement",
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
		"combat.regen":           "Régénération +%d",
		"combat.unique_slain":    "Créature Unique vaincue — %s, %s",
		"combat.venom_pill":      "☠ Venin",
		"combat.haste_pill":      "Rapide",
		"combat.ready_evolve":    "⬆ %s prêt à évoluer",
		"combat.appears":         "%s apparaît",
		"combat.tt_stats":        "Rang : %s\nPV : %d  ·  ATK : %d  ·  DEF : %d",
		"combat.trap_tt":         "Piège  ·  Dégâts : %d",
		"combat.trap_ignored":    "\n(Ignoré — modificateur Fantôme)",
		"combat.bless_tt":        "Bénédiction\n%s",
		"combat.stinger.trap":      "▲  PIÈGE",
		"combat.stinger.bless":     "✦  BÉNÉDICTION",
		"combat.stinger.trap_dmg":  "−%d PV",
		"combat.stinger.ignored":   "Ignoré — modificateur Fantôme",
		"combat.unique_beaten":   "✔  %s a déjà été vaincu",
		"combat.unique_watches":  "☠  %s vous observe...",
		"combat.unique_fight":    "⚔  Affronter %s",
		"combat.unique_refight":  "⚔  Réaffronter %s",

		# ── UI de combat CTB (Rework Combat — chantier 5) ─────
		"ctb.attaquer":       "⚔  Attaquer",
		"ctb.defendre":       "🛡  Défendre",
		"ctb.choisir_cible":  "Choisir la cible :",
		"ctb.annuler":        "Annuler",
		"ctb.a_toi":          "Au tour de %s",
		"ctb.file_titre":     "Ordre d'action",
		"ctb.embuscade":      "⚡ EMBUSCADE !",
		"ctb.embuscade_sub":  "L'ennemi frappe le premier — initiative retardée",
		"ctb.victoire":       "VICTOIRE",
		"ctb.defaite":        "DÉFAITE",
		"ctb.continuer":      "Cliquer pour continuer",
		"ctb.garde_pill":     "🛡 Garde",
		"ctb.crit_float":     "%d CRIT !",
		"ctb.combat_titre":   "⚔  COMBAT",
		"ctb.recompenses":    "+%d XP   ·   +%d Euren",
		"ctb.entete_heros":   "Nv %d · XP %d/%d · Euren (run) %d",

		# ── CycleSummaryScreen ───────────────────────────────
		"cycle.title":            "EXPÉDITION TERMINÉE  —  %s",
		"cycle.banner_title":     "Retour au village",
		"cycle.back_village":     "🏠  RETOUR AU VILLAGE",
		"cycle.back_biome":       "⚔  RETOURNER DANS LE BIOME",
		"district.hero.title":      "Quartier du Héros",
		"panel.district_house":     "Maison",
		"panel.district_garden":    "Jardin",
		"panel.district_training":  "Entrainement",
		"district.forge.title":     "Quartier de la Forge",
		"panel.district_armurier":  "Armurier",
		"panel.district_forgeron":  "Forgeron",
		"panel.district_joaillier": "Joaillier",
		"panel.district_couturier": "Couturier",
		"district.adventure.title":   "Quartier d'Expédition",
		"panel.district_reliquaire":  "Reliquaire",
		"panel.district_tour":        "Tour de Guet",
		"panel.district_palissade":   "Palissade",

		# ── Bâtiments de quartier (Chantier 4) ───────────────
		"building.delabre":            "Délabré",
		"building.frozen":             "Gelé — étoffes indisponibles dans ces terres (post-VS).",
		"building.max_rank":           "▲ Palier Max atteint",
		"building.route.title":        "Route à reconstruire",
		"building.route.hint":         "Reconstruisez la route pour accéder à la couche gestion de ce quartier (ses bâtiments).",
		"building.route.forge_locked": "La route de la Forge se reconstruit une fois le hub Forge débloqué (Village Peu Commun).",
		"building.route.craftsmen_locked": "Pas encore d'artisans assez expérimentés, et rien ne se récolte avant la Forge. Reconstruire les routes s'ouvrira au Village Peu Commun.",
		"building.route.btn":          "Reconstruire la route",
		"building.bonuses.title":      "Bonus actifs",
		"building.bonuses.none":       "Reconstruisez ce bâtiment pour débloquer ses bonus.",
		"building.bonuses.registry":   "Registre des succès — récompenses à venir.",
		"building.upgrade.title":      "Améliorer → %s",
		"building.upgrade.btn":        "Améliorer le bâtiment",

		# ── Bonus de village par canal (Chantier 4) ──────────
		"village.bonus.atk_pct":                        "ATK +%d%%",
		"village.bonus.def_pct":                        "DEF +%d%%",
		"village.bonus.hp_max_pct":                     "PV max +%d%%",
		"village.bonus.crit_pct":                       "Critique +%d%%",
		"village.bonus.regen_pct":                      "Régén PV entre événements +%d%%",
		"village.bonus.xp_distributed_pct":             "XP distribuée +%d%%",
		"village.bonus.bless_effect_pct":               "Effet des bénédictions +%d%%",
		"village.bonus.drop_rare_pct":                  "Drop de ressource rare +%d%%",
		"village.bonus.ambush_gauge_start_pct":         "Jauge ATB de départ sous embuscade : %d%%",
		"village.bonus.all_expedition_gauge_start_pct": "Jauge ATB de départ (toute expédition) : %d%%",
		"village.bonus.ignore_first_lethal":            "Annule le 1er coup létal de l'expédition (PV à 1)",
		"village.bonus.debuff_start_reduction":         "−%d stack de debuff subi",
		"village.bonus.debuff_immunity_tier":           "Immunité aux debuffs des créatures ≤ %s",
		"village.bonus.bless_antidote_extra":           "Les antidotes retirent +%d debuff",
		"village.bonus.forge_points_reduction_arme":    "−%d%% coût en points de Forge (Arme)",
		"village.bonus.forge_points_reduction_armure":  "−%d%% coût en points de Forge (Armure)",
		"village.bonus.forge_points_reduction_anneau":  "−%d%% coût en points de Forge (Anneau)",
		"village.bonus.forge_xp_reduction_arme":        "−%d%% XP requise (Arme)",
		"village.bonus.forge_xp_reduction_armure":      "−%d%% XP requise (Armure)",
		"village.bonus.forge_xp_reduction_anneau":      "−%d%% XP requise (Anneau)",
		"district.reveal.tt_title": "Point d'énergie",
		"district.reveal.tt_body":  "Cliquez pour révéler : %s",
		"cycle.section.discoveries": "◆  DÉCOUVERTES",
		"cycle.section.resources":   "◆  RESSOURCES COLLECTÉES",
		"cycle.section.xp":          "◆  RÉPARTITION XP",
		"cycle.discovery.new":           "★ NOUVEAU",
		"cycle.discovery.unique_beaten": "Créature unique vaincue",
		"cycle.section.evolutions":  "◆  ÉVOLUTIONS DISPONIBLES",
		"cycle.xp_total":            "XP total — %d",
		"cycle.hero_label":          "Héros",
		"cycle.stat.combats":        "Combats",
		"cycle.stat.events":         "Événements",
		"cycle.stat.loot":           "Ingrédients",
		"cycle.stat.xp":             "XP totale",

		# ── Settings ─────────────────────────────────────────
		"settings.title":         "⚙  PARAMÈTRES",
		"settings.audio":         "◆  AUDIO",
		"settings.music":         "Musique",
		"settings.sfx":           "Bruitage",
		"settings.display":       "◆  AFFICHAGE",
		"settings.fullscreen":    "Plein Écran",
		"settings.save":          "◆  SAUVEGARDE",
		"settings.export":        "📤  Export",
		"settings.import":        "📥  Import",
		"settings.language":      "◆  LANGUE",
		"settings.lang.fr":       "Français",
		"settings.lang.en":       "English",
		"settings.quit":          "⏻  Sauvegarder et quitter",

		# ── Message d'accueil (WelcomeOverlay) ────────────────
		"welcome.title": "Bienvenue dans IdleEvolution",
		"welcome.body": "Ici, [b]tout peut évoluer[/b] — vos alliés comme vos ennemis. C'est le cœur du jeu : chaque créature, chaque équipement, chaque biome grandit, mue et se transforme à mesure que vous avancez.\n\nCe que vous découvrez aujourd'hui est un [b]prototype[/b] (proof of concept) : les fondations d'une expérience que je veux rendre vraiment captivante.\n\nPour y arriver, j'ai besoin de votre regard. [b]Le moindre retour compte[/b] — ce qui vous plaît, ce qui vous perd, ce qui vous donne envie de continuer ou de tout lâcher. Jouez, explorez, et dites-moi tout.\n\nBonne évolution.",
		"welcome.dont_show": "Je ne veux plus voir ce message",
		"welcome.start": "Commencer l'aventure",

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
		"tier.max_rank": "Max Tier Reached",
		"tier.max_level":"▲ Max Tier Reached",

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
		"menu.map":       "MAP",
		"menu.forge":     "FORGE",
		"menu.sanctuary": "SANCTUARY",
		"menu.relic":     "RELIC",
		"menu.tbd":       "?",

		# ── Tooltips hexagones ────────────────────────────────
		"hex_tt.hero":      "Your hero and their passives.\nCheck equipment and progression.",
		"hex_tt.adventure": "Go on an expedition.\nChoose a biome and face its creatures.",
		"hex_tt.map":       "3D holographic map.\nExplore the sector and select a discovered biome.",
		"hex_tt.forge":     "The Blacksmith.\nUpgrade your gear using collected ingredients.",
		"hex_tt.sanctuary": "Evolution Sanctuary.\nEvolve your entities to the next rank.",
		"hex_tt.relic":     "Ancient Relics.\nUnlock rare permanent powers.",
		"hex_tt.tbd":       "Mystery ahead...",

		# ── Éclosion ─────────────────────────────────────────
		"birth.phrase_25":  "A heartbeat… then another.  Something stirs in the dark.",
		"birth.phrase_50":  "The long sleep tears apart.  My memories slip like water through my fingers.",
		"birth.phrase_75":  "A village, close by…  and scattered memory fragments all around.",
		"birth.phrase_100": "I no longer know who I am…\nbut I am waking.",
		"birth.flavor":     "Rekindle the spark…  awaken the sleeping soul.",
		"birth.whisper.1":  "A glimmer, there, deep down below…",
		"birth.whisper.2":  "Ancient voices murmur my forgotten name.",
		"birth.whisper.3":  "The cold recedes.  Something breathes nearby.",
		"birth.whisper.4":  "Shadows drift at the dream's edge.",
		"birth.whisper.5":  "A memory surfaces, then slips away.",
		"birth.whisper.6":  "The earth trembles beneath long silence.",
		"birth.whisper.7":  "Someone awaits me, close — I feel it.",
		"birth.whisper.8":  "Embers still glow beneath the ash.",
		"birth.whisper.9":  "The void fills with soft whispers.",
		"birth.whisper.10": "My eyelids weigh like passing centuries.",

		# ── Hints contextuels ────────────────────────────────
		"hint.start":          "Go on an expedition to gain XP and progress your entities",
		"hint.reach_rare":     "Bring a biome to Rare rank to free a Memory Fragment",
		"hint.upgrade_ready":  "The Village can evolve — use the button at the center of the hub",
		"hint.need_fragments": "%d more Memory Fragment(s) — evolve your biomes (Rare, Legendary, Unique)",

		# ── Conditions Village ────────────────────────────────
		"village.cond.fragments": "Fragments",
		"village.cond.header":    "▾  NEXT TIER  ▾",
		"village.cond.ready":     "✦  READY TO EVOLVE  ✦",
		"village.cond.kills":     "Creatures defeated",
		"village.kills.tt_body":  "The Village grows ON ITS OWN. First tier: defeating enough creatures on expeditions unlocks the Forge (and activates drops). No click, no cost.\n\nDefeated: %d  ·  Required for the next tier: %d",
		"village.cond.buildings": "Buildings rebuilt",
		"village.buildings.tt_body": "The Village grows ON ITS OWN: it ranks up as soon as enough buildings are rebuilt (Common tier or higher), across all quarters. No click, no cost.\n\nRebuilt: %d  ·  Required for the next tier: %d",
		"village.frag.tt_title":  "Memory Fragments",
		"village.frag.tt_body":   "A biome frees a Fragment when it reaches a new milestone:\nRare, then Legendary, then Unique.\nGo on expeditions to earn XP for your biomes,\nthen evolve them.\n\nCollected: %d  ·  Required for the next tier: %d",
		"village.cond.xp":        "Village XP",
		"village.cond.hero_xp":   "Hero at max XP",
		"village.evolve_btn":     "Evolve the Village",
		"village.tier_label":     "Village",
		"village.soon":           "✦  %s  ✦\n\nComing soon",
		"village.fragment_freed": "🔮  Fragment freed: %s",
		"village.biome_revealed": "✦  New biome revealed: %s  ✦",
		"village.equipment_unlocked": "⚔  Equipment obtained: %s",

		# ── Generic UI ───────────────────────────────────────
		"ui.none": "None",

		# ── Bouton Évoluer ────────────────────────────────────
		"btn.evolve":           "EVOLVE ▲",
		"evolve.tt_title":      "Evolution — %s",
		"evolve.tt_body":       "Rank %s  →  Rank %s\nPermanent — triggers the ascension ritual.",
		"village.evolve.tt_body": "The Village reaches %s rank —\nnew structures unlock around the ring.",
		"ritual.passive_unlocked": "Passive unlocked: %s",
		"ritual.new_tier":         "New rank reached — Improved abilities",
		"ritual.eclosion_title":   "HATCHING",
		"ritual.eclosion_text":    "The Village has hatched! You can now set out on expeditions!",
		"ritual.village.2":        "The Sanctuary is now accessible!",
		"ritual.village.3":        "The Relic is now accessible!",
		"ritual.village.4":        "The final mystery opens…",
		"ritual.village.default":  "New Village tier!",

		# ── HeroPanel ────────────────────────────────────────
		"hero.section.stats":       "◆  STATISTICS",
		"hero.section.equip":       "◆  EQUIPMENT",
		"hero.section.passives":    "◆  PASSIVES",
		"hero.section.ingredients": "◆  INGREDIENTS",
		"hero.stat.atk":            "ATK",
		"hero.stat.def":            "DEF",
		"hero.stat.hp":             "HP",
		"hero.stat.vit":            "SPD",
		"hero.stat.crit":           "CRIT",
		"hero.stat.atk_tt":         "Damage per hit: %d (normal) · %d (crit).",
		"hero.stat.def_tt":         "Reduces incoming damage by %d%%.",
		"hero.stat.hp_tt":          "The hero's life force. At 0, his consciousness fades and reforms at the Village.",
		"hero.stat.vit_tt":         "Attack rate: %s strikes per second.",
		"hero.stat.crit_tt":        "Chance %d%% · Crit damage ×%s\nAverage DPS +%d%%.",
		"hero.equip.placeholder":   "Locked",
		"hero.equip.placeholder_tt":"Equipment not found yet.\nProgress the %s biome to retrieve it.",
		"hero.equip.slot.arme":     "Weapon",
		"hero.equip.slot.anneau":   "Ring",
		"hero.equip.slot.armure":   "Armor",
		"hero.equip.slot.ceinture": "Belt",
		"hero.equip.slot.bouclier": "Shield",
		"hero.equip.slot.talisman": "Talisman",
		"hero.forge_required":      "🔨  Forge Required",
		"hero.forge_ready":         "🔨  Ready to forge — head to the Forge",
		"hero.passive.unlock_hdr":  "— TO UNLOCK —",
		"hero.passive.tt_mastery":  "Mastery: %s",
		"hero.passive.tt_effect":   "\nEffect: %s",
		"hero.equip.tt_slot":       "Slot: %s  ·  Rank: %s",

		# ── ForgePanel ───────────────────────────────────────
		"forge.smith_locked":    "🔨  The Blacksmith\n\n« I can't help you\njust yet. »\n\nBring a biome to Rare rank\nto free a Fragment and\nevolve the Village.",
		"forge.section.ingr":   "◆  INGREDIENTS",
		"forge.section.equip":  "◆  EQUIPMENT",
		"forge.ingr.unique":    "Unique ingredient — only one obtainable.",
		"forge.ingr.tt_stock":  "Biome: %s\nIn stock: %d",
		"forge.equip.locked":   "🔒  %s  —  Raise %s to %s rank to obtain it",
		"forge.equip.max_rank": "▲ Max Tier Reached",
		"forge.equip.low_xp":  "⧖  Insufficient XP — continue adventuring",
		"forge.equip.no_recipe":"Recipe not defined",
		"forge.equip.forge_btn":"Forge",
		"forge.equip.tt_slot":  "Slot: %s  ·  Rank: %s",
		"forge.equip.tt_next":  "\n→ %s: %s",
		"forge.ingr.x_of_y":        "%d / %d",
		"forge.locked.title":       "THE BLACKSMITH",
		"forge.locked.quote":       "« I can't help you just yet. »",
		"forge.locked.hint":        "Bring a biome to Rare rank to free\na Memory Fragment and evolve the Village.",
		"forge.recipe.tt_stock":    "In stock: %d\nRequired: %d",
		"forge.equip.low_xp_pct":   "⧖  XP — %d%%  (keep adventuring)",
		"forge.equip.forge_unavail":      "Equipment not ready yet",
		"forge.equip.forge_tt_unavail":   "Fill the XP bar and gather the required ingredients.",

		# ── Forge — tier & tree (Chantier 5) ─────────────────
		"forge.points":          "Forge points: %d",
		"forge.evolve_btn":      "Evolve",
		"forge.open_tree":       "Open tree",
		"forge.tree_locked":     "The tree activates at the equipment's Uncommon tier.",
		"forge.node.type.mineur":   "Minor",
		"forge.node.type.notable":  "Notable",
		"forge.node.type.keystone": "Keystone",
		"forge.node.strate":        "Tier %d",
		"forge.node.cost":          "Cost: %d pts",
		"forge.node.owned":         "Owned",
		"forge.node.locked_strate":     "Requires equipment at tier %d",
		"forge.node.locked_connexite":  "Requires an adjacent node",
		"forge.stat.atk":   "ATK",
		"forge.stat.def":   "DEF",
		"forge.stat.crit":  "crit",
		"forge.stat.atb":   "ATB speed",
		"forge.stat.hp":    "Max HP",
		"forge.stat.regen": "regen",
		"forge.stat.drop":  "rare drop",
		"forge.effect.stat_pct":               "Secondary stat bonus",
		"forge.effect.per_tier":               "Scales with equipment tier",
		"forge.effect.crit_mult":              "+ crit multiplier",
		"forge.effect.gauge_start":            "Higher starting ATB gauge",
		"forge.effect.def_ignore":             "Ignores part of enemy DEF",
		"forge.effect.cond_atk_hp_above":      "+ATK while HP is high",
		"forge.effect.residual":               "Residual damage on the enemy",
		"forge.effect.endurcissement_counter": "+damage vs Hardening",
		"forge.effect.ambush_negate":          "Negates the ambush penalty",
		"forge.effect.poison_stack_reduction": "−1 venom stack suffered",

		# ── AdventurePanel ───────────────────────────────────
		"adv.running.expedition": "Expedition in progress",
		"adv.biome_placeholder":  "Choose a biome to start an expedition",
		"adv.start_btn":          "⚔   START EXPEDITION",
		"adv.start_btn_named":    "⚔   START EXPEDITION — %s",
		"adv.map_btn":            "🗺   MAP",
		"adv.map_title":          "EXPEDITION MAP",
		"adv.map_hint":           "Select a discovered sector",
		"adv.combat_wip":         "⚒ Combat rework in progress — expeditions run without combats for now",
		"adv.section.biomes":     "◆  AVAILABLE BIOMES",
		"adv.entities_count":     "Entities %d/%d",
		"adv.cat.creature":       "Creature",
		"adv.cat.trap":           "Trap",
		"adv.cat.blessing":       "Blessing",
		"adv.cat.ingredient":     "Ingredient",
		"adv.cat.resource":       "Resource",
		"adv.zone_max":           "Max zone: %s",
		"adv.mechanic_label":     "Mechanic: %s",
		"adv.mechanic_tt_title":  "Mechanic — %s",
		"adv.mechanic_locked":    "%s  —  Unlocked at Rare",
		"adv.mechanic_tt_locked": "Reach Rare to unlock this mechanic.",
		"adv.ingr.tooltip":       "Biome: %s\nIn stock: %d",
		"adv.next.title":         "Next rank — %s",
		"adv.next.fragment":      "Frees a Memory Fragment",
		"adv.next.mechanic":      "Activates the %s mechanic",
		"adv.next.zone":          "Unlocks the %s zone",
		"adv.next.secondary":     "Reveals a new biome",
		"adv.next.equipment":     "Grants the biome's equipment",
		"adv.next.tt":            "Earn XP on expeditions in this biome,\nthen use the EVOLVE button when its bar is full.",
		"adv.trap.dmg_zones":     "Surface: 8%% HP  ·  Depths: 15%% HP  ·  Abyss: 30%% HP",
		"adv.trap.mastery_note":  "\nMastery reduces damage taken.",
		"adv.bless.desc":         "XP bonus and healing based on zone.\nMastery increases the effect.",
		"adv.creature.tt":        "Zone: %s\nMastery: %s",

		# ── Mécaniques fortes ─────────────────────────────────
		"mech.ambush.name":       "Ambush",
		"mech.ambush.desc":       "The creature strikes first.",
		"mech.poison.name":       "Poisoning",
		"mech.poison.desc":       "The toxic swamp poisons the hero on each enemy hit (max 3).",
		"mech.endurcissement.name": "Hardening",
		"mech.endurcissement.desc": "Hero's damage reduced by 20% against biome creatures.",

		# ── CombatScene ──────────────────────────────────────
		"combat.end_btn":         "End expedition",
		"combat.evolve_badge":    "▲ %d",
		"combat.evolve_tt_title": "Ready to evolve (%d)",
		"combat.loot.title":      "Loot",
		"combat.loot.empty":      "nothing yet",
		"combat.xp_float":        "+%d XP",
		"combat.xp_type.hero":      "Hero",
		"combat.xp_type.biome":     "Biome",
		"combat.xp_type.creature":  "Creature",
		"combat.xp_type.passive":   "Passive",
		"combat.xp_type.equipment": "Equipment",
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
		"combat.regen":           "Regeneration +%d",
		"combat.unique_slain":    "Unique Creature slain — %s, %s",
		"combat.venom_pill":      "☠ Venom",
		"combat.haste_pill":      "Haste",
		"combat.ready_evolve":    "⬆ %s ready to evolve",
		"combat.appears":         "%s appears",
		"combat.tt_stats":        "Rank: %s\nHP: %d  ·  ATK: %d  ·  DEF: %d",
		"combat.trap_tt":         "Trap  ·  Damage: %d",
		"combat.trap_ignored":    "\n(Ignored — Ghost modifier)",
		"combat.bless_tt":        "Blessing\n%s",
		"combat.stinger.trap":      "▲  TRAP",
		"combat.stinger.bless":     "✦  BLESSING",
		"combat.stinger.trap_dmg":  "−%d HP",
		"combat.stinger.ignored":   "Ignored — Ghost modifier",
		"combat.unique_beaten":   "✔  %s has already been defeated",
		"combat.unique_watches":  "☠  %s is watching you...",
		"combat.unique_fight":    "⚔  Fight %s",
		"combat.unique_refight":  "⚔  Fight %s again",

		# ── UI de combat CTB (Rework Combat — chantier 5) ─────
		"ctb.attaquer":       "⚔  Attack",
		"ctb.defendre":       "🛡  Defend",
		"ctb.choisir_cible":  "Choose a target:",
		"ctb.annuler":        "Cancel",
		"ctb.a_toi":          "%s's turn",
		"ctb.file_titre":     "Action order",
		"ctb.embuscade":      "⚡ AMBUSH!",
		"ctb.embuscade_sub":  "The enemy strikes first — initiative delayed",
		"ctb.victoire":       "VICTORY",
		"ctb.defaite":        "DEFEAT",
		"ctb.continuer":      "Click to continue",
		"ctb.garde_pill":     "🛡 Guard",
		"ctb.crit_float":     "%d CRIT!",
		"ctb.combat_titre":   "⚔  BATTLE",
		"ctb.recompenses":    "+%d XP   ·   +%d Euren",
		"ctb.entete_heros":   "Lv %d · XP %d/%d · Euren (run) %d",

		# ── CycleSummaryScreen ───────────────────────────────
		"cycle.title":            "EXPEDITION ENDED  —  %s",
		"cycle.banner_title":     "Back to the village",
		"cycle.back_village":     "🏠  BACK TO VILLAGE",
		"cycle.back_biome":       "⚔  RETURN TO BIOME",
		"district.hero.title":      "Hero's District",
		"panel.district_house":     "House",
		"panel.district_garden":    "Garden",
		"panel.district_training":  "Training",
		"district.forge.title":     "Forge District",
		"panel.district_armurier":  "Armorer",
		"panel.district_forgeron":  "Blacksmith",
		"panel.district_joaillier": "Jeweler",
		"panel.district_couturier": "Tailor",
		"district.adventure.title":   "Expedition District",
		"panel.district_reliquaire":  "Reliquary",
		"panel.district_tour":        "Watchtower",
		"panel.district_palissade":   "Palisade",

		# ── Quarter buildings (Chantier 4) ───────────────────
		"building.delabre":            "Derelict",
		"building.frozen":             "Frozen — fabrics unavailable in these lands (post-VS).",
		"building.max_rank":           "▲ Max rank reached",
		"building.route.title":        "Road to rebuild",
		"building.route.hint":         "Rebuild the road to access this quarter's management layer (its buildings).",
		"building.route.forge_locked": "The Forge road can be rebuilt once the Forge hub is unlocked (Village Uncommon).",
		"building.route.craftsmen_locked": "No craftsmen experienced enough yet, and nothing is harvested before the Forge. Rebuilding roads opens at Village Uncommon.",
		"building.route.btn":          "Rebuild the road",
		"building.bonuses.title":      "Active bonuses",
		"building.bonuses.none":       "Rebuild this building to unlock its bonuses.",
		"building.bonuses.registry":   "Hall of deeds — rewards to come.",
		"building.upgrade.title":      "Upgrade → %s",
		"building.upgrade.btn":        "Upgrade building",

		# ── Village bonuses by channel (Chantier 4) ──────────
		"village.bonus.atk_pct":                        "ATK +%d%%",
		"village.bonus.def_pct":                        "DEF +%d%%",
		"village.bonus.hp_max_pct":                     "Max HP +%d%%",
		"village.bonus.crit_pct":                       "Crit +%d%%",
		"village.bonus.regen_pct":                      "HP regen between events +%d%%",
		"village.bonus.xp_distributed_pct":             "Distributed XP +%d%%",
		"village.bonus.bless_effect_pct":               "Blessing effect +%d%%",
		"village.bonus.drop_rare_pct":                  "Rare resource drop +%d%%",
		"village.bonus.ambush_gauge_start_pct":         "Starting ATB gauge under ambush: %d%%",
		"village.bonus.all_expedition_gauge_start_pct": "Starting ATB gauge (every expedition): %d%%",
		"village.bonus.ignore_first_lethal":            "Negates the expedition's first lethal hit (HP to 1)",
		"village.bonus.debuff_start_reduction":         "−%d debuff stack suffered",
		"village.bonus.debuff_immunity_tier":           "Immune to debuffs from creatures ≤ %s",
		"village.bonus.bless_antidote_extra":           "Antidotes remove +%d debuff",
		"village.bonus.forge_points_reduction_arme":    "−%d%% Forge point cost (Weapon)",
		"village.bonus.forge_points_reduction_armure":  "−%d%% Forge point cost (Armor)",
		"village.bonus.forge_points_reduction_anneau":  "−%d%% Forge point cost (Ring)",
		"village.bonus.forge_xp_reduction_arme":        "−%d%% XP required (Weapon)",
		"village.bonus.forge_xp_reduction_armure":      "−%d%% XP required (Armor)",
		"village.bonus.forge_xp_reduction_anneau":      "−%d%% XP required (Ring)",
		"district.reveal.tt_title": "Energy point",
		"district.reveal.tt_body":  "Click to reveal: %s",
		"cycle.section.discoveries": "◆  DISCOVERIES",
		"cycle.section.resources":   "◆  COLLECTED RESOURCES",
		"cycle.section.xp":          "◆  XP BREAKDOWN",
		"cycle.discovery.new":           "★ NEW",
		"cycle.discovery.unique_beaten": "Unique creature defeated",
		"cycle.section.evolutions":  "◆  AVAILABLE EVOLUTIONS",
		"cycle.xp_total":            "Total XP — %d",
		"cycle.hero_label":          "Hero",
		"cycle.stat.combats":        "Battles",
		"cycle.stat.events":         "Events",
		"cycle.stat.loot":           "Ingredients",
		"cycle.stat.xp":             "Total XP",

		# ── Settings ─────────────────────────────────────────
		"settings.title":         "⚙  SETTINGS",
		"settings.audio":         "◆  AUDIO",
		"settings.music":         "Music",
		"settings.sfx":           "Sound FX",
		"settings.display":       "◆  DISPLAY",
		"settings.fullscreen":    "Fullscreen",
		"settings.save":          "◆  SAVE",
		"settings.export":        "📤  Export",
		"settings.import":        "📥  Import",
		"settings.language":      "◆  LANGUAGE",
		"settings.lang.fr":       "Français",
		"settings.lang.en":       "English",
		"settings.quit":          "⏻  Save and quit",

		# ── Message d'accueil (WelcomeOverlay) ────────────────
		"welcome.title": "Welcome to IdleEvolution",
		"welcome.body": "Here, [b]everything can evolve[/b] — your allies as much as your enemies. That's the heart of the game: every creature, every piece of gear, every biome grows, morphs and transforms as you progress.\n\nWhat you're discovering today is a [b]prototype[/b] (proof of concept): the foundations of an experience I want to make truly captivating.\n\nTo get there, I need your eyes on it. [b]Every bit of feedback matters[/b] — what you enjoy, what loses you, what makes you want to keep going or quit. Play, explore, and tell me everything.\n\nHappy evolving.",
		"welcome.dont_show": "Don't show this message again",
		"welcome.start": "Begin the adventure",

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

# Libellé court du type d'entité réceptrice (XP flottante de combat).
# Passif unique regroupé avec les passifs. Vide pour un type non pertinent.
func entity_type_label(entity_type: String) -> String:
	match entity_type:
		Enums.EntityType.HERO:      return T("combat.xp_type.hero")
		Enums.EntityType.BIOME:     return T("combat.xp_type.biome")
		Enums.EntityType.CREATURE:  return T("combat.xp_type.creature")
		Enums.EntityType.PASSIVE, Enums.EntityType.PASSIF_UNIQUE: return T("combat.xp_type.passive")
		Enums.EntityType.EQUIPMENT: return T("combat.xp_type.equipment")
		_:                          return ""

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

# Nom d'affichage localisé d'une entité (dict GameData ou entrée de pool),
# au palier de Maîtrise COURANT de l'entité. TOUJOURS passer par ici pour
# afficher un nom d'entité — jamais lire nom_affichage_fr directement dans l'UI.
func entity_name(entity: Dictionary, fallback: String = "?") -> String:
	return entity_name_at(entity, int(entity.get("maitrise_actuelle", 0)), fallback)

# Nom d'affichage localisé AU PALIER DONNÉ : cherche dans noms_par_palier_*
# (palier exact, sinon le plus proche en dessous — même sémantique que
# stats_at_tier), puis retombe sur nom_affichage_* / `name` (passifs) /
# fallback. Sert quand le palier affiché n'est pas le palier courant
# (ex. rituel d'ascension : nom d'avant → nom d'après).
func entity_name_at(entity: Dictionary, tier: int, fallback: String = "?") -> String:
	var lang: String = GameSettings.language if GameSettings else "fr"
	var per_tier_keys: Array[String] = ["noms_par_palier_fr"]
	if lang == "en":
		per_tier_keys = ["noms_par_palier_en", "noms_par_palier_fr"]
	for key in per_tier_keys:
		var per_tier := entity.get(key, {}) as Dictionary
		if per_tier.is_empty():
			continue
		var t := tier
		while t >= 0:
			if per_tier.has(t):
				var n := str(per_tier[t])
				if not n.is_empty():
					return n
			t -= 1
	if lang == "en":
		var en := str(entity.get("nom_affichage_en", ""))
		if not en.is_empty():
			return en
	var fr := str(entity.get("nom_affichage_fr", ""))
	if not fr.is_empty():
		return fr
	var n := str(entity.get("name", ""))
	if not n.is_empty():
		return n
	return fallback

# Lore localisé d'une entité, au palier de Maîtrise COURANT (comme entity_name).
func entity_lore(entity: Dictionary) -> String:
	return entity_lore_at(entity, int(entity.get("maitrise_actuelle", 0)))

# Lore localisé AU PALIER DONNÉ : cherche dans lore_par_palier_* (palier exact,
# sinon le plus proche en dessous — même sémantique que entity_name_at), puis
# retombe sur lore_en/lore_fr. Permet un texte narratif différent par évolution.
func entity_lore_at(entity: Dictionary, tier: int) -> String:
	var lang: String = GameSettings.language if GameSettings else "fr"
	var per_tier_keys: Array[String] = ["lore_par_palier_fr"]
	if lang == "en":
		per_tier_keys = ["lore_par_palier_en", "lore_par_palier_fr"]
	for key in per_tier_keys:
		var per_tier := entity.get(key, {}) as Dictionary
		if per_tier.is_empty():
			continue
		var t := tier
		while t >= 0:
			if per_tier.has(t):
				var l := str(per_tier[t])
				if not l.is_empty():
					return l
			t -= 1
	if lang == "en":
		var en := str(entity.get("lore_en", ""))
		if not en.is_empty():
			return en
	return str(entity.get("lore_fr", ""))

# Description localisée d'un effet de passif (dict des tier_effects) —
# description_en si langue EN et champ rempli, sinon description (FR).
func effect_desc(effect: Dictionary) -> String:
	var lang: String = GameSettings.language if GameSettings else "fr"
	if lang == "en":
		var en := str(effect.get("description_en", ""))
		if not en.is_empty():
			return en
	return str(effect.get("description", ""))
