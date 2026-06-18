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

# ─── Filtres du journal ──────────────────────────────────────
const LOG_TAB_KEYS: Array[String] = ["all", "hero", "monster", "attack", "defense", "heal", "status"]

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
var _hero_stats_panel:  PanelContainer
var _hero_stats_rows:   VBoxContainer
var _enemy_stats_panel: PanelContainer
var _enemy_stats_rows:  VBoxContainer

# ─── Feed passifs ────────────────────────────────────────────
var _feed_box:  HBoxContainer
var _feed_wrap: CenterContainer   # masqué quand vide → ne réserve aucune place

# ─── Journal ─────────────────────────────────────────────────
var _log_vbox:    VBoxContainer
var _log_entries: Array = []          # [{node: RichTextLabel, tags: Array}]
var _log_filter:  String = "all"
var _tab_buttons: Dictionary = {}     # nom → Button

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
var _loot_banner:  PanelContainer        # cible « qui encaisse »
var _loot_row:     HBoxContainer         # rangée de pastilles empilées
var _loot_hint:    Label                 # libellé affiché quand le bandeau est vide
var _loot_pellets: Dictionary = {}       # item_id → {box: Control, count: Label, qty: int}

# ─── Couche FX (halos de palier) ─────────────────────────────
# Plein écran, transparente à la souris : reçoit le burst de halo coloré quand
# une entité atteint son palier (entity_ready_to_evolve). L'XP flottante par
# entité a été retirée (chiffres bruts illisibles en plein combat).
var _xp_fx_layer:    Control                # couche plein écran pour les halos de palier

# ─── Overlays (zone + Unique) ────────────────────────────────
var _zone_panel:   PanelContainer = null   # petit panneau strate, centré sur la barre VS
var _zone_label:   Label   = null
var _unique_panel: Control = null

# ─── État ────────────────────────────────────────────────────
var _cycle_xp:    float = 0.0
var _navigating:  bool  = false
var _hero_shield: float = 0.0

# ─── Jauges ATB honnêtes (refonte temps réel) ───────────────
# Chaque barre se remplit en continu à la cadence RÉELLE de son combattant
# (CombatPlayer.*_atb_interval), indépendamment de l'autre : un combattant
# rapide remplit visiblement plus vite. La jauge est pleine pile au moment où
# le combattant frappe, puis se vide et redémarre.
var _hero_atb_tween:  Tween = null
var _enemy_atb_tween: Tween = null
# Fenêtre de hâte (rail de vitesse) : tween d'ordonnancement on/off du feedback.
var _hero_haste_tween:  Tween = null
var _enemy_haste_tween: Tween = null

# ─── Polish combat ──────────────────────────────────────────
var _danger_pulse_tween: Tween   = null   # pulse PV critique (item 5)
var _shield_state_pill:  Control = null   # pill bouclier bleue  (item 8)
var _poison_state_pill:  Control = null   # pill venin violette  (item 8)
var _hero_haste_pill:    Control = null   # pill « Hâte » héros (rail de vitesse)
var _enemy_haste_pill:   Control = null   # pill « Hâte » créature
var _mechanic_label:     Label   = null   # badge mécanique forte permanente (item 4)
var _stinger:            Control = null   # bandeau d'événement piège/bénédiction
var _evolve_chime: AudioStreamPlayer = null  # carillon « prête à évoluer »

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
	root.add_child(_build_feed())
	if LOG_ENABLED:
		root.add_child(_build_log())
	root.add_child(_build_bottom_bar())

	_build_zone_label()
	_build_mechanic_label()

	# Couche FX pour les halos de palier : par-dessus la zone de combat, sous les
	# stingers (z 90+). Transparente à la souris.
	_xp_fx_layer = Control.new()
	_xp_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fx_layer.z_index = 50
	add_child(_xp_fx_layer)

	_build_audio()

# ── Audio : carillon « prête à évoluer » ────────────────────
# Son généré procéduralement (même famille que le crystal du rituel d'évolution)
# mais plus court et plus sec — une cloche/notification brève.
func _build_audio() -> void:
	_evolve_chime = AudioStreamPlayer.new()
	_evolve_chime.volume_db = -5.0
	# Pas de bus dédié dans ce projet : on garde "Master" (défaut) plutôt que
	# "SFX" (inexistant → erreur runtime).
	_evolve_chime.stream    = _generate_chime_wav()
	add_child(_evolve_chime)

# Cloche brillante (fondamentale + harmoniques inharmoniques) à décroissance
# rapide : attaque sèche, ~0,5 s mais éteinte bien avant. Mono 16 bits.
func _generate_chime_wav() -> AudioStreamWAV:
	var sr        := 22050
	var freq      := 1318.5            # mi aigu — clair, type notification
	var n_samples := int(sr * 0.5)
	var data      := PackedByteArray()
	data.resize(n_samples * 2)
	for i: int in n_samples:
		var t        := float(i) / float(sr)
		var envelope := exp(-t * 13.0)
		var sample_f := (sin(t * freq * TAU) * 0.60
					   + sin(t * freq * 2.01 * TAU) * 0.26
					   + sin(t * freq * 3.02 * TAU) * 0.12) * envelope
		var v := clampi(int(sample_f * 0.55 * 32767.0), -32768, 32767)
		data[i * 2 + 0] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = sr
	wav.data     = data
	return wav

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
	_hero_stats_panel = _make_stats_panel(true)
	area.add_child(_hero_stats_panel)
	_enemy_stats_panel = _make_stats_panel(false)
	area.add_child(_enemy_stats_panel)
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

