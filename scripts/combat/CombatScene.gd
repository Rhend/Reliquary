# ============================================================
# CombatScene — Scène de combat (refonte UI).
#
# Layout :
#   Zone combat : colonne Héros (gauche) ↔ colonne Ennemi (droite),
#                 séparées par un séparateur diagonal "VS".
#                 Chaque colonne : nom · double anneau (cooldown + PV)
#                 · pill d'action · pills d'états.
#   Feed passifs : bande de pills transitoires.
#   Journal      : log filtrable par onglets (Tout/Héros/Monstre/…).
#   Barre de bas : "XP ce cycle — X"  ·  bouton fin d'expédition.
#
# La logique de combat (CombatPlayer / CombatResolver / AdventureSystem)
# n'est pas modifiée : la scène ne fait que présenter les signaux.
# ============================================================
class_name CombatScene extends Control

# ─── Journal de combat (DÉSACTIVÉ) ───────────────────────────
# Jugé peu utile au playtest : l'espace qu'il occupait est rendu à la
# zone de combat (les anneaux s'agrandissent automatiquement).
# Tout le code du journal est conservé et compile toujours :
# remettre LOG_ENABLED à true suffit pour le réactiver.
const LOG_ENABLED := false

# ─── Nœuds racine ────────────────────────────────────────────
var _shaker: Control          # conteneur décalé pour le shake d'écran
var _hero_bg:     BiomeBackground   # fond ambiance Ville (côté héros, gauche)
var _creature_bg: BiomeBackground   # fond ambiance biome (côté créature, droite)

# ─── Combattants ─────────────────────────────────────────────
# Barres JRPG (bande basse de l'arène) : nom + PV chiffrés + jauge ATB.
# Remplacent le double anneau (CombatRing). L'espace central de l'arène est
# libéré (futur : boule d'énergie + personnages).
var _hero_bar:    CombatBar
var _enemy_bar:   CombatBar
# Boules d'énergie (centre de chaque moitié) : proxys de combattant teintés à la
# rareté, animés par les steps de combat. Remplaçables par les persos dessinés.
var _hero_fighter:  CombatFighter
var _enemy_fighter: CombatFighter
var _hero_name:   Label           # = _hero_bar.name_label (réf. pour .text + tooltip)
var _enemy_name:  Label
var _hero_action: Label
var _enemy_action: Label
var _hero_states: HBoxContainer
var _enemy_states: HBoxContainer

# ─── Encadrés de caractéristiques (coins de la zone de combat) ──
# Héros en haut à gauche (visible toute l'expédition), créature en haut à
# droite (visible seulement en combat de créature). Masqués pour les
# pièges/bénédictions, dont l'effet est déjà annoncé au centre (stinger).
var _stats := CombatStats.new()           # encadrés de stats héros/créature (extrait)

# ─── Journal ─────────────────────────────────────────────────
var _log := CombatLog.new()           # journal à onglets (concern extrait)

# ─── Barre de bas ────────────────────────────────────────────
var _xp_label: Label
var _flee_btn: Button

# ─── Compteur « prêtes à évoluer » (badge sur le bouton fin) ──
# Badge or accolé au bouton : nombre d'entités actuellement éligibles à une
# évolution. RECOMPTÉ (jamais incrémenté) à chaque entity_ready_to_evolve /
# entity_evolved / adventure_started, depuis MasterySystem.can_evolve (source
# de vérité). _evolve_ready_ids alimente aussi le tooltip de survol.
var _evolve_badge:     PanelContainer = null
var _evolve_badge_lbl: Label          = null
var _evolve_ready_ids: Array          = []

# ─── Bandeau de butin du cycle (barre de bas, à gauche) ──────
# Les pastilles d'ingrédients volent depuis la créature et s'y empilent.
# Aucune logique de drop ici : on ne fait qu'écouter EventBus.loot_dropped.
var _loot := CombatLootBanner.new(self)  # bandeau de butin (concern extrait)

# ─── Couche FX (halos de palier) ─────────────────────────────
# Plein écran, transparente à la souris : reçoit le burst de halo coloré quand
# une entité atteint son palier (entity_ready_to_evolve). L'XP flottante par
# entité a été retirée (chiffres bruts illisibles en plein combat).
var _xp_fx_layer:    Control                # couche plein écran pour les halos de palier

# ─── Overlays (zone + Unique) ────────────────────────────────
var _zonemech := CombatZoneMechanic.new(self)   # bandeaux strate + mécanique (extrait)
var _unique_panel: Control = null

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:    float = 0.0
var _navigating:  bool  = false

# ─── Jauges ATB honnêtes (refonte temps réel) ───────────────
# Chaque barre se remplit en continu à la cadence RÉELLE de son combattant
# (CombatPlayer.*_atb_interval), indépendamment de l'autre : un combattant
# rapide remplit visiblement plus vite. La jauge est pleine pile au moment où
# le combattant frappe, puis se vide et redémarre.
# Tweens indexés par camp (is_hero) : évite la duplication hero/enemy partout.
var _atb_tween:   Dictionary = {true: null, false: null}   # charge ATB
var _haste_tween: Dictionary = {true: null, false: null}   # ordonnancement on/off hâte

# ─── Polish combat ──────────────────────────────────────────
var _danger_pulse_tween: Tween   = null   # pulse PV critique (item 5)
var _poison_state_pill:  Control = null   # pill venin violette ennemie (Contact Venimeux)
var _hero_poison_pill:   Control = null   # pill poison PERSISTANTE du héros (B3)
var _hero_poison_token:  int     = 0      # invalide les masquages différés obsolètes
var _haste_pill: Dictionary = {true: null, false: null}   # pill « Rapide » par camp
var _stinger := CombatStinger.new(self)   # bandeau d'événement piège/bénédiction (extrait)

# ═══════════════════════════════════════════════════════════
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_signals()
	# La scène est chargée APRÈS l'émission de adventure_started (le Village démarre
	# l'aventure puis change de scène) : ce signal est donc raté. On rejoue l'init
	# côté héros si une expédition est déjà en cours — sinon la boule et la barre
	# du héros restent muettes jusqu'au premier combat de créature (et n'apparaissent
	# pas du tout si la 1re rencontre est un piège/bénédiction).
	if AdventureSystem.is_running:
		_on_adventure_started(AdventureSystem.current_biome_id)

# ═══════════════════════════════════════════════════════════
#  Construction de l'UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UIColors.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_shaker = Control.new()
	_shaker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shaker)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	_shaker.add_child(root)

	root.add_child(_build_combat_area())
	root.add_child(_build_combatant_bars())
	if LOG_ENABLED:
		root.add_child(_log.build())
	root.add_child(_build_bottom_bar())

	_zonemech.build()

	# Couche FX pour les halos de palier : par-dessus la zone de combat, sous les
	# stingers (z 90+). Transparente à la souris.
	_xp_fx_layer = Control.new()
	_xp_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fx_layer.z_index = 50
	add_child(_xp_fx_layer)

