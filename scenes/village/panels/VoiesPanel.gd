# ============================================================
# VoiesPanel — Contenu du panneau glissant « VOIES » du QG (Rework
# économique du QG, chantier 12). Placeholder sobre acté : les contenus
# réels des 6 quartiers viendront avec la session narration/PNJ.
#
# Une VOIE par Lieutenant (source data-driven : destinations.tres →
# lieutenants_par_lieu). Posséder l'objet unique du Lieutenant (« Sceau »,
# accordé au premier kill — chantier 12) permet d'OUVRIR la voie : action
# manuelle « prêt → clic » (pilier conservé), persistée avec la partie
# (GameData.ouvrir_voie). Le quartier au bout est un placeholder vide
# (« Voie scellée » → « Quartier restauré — contenu à venir »).
#
# Le panneau affiche aussi la liste sobre des Sceaux possédés (règle
# chantier 12 : l'objet doit être visible quelque part) et le compteur
# « quartiers restaurés » (source unique : GameData.nb_voies_ouvertes —
# l'évolution visuelle du QG s'y branchera, DA hors scope).
#
# Module sans état (fonctions statiques) ; host = nœud Village (API
# publique : rp_content, panel_ui_state). Rafraîchissement : le Village
# écoute EventBus.voie_ouverte.
# ============================================================
class_name VoiesPanel

# Même ressource que le Village : destination → Lieutenant (les clés = les 6 voies).
const DESTINATIONS: ExpeDestinationsData = preload("res://data/expedition/destinations.tres")

# Point d'entrée : peuple host.rp_content avec le panneau des voies.
static func build(host: Village) -> void:
	var tcolor := UIColors.tier_color(host.village_tier())
	var lieux: Array = DESTINATIONS.lieutenants_par_lieu.keys()

	# ── Compteur « quartiers restaurés » (source unique GameData) ──
	var compteur := UIHelpers.label(Translations.T("voies.compteur")
			% [GameData.nb_voies_ouvertes(), lieux.size()], 14, tcolor.lightened(0.25))
	compteur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.rp_content.add_child(compteur)

	# ── Sceaux possédés (liste sobre) ─────────────────────────
	var sceaux_sec := UIHelpers.collapsible_section(Translations.T("voies.sceaux_titre"),
			tcolor, true, host.panel_ui_state())
	host.rp_content.add_child(sceaux_sec["wrapper"])
	var sceaux_body := sceaux_sec["body"] as VBoxContainer
	var possedes: Array = GameData.objets_lieutenants()
	if possedes.is_empty():
		var aucun := UIHelpers.label(Translations.T("voies.sceaux_aucun"), 11, UIColors.TEXT_MUTED)
		aucun.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sceaux_body.add_child(aucun)
	else:
		for lieu in possedes:
			sceaux_body.add_child(UIHelpers.label(
					"◆ " + Translations.T("voies.sceau") % _nom_lieu(str(lieu)),
					11, UIColors.TIER_LEGENDAIRE))

	host.rp_content.add_child(HSeparator.new())

	# ── Les 6 voies, une carte par Lieu ───────────────────────
	for lieu in lieux:
		host.rp_content.add_child(_carte_voie(str(lieu)))

# Carte d'une voie : nom du Lieu + état (scellée / prête à ouvrir / restaurée).
static func _carte_voie(lieu_id: String) -> Control:
	var ouverte := GameData.voie_ouverte(lieu_id)
	var possede := GameData.possede_objet_lieutenant(lieu_id)
	var accent: Color = UIColors.LOG_VICTORY if ouverte \
			else (UIColors.TIER_LEGENDAIRE if possede else UIColors.TEXT_MUTED)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(accent, 0.10 if ouverte or possede else 0.04, 0.45, 1, 6))
	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)

	var titre_row := HBoxContainer.new()
	titre_row.add_theme_constant_override("separation", 8)
	vb.add_child(titre_row)
	var icone := "✦" if ouverte else ("◆" if possede else "🔒")
	titre_row.add_child(UIHelpers.label(icone, 13, accent))
	var nom := UIHelpers.label(_nom_lieu(lieu_id), 13, accent.lerp(Color.WHITE, 0.30))
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titre_row.add_child(nom)

	if ouverte:
		vb.add_child(UIHelpers.label(Translations.T("voies.restauree"), 11, accent))
	elif possede:
		# Action manuelle « prêt → clic » : l'objet ouvre la voie, jamais tout seul.
		var btn := Button.new()
		btn.text = Translations.T("voies.restaurer_btn")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", accent)
		btn.add_theme_stylebox_override("normal", UIHelpers.card_style(accent, 0.10, 0.70, 1, 5))
		btn.add_theme_stylebox_override("hover", UIHelpers.card_style(accent, 0.22, 1.0, 2, 5))
		btn.pressed.connect(func() -> void:
			if GameData.ouvrir_voie(lieu_id):
				AudioManager.play_sfx("ui_select", -6.0))
		vb.add_child(btn)
	else:
		var hint := UIHelpers.label("%s — %s" % [Translations.T("voies.scellee"),
				Translations.T("voies.scellee_hint")], 11, UIColors.TEXT_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)
	return card

# Nom affiché d'un Lieu : « ??? » tant que le Lieu n'est pas découvert (ne
# jamais trahir un biome caché), sinon le nom traduit de l'entité.
static func _nom_lieu(lieu_id: String) -> String:
	var e := GameData.get_entity(lieu_id)
	if e.is_empty() or not e.get("est_decouvert", false):
		return "???"
	return Translations.entity_name(e, lieu_id)