# Encadré de stats ancré dans un coin haut de la zone de combat (gauche =
# héros, droite = créature). Auto-dimensionné, transparent à la souris,
# masqué jusqu'à ce qu'on le remplisse.
func _make_stats_panel(is_hero: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	# Style « plaque JRPG » du jeu, re-teinté au palier dans _style_mini_panel.
	_style_mini_panel(panel, UIColors.CARD_NEUTRAL)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	# Coin haut, auto-dimensionné : on pose un rect de taille nulle dans le coin
	# et on laisse grow_* l'agrandir vers le contenu (motif Godot standard).
	# offset_top = 36 : juste sous la bande des labels Zone (centre) et
	# Mécanique forte (coin haut-droite), pour ne pas les recouvrir.
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_top = 36
	panel.offset_bottom = 36
	panel.grow_vertical = Control.GROW_DIRECTION_END
	if is_hero:
		panel.anchor_left = 0.0
		panel.anchor_right = 0.0
		panel.grow_horizontal = Control.GROW_DIRECTION_END
		panel.offset_left = 10
		panel.offset_right = 10
	else:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.offset_left = -10
		panel.offset_right = -10

	var m := UIHelpers.margin_of(8)
	panel.add_child(m)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(rows)
	if is_hero:
		_hero_stats_rows = rows
	else:
		_enemy_stats_rows = rows
	return panel

# Style « mini plaque » dans la DA du jeu : fond sombre translucide (lisible
# par-dessus le fond animé) + bordure teintée au palier + coins arrondis + ombre.
func _style_mini_panel(panel: PanelContainer, color: Color) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color     = Color(0.04, 0.05, 0.09, 0.90)
	st.border_color = Color(color.r, color.g, color.b, 0.70)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size  = 6
	panel.add_theme_stylebox_override("panel", st)

# (Re)remplit un encadré de stats : titre palier coloré + filet + PV/ATK/DEF/VIT.
# Re-teinte aussi le cadre à la couleur du palier (DA cohérente avec les cartes).
func _fill_stats_panel(panel: PanelContainer, rows: VBoxContainer, color: Color,
		tier: int, pv: int, atk: int, def: int, vit: int) -> void:
	_style_mini_panel(panel, color)
	for c in rows.get_children():
		c.free()
	var tier_lbl := Label.new()
	tier_lbl.text = GameData.get_tier_name(tier).to_upper()
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.add_theme_font_size_override("font_size", 10)
	tier_lbl.add_theme_color_override("font_color", color)
	rows.add_child(tier_lbl)
	# Filet séparateur teinté sous le titre.
	var sep := ColorRect.new()
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.color                 = Color(color.r, color.g, color.b, 0.35)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(sep)
	_add_stat_row(rows, Translations.T("hero.stat.hp"),  pv,  UIColors.STAT_HP)
	_add_stat_row(rows, Translations.T("hero.stat.atk"), atk, UIColors.STAT_ATK)
	_add_stat_row(rows, Translations.T("hero.stat.def"), def, UIColors.STAT_DEF)
	_add_stat_row(rows, Translations.T("hero.stat.vit"), vit, UIColors.FILTER_ON)

# Calcule les stats effectives du héros (mêmes sources que combat_player :
# base + équipement, VIT accélérée par attack_speed_pct) et remplit/affiche
# son encadré (haut-gauche).
func _refresh_hero_stats(htier: int) -> void:
	if _hero_stats_rows == null:
		return
	var hstats := GameData.get_effective_stats("hero")
	var heqp   := GameData.get_equipment_bonuses()
	var vit := int(round(float(hstats.get("vit", 20)) \
			* (1.0 + float(heqp.get("attack_speed_pct", 0.0)) / 100.0)))
	_fill_stats_panel(_hero_stats_panel, _hero_stats_rows, UIColors.tier_color(htier), htier,
			int(AdventureSystem.get_max_hp()),
			int(hstats.get("atk", 0)) + int(heqp.get("atk", 0)),
			int(hstats.get("def", 0)) + int(heqp.get("def", 0)),
			vit)
	_hero_stats_panel.visible = true

func _add_stat_row(rows: VBoxContainer, label: String, value: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(34, 0)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color)
	row.add_child(l)
	var v := Label.new()
	v.text = str(value)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(v)
	rows.add_child(row)

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
	var action := Label.new()
	action.text = "—"
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.add_theme_font_size_override("font_size", 14)
	action.add_theme_constant_override("outline_size", 3)
	action.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	action.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
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
# Chaque barre est coiffée par-dessous d'une rangée de pills d'état (bonus/malus :
# bouclier, venin, hâte) alignée sous le bord du combattant (gauche pour le héros,
# droite pour la créature miroir).
# Les labels de nom vivent DANS les barres (_hero_name/_enemy_name : .text + tooltips).
func _build_combatant_bars() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",  12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_bottom", 2)

	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 0)
	m.add_child(band)

	# Colonne héros : barre + rangée d'états dessous (alignée à gauche).
	var hero_col := VBoxContainer.new()
	hero_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_col.size_flags_stretch_ratio = 1.0
	hero_col.add_theme_constant_override("separation", 0)
	_hero_bar = CombatBar.new()
	_hero_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_col.add_child(_hero_bar)
	_hero_states = _make_states_row(false)
	hero_col.add_child(_hero_states)
	band.add_child(hero_col)

	# Espaceur central (~le tiers d'une barre) : écarte les deux barres du centre.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.42
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(spacer)

	# Colonne créature : barre miroir + rangée d'états dessous (alignée à droite).
	var enemy_col := VBoxContainer.new()
	enemy_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_col.size_flags_stretch_ratio = 1.0
	enemy_col.add_theme_constant_override("separation", 0)
	_enemy_bar = CombatBar.new()
	_enemy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_bar.mirrored = true
	enemy_col.add_child(_enemy_bar)
	_enemy_states = _make_states_row(true)
	enemy_col.add_child(_enemy_states)
	band.add_child(enemy_col)

	_hero_name  = _hero_bar.name_label
	_enemy_name = _enemy_bar.name_label
	return m