# ── Zone de combat : fonds animés + 2 colonnes + séparateur diagonal ──
# Les fonds (Ville côté héros, biome côté créature) sont CONFINÉS à cette zone
# (pas derrière le journal). clip_contents borne le rendu ; la diagonale du
# shader s'aligne donc sur le séparateur VS de cette même zone.
func _build_combat_area() -> Control:
	var area := Control.new()
	area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size   = Vector2(0, 320)
	area.clip_contents = true

	var zone := int(AdventureSystem.zone_courante)

	# Côté héros (gauche) : ambiance Ville. add_child d'abord (→ _ready crée le
	# material), puis configuration.
	_hero_bg = BiomeBackground.new()
	area.add_child(_hero_bg)
	_hero_bg.apply_preset("city")
	_hero_bg.set_split(1, CombatVS.BAND_WIDTH)
	_hero_bg.set_zone(zone)

	# Côté créature (droite) : ambiance du biome de l'expédition.
	var biome_id := AdventureSystem.current_biome_id
	if biome_id == "":
		biome_id = GameData.player.get("active_biome_id", "") as String
	_creature_bg = BiomeBackground.new()
	area.add_child(_creature_bg)
	_creature_bg.apply_preset(BiomeBackground.preset_for_biome(biome_id))
	_creature_bg.set_split(2, CombatVS.BAND_WIDTH)
	_creature_bg.set_zone(zone)

	# Boules d'énergie : au centre de chaque moitié, par-dessus les fonds mais
	# sous les colonnes (la pill d'action reste lisible). Masquées tant qu'aucun
	# combattant n'occupe la moitié (le héros est révélé au départ d'expédition).
	_hero_fighter = _make_fighter(1.0, 0.25)
	area.add_child(_hero_fighter)
	_enemy_fighter = _make_fighter(-1.0, 0.75)
	area.add_child(_enemy_fighter)

	# Colonnes par-dessus les fonds. Héros (gauche) | séparateur 80px | Ennemi (droite).
	# Le séparateur VS prend la couleur d'accent du biome exploré (ambiance).
	var vs := CombatVS.new()
	vs.accent_color = BiomeBackground.accent_for_biome(biome_id)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_build_column(true))
	hbox.add_child(vs)
	hbox.add_child(_build_column(false))
	area.add_child(hbox)

	# Encadrés de caractéristiques dans les coins (par-dessus les colonnes).
	area.add_child(_stats.build_hero())
	area.add_child(_stats.build_enemy())
	return area

# Crée une boule de combattant, centrée sur la fraction horizontale `cx` de
# l'arène (0.25 = milieu de la moitié gauche, 0.75 = moitié droite), masquée.
func _make_fighter(facing: float, cx: float) -> CombatFighter:
	const FS := 150.0
	var f := CombatFighter.new()
	f.facing_dir = facing
	f.anchor_left = cx; f.anchor_right = cx
	f.anchor_top = 0.5;  f.anchor_bottom = 0.5
	f.offset_left = -FS * 0.5; f.offset_right = FS * 0.5
	f.offset_top  = -FS * 0.5; f.offset_bottom = FS * 0.5
	f.visible = false
	return f


# Construit une colonne de l'arène (bande centrale) : intention d'action,
# calée vers le HAUT de la moitié pour laisser le centre à la boule d'énergie
# (centrée verticalement). Les pills d'état (bonus/malus) vivent désormais SOUS
# la barre du combattant (cf. _build_combatant_bars), pas ici. Plus d'anneau
# ni de plaque de nom.
func _build_column(is_hero: bool) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	# Décolle du bord haut (sous la bande zone/mécanique/stats).
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 44)
	col.add_child(top_pad)

	# Pill d'action : PanelContainer + Label (on garde la référence au Label).
	# Masquée par défaut — aucune capsule visible hors d'une action chargée.
	var action_box := PanelContainer.new()
	action_box.visible = false
	action_box.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.TEXT_MUTED, 0.12, 0.50, 1, 8))
	var action := UIHelpers.label("—", 14, UIColors.TEXT_MUTED)
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.add_theme_constant_override("outline_size", 3)
	action.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	action_box.add_child(action)
	var action_center := CenterContainer.new()
	action_center.add_child(action_box)
	col.add_child(action_center)

	if is_hero:
		_hero_action = action
	else:
		_enemy_action = action
	return col

# ── Bande basse de l'arène : deux barres JRPG ────────────────
# Héros calé à GAUCHE, créature calée à DROITE (barre miroir : se remplit depuis
# le bord droit). Un espaceur central élastique creuse l'écart pour ne pas que
# les barres se rejoignent au centre (et libère la place pour la boule à venir).
# Les pills d'état (bonus/malus : bouclier, venin, hâte, régén, poison) vivent
# DANS le cadre de chaque barre, sous la jauge ATB (cf. CombatBar.states_row) ;
# le cadre grandit pour les englober et ne réserve la place que s'il y en a.
# Les labels de nom vivent DANS les barres (_hero_name/_enemy_name : .text + tooltips).
func _build_combatant_bars() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",  12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_bottom", 2)

	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 0)
	m.add_child(band)

	# Barres top-alignées (SHRINK_BEGIN) : si l'une grandit (états), l'autre reste
	# courte et les jauges PV/ATB des deux restent alignées en haut.
	_hero_bar = CombatBar.new()
	_hero_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_bar.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_hero_bar.size_flags_stretch_ratio = 1.0
	band.add_child(_hero_bar)

	# Espaceur central (~le tiers d'une barre) : écarte les deux barres du centre.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.42
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(spacer)

	_enemy_bar = CombatBar.new()
	_enemy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_bar.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_enemy_bar.size_flags_stretch_ratio = 1.0
	_enemy_bar.mirrored = true
	band.add_child(_enemy_bar)

	_hero_name  = _hero_bar.name_label
	_enemy_name = _enemy_bar.name_label
	# Les rangées d'états sont fournies par les barres elles-mêmes (dans le cadre).
	_hero_states  = _hero_bar.states_row
	_enemy_states = _enemy_bar.states_row
	return m

