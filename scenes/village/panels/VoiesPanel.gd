# ============================================================
# VoiesPanel — Contenu du panneau glissant « VOIES » du QG (chantier 12 ;
# refondu au chantier 13 : ORDRE FIXE). Placeholder sobre acté : les
# contenus des voies 2-6 viendront avec la session narration/PNJ.
#
# Modèle (acté 06/07/2026) : les voies s'ouvrent dans l'ordre 1 → 6 ;
# ouvrir la voie n exige les voies 1..n-1 ouvertes + 1 SCEAU LIBRE
# (Sceaux possédés − voies ouvertes ≥ 1 — les Sceaux restent tracés par
# Lieutenant d'origine pour la narration, mais se dépensent comme un
# compteur interchangeable). VOIE 1 = ATELIER/FORGE : son ouverture fait
# apparaître l'hex Forge et déverrouille le panneau. Action manuelle
# « prêt → clic » conservée (GameData.ouvrir_voie_suivante).
#
# Le panneau affiche : compteur de quartiers restaurés (source unique
# GameData.nb_voies_ouvertes), Sceaux possédés (provenance) + Sceaux
# LIBRES, puis les 6 voies dans l'ordre — la voie suivante ouvrable est
# mise en avant. Module sans état ; host = nœud Village (API publique).
# Rafraîchissement : le Village écoute EventBus.voie_ouverte.
# ============================================================
class_name VoiesPanel

# Point d'entrée : peuple host.rp_content avec le panneau des voies.
static func build(host: Village) -> void:
	var tcolor := UIColors.tier_color(host.village_tier())

	# ── Compteur « quartiers restaurés » (source unique GameData) ──
	var compteur := UIHelpers.label(Translations.T("voies.compteur")
			% [GameData.nb_voies_ouvertes(), GameData.NB_VOIES], 14, tcolor.lightened(0.25))
	compteur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.rp_content.add_child(compteur)

	# ── Sceaux : possédés (provenance par Lieu) + LIBRES ──────
	var sceaux_sec := UIHelpers.collapsible_section(Translations.T("voies.sceaux_titre"),
			tcolor, true, host.panel_ui_state())
	host.rp_content.add_child(sceaux_sec["wrapper"])
	var sceaux_body := sceaux_sec["body"] as VBoxContainer
	var libres := UIHelpers.label(Translations.T("voies.sceaux_libres")
			% GameData.sceaux_libres(), 12,
			UIColors.TIER_LEGENDAIRE if GameData.sceaux_libres() > 0 else UIColors.TEXT_MUTED)
	sceaux_body.add_child(libres)
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

	# ── Les 6 voies, DANS L'ORDRE ─────────────────────────────
	for numero in range(1, GameData.NB_VOIES + 1):
		host.rp_content.add_child(_carte_voie(numero))

# Nom affiché d'une voie : la 1 est l'Atelier (contenu fixe connu), les
# suivantes restent des quartiers scellés génériques (session narration).
static func _nom_voie(numero: int) -> String:
	if numero == GameData.VOIE_ATELIER:
		return Translations.T("voies.nom_atelier")
	return Translations.T("voies.nom_generique")

# Carte d'une voie : numéro + état (restaurée / SUIVANTE ouvrable — mise en
# avant / verrouillée derrière la précédente).
static func _carte_voie(numero: int) -> Control:
	var ouverte := GameData.voie_ouverte(numero)
	var suivante := numero == GameData.nb_voies_ouvertes() + 1
	var ouvrable := suivante and GameData.sceaux_libres() >= 1
	var accent: Color = UIColors.LOG_VICTORY if ouverte \
			else (UIColors.TIER_LEGENDAIRE if ouvrable else UIColors.TEXT_MUTED)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			UIHelpers.card_style(accent, 0.10 if ouverte or ouvrable else 0.04,
					0.60 if ouvrable else 0.45, 2 if ouvrable else 1, 6))
	var m := UIHelpers.margin_of(10)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)

	var titre_row := HBoxContainer.new()
	titre_row.add_theme_constant_override("separation", 8)
	vb.add_child(titre_row)
	var icone := "✦" if ouverte else ("◆" if ouvrable else "🔒")
	titre_row.add_child(UIHelpers.label(icone, 13, accent))
	var nom := UIHelpers.label("%d.  %s" % [numero, _nom_voie(numero)], 13,
			accent.lerp(Color.WHITE, 0.30))
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titre_row.add_child(nom)

	if ouverte:
		vb.add_child(UIHelpers.label(Translations.T("voies.atelier_restaure")
				if numero == GameData.VOIE_ATELIER
				else Translations.T("voies.restauree"), 11, accent))
	elif suivante:
		if ouvrable:
			# Action manuelle « prêt → clic » : 1 Sceau libre → la voie s'ouvre.
			var btn := Button.new()
			btn.text = Translations.T("voies.restaurer_btn")
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.add_theme_font_size_override("font_size", 13)
			btn.add_theme_color_override("font_color", accent)
			btn.add_theme_stylebox_override("normal", UIHelpers.card_style(accent, 0.10, 0.70, 1, 5))
			btn.add_theme_stylebox_override("hover", UIHelpers.card_style(accent, 0.22, 1.0, 2, 5))
			btn.pressed.connect(func() -> void:
				if GameData.ouvrir_voie_suivante():
					AudioManager.play_sfx("ui_select", -6.0))
			vb.add_child(btn)
		else:
			var hint := UIHelpers.label("%s — %s" % [Translations.T("voies.scellee"),
					Translations.T("voies.suivante_hint")], 11, UIColors.TEXT_MUTED)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(hint)
	else:
		var verrou := UIHelpers.label("%s — %s" % [Translations.T("voies.scellee"),
				Translations.T("voies.verrouillee")], 11, UIColors.TEXT_MUTED)
		verrou.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(verrou)
	return card

# Nom affiché d'un Lieu (provenance d'un Sceau) : « ??? » tant que le Lieu
# n'est pas découvert (ne jamais trahir un biome caché).
static func _nom_lieu(lieu_id: String) -> String:
	var e := GameData.get_entity(lieu_id)
	if e.is_empty() or not e.get("est_decouvert", false):
		return "???"
	return Translations.entity_name(e, lieu_id)