# Rangée de pills d'état juste sous la barre ATB. Aucune hauteur réservée :
# tant qu'aucun bonus/malus n'est présent, la rangée est vide donc plate (zéro
# place prise). `align_right` cale les pills sous le bord droit (créature miroir).
func _make_states_row(align_right: bool) -> HBoxContainer:
	var states := HBoxContainer.new()
	states.alignment = BoxContainer.ALIGNMENT_END if align_right else BoxContainer.ALIGNMENT_BEGIN
	states.add_theme_constant_override("separation", 4)
	states.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return states

# ── Feed passifs ───────────────────────────────────────────
# Masqué tant qu'aucun toast n'est affiché : le VBox racine ne lui alloue alors
# ni hauteur ni séparation → plus d'espace vide entre les barres et le butin.
func _build_feed() -> Control:
	_feed_wrap = CenterContainer.new()
	_feed_wrap.visible = false
	_feed_box = HBoxContainer.new()
	_feed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_feed_box.add_theme_constant_override("separation", 6)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_wrap.add_child(_feed_box)
	return _feed_wrap

# Replie le feed dès qu'il ne reste plus aucun toast vivant (ignore ceux en
# cours de libération). Branché sur tree_exited de chaque toast.
func _update_feed_visibility() -> void:
	if not is_instance_valid(_feed_wrap):
		return
	for c in _feed_box.get_children():
		if c is Control and not (c as Node).is_queued_for_deletion():
			_feed_wrap.visible = true
			return
	_feed_wrap.visible = false

# ── Journal à onglets ──────────────────────────────────────
func _build_log() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.custom_minimum_size = Vector2(0, 180)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	outer.add_child(tabs)
	var tab_labels := Translations.log_tabs()
	for i in LOG_TAB_KEYS.size():
		var key := LOG_TAB_KEYS[i]
		var b := Button.new()
		b.text = tab_labels[i]
		b.toggle_mode = true
		b.button_pressed = (key == _log_filter)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var is_active := (key == _log_filter)
		var tc := UIColors.FILTER_ON if is_active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color",         tc)
		b.add_theme_color_override("font_pressed_color", UIColors.FILTER_ON)
		b.add_theme_color_override("font_hover_color",   Color(1, 1, 1, 0.75))
		b.add_theme_stylebox_override("normal",   UIHelpers.card_style(tc, 0.0 if not is_active else 0.12, 0.0 if not is_active else 0.50, 1 if is_active else 0, 4))
		b.add_theme_stylebox_override("pressed",  UIHelpers.card_style(UIColors.FILTER_ON, 0.12, 0.50, 1, 4))
		b.add_theme_stylebox_override("hover",    UIHelpers.card_style(UIColors.TEXT_MUTED, 0.08, 0.30, 0, 4))
		b.pressed.connect(_set_filter.bind(key))
		tabs.add_child(b)
		_tab_buttons[key] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var panel := PanelContainer.new()
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIHelpers.card_style(UIColors.CARD_NEUTRAL, 0.05, 0.30, 1, 4))
	outer.add_child(panel)
	var m := UIHelpers.margin_of(6)
	panel.add_child(m)
	m.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_log_vbox)
	return outer

# ── Barre de bas ───────────────────────────────────────────
# Bandeau de butin (gauche) ↔ bouton fin d'expédition (droite).
func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	# Bandeau de butin du cycle : encaisse les pastilles venues de la créature.
	bar.add_child(_build_loot_banner())

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

	var label := Label.new()
	label.text = Translations.T("combat.end_btn")
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", tcolor)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)

	# Badge « ▲ N » : pastille colorée à la rareté du meilleur palier prêt
	# (UIColors.tier_color), masquée tant qu'aucune entité n'est prête.
	_evolve_badge = PanelContainer.new()
	_evolve_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_evolve_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_evolve_badge.visible = false
	_evolve_badge_lbl = Label.new()
	_evolve_badge_lbl.add_theme_font_size_override("font_size", 13)
	_evolve_badge_lbl.add_theme_color_override("font_color", Color.WHITE)
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