# ── Barre de bas ───────────────────────────────────────────
# Bandeau de butin (gauche) ↔ bouton fin d'expédition (droite).
func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	# Bandeau de butin du cycle : encaisse les pastilles venues de la créature.
	# Aucun drop tant que la Forge n'est pas débloquée (Village ≥ Peu Commun) → on
	# masque le bandeau avant (espaceur pour garder le bouton de fin à droite). Au T0
	# le farm sert au compteur de kills, pas au loot.
	if int(GameData.village.get("maitrise_actuelle", 0)) >= Balance.FORGE_HUB_UNLOCK_VILLAGE_TIER:
		bar.add_child(_loot.build())
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(spacer)

	# Le compteur « XP ce cycle » a été retiré (l'espace est rendu à la zone de
	# combat). _xp_label reste null : _update_xp_label() est inerte (garde de
	# nullité). Le total d'XP du cycle reste affiché dans le résumé.
	var tcolor := _hero_tier_color()
	# Bouton SANS texte propre : son contenu (libellé + badge) vit dans un HBox
	# interne centré, pour que le badge soit DANS le bouton et toujours visible.
	_flee_btn = Button.new()
	_flee_btn.custom_minimum_size = Vector2(280, 42)
	_flee_btn.add_theme_stylebox_override("normal", UIHelpers.card_style(tcolor, 0.14, 1.0, 2, 6))
	_flee_btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(tcolor, 0.30, 1.0, 2, 6))
	_flee_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIHelpers.add_hover_feedback(_flee_btn)
	_flee_btn.pressed.connect(_on_flee_pressed)
	# Survol du bouton → tooltip listant les entités prêtes à évoluer (s'il y en a).
	_flee_btn.mouse_entered.connect(_show_evolve_tooltip)
	_flee_btn.mouse_exited.connect(TooltipOverlay.hide_tooltip)

	# Contenu interne : libellé + badge, centrés en groupe. Transparent à la
	# souris → le bouton garde le survol (tooltip) et le clic.
	var inner := HBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flee_btn.add_child(inner)

	var label := UIHelpers.label(Translations.T("combat.end_btn"), 15, tcolor)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)

	# Badge « ▲ N » : pastille colorée à la rareté du meilleur palier prêt
	# (UIColors.tier_color), masquée tant qu'aucune entité n'est prête.
	_evolve_badge = PanelContainer.new()
	_evolve_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_evolve_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_evolve_badge.visible = false
	_evolve_badge_lbl = UIHelpers.label("", 13, Color.WHITE)
	_evolve_badge_lbl.add_theme_constant_override("outline_size", 3)
	_evolve_badge_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# IGNORE : sans ça, le label (STOP par défaut) vole le survol au bouton dès
	# que le badge apparaît → le tooltip d'évolution clignote/ne s'affiche pas.
	_evolve_badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_evolve_badge.add_child(_evolve_badge_lbl)
	inner.add_child(_evolve_badge)

	var flee_margin := MarginContainer.new()
	flee_margin.add_theme_constant_override("margin_right", 5)
	flee_margin.add_theme_constant_override("margin_bottom", 4)
	flee_margin.add_child(_flee_btn)
	bar.add_child(flee_margin)
	return bar

# Position globale d'où jaillissent les pastilles de butin : centre de la boule
# d'énergie de la créature (fallbacks : barre créature, puis centre-droit de
# l'arène). Appelé par CombatLootBanner à chaque drop.
func loot_source_pos() -> Vector2:
	if _enemy_fighter and is_instance_valid(_enemy_fighter) and _enemy_fighter.visible:
		return _enemy_fighter.global_position + _enemy_fighter.size * 0.5
	elif _enemy_bar and is_instance_valid(_enemy_bar):
		return _enemy_bar.global_position + _enemy_bar.size * 0.5
	return size * Vector2(0.72, 0.40)

# ── Helpers UI ─────────────────────────────────────────────

# Description lisible de l'effet d'une bénédiction (pour le tooltip).
# Effets supportés par AdventureSystem : "heal" et "xp_bonus".
func _benediction_desc(effet: String, valeur: int) -> String:
	match effet:
		Enums.BlessEffect.HEAL:     return Translations.T("combat.bless.heal") % valeur
		Enums.BlessEffect.XP_BONUS: return Translations.T("combat.bless.xp")   % valeur
		_:                          return effet if effet != "" else Translations.T("combat.bless.unknown")

# ═══════════════════════════════════════════════════════════
#  Signaux
# ═══════════════════════════════════════════════════════════

func _connect_signals() -> void:
	EventBus.adventure_started.connect(_on_adventure_started)
	EventBus.adventure_event_resolved.connect(_on_event_resolved)
	EventBus.creature_unique_vaincue.connect(_on_creature_unique_vaincue)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.loot_dropped.connect(_on_loot_dropped)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.bleed_ticked.connect(_on_bleed_ticked)
	EventBus.adventure_cycle_ended.connect(_on_cycle_ended)
	EventBus.adventure_stopped.connect(_on_adventure_stopped)
	EventBus.entity_ready_to_evolve.connect(_on_entity_ready_to_evolve)
	EventBus.entity_evolved.connect(_on_entity_evolved)
	CombatPlayer.step_started.connect(_on_step_started)
	CombatPlayer.step_ended.connect(_on_step_ended)

# ═══════════════════════════════════════════════════════════
#  Handlers
# ═══════════════════════════════════════════════════════════

