# ============================================================
# CombatStats.gd — Encadrés de caractéristiques de combat (extrait de CombatScene).
#
# Deux mini-plaques JRPG ancrées dans les coins hauts de l'arène (héros à
# gauche, créature à droite) : titre de palier coloré + PV/ATK/DEF/VIT. Le
# cadre est re-teinté au palier à chaque remplissage.
#
# Pur builder/rafraîchisseur (aucun état du host) : l'appelant ajoute les
# panneaux retournés à l'arbre et pilote la visibilité ennemie ; le héros se
# montre tout seul au refresh. Les stats viennent des autoloads (GameData /
# AdventureSystem / StatStacker), mêmes sources que combat_player.
# ============================================================
class_name CombatStats
extends RefCounted

var _hero_panel:  PanelContainer
var _hero_rows:   VBoxContainer
var _enemy_panel: PanelContainer
var _enemy_rows:  VBoxContainer

# Encadré ancré dans un coin haut de l'arène (gauche = héros, droite = créature).
# Auto-dimensionné, transparent à la souris, masqué jusqu'au remplissage.
func _make_panel(is_hero: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	# Style « plaque JRPG » du jeu, re-teinté au palier dans _style.
	_style(panel, UIColors.CARD_NEUTRAL)
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
		_hero_panel = panel
		_hero_rows  = rows
	else:
		_enemy_panel = panel
		_enemy_rows  = rows
	return panel

func build_hero() -> PanelContainer:
	return _make_panel(true)

func build_enemy() -> PanelContainer:
	return _make_panel(false)

func set_enemy_visible(v: bool) -> void:
	if _enemy_panel:
		_enemy_panel.visible = v

# Style « mini plaque » dans la DA du jeu : fond sombre translucide (lisible
# par-dessus le fond animé) + bordure teintée au palier + coins arrondis + ombre.
func _style(panel: PanelContainer, color: Color) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color     = Color(0.04, 0.05, 0.09, 0.90)
	st.border_color = Color(color.r, color.g, color.b, 0.70)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size  = 6
	panel.add_theme_stylebox_override("panel", st)

# (Re)remplit un encadré : titre palier coloré + filet + PV/ATK/DEF/VIT.
# Re-teinte aussi le cadre à la couleur du palier (DA cohérente avec les cartes).
func _fill(panel: PanelContainer, rows: VBoxContainer, color: Color,
		tier: int, pv: int, atk: int, def: int, vit: int) -> void:
	_style(panel, color)
	for c in rows.get_children():
		c.free()
	var tier_lbl := UIHelpers.label(GameData.get_tier_name(tier).to_upper(), 10, color)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(tier_lbl)
	# Filet séparateur teinté sous le titre.
	var sep := ColorRect.new()
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.color                 = Color(color.r, color.g, color.b, 0.35)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(sep)
	_add_row(rows, Translations.T("hero.stat.hp"),  pv,  UIColors.STAT_HP)
	_add_row(rows, Translations.T("hero.stat.atk"), atk, UIColors.STAT_ATK)
	_add_row(rows, Translations.T("hero.stat.def"), def, UIColors.STAT_DEF)
	_add_row(rows, Translations.T("hero.stat.vit"), vit, UIColors.FILTER_ON)

# Calcule les stats effectives du héros (mêmes sources que combat_player : base
# + équipement, VIT accélérée par attack_speed_pct) et remplit/affiche l'encadré.
func refresh_hero(htier: int) -> void:
	if _hero_rows == null:
		return
	var hstats := GameData.get_effective_stats("hero")
	var heqp   := GameData.get_equipment_bonuses()
	var vit := int(round(StatStacker.final_stat(float(hstats.get("vit", 20)),
			[float(heqp.get("attack_speed_pct", 0.0)) / 100.0], "vit")))
	_fill(_hero_panel, _hero_rows, UIColors.tier_color(htier), htier,
			int(AdventureSystem.get_max_hp()),
			int(hstats.get("atk", 0)) + int(heqp.get("atk", 0)),
			int(hstats.get("def", 0)) + int(heqp.get("def", 0)),
			vit)
	_hero_panel.visible = true

# Remplit et affiche l'encadré de la créature (stats déjà calculées par l'appelant).
func fill_enemy(etier: int, pv: int, atk: int, def: int, vit: int) -> void:
	if _enemy_rows == null:
		return
	_fill(_enemy_panel, _enemy_rows, UIColors.tier_color(etier), etier, pv, atk, def, vit)
	_enemy_panel.visible = true

func _add_row(rows: VBoxContainer, label: String, value: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UIHelpers.label(label, 11, color)
	l.custom_minimum_size = Vector2(34, 0)
	row.add_child(l)
	var v := UIHelpers.label(str(value), 11, Color.WHITE)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	rows.add_child(row)