# Bandeau de butin : titre + rangée de pastilles. Sa propre case « encaisse »
# (impact) à chaque ingrédient qui s'y empile. Vidé à chaque début d'expédition.
func _build_loot_banner() -> Control:
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("margin_left",   5)
	wrap.add_theme_constant_override("margin_bottom", 4)

	_loot_banner = PanelContainer.new()
	_loot_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_banner.custom_minimum_size = Vector2(0, 42)
	_loot_banner.add_theme_stylebox_override("panel",
			UIHelpers.card_style(UIColors.LOG_LOOT, 0.06, 0.45, 1, 6))
	wrap.add_child(_loot_banner)

	# Marge serrée (6 px) pour laisser un maximum de hauteur aux pastilles.
	var m := UIHelpers.margin_of(6)
	_loot_banner.add_child(m)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(inner)

	var title := Label.new()
	title.text = Translations.T("combat.loot.title")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UIColors.LOG_LOOT)
	inner.add_child(title)

	_loot_row = HBoxContainer.new()
	_loot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_row.add_theme_constant_override("separation", 6)
	inner.add_child(_loot_row)

	_loot_hint = Label.new()
	_loot_hint.text = Translations.T("combat.loot.empty")
	_loot_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loot_hint.add_theme_font_size_override("font_size", 12)
	_loot_hint.add_theme_color_override("font_color", UIColors.TEXT_MUTED)
	_loot_row.add_child(_loot_hint)
	return wrap

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
	_reset_loot_banner()
	_refresh_evolve_counter()
	_update_zone_label(AdventureSystem.zone_courante)
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
	_refresh_hero_stats(htier)

	# Colonne ennemi en attente (vide) jusqu'au premier événement.
	_enemy_name.text = "—"
	_enemy_bar.setup(UIColors.TEXT_MUTED)
	_enemy_bar.set_hp(0, 1)
	_hide_action(_enemy_action)

	if _mechanic_label:
		_mechanic_label.visible = false
	match BiomeMechanics.active_mechanic:
		"ambush":
			var ac := Color(1.0, 0.42, 0.10)
			_push_feed(Translations.mech_name("ambush"), ac)
			_show_mechanic_label("⚡ " + Translations.mech_name("ambush"), ac)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("ambush"),
					Translations.mech_desc("ambush"), ac)
		"poison":
			var pc := Color(0.62, 0.15, 0.78)
			_push_feed(Translations.mech_name("poison"), pc)
			_show_mechanic_label("☠ " + Translations.mech_name("poison"), pc)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("poison"),
					Translations.mech_desc("poison"), pc)
		"endurcissement":
			var ec := Color(0.80, 0.55, 0.25)
			_push_feed(Translations.mech_name("endurcissement"), ec)
			_show_mechanic_label("🗻 " + Translations.mech_name("endurcissement"), ec)
			UIHelpers.register_tooltip(_mechanic_label, Translations.mech_name("endurcissement"),
					Translations.mech_desc("endurcissement"), ec)

func _on_event_resolved(event_data: Dictionary) -> void:
	match event_data.get("type", ""):
		Enums.EntityType.TRAP:
			# Piège : effet annoncé au centre (stinger) → pas d'encadré de stats.
			# Pas de combattant adverse : la boule créature reste masquée.
			_enemy_stats_panel.visible = false
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
			_show_event_stinger(Translations.T("combat.stinger.trap"), tname,
					trap_detail, UIColors.TYPE_TRAP, not ignored)
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
			_enemy_stats_panel.visible = false
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
			_show_event_stinger(Translations.T("combat.stinger.bless"), bname,
					bdesc, UIColors.TYPE_BENEDICTION, false)
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
	_refresh_hero_stats(htier)
	_fill_stats_panel(_enemy_stats_panel, _enemy_stats_rows, UIColors.tier_color(etier), etier,
			int(enemy_hp),
			int(enemy.get("atk", 0)),
			int(enemy.get("def", 0)),
			int(enemy.get("vit", 0)))
	_enemy_stats_panel.visible = true

	# Jauges ATB honnêtes : chaque barre démarre sa charge à la cadence réelle de
	# son combattant ; elle sera pleine pile quand il frappera (puis redémarre à
	# chaque coup, cf. _on_step_ended).
	_charge_atb(true,  CombatPlayer.hero_atb_interval)
	_charge_atb(false, CombatPlayer.enemy_atb_interval)
	_hide_action(_hero_action)
	_hide_action(_enemy_action)
	_hero_shield = 0.0
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

	var is_hero := step.attacker == "hero"
	var lbl  := _hero_action if is_hero else _enemy_action
	var base_col := UIColors.STAT_ATK if is_hero else UIColors.TYPE_TRAP
	_show_action(lbl, Translations.T("combat.action.crit") if step.is_crit else Translations.T("combat.action.attack"),
			UIColors.FILTER_ON if step.is_crit else base_col)