func _on_adventure_started(_biome_id: String) -> void:
	_flee_btn.disabled = false
	_cycle_xp = 0.0
	_update_xp_label()
	_loot.reset()
	_refresh_evolve_counter()
	_zonemech.update_zone(AdventureSystem.zone_courante)
	if AdventureSystem.zone_courante == Enums.Zone.ABYSSE:
		_show_unique_indicator()

	var c      := GameData.get_entity("hero")
	var htier  := int(c.get("maitrise_actuelle", 0))
	var hname  := Translations.entity_name(c)
	_hero_name.text = hname.to_upper()
	_hero_bar.setup(UIColors.tier_color(htier))
	_hero_bar.set_hp(AdventureSystem.current_hp, AdventureSystem.current_hp)
	_hero_bar.enter_combat()
	_hide_action(_hero_action)
	# Boule du héros révélée et vivante ; celle de la créature reste masquée
	# jusqu'à la première rencontre.
	_hero_fighter.setup(UIColors.tier_color(htier))
	_hero_fighter.play_idle()
	_enemy_fighter.visible = false

	# Tooltip JRPG sur le héros (stats effectives avec équipement)
	var hstats := GameData.get_effective_stats("hero")
	var heqp   := GameData.get_equipment_bonuses()
	var htt    := Translations.T("combat.tt_stats") % [
		GameData.get_tier_name(htier),
		int(AdventureSystem.current_hp),
		int(hstats.get("atk", 0)) + int(heqp.get("atk", 0)),
		int(hstats.get("def", 0)) + int(heqp.get("def", 0))]
	UIHelpers.register_tooltip(_hero_name, hname, htt, UIColors.tier_color(htier),
			Translations.entity_lore(c))

	# Encadré de stats du héros (haut-gauche), visible toute l'expédition.
	_stats.refresh_hero(htier)

	# Colonne ennemi en attente (vide) jusqu'au premier événement.
	_enemy_name.text = "—"
	_enemy_bar.setup(UIColors.TEXT_MUTED)
	_enemy_bar.set_hp(0, 1)
	_hide_action(_enemy_action)

	_zonemech.hide_mechanic()
	match BiomeMechanics.active_mechanic:
		"ambush":
			var ac := UIColors.MECH_AMBUSH
			_push_under_bar_pill(_hero_states, Translations.mech_name("ambush"), ac)
			_zonemech.show_mechanic("⚡ " + Translations.mech_name("ambush"), ac,
					Translations.mech_name("ambush"), Translations.mech_desc("ambush"))
		"poison":
			var pc := UIColors.MECH_POISON
			_push_under_bar_pill(_hero_states, Translations.mech_name("poison"), pc)
			_zonemech.show_mechanic("☠ " + Translations.mech_name("poison"), pc,
					Translations.mech_name("poison"), Translations.mech_desc("poison"))
		"endurcissement":
			var ec := UIColors.MECH_ENDURANCE
			_push_under_bar_pill(_hero_states, Translations.mech_name("endurcissement"), ec)
			_zonemech.show_mechanic("🗻 " + Translations.mech_name("endurcissement"), ec,
					Translations.mech_name("endurcissement"), Translations.mech_desc("endurcissement"))

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		Enums.EntityType.TRAP:
			# Piège : effet annoncé au centre (stinger) → pas d'encadré de stats.
			# Pas de combattant adverse : la boule créature reste masquée.
			_stats.set_enemy_visible(false)
			_enemy_fighter.visible = false
			var trap := event_data.get("trap", {}) as Dictionary
			var tname := Translations.entity_name(trap)
			_enemy_name.text = tname.to_upper()
			_enemy_bar.setup(UIColors.TYPE_TRAP)
			_enemy_bar.set_hp(1, 1)
			_enemy_bar.enter_combat()
			_hide_action(_enemy_action)
			# PV réellement perdus, calculés par AdventureSystem (pourcentage du
			# PV max selon la zone). L'ancien code lisait trap["damage"] (clé
			# inexistante : le champ .tres est `degats`) → affichait toujours 0.
			var tdmg := int(event_data.get("trap_damage", 0))
			var trap_tt := Translations.T("combat.trap_tt") % tdmg
			var ignored := event_data.get("ignored", false) as bool
			if ignored:
				trap_tt += Translations.T("combat.trap_ignored")
			UIHelpers.register_tooltip(_enemy_name, tname, trap_tt, UIColors.TYPE_TRAP)
			var trap_detail := Translations.T("combat.stinger.ignored") if ignored \
					else Translations.T("combat.stinger.trap_dmg") % tdmg
			_stinger.show(Translations.T("combat.stinger.trap"), tname,
					trap_detail, UIColors.TYPE_TRAP, not ignored)
			AudioManager.play_sfx("trap_appear", -4.0)
			if not ignored:
				_hero_bar.update_hp(AdventureSystem.current_hp)
				_hero_bar.damage(tdmg, false)
				_hero_fighter.play_hit()
				_check_danger_pulse()
				_add_log("[color=%s]%s[/color] inflige [color=%s]-%d[/color]"
						% [_hex(UIColors.TIER_EPIQUE), tname, _hex(UIColors.LOG_DEFEAT), tdmg],
						["monster", "attack", "status"])
		Enums.EntityType.BENEDICTION:
			# Bénédiction : effet annoncé au centre (stinger) → pas d'encadré de stats.
			_stats.set_enemy_visible(false)
			_enemy_fighter.visible = false
			var bene := event_data.get("effect", {}) as Dictionary
			var bname := Translations.entity_name(bene)
			_enemy_name.text = bname.to_upper()
			_enemy_bar.setup(UIColors.TYPE_BENEDICTION)
			_enemy_bar.set_hp(1, 1)
			_enemy_bar.enter_combat()
			_hide_action(_enemy_action)
			var beff   := bene.get("effet", "") as String
			var bval   := int(bene.get("valeur", 0))
			var bdesc  := _benediction_desc(beff, bval)
			UIHelpers.register_tooltip(_enemy_name, bname,
				Translations.T("combat.bless_tt") % bdesc,
				UIColors.TYPE_BENEDICTION)
			_stinger.show(Translations.T("combat.stinger.bless"), bname,
					bdesc, UIColors.TYPE_BENEDICTION, false)
			AudioManager.play_sfx("benediction_appear", -5.0)
			_add_log("[color=%s]%s[/color]" % [_hex(UIColors.TYPE_BENEDICTION), bname], ["status"])

func _on_combat_started(hero_id: String, enemy: Dictionary,
		hero_hp: float, enemy_hp: float) -> void:
	var c        := GameData.get_entity(hero_id)
	var htier    := int(c.get("maitrise_actuelle", 0))
	var hero_max := AdventureSystem.get_max_hp()
	_hero_name.text = Translations.entity_name(c).to_upper()
	_hero_bar.setup(UIColors.tier_color(htier))
	_hero_bar.set_hp(hero_hp, hero_max)

	var ename      := enemy.get("name", "Ennemi") as String
	var etier      := int(enemy.get("tier", 0))
	var etier_name := GameData.get_tier_name(etier)
	_enemy_name.text = ename.to_upper()
	_enemy_bar.setup(UIColors.tier_color(etier))
	_enemy_bar.set_hp(enemy_hp, enemy_hp)
	# Arrivée de la rencontre : pop élastique de la barre.
	_enemy_bar.enter_combat()

	# Boules des deux combattants : (re)teintées au palier, vivantes (idle).
	_hero_fighter.setup(UIColors.tier_color(htier))
	_hero_fighter.play_idle()
	_enemy_fighter.setup(UIColors.tier_color(etier))
	_enemy_fighter.play_idle()

	# Tooltip JRPG sur le nom de l'ennemi : rang + stats
	var ett := Translations.T("combat.tt_stats") % [
		etier_name,
		int(enemy_hp),
		int(enemy.get("atk", 0)),
		int(enemy.get("def", 0))]
	var enemy_entity := GameData.get_entity(enemy.get("id", ""))
	UIHelpers.register_tooltip(_enemy_name, ename, ett, UIColors.tier_color(etier),
			Translations.entity_lore(enemy_entity))

	# Encadrés de caractéristiques : héros (gauche) rafraîchi + créature (droite).
	_stats.refresh_hero(htier)
	_stats.fill_enemy(etier, int(enemy_hp),
			int(enemy.get("atk", 0)),
			int(enemy.get("def", 0)),
			int(enemy.get("vit", 0)))

	# Jauges ATB honnêtes : chaque barre démarre sa charge à la cadence réelle de
	# son combattant ; elle sera pleine pile quand il frappera (puis redémarre à
	# chaque coup, cf. _on_step_ended).
	_charge_atb(true,  CombatPlayer.hero_atb_interval)
	_charge_atb(false, CombatPlayer.enemy_atb_interval)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_stop_danger_pulse()
	_clear_state_pills()
	_clear_haste()
	# Feedback de hâte (rail de vitesse) : pill + jauge teintée pendant la fenêtre
	# (APRÈS _clear_state_pills, qui vide les pills d'états).
	_setup_haste(true,  CombatPlayer.hero_haste_window)
	_setup_haste(false, CombatPlayer.enemy_haste_window)
	_flee_btn.disabled = false
	_add_log(Translations.T("combat.appears") \
			% ("[color=%s]%s[/color]" % [_hex(Color(1.0, 0.8, 0.2)), ename]), ["monster"])

# Début du cooldown : on affiche l'INTENTION de l'attaquant. La jauge ATB n'est
# PLUS pilotée ici : chaque barre se remplit en continu à sa cadence réelle
# (cf. _charge_atb), donc elle est déjà pleine quand le coup atterrit
# (_on_step_ended). Aucun dégât appliqué ici.
func _on_step_started(step: CombatStep) -> void:
	# Tick de poison : instantané, pas d'action chargée ni d'intention affichée.
	if step.is_poison or step.is_passive_poison:
		return

	# Souffle de l'attaque lancée (placeholder).
	AudioManager.play_sfx("attack", -7.0)

	var is_hero := step.attacker == "hero"
	var lbl  := _hero_action if is_hero else _enemy_action
	var base_col := UIColors.STAT_ATK if is_hero else UIColors.TYPE_TRAP
	_show_action(lbl, Translations.T("combat.action.crit") if step.is_crit else Translations.T("combat.action.attack"),
			UIColors.FILTER_ON if step.is_crit else base_col)