# Lance (ou relance) la charge continue d'une jauge ATB sur `interval` secondes
# de lecture : la barre va de 0 à 1 puis reste pleine jusqu'à la prochaine
# relance (au coup suivant du combattant). Honnête : un combattant rapide a un
# `interval` plus court, donc une jauge qui monte plus vite.
func _charge_atb(is_hero: bool, interval: float) -> void:
	var bar := _hero_bar if is_hero else _enemy_bar
	if is_hero:
		if _hero_atb_tween and _hero_atb_tween.is_valid():
			_hero_atb_tween.kill()
	else:
		if _enemy_atb_tween and _enemy_atb_tween.is_valid():
			_enemy_atb_tween.kill()
	bar.set_atb(0.0)
	var tw := create_tween()
	tw.tween_method(bar.set_atb, 0.0, 1.0, maxf(interval, 0.05)).set_ease(Tween.EASE_IN)
	if is_hero:
		_hero_atb_tween = tw
	else:
		_enemy_atb_tween = tw

# Stoppe les charges ATB en cours (fin de combat / arrêt d'expédition).
func _stop_atb() -> void:
	if _hero_atb_tween and _hero_atb_tween.is_valid():
		_hero_atb_tween.kill()
	if _enemy_atb_tween and _enemy_atb_tween.is_valid():
		_enemy_atb_tween.kill()

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
	if is_hero:
		_hero_haste_tween = tw
	else:
		_enemy_haste_tween = tw

# Active/coupe le feedback hâte : jauge ATB teintée + pill « Hâte ».
func _set_haste_active(is_hero: bool, active: bool) -> void:
	var bar := _hero_bar if is_hero else _enemy_bar
	if is_instance_valid(bar):
		bar.set_haste(active)
	if active:
		var states := _hero_states if is_hero else _enemy_states
		var existing := _hero_haste_pill if is_hero else _enemy_haste_pill
		if (existing == null or not is_instance_valid(existing)) and states:
			var pill := _make_state_pill_node("⚡ " + Translations.T("combat.haste_pill"), UIColors.HASTE)
			states.add_child(pill)
			if is_hero:
				_hero_haste_pill = pill
			else:
				_enemy_haste_pill = pill
	else:
		_remove_haste_pill(is_hero)

func _remove_haste_pill(is_hero: bool) -> void:
	var pill := _hero_haste_pill if is_hero else _enemy_haste_pill
	if pill and is_instance_valid(pill):
		pill.queue_free()
	if is_hero:
		_hero_haste_pill = null
	else:
		_enemy_haste_pill = null

# Coupe tout feedback hâte en cours (changement de rencontre / fin de combat).
func _clear_haste() -> void:
	if _hero_haste_tween and _hero_haste_tween.is_valid():
		_hero_haste_tween.kill()
	if _enemy_haste_tween and _enemy_haste_tween.is_valid():
		_enemy_haste_tween.kill()
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
		if step.shield_absorbed > 0:
			_hero_shield = maxf(_hero_shield - float(step.shield_absorbed), 0.0)
			_update_shield_pill(int(_hero_shield))
			_add_log("[color=%s]%s[/color]"
					% [_hex(Color(0.3, 0.7, 1.0)), Translations.T("combat.shield_absorb") % step.shield_absorbed], ["defense", "status"])
		if step.damage > 0:
			_hero_bar.update_hp(float(step.target_hp_after))
			_hero_bar.damage(step.damage, step.is_crit)
			if step.is_crit:
				_screen_shake(1.7)
			if step.is_killing_blow:
				_kill_impact(_hero_bar)
			_fighter_take(_hero_fighter, step.is_killing_blow)
			_check_danger_pulse()
		elif step.shield_absorbed > 0:
			_hero_bar.update_hp(float(step.target_hp_after))
		if step.is_shield_proc:
			_hero_shield = float(step.shield_value)
			_push_feed(Translations.T("combat.shield_pill") % step.shield_value, Color(0.3, 0.7, 1.0))
			_update_shield_pill(int(_hero_shield))
			_add_log("[color=%s]%s[/color]" % [_hex(Color(0.3, 0.7, 1.0)), Translations.T("combat.shield_proc")], ["defense", "status"])
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
	_push_under_bar_pill(_hero_states, "☠ -%d" % int(damage), Color(0.62, 0.15, 0.78))
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

# Vide le bandeau (nouveau cycle) : pastilles retirées, indice « vide » rétabli.
func _reset_loot_banner() -> void:
	if not _loot_row:
		return
	for child in _loot_row.get_children():
		if child != _loot_hint:
			child.queue_free()
	_loot_pellets.clear()
	if _loot_hint:
		_loot_hint.visible = true

# drops : Array de { item_id, name, qty }. source_name non utilisé ici.
func _on_loot_dropped(drops: Array, _source_name: String) -> void:
	for d in drops:
		var item_id := String(d.get("item_id", ""))
		if item_id == "":
			continue
		var ingr := GameData.get_entity(item_id)
		var nom  := Translations.entity_name(ingr, String(d.get("name", item_id)))
		_spawn_loot_pellet(item_id, nom, int(d.get("qty", 1)))

# Badge rond placeholder (en attendant les icônes de Christophe) :
# pastille colorée + initiale du nom.
func _make_loot_badge(color: Color, initial: String, diameter: int) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(diameter, diameter)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color     = Color(color.r, color.g, color.b, 0.92)
	st.border_color = color.lightened(0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(int(diameter / 2))
	st.shadow_color = Color(0, 0, 0, 0.40)
	st.shadow_size  = 4
	badge.add_theme_stylebox_override("panel", st)
	var lbl := Label.new()
	lbl.text = initial
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", int(diameter * 0.5))
	lbl.add_theme_color_override("font_color", Color(0.06, 0.06, 0.09))
	badge.add_child(lbl)
	return badge

# Une pastille jaillit de l'anneau de la créature (centre-droit de l'arène),
# fait un pop sur place, puis vole en arc vers le bandeau et s'y empile.
func _spawn_loot_pellet(item_id: String, item_name: String, qty: int) -> void:
	var color   := UIColors.loot_color(item_id)
	var initial := item_name.substr(0, 1).to_upper() if item_name != "" else "?"
	const D := 33   # +25 % vs taille du bandeau, pour bien la voir jaillir
	var half := Vector2(D, D) * 0.5

	# Origine : centre de la boule d'énergie de la créature (là où elle « lâche »
	# l'ingrédient), pas sa barre ATB. Fallbacks : barre créature, puis centre-droit.
	var start_c := size * Vector2(0.72, 0.40)
	if _enemy_fighter and is_instance_valid(_enemy_fighter) and _enemy_fighter.visible:
		start_c = _enemy_fighter.global_position + _enemy_fighter.size * 0.5
	elif _enemy_bar and is_instance_valid(_enemy_bar):
		start_c = _enemy_bar.global_position + _enemy_bar.size * 0.5
	# Cible : tiers gauche du bandeau (fallback : coin bas-gauche).
	var end_c := size * Vector2(0.10, 0.95)
	if _loot_banner and is_instance_valid(_loot_banner):
		end_c = _loot_banner.global_position + _loot_banner.size * Vector2(0.15, 0.5)

	var pellet := _make_loot_badge(color, initial, D)
	pellet.z_index = 120
	add_child(pellet)
	pellet.pivot_offset    = half
	pellet.global_position = start_c - half
	pellet.scale           = Vector2(0.3, 0.3)

	var arc_h := 60.0 + absf(end_c.x - start_c.x) * 0.10

	var tw := create_tween()
	# Jaillissement : pop élastique sur place.
	tw.tween_property(pellet, "scale", Vector2(1.05, 1.05), 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Vol en arc vers le bandeau (apex via sinus). Lambda mono-ligne : un corps
	# multi-ligne en argument non-final casse l'indentation côté GDScript.
	tw.tween_method(func(t: float) -> void: pellet.set("global_position",
			start_c.lerp(end_c, t) - Vector2(0.0, arc_h * sin(PI * t)) - half),
			0.0, 1.0, 0.46).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Léger rétrécissement en approche (s'écrase dans le bandeau).
	tw.parallel().tween_property(pellet, "scale", Vector2(0.7, 0.7), 0.46) \
			.set_ease(Tween.EASE_IN)
	# Atterrissage : empilement + impact du bandeau.
	tw.tween_callback(func() -> void:
		pellet.queue_free()
		_loot_land(item_id, item_name, qty, color, initial)
	)

# La pastille atterrit : crée son entrée dans le bandeau, ou incrémente le
# compteur de l'entrée existante (×2, ×3…) avec un punch. Le bandeau encaisse.
func _loot_land(item_id: String, item_name: String, qty: int, color: Color, initial: String) -> void:
	if _loot_hint:
		_loot_hint.visible = false
	_punch(_loot_banner, 1.03)

	if _loot_pellets.has(item_id):
		var entry: Dictionary = _loot_pellets[item_id]
		entry["qty"] = int(entry["qty"]) + qty
		var cl: Label = entry["count"]
		cl.text    = "×%d" % int(entry["qty"])
		cl.visible = int(entry["qty"]) > 1
		_punch(entry["box"], 1.25)
		return

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	# Badge dimensionné au max de la hauteur utile du bandeau (≈ 42 − 2×6).
	box.add_child(_make_loot_badge(color, initial, 30))
	var nm := Label.new()
	nm.text = item_name
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(nm)
	var cnt := Label.new()
	cnt.text    = "×%d" % qty
	cnt.visible = qty > 1
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.add_theme_font_size_override("font_size", 14)
	cnt.add_theme_color_override("font_color", UIColors.LOG_LOOT)
	box.add_child(cnt)
	_loot_row.add_child(box)
	_loot_pellets[item_id] = {"box": box, "count": cnt, "qty": qty}

	# Pop d'apparition (pivot connu une fois la taille calculée).
	box.scale = Vector2(0.6, 0.6)
	box.resized.connect(func() -> void:
		box.pivot_offset = box.size * 0.5
	, CONNECT_ONE_SHOT)
	create_tween().tween_property(box, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Petit « punch » de mise à l'échelle (impact d'encaissement).
func _punch(node: Control, amount: float) -> void:
	if not node or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(amount, amount), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Position d'ancrage du halo de palier selon le type de l'entité.
func _evolve_anchor(entity: Dictionary) -> Vector2:
	var etype := String(entity.get("entity_type", ""))
	if etype == Enums.EntityType.HERO and _hero_bar and is_instance_valid(_hero_bar):
		return _hero_bar.global_position + _hero_bar.size * 0.5
	if etype == Enums.EntityType.CREATURE and _enemy_bar and is_instance_valid(_enemy_bar):
		return _enemy_bar.global_position + _enemy_bar.size * 0.5
	return size * Vector2(0.5, 0.40)

# ═══════════════════════════════════════════════════════════
#  Animation cooldown / shake / feed
# ═══════════════════════════════════════════════════════════

# ─── Stinger d'événement (piège / bénédiction) ──────────────
# Bandeau central impossible à rater : flash plein écran teinté +
# slam-in (scale TRANS_BACK), maintien ~AFFICHAGE_EVENEMENT, fondu.
# Résout « je ne vois jamais les pièges/bénédictions » : sans journal,
# le seul indice était le nom dans la colonne ennemie pendant 2,5 s.
func _show_event_stinger(title: String, name_txt: String, detail: String,
		color: Color, danger: bool) -> void:
	if is_instance_valid(_stinger):
		_stinger.queue_free()

	# Flash plein écran teinté (rouge danger / vert bénédiction).
	var flash := ColorRect.new()
	flash.color = Color(color.r, color.g, color.b, 0.18)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 90
	add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	ftw.tween_callback(flash.queue_free)

	# Bandeau centré dans le tiers haut de la zone de combat.
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.anchor_bottom = 0.58
	holder.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	holder.z_index       = 95
	add_child(holder)
	_stinger = holder

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.04, 0.05, 0.09, 0.94)
	ps.border_color = Color(color.r, color.g, color.b, 0.95)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.shadow_color = Color(color.r, color.g, color.b, 0.35)
	ps.shadow_size  = 16
	panel.add_theme_stylebox_override("panel", ps)
	holder.add_child(panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)

	var kind_lbl := Label.new()
	kind_lbl.text = title
	kind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_lbl.add_theme_font_size_override("font_size", 12)
	kind_lbl.add_theme_color_override("font_color", color.lightened(0.25))
	vb.add_child(kind_lbl)

	var name_lbl := Label.new()
	name_lbl.text = name_txt.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	vb.add_child(name_lbl)

	if detail != "":
		var detail_lbl := Label.new()
		detail_lbl.text = detail
		detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_lbl.add_theme_font_size_override("font_size", 17)
		detail_lbl.add_theme_color_override("font_color", color.lightened(0.30))
		detail_lbl.add_theme_constant_override("outline_size", 4)
		detail_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		vb.add_child(detail_lbl)

	if danger:
		_screen_shake()

	# Slam-in → maintien → fondu de sortie.
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_callback(func() -> void:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(1.35, 1.35)
	)
	tw.set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# set_parallel(false) : tout ce qui suit redevient séquentiel (chain()
	# ne chaînerait que le tweener suivant, le fondu partirait trop tôt).
	tw.set_parallel(false)
	tw.tween_interval(maxf(Balance.AFFICHAGE_EVENEMENT - 0.3, 0.6))
	tw.tween_property(holder, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)

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

# Ajoute un pill transitoire dans le feed (pop-in, disparaît après ~2s).
func _push_feed(text: String, color: Color) -> void:
	if not _feed_box:
		return
	var box := PanelContainer.new()
	var style := UIHelpers.card_style(color, 0.26, 0.90, 1, 9)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 2
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_color_override("font_color", color.lightened(0.30))
	box.add_child(lbl)
	_feed_box.add_child(box)
	# Déplie le feed (replié à vide) et le replie quand ce toast disparaît.
	if is_instance_valid(_feed_wrap):
		_feed_wrap.visible = true
	box.tree_exited.connect(_update_feed_visibility)
	# Pop-in (pivot connu une fois la taille calculée).
	box.scale = Vector2(0.5, 0.5)
	box.resized.connect(func() -> void:
		box.pivot_offset = box.size * 0.5
	, CONNECT_ONE_SHOT)
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	# Suppression garantie via un SceneTreeTimer indépendant du Tween.
	get_tree().create_timer(2.6).timeout.connect(box.queue_free)

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

# Ajoute une entrée de log (la plus récente en haut), taguée pour le filtre.
# No-op tant que LOG_ENABLED est false (journal non construit).
func _add_log(bbcode: String, tags: Array) -> void:
	if not LOG_ENABLED:
		return
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content    = true
	rt.scroll_active  = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 12)
	rt.text = bbcode
	_log_vbox.add_child(rt)
	_log_vbox.move_child(rt, 0)
	_log_entries.push_front({"node": rt, "tags": tags})
	rt.visible = _matches_filter(tags)

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

func _set_filter(tab: String) -> void:
	_log_filter = tab
	for tab_name: String in _tab_buttons:
		var b: Button = _tab_buttons[tab_name]
		var active := (tab_name == tab)
		b.button_pressed = active
		var tc := UIColors.FILTER_ON if active else UIColors.TEXT_MUTED
		b.add_theme_color_override("font_color", tc)
		b.add_theme_stylebox_override("normal", UIHelpers.card_style(tc, 0.12 if active else 0.0, 0.50 if active else 0.0, 1 if active else 0, 4))
	for entry: Dictionary in _log_entries:
		entry["node"].visible = _matches_filter(entry["tags"])

func _matches_filter(tags: Array) -> bool:
	return _log_filter == "all" or _log_filter in tags

# ═══════════════════════════════════════════════════════════
#  Zone + Créature Unique (overlays conservés)
# ═══════════════════════════════════════════════════════════

# Petit panneau de strate (Surface/Profondeur/Abysse) centré en haut de l'arène,
# par-dessus la barre oblique VS. Auto-dimensionné à son texte (grow symétrique
# autour du centre). Le style (teinte de bordure) est posé par _update_zone_label.
func _build_zone_label() -> void:
	_zone_panel = PanelContainer.new()
	_zone_panel.anchor_left = 0.5; _zone_panel.anchor_right = 0.5
	_zone_panel.anchor_top  = 0.0; _zone_panel.anchor_bottom = 0.0
	_zone_panel.offset_top  = 8
	_zone_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_zone_panel.grow_vertical   = Control.GROW_DIRECTION_END
	_zone_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	_zone_label = Label.new()
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.add_theme_constant_override("outline_size", 3)
	_zone_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_panel.add_child(_zone_label)
	add_child(_zone_panel)

func _build_mechanic_label() -> void:
	_mechanic_label = Label.new()
	_mechanic_label.anchor_left  = 1.0; _mechanic_label.anchor_right  = 1.0
	_mechanic_label.anchor_top   = 0.0; _mechanic_label.anchor_bottom = 0.0
	_mechanic_label.offset_left  = -170; _mechanic_label.offset_right = -6
	_mechanic_label.offset_top   = 6;    _mechanic_label.offset_bottom = 30
	_mechanic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mechanic_label.add_theme_font_size_override("font_size", 13)
	_mechanic_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_mechanic_label.visible = false
	add_child(_mechanic_label)

func _update_zone_label(zone: Enums.Zone) -> void:
	if not _zone_label or not _zone_panel:
		return
	var idx   := clampi(int(zone), 0, 2)
	var color := UIColors.zone_color(idx)
	_zone_label.text = "◆ " + Translations.zone_name(idx)
	_zone_label.add_theme_color_override("font_color", color)

	# Panneau sombre à bordure teintée strate, avec un peu d'air autour du texte.
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(UIColors.BG_DARK.r, UIColors.BG_DARK.g, UIColors.BG_DARK.b, 0.88)
	s.border_color = Color(color.r, color.g, color.b, 0.85)
	s.set_border_width_all(1)
	s.set_corner_radius_all(7)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 3;   s.content_margin_bottom = 3
	_zone_panel.add_theme_stylebox_override("panel", s)

	UIHelpers.register_tooltip(_zone_panel, Translations.zone_name(idx),
			Translations.zone_tooltip(idx), color)

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
	var lbl := Label.new()
	lbl.text = Translations.T("combat.unique_beaten" if already_beaten else "combat.unique_watches") % nom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UIColors.TEXT_MUTED if already_beaten else color)
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
#  Polish combat — item 4 (badge mécanique forte)
# ═══════════════════════════════════════════════════════════