# Barre / rangée d'états d'un camp (is_hero) — évite le ternaire répété partout.
func _bar(is_hero: bool) -> CombatBar:
	return _hero_bar if is_hero else _enemy_bar

func _states(is_hero: bool) -> HBoxContainer:
	return _hero_states if is_hero else _enemy_states

# Tue le tween stocké dans `dict[is_hero]` s'il est encore valide.
func _kill_tween(dict: Dictionary, is_hero: bool) -> void:
	var tw: Tween = dict[is_hero]
	if tw and tw.is_valid():
		tw.kill()

# Lance (ou relance) la charge continue d'une jauge ATB sur `interval` secondes
# de lecture : la barre va de 0 à 1 puis reste pleine jusqu'à la prochaine
# relance (au coup suivant du combattant). Honnête : un combattant rapide a un
# `interval` plus court, donc une jauge qui monte plus vite.
func _charge_atb(is_hero: bool, interval: float) -> void:
	_kill_tween(_atb_tween, is_hero)
	var bar := _bar(is_hero)
	bar.set_atb(0.0)
	var tw := create_tween()
	tw.tween_method(bar.set_atb, 0.0, 1.0, maxf(interval, 0.05)).set_ease(Tween.EASE_IN)
	_atb_tween[is_hero] = tw

# Stoppe les charges ATB en cours (fin de combat / arrêt d'expédition).
func _stop_atb() -> void:
	_kill_tween(_atb_tween, true)
	_kill_tween(_atb_tween, false)

# ─── Feedback de hâte (rail de vitesse temporaire) ──────────
# Programme l'activation puis la coupure du feedback « Hâte » d'un combattant sur
# la fenêtre `window` = (début, fin) en secondes de lecture. ZERO → rien.
func _setup_haste(is_hero: bool, window: Vector2) -> void:
	if window == Vector2.ZERO or window.y <= window.x:
		return
	var tw := create_tween()
	if window.x > 0.001:
		tw.tween_interval(window.x)
	tw.tween_callback(_set_haste_active.bind(is_hero, true))
	tw.tween_interval(maxf(window.y - maxf(window.x, 0.0), 0.05))
	tw.tween_callback(_set_haste_active.bind(is_hero, false))
	_haste_tween[is_hero] = tw

# Active/coupe le feedback hâte : jauge ATB teintée + pill « Rapide ».
func _set_haste_active(is_hero: bool, active: bool) -> void:
	var bar := _bar(is_hero)
	if is_instance_valid(bar):
		bar.set_haste(active)
	if not active:
		_remove_haste_pill(is_hero)
		return
	var existing: Control = _haste_pill[is_hero]
	var states := _states(is_hero)
	if (existing == null or not is_instance_valid(existing)) and states:
		var pill := _make_state_pill_node("⚡ " + Translations.T("combat.haste_pill"), UIColors.HASTE)
		states.add_child(pill)
		_haste_pill[is_hero] = pill

func _remove_haste_pill(is_hero: bool) -> void:
	var pill: Control = _haste_pill[is_hero]
	if pill and is_instance_valid(pill):
		pill.queue_free()
	_haste_pill[is_hero] = null

# Coupe tout feedback hâte en cours (changement de rencontre / fin de combat).
func _clear_haste() -> void:
	_kill_tween(_haste_tween, true)
	_kill_tween(_haste_tween, false)
	if is_instance_valid(_hero_bar):
		_hero_bar.set_haste(false)
	if is_instance_valid(_enemy_bar):
		_enemy_bar.set_haste(false)
	_remove_haste_pill(true)
	_remove_haste_pill(false)

# Joue la réaction d'un combattant touché : mort si coup fatal, sinon recul.
func _fighter_take(target: CombatFighter, killing: bool) -> void:
	if killing:
		target.play_death()
	else:
		target.play_hit()

# Fin du cooldown : l'attaque atterrit. On applique les dégâts/soins/états,
# on réinitialise les jauges ATB et on masque les pills d'action. Les boules
# d'énergie réagissent (attaque de l'acteur, recul/mort de la cible).
func _on_step_ended(step: CombatStep) -> void:
	if step.is_passive_poison:
		# Contact Venimeux : le venin du héros ronge l'ENNEMI.
		_enemy_bar.update_hp(float(step.target_hp_after))
		_enemy_bar.poison(step.damage)
		_add_log("[color=%s]%s[/color] [color=%s]-%d[/color]"
				% [_hex(UIColors.TIER_EPIQUE), Translations.T("combat.venom"), _hex(UIColors.LOG_DEFEAT), step.damage],
				["status", "attack"])
		if step.is_killing_blow:
			_kill_impact(_enemy_bar)
		_fighter_take(_enemy_fighter, step.is_killing_blow)
	elif step.is_poison:
		# Poison de biome (Marécage) : le marais toxique ronge le HÉROS.
		_hero_bar.update_hp(float(step.target_hp_after))
		_hero_bar.poison(step.damage)
		_mark_hero_poisoned()   # B3 : indicateur persistant le temps de l'altération
		_add_log("[color=%s]%s[/color] [color=%s]-%d[/color]"
				% [_hex(UIColors.TIER_EPIQUE), Translations.T("combat.poison"), _hex(UIColors.LOG_DEFEAT), step.damage],
				["status", "attack"])
		if step.is_killing_blow:
			_kill_impact(_hero_bar)
		else:
			_check_danger_pulse()
		_fighter_take(_hero_fighter, step.is_killing_blow)
	elif step.attacker == "hero":
		_hero_fighter.play_attack()
		_enemy_bar.update_hp(float(step.target_hp_after))
		_enemy_bar.damage(step.damage, step.is_crit)
		if step.is_crit:
			_screen_shake(1.7)
		if step.is_killing_blow:
			_kill_impact(_enemy_bar)
		_fighter_take(_enemy_fighter, step.is_killing_blow)
		_log_attack(_hero_name.text, step.damage, step.is_crit, ["hero", "attack"])
		if step.passive_poison_proc:
			_add_log("[color=%s]%s[/color]" % [_hex(UIColors.TIER_EPIQUE), Translations.T("combat.venom_contact")], ["status"])
			_update_poison_pill(true)
	else:
		_enemy_fighter.play_attack()
		if step.damage > 0:
			_hero_bar.update_hp(float(step.target_hp_after))
			_hero_bar.damage(step.damage, step.is_crit)
			if step.is_crit:
				_screen_shake(1.7)
			if step.is_killing_blow:
				_kill_impact(_hero_bar)
			_fighter_take(_hero_fighter, step.is_killing_blow)
			_check_danger_pulse()
		_log_attack(_enemy_name.text, step.damage, step.is_crit, ["monster", "attack"])

	# Jauge ATB : seul l'attaquant qui vient de frapper voit sa jauge se vider et
	# redémarrer (à sa cadence). Les ticks de poison ne sont PAS un coup d'attaque
	# d'un combattant → ils ne touchent aucune jauge. L'autre barre continue sa
	# charge sans interruption.
	if not step.is_poison and not step.is_passive_poison:
		# Intervalle = temps jusqu'au PROCHAIN coup du combattant (honnête même
		# sous hâte : les coups se rapprochent → la jauge remonte plus vite).
		if step.attacker == "hero":
			_charge_atb(true, CombatPlayer.gap_to_next_attack(true))
		else:
			_charge_atb(false, CombatPlayer.gap_to_next_attack(false))
	_hide_action(_hero_action)
	_hide_action(_enemy_action)