func _show_mechanic_label(text: String, color: Color) -> void:
	if not _mechanic_label:
		return
	_mechanic_label.text = text
	_mechanic_label.add_theme_color_override("font_color", color)
	_mechanic_label.visible = true

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
	_shield_state_pill = null
	_poison_state_pill = null
	# Les pills de hâte sont des enfants de _hero_states/_enemy_states (libérés
	# ci-dessus) : on annule juste les références pour éviter tout pointeur mort.
	_hero_haste_pill  = null
	_enemy_haste_pill = null

func _update_shield_pill(value: int) -> void:
	var color := Color(0.3, 0.7, 1.0)
	if value <= 0:
		if _shield_state_pill and is_instance_valid(_shield_state_pill):
			_shield_state_pill.queue_free()
		_shield_state_pill = null
		return
	if _shield_state_pill == null or not is_instance_valid(_shield_state_pill):
		_shield_state_pill = _make_state_pill_node("🛡 %d" % value, color)
		if _hero_states:
			_hero_states.add_child(_shield_state_pill)
	else:
		(_shield_state_pill.get_child(0) as Label).text = "🛡 %d" % value

func _update_poison_pill(active: bool) -> void:
	var color := Color(0.62, 0.15, 0.78)
	if not active:
		if _poison_state_pill and is_instance_valid(_poison_state_pill):
			_poison_state_pill.queue_free()
		_poison_state_pill = null
		return
	if _poison_state_pill == null or not is_instance_valid(_poison_state_pill):
		_poison_state_pill = _make_state_pill_node(Translations.T("combat.venom_pill"), color)
		if _enemy_states:
			_enemy_states.add_child(_poison_state_pill)

func _make_state_pill_node(text: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIHelpers.card_style(color, 0.18, 0.70, 1, 6))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	box.add_child(lbl)
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
	_push_feed(Translations.T("combat.ready_evolve") % nom, target)
	# Carillon court et sec (même famille que le crystal du rituel d'évolution) :
	# marque le coup quand une entité devient éligible.
	if is_instance_valid(_evolve_chime):
		_evolve_chime.play()
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