func _on_combat_ended(result: Dictionary) -> void:
	_stop_atb()
	_clear_haste()
	_hero_bar.set_atb(0.0)
	_enemy_bar.set_atb(0.0)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_stop_danger_pulse()
	_clear_state_pills()
	if result.get("victory", false):
		# La barre du vaincu s'éteint avec lui (fade_defeated dim la barre entière,
		# nom compris ; la prochaine rencontre la ravive via setup/enter_combat).
		_hero_bar.celebrate()
		_enemy_bar.fade_defeated()
		_cycle_xp = AdventureSystem.get_cycle_xp()
		_update_xp_label()
		_add_log("[color=%s]%s[/color]" % [_hex(UIColors.LOG_VICTORY), Translations.T("combat.victory")], ["hero"])
	else:
		_enemy_bar.celebrate()
		_hero_bar.fade_defeated()
		_add_log("[color=%s]%s[/color]" % [_hex(Color(1.0, 0.5, 0.2)), Translations.T("combat.defeat")], ["monster"])


func _on_heal_applied(amount: float, new_hp: float) -> void:
	_hero_bar.update_hp(new_hp)
	_hero_bar.heal(int(amount))
	# Toast de régénération sous la barre du héros (et non au centre de l'écran).
	_push_under_bar_pill(_hero_states, "♥ " + Translations.T("combat.regen") % int(amount), UIColors.HEAL_COLOR)
	_add_log("[color=%s]%s[/color]" % [_hex(UIColors.HEAL_COLOR), Translations.T("combat.regen") % int(amount)], ["heal"])
	_check_danger_pulse()

# Tick de saignement/poison infligé par un piège (ex. Baies empoisonnées) : ronge
# le héros entre les rencontres. Sans retour visuel, le joueur ne « voyait » pas
# l'état poison → chiffre flottant vert sur la barre + pill poison transitoire.
func _on_bleed_ticked(damage: float, new_hp: float, _remaining: int) -> void:
	if is_instance_valid(_hero_bar):
		_hero_bar.update_hp(new_hp)
		_hero_bar.poison(int(damage))
	_push_under_bar_pill(_hero_states, "☠ -%d" % int(damage), UIColors.POISON)
	_check_danger_pulse()

func _on_cycle_ended(result: Dictionary) -> void:
	_flee_btn.disabled = true
	_cycle_xp = float(result.get("xp_total", 0.0))
	_update_xp_label()
	_navigate_to_summary()

func _on_adventure_stopped() -> void:
	_navigate_to_summary()

func _on_flee_pressed() -> void:
	AdventureSystem.stop_adventure()

# ═══════════════════════════════════════════════════════════
#  Bandeau de butin du cycle
#  Écoute EventBus.loot_dropped (drops déjà calculés par AdventureSystem) et
#  ne fait que LE PRÉSENTER : une pastille jaillit de la créature, décrit un
#  arc et s'empile dans le bandeau en bas à gauche.
# ═══════════════════════════════════════════════════════════

# Wrapper fin vers CombatLootBanner — la connexion EventBus reste sur ce Node
# (auto-déconnexion à la libération de la scène). source_name non utilisé.
func _on_loot_dropped(drops: Array, _source_name: String) -> void:
	_loot.on_loot_dropped(drops)

# Position d'ancrage du halo de palier selon le type de l'entité.
func _evolve_anchor(entity: Dictionary) -> Vector2:
	var etype := String(entity.get("entity_type", ""))
	if etype == Enums.EntityType.HERO and _hero_bar and is_instance_valid(_hero_bar):
		return _hero_bar.global_position + _hero_bar.size * 0.5
	if etype == Enums.EntityType.CREATURE and _enemy_bar and is_instance_valid(_enemy_bar):
		return _enemy_bar.global_position + _enemy_bar.size * 0.5
	return size * Vector2(0.5, 0.40)

# Rangée d'états sous laquelle accrocher un toast lié à une entité : la barre
# créature pour une créature, sinon la barre du héros (côté joueur par défaut).
func _states_for_entity(entity: Dictionary) -> HBoxContainer:
	if String(entity.get("entity_type", "")) == Enums.EntityType.CREATURE:
		return _enemy_states
	return _hero_states

# ═══════════════════════════════════════════════════════════
#  Animation cooldown / shake / feed
# ═══════════════════════════════════════════════════════════

# Le stinger d'événement (piège / bénédiction) vit dans CombatStinger
# (scripts/combat/CombatStinger.gd) — cf. membre _stinger.

# Shake d'écran : translation X/Y amortie sur ~350ms puis retour.
# strength : 1.0 = coup normal, ~1.7 = critique (plus ample + vertical).
func _screen_shake(strength: float = 1.0) -> void:
	var tw := create_tween()
	var amps := [5.0, -5.0, 4.0, -3.0]
	for a: float in amps:
		tw.tween_property(_shaker, "position",
				Vector2(a * strength, -a * 0.45 * (strength - 0.6)),
				0.35 / float(amps.size())).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_shaker, "position", Vector2.ZERO, 0.05)

# ═══════════════════════════════════════════════════════════
#  Journal
# ═══════════════════════════════════════════════════════════

# Affiche l'intention d'action (capsule visible). Le parent du label est la capsule.
func _show_action(lbl: Label, text: String, color: Color) -> void:
	lbl.text = text
	lbl.add_theme_color_override("font_color", color.lightened(0.30))
	var box := lbl.get_parent()
	if box is PanelContainer:
		# Capsule bien visible : fond plus dense, bordure franche, padding.
		var style := UIHelpers.card_style(color, 0.30, 0.95, 1, 9)
		style.content_margin_left   = 12
		style.content_margin_right  = 12
		style.content_margin_top    = 3
		style.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", style)
		box.visible = true
		# Pop d'annonce : la capsule claque à chaque intention d'action.
		var bc := box as Control
		bc.pivot_offset = bc.size * 0.5
		bc.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(bc, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Masque entièrement la capsule d'action : aucun résidu visible hors action.
func _hide_action(lbl: Label) -> void:
	var box := lbl.get_parent()
	if box is PanelContainer:
		box.visible = false

# Wrapper fin vers CombatLog — no-op tant que LOG_ENABLED est false (journal
# non construit, cf. _build_bottom_bar). Les sites d'appel restent inchangés.
func _add_log(bbcode: String, tags: Array) -> void:
	if LOG_ENABLED:
		_log.add(bbcode, tags)

func _log_attack(attacker_name: String, dmg: int, is_crit: bool, tags: Array) -> void:
	var is_hero_attacker := "hero" in tags
	var prefix   := "[color=%s]%s[/color] " % [
		_hex(Color(0.55, 0.36, 0.97) if is_hero_attacker else Color(0.86, 0.15, 0.15)),
		"⚔" if is_hero_attacker else "🗡"
	]
	var name_part := "[color=%s]%s[/color]" % [_hex(UIColors.LOG_IGNORED), attacker_name]
	var dmg_part: String
	if is_crit:
		dmg_part = "[b][color=%s]★ %d[/color][/b]" % [_hex(UIColors.FILTER_ON), dmg]
	else:
		dmg_part = "[color=%s]-%d[/color]" % [_hex(UIColors.LOG_DEFEAT), dmg]
	_add_log("%s%s → %s" % [prefix, name_part, dmg_part], tags)

# ═══════════════════════════════════════════════════════════
#  Zone + Créature Unique (overlays conservés)
# ═══════════════════════════════════════════════════════════

func _show_unique_indicator() -> void:
	if _unique_panel != null:
		return
	var biome := GameData.get_entity(AdventureSystem.current_biome_id)
	var unique := biome.get("creature_unique", {}) as Dictionary
	if unique.is_empty():
		return
	var nom            := Translations.entity_name(unique, "???")
	var already_beaten := biome.get("creature_unique_vaincue", false) as bool
	var color          := UIColors.ZONE_ABYSSE

	_unique_panel = PanelContainer.new()
	_unique_panel.anchor_left = 0.5; _unique_panel.anchor_right = 0.5
	_unique_panel.anchor_top = 0.0;  _unique_panel.anchor_bottom = 0.0
	_unique_panel.offset_left = -150; _unique_panel.offset_right = 150
	_unique_panel.offset_top = 34;    _unique_panel.offset_bottom = 96
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.06, 0.90) if already_beaten else Color(0.18, 0.0, 0.0, 0.90)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_unique_panel.add_theme_stylebox_override("panel", style)
	add_child(_unique_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_unique_panel.add_child(vb)
	var lbl := UIHelpers.label(
			Translations.T("combat.unique_beaten" if already_beaten else "combat.unique_watches") % nom,
			13, UIColors.TEXT_MUTED if already_beaten else color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var btn := Button.new()
	btn.text = Translations.T("combat.unique_refight" if already_beaten else "combat.unique_fight") % nom
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_stylebox_override("normal", UIHelpers.card_style(color, 0.15, 1.0, 1, 4))
	btn.add_theme_stylebox_override("hover",  UIHelpers.card_style(color, 0.30, 1.0, 1, 4))
	btn.pressed.connect(AdventureSystem.start_unique_combat)
	vb.add_child(btn)

func _hide_unique_indicator() -> void:
	if _unique_panel and is_instance_valid(_unique_panel):
		_unique_panel.queue_free()
	_unique_panel = null

func _on_creature_unique_vaincue(_biome_id: String, ingredient_id: String, passif_id: String) -> void:
	_hide_unique_indicator()
	_show_unique_indicator()  # reconstruit avec état "déjà vaincu" + bouton réaffronter
	var ingr := Translations.entity_name(GameData.get_entity(ingredient_id), ingredient_id)
	var passif := Translations.entity_name(GameData.get_entity(passif_id), passif_id)
	_add_log("[color=%s]%s[/color]"
			% [_hex(Color(1.0, 0.8, 0.2)), Translations.T("combat.unique_slain") % [ingr, passif]], ["hero"])

# ═══════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════

func _update_xp_label() -> void:
	if not _xp_label:
		return
	_xp_label.text = Translations.T("combat.xp_label_fmt") % int(_cycle_xp)
	# Petit pop à chaque gain : le compteur vit au rythme du cycle.
	_xp_label.pivot_offset = _xp_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(_xp_label, "scale", Vector2(1.12, 1.12), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_xp_label, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hero_tier_color() -> Color:
	return UIColors.tier_color(int(GameData.get_entity("hero").get("maitrise_actuelle", 0)))

# Convertit une couleur en chaîne hex "#rrggbb" pour le BBCode.
func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

func _navigate_to_summary() -> void:
	if _navigating:
		return
	_navigating = true
	UIHelpers.fade_to_scene(self, "res://scenes/cycle/CycleSummaryScreen.tscn")

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 5 (pulse PV danger ≤30 %)
# ═══════════════════════════════════════════════════════════

func _check_danger_pulse() -> void:
	var max_hp := AdventureSystem.get_max_hp()
	if max_hp <= 0.0:
		return
	var ratio := AdventureSystem.current_hp / max_hp
	if ratio <= 0.30 and AdventureSystem.current_hp > 0.0:
		if not _danger_pulse_tween or not _danger_pulse_tween.is_running():
			_start_danger_pulse()
	else:
		_stop_danger_pulse()

func _start_danger_pulse() -> void:
	if _danger_pulse_tween:
		_danger_pulse_tween.kill()
	_danger_pulse_tween = create_tween().set_loops()
	_danger_pulse_tween.tween_property(_hero_bar, "modulate:a", 0.45, 0.35).set_trans(Tween.TRANS_SINE)
	_danger_pulse_tween.tween_property(_hero_bar, "modulate:a", 1.0,  0.35).set_trans(Tween.TRANS_SINE)

func _stop_danger_pulse() -> void:
	if _danger_pulse_tween:
		_danger_pulse_tween.kill()
		_danger_pulse_tween = null
	if _hero_bar:
		_hero_bar.modulate.a = 1.0

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 6 (flash coup fatal)
# ═══════════════════════════════════════════════════════════

func _kill_impact(bar: CombatBar) -> void:
	var tw := create_tween()
	tw.tween_property(bar, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.06)
	tw.tween_property(bar, "modulate", Color.WHITE, 0.40).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 8 (pills d'état colorées)
# ═══════════════════════════════════════════════════════════

func _clear_state_pills() -> void:
	if _hero_states:
		for child in _hero_states.get_children():
			child.queue_free()
	if _enemy_states:
		for child in _enemy_states.get_children():
			child.queue_free()
	_poison_state_pill = null
	_hero_poison_pill  = null
	_hero_poison_token += 1   # invalide tout masquage de poison héros en vol
	# Les pills de hâte sont des enfants de _hero_states/_enemy_states (libérés
	# ci-dessus) : on annule juste les références pour éviter tout pointeur mort.
	_haste_pill[true]  = null
	_haste_pill[false] = null

func _update_poison_pill(active: bool) -> void:
	_poison_state_pill = _set_persistent_pill(
			_poison_state_pill, _enemy_states, active, Translations.T("combat.venom_pill"), UIColors.POISON)

# B3 : le héros empoisonné garde un indicateur PERSISTANT le temps de l'altération,
# et non un simple flash par tick. Chaque tick rafraîchit la pill puis réarme un
# délai de masquage > l'intervalle entre deux ticks (en temps de lecture) → aucun
# clignotement entre ticks ; la pill disparaît peu après le DERNIER tick (fin de
# l'effet) faute de réarmement.
func _mark_hero_poisoned() -> void:
	_hero_poison_pill = _set_persistent_pill(_hero_poison_pill, _hero_states, true,
			"☠ " + Translations.T("combat.poison"), UIColors.POISON)
	_hero_poison_token += 1
	var token := _hero_poison_token
	var speed := maxf(GameSettings.combat_speed, 0.01)
	var delay := Balance.BIOME_POISON_TICK_INTERVAL / speed * 1.3 + 0.3
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(self) and token == _hero_poison_token:
			_hero_poison_pill = _set_persistent_pill(_hero_poison_pill, _hero_states, false, "", UIColors.POISON)
	)

# Pose / met à jour / retire une pill d'état PERSISTANTE (bouclier, venin). La
# référence est passée puis renvoyée (GDScript ne passe pas les membres par
# référence) : `_x = _set_persistent_pill(_x, …)`. Renvoie null quand retirée.
func _set_persistent_pill(pill: Control, states: HBoxContainer, active: bool,
		text: String, color: Color) -> Control:
	if not active:
		if pill and is_instance_valid(pill):
			pill.queue_free()
		return null
	if pill == null or not is_instance_valid(pill):
		pill = _make_state_pill_node(text, color)
		if states:
			states.add_child(pill)
	else:
		(pill.get_child(0) as Label).text = text
	return pill

func _make_state_pill_node(text: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.18, 0.70, 1, 6))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(UIHelpers.label(text, 11, color))
	return box

# Pill transitoire (toast) ajouté SOUS la barre d'un combattant : pop-in, puis
# fondu et disparition après ~2 s. Pour les événements ponctuels (régénération,
# tick de poison) — affichés au même endroit que les états persistants, plutôt
# qu'au centre de l'écran.
func _push_under_bar_pill(states: HBoxContainer, text: String, color: Color) -> void:
	if not states or not is_instance_valid(states):
		return
	var pill := _make_state_pill_node(text, color)
	states.add_child(pill)
	pill.scale = Vector2(0.5, 0.5)
	pill.resized.connect(func() -> void:
		pill.pivot_offset = pill.size * 0.5
	, CONNECT_ONE_SHOT)
	var tw := create_tween()
	tw.tween_property(pill, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(pill, "modulate:a", 0.0, 0.4)
	get_tree().create_timer(2.4).timeout.connect(pill.queue_free)

# ═══════════════════════════════════════════════════════════
#  Polish combat — item 9 (notification d'évolution)
# ═══════════════════════════════════════════════════════════

func _on_entity_ready_to_evolve(entity_id: String) -> void:
	# Recompte la liste éligible (jamais d'incrément) à chaque franchissement.
	_refresh_evolve_counter()
	if not AdventureSystem.is_running:
		return
	var entity := GameData.get_entity(entity_id)
	var nom    := Translations.entity_name(entity, entity_id)
	var tier   := int(entity.get("maitrise_actuelle", 0))
	var target := UIColors.tier_color(mini(tier + 1, 5))
	# Toast sous la barre de l'entité concernée (créature à droite, sinon héros).
	_push_under_bar_pill(_states_for_entity(entity), Translations.T("combat.ready_evolve") % nom, target)
	# Carillon court et sec (même famille que le crystal du rituel d'évolution) :
	# marque le coup quand une entité devient éligible.
	AudioManager.play_sfx("evolve_ready", -5.0)
	# Tâche B — flash de palier : halo de la couleur du palier cible, ancré sur
	# l'entité concernée (héros / créature) ou au centre de l'arène.
	if is_instance_valid(_xp_fx_layer):
		UIHelpers.tier_halo_burst(_xp_fx_layer, _evolve_anchor(entity), target)

# Une entité a évolué (action joueur, hors combat) → recompte la liste éligible.
func _on_entity_evolved(_entity_id: String, _new_tier: int) -> void:
	_refresh_evolve_counter()

# ─── Compteur « prêtes à évoluer » ──────────────────────────
# Recompte INTÉGRALEMENT les entités éligibles (MasterySystem.can_evolve =
# source de vérité : seuil franchi ET palier suivant disponible) — pas
# d'incrément/décrément, donc aucune dérive. Met à jour le badge et masque
# quand 0.
func _refresh_evolve_counter() -> void:
	_evolve_ready_ids.clear()
	var best_target := 0   # meilleur palier cible parmi les entités prêtes → teinte du badge
	for eid: String in GameData.entities:
		if MasterySystem.can_evolve(eid):
			_evolve_ready_ids.append(eid)
			var t := int(GameData.get_entity(eid).get("maitrise_actuelle", 0)) + 1
			best_target = maxi(best_target, mini(t, Balance.GLOBAL_MAX_TIER))
	if not is_instance_valid(_evolve_badge):
		return
	var n := _evolve_ready_ids.size()
	_evolve_badge.visible = n > 0
	if n > 0:
		_evolve_badge_lbl.text = Translations.T("combat.evolve_badge") % n
		# Pastille teintée à la rareté du meilleur palier prêt (code couleur standard).
		var c := UIColors.tier_color(best_target)
		var bs := StyleBoxFlat.new()
		bs.bg_color     = Color(c.r, c.g, c.b, 0.95)
		bs.border_color = Color(0, 0, 0, 0.55)
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(9)
		bs.content_margin_left = 7; bs.content_margin_right = 7
		bs.content_margin_top  = 1; bs.content_margin_bottom = 1
		_evolve_badge.add_theme_stylebox_override("panel", bs)

# Tooltip de survol du bouton : liste des entités prêtes (nom + palier actuel →
# palier cible). Aucun tooltip si rien n'est prêt (le bouton reste normal).
# Chaque palier est colorié à sa rareté via UIColors.tier_color (BBCode), le
# nom de l'entité prend la couleur de son palier cible.
func _show_evolve_tooltip() -> void:
	if _evolve_ready_ids.is_empty():
		return
	var lines: PackedStringArray = []
	var accent_tier := 0   # palier cible le plus élevé → couleur d'accent du tooltip
	for eid: String in _evolve_ready_ids:
		var e      := GameData.get_entity(eid)
		var tier   := int(e.get("maitrise_actuelle", 0))
		var target := mini(tier + 1, Balance.GLOBAL_MAX_TIER)
		accent_tier = maxi(accent_tier, target)
		var cur_c  := UIColors.tier_color(tier).to_html(false)
		var tgt_c  := UIColors.tier_color(target).to_html(false)
		lines.append("[color=#%s]%s[/color]  [color=#%s]%s[/color] → [color=#%s]%s[/color]" % [
				tgt_c, Translations.entity_name(e, eid),
				cur_c, GameData.get_tier_name(tier),
				tgt_c, GameData.get_tier_name(target)])
	TooltipOverlay.show_for(
			Translations.T("combat.evolve_tt_title") % _evolve_ready_ids.size(),
			"\n".join(lines),
			UIColors.tier_color(accent_tier))
