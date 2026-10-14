# ============================================================
# InventairePanel — INVENTAIRE de l'Atelier (14/10/2026), vue PRINCIPALE du
# panneau Forge/Atelier (voie 1). Remplace l'ancienne liste de cartes de
# ForgePanel, dont la Forge (palier d'XP, évolution, arbre) devient une
# SECTION du détail d'une pièce d'équipement (`ForgePanel.section_equipement`).
#
# Trois onglets, une grille de cases à gauche, une fiche détail à droite :
#   • Équipement   — les 6 slots du héros (3 réels, 3 placeholders vides)
#                    puis la réserve ; Équiper / Déséquiper depuis la fiche ;
#   • Matériaux    — `player.resources` (Ferraille, Puce…) ;
#   • Consommables — stock persistant (`StockConsommables`), une case par
#                    type avec compteur ×N, fabrication à l'Atelier.
# Tri (nom / rareté / quantité) + recherche par nom. Peau cyberpunk
# intérimaire : `ExpeStyle` + palette dérivée du palier de Maîtrise du QG (voir `_p`).
#
# État d'UI (onglet, tri, recherche, sélection) dans `host.panel_ui_state()` :
# il survit aux reconstructions du panneau. Les actions (équiper, fabriquer)
# émettent leurs signaux (`equipment_changed`, `resources_changed`) : Village
# rafraîchit le panneau « forge » tout seul ; seuls les changements d'état
# purement UI appellent `_refresh_active_panel()`.
# ============================================================
class_name InventairePanel

enum Onglet { EQUIPEMENT, MATERIAUX, CONSOMMABLES }
enum Tri { NOM, RARETE, QUANTITE }

const COLONNES := 4
const TAILLE_CASE := Vector2(80, 84)

# Glyphes MONOCHROMES (les emoji couleur jurent avec la peau cyberpunk).
const GLYPHES_SLOT := {
	"arme": "╳", "anneau": "◎", "armure": "⬡",
	"ceinture": "▬", "bouclier": "◈", "talisman": "✦",
}
const GLYPHE_MATERIAU := "⬢"
const GLYPHE_CONSO_DEGATS := "✹"
const GLYPHE_CONSO_SOIN := "✚"

# ─── Palette : TOUT dérive du palier de Maîtrise du QG ───────
# Règle de DA (Rhend, 14/10/2026) : les couleurs de l'UI sont liées au palier
# de Maîtrise du village (`UIColors.tier_color(village_tier())`) ; on joue sur
# les teintes d'UNE même couleur pour les niveaux de lecture. Seules les
# couleurs de RARETÉ des pièces d'équipement (tier_color de la pièce) en
# sortent : elles portent une information de jeu.
#   base  = bordures, cadres, onglet actif    vif   = titres, accents, actions
#   eclat = valeurs mises en avant (Euren, ×N, coûts, sélection)
#   texte = texte courant                      doux  = texte secondaire/inactif
static var _p: Dictionary = {}

static func _definir_palette(base: Color) -> void:
	_p = {
		"base": base,
		"vif": base.lightened(0.35),
		"eclat": base.lightened(0.45),
		"texte": base.lerp(Color.WHITE, 0.80),
		"doux": base.darkened(0.35),
	}

static func build(host: Village) -> void:
	_definir_palette(UIColors.tier_color(host.village_tier()))
	var st: Dictionary = host.panel_ui_state()
	var onglet := int(st.get("onglet", Onglet.EQUIPEMENT))
	var racine := VBoxContainer.new()
	racine.add_theme_constant_override("separation", 8)
	racine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.rp_content.add_child(racine)

	racine.add_child(_entete())
	racine.add_child(_barre_onglets(host, st, onglet))
	racine.add_child(_barre_outils(host, st))

	var corps := HBoxContainer.new()
	corps.add_theme_constant_override("separation", 10)
	corps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	racine.add_child(corps)

	var objets := _objets(onglet, st)
	var sel_key := str(st.get("sel", ""))
	# Une sélection d'un autre onglet / disparue ne doit pas rester affichée.
	var courant: Dictionary = {}
	for o: Dictionary in objets:
		if str(o["key"]) == sel_key:
			courant = o
	corps.add_child(_grille(host, st, objets, courant))
	corps.add_child(_detail(host, courant))

# ─── Barres ──────────────────────────────────────────────────

# Titre + monnaies du QG (Euren, Modules) : de quoi juger d'un coup d'œil ce
# qu'on peut fabriquer.
static func _entete() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var titre := ExpeStyle.label_neon(Translations.T("inv.titre"), 17, _p["base"])
	titre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(titre)
	h.add_child(ExpeStyle.label_mono(
			Translations.T("inv.cout_euren") % int(roundf(ProgressionHeros.euren())),
			12, _p["eclat"]))
	h.add_child(ExpeStyle.label_mono(
			Translations.T("inv.cout_modules") % ProgressionHeros.modules(),
			12, _p["vif"]))
	return h

static func _barre_onglets(host: Village, st: Dictionary, onglet: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var noms := [Translations.T("inv.tab.equip"), Translations.T("inv.tab.mat"),
			Translations.T("inv.tab.conso")]
	for i in noms.size():
		var actif := i == onglet
		var b := ExpeStyle.bouton(noms[i],
				_p["base"] if actif else _p["doux"], 12,
				Vector2(0, 32))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if actif:
			ExpeStyle.habiller_bouton_neon(b, _p["base"], 12, 0.45)
		b.pressed.connect(func() -> void:
			if int(st.get("onglet", 0)) == i:
				return
			st["onglet"] = i
			st["sel"] = ""
			host._refresh_active_panel())
		h.add_child(b)
	return h

static func _barre_outils(host: Village, st: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var recherche := LineEdit.new()
	recherche.placeholder_text = Translations.T("inv.recherche")
	recherche.text = str(st.get("recherche", ""))
	recherche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recherche.custom_minimum_size = Vector2(0, 30)
	recherche.add_theme_font_override("font", ExpeStyle.police_mono())
	recherche.add_theme_font_size_override("font_size", 12)
	recherche.add_theme_color_override("font_color", _p["texte"])
	recherche.add_theme_stylebox_override("normal",
			ExpeStyle.style_chip(_p["base"]))
	recherche.add_theme_stylebox_override("focus",
			ExpeStyle.style_panneau(_p["base"], 0.95, 1, 2))
	# Validation à Entrée (pas à chaque frappe : la reconstruction du panneau
	# volerait le focus du champ).
	recherche.text_submitted.connect(func(t: String) -> void:
		st["recherche"] = t
		host._refresh_active_panel())
	h.add_child(recherche)

	var tri := OptionButton.new()
	tri.custom_minimum_size = Vector2(120, 30)
	tri.add_item(Translations.T("inv.tri.nom"), Tri.NOM)
	tri.add_item(Translations.T("inv.tri.rarete"), Tri.RARETE)
	tri.add_item(Translations.T("inv.tri.qte"), Tri.QUANTITE)
	tri.select(int(st.get("tri", Tri.NOM)))
	tri.add_theme_font_size_override("font_size", 12)
	tri.item_selected.connect(func(idx: int) -> void:
		st["tri"] = idx
		host._refresh_active_panel())
	h.add_child(tri)
	return h

# ─── Modèle ──────────────────────────────────────────────────

# Liste des objets de l'onglet, filtrée par la recherche et triée. Pour
# l'équipement, les SLOTS restent en tête dans leur ordre fixe : seule la
# réserve est triée/filtrée.
static func _objets(onglet: int, st: Dictionary) -> Array[Dictionary]:
	var requete := str(st.get("recherche", "")).strip_edges().to_lower()
	var tri := int(st.get("tri", Tri.NOM))
	var out: Array[Dictionary] = []
	match onglet:
		Onglet.EQUIPEMENT:
			for slot_key: String in GameData.EQUIP_SLOT_KEYS:
				var id := str(GameData.player["equipped"].get(slot_key, ""))
				out.append(_objet_equipement(id, slot_key, true))
			var reserve: Array[Dictionary] = []
			for id: String in GameData.equipement_en_reserve():
				reserve.append(_objet_equipement(id, GameData.slot_key_pour(id), false))
			out.append_array(_filtrer_trier(reserve, requete, tri))
		Onglet.MATERIAUX:
			var mats: Array[Dictionary] = []
			var res: Dictionary = GameData.player.get("resources", {})
			for rid: String in res:
				if int(res[rid]) <= 0:
					continue
				var ent := GameData.get_entity(rid)
				mats.append({
					"key": "mat:" + rid, "kind": "mat", "id": rid,
					"nom": Translations.entity_name(ent, rid),
					"qty": int(res[rid]), "tier": int(ent.get("maitrise_actuelle", 0)),
					"glyphe": GLYPHE_MATERIAU,
				})
			out.append_array(_filtrer_trier(mats, requete, tri))
		Onglet.CONSOMMABLES:
			var consos: Array[Dictionary] = []
			var cat := StockConsommables.catalogue()
			for cid: String in cat:
				var d: ConsommableData = cat[cid]
				var soin: bool = d.effet == Enums.EffetConsommable.SOIN_PCT_PV_MAX
				consos.append({
					"key": "conso:" + cid, "kind": "conso", "id": cid,
					"nom": Translations.resource_name(d, cid),
					"qty": StockConsommables.quantite(cid), "tier": 0,
					"glyphe": GLYPHE_CONSO_SOIN if soin else GLYPHE_CONSO_DEGATS,
				})
			out.append_array(_filtrer_trier(consos, requete, tri))
	return out

static func _objet_equipement(id: String, slot_key: String, porte: bool) -> Dictionary:
	var ent := GameData.get_entity(id) if id != "" else {}
	return {
		"key": ("slot:" + slot_key) if porte else ("res:" + id),
		"kind": "equip", "id": id, "slot": slot_key, "porte": porte,
		"vide": id == "",
		"nom": Translations.entity_name(ent, id) if id != "" else \
				Translations.T("inv.slot." + slot_key),
		"qty": 1, "tier": int(ent.get("maitrise_actuelle", 0)),
		"glyphe": str(GLYPHES_SLOT.get(slot_key, "◇")),
	}

static func _filtrer_trier(liste: Array[Dictionary], requete: String, tri: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in liste:
		if requete == "" or str(o["nom"]).to_lower().contains(requete):
			out.append(o)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match tri:
			Tri.RARETE:
				if int(a["tier"]) != int(b["tier"]):
					return int(a["tier"]) > int(b["tier"])
			Tri.QUANTITE:
				if int(a["qty"]) != int(b["qty"]):
					return int(a["qty"]) > int(b["qty"])
		return str(a["nom"]).naturalnocasecmp_to(str(b["nom"])) < 0)
	return out

# ─── Grille ──────────────────────────────────────────────────

static func _grille(host: Village, st: Dictionary, objets: Array[Dictionary],
		courant: Dictionary) -> Control:
	var cadre := PanelContainer.new()
	cadre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cadre.size_flags_stretch_ratio = 3.0
	cadre.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cadre.add_theme_stylebox_override("panel",
			ExpeStyle.style_neon(_p["base"], 0.8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	cadre.add_child(vb)
	ExpeStyle.scanlines(cadre, 0.05)   # par-dessus, souris ignorée
	if objets.is_empty():
		vb.add_child(ExpeStyle.label_mono(Translations.T("inv.vide"), 12,
				_p["doux"]))
		return cadre
	var sel_key := str(courant.get("key", "__"))
	# Équipement : deux sections (slots portés / réserve) pour qu'on lise
	# d'un coup d'œil ce qui est équipé ; les autres onglets : une grille.
	var portes: Array[Dictionary] = []
	var autres: Array[Dictionary] = []
	for o: Dictionary in objets:
		if bool(o.get("porte", false)):
			portes.append(o)
		else:
			autres.append(o)
	if not portes.is_empty():
		vb.add_child(_legende(Translations.T("inv.porte")))
		vb.add_child(_grille_cases(host, st, portes, sel_key))
		if not autres.is_empty():
			vb.add_child(_legende(Translations.T("inv.reserve")))
	if not autres.is_empty():
		vb.add_child(_grille_cases(host, st, autres, sel_key))
	return cadre

static func _legende(texte: String) -> Label:
	return ExpeStyle.label_mono(texte.to_upper(), 10, _p["doux"])

static func _grille_cases(host: Village, st: Dictionary, objets: Array[Dictionary],
		sel_key: String) -> Control:
	var g := GridContainer.new()
	g.columns = COLONNES
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for o: Dictionary in objets:
		g.add_child(_case(host, st, o, str(o["key"]) == sel_key))
	return g

# Case : glyphe monochrome + nom court + quantité. Bordure = rareté pour
# l'équipement, cyan pour le reste, grisée si vide / non possédé, or si choisie.
static func _case(host: Village, st: Dictionary, o: Dictionary, choisie: bool) -> Control:
	var vide := bool(o.get("vide", false)) \
			or (int(o["qty"]) <= 0 and str(o["kind"]) != "equip")
	var slot_vide := vide   # slot d'équipement sans pièce OU consommable non possédé : même gris
	var accent: Color = UIColors.SLOT_VIDE if slot_vide else _p["doux"]
	if not vide:
		accent = UIColors.tier_color(int(o["tier"])) if str(o["kind"]) == "equip" \
				else _p["base"]
	if choisie:
		accent = _p["eclat"]
	var b := Button.new()
	b.custom_minimum_size = TAILLE_CASE
	ExpeStyle.habiller_bouton_neon(b, accent, 12, 0.50 if choisie else 0.16)
	if choisie:
		ExpeStyle.pulser(b)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(o["nom"])
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var couleur_texte: Color = _p["texte"]
	if slot_vide:
		couleur_texte = UIColors.SLOT_VIDE
	elif vide:
		couleur_texte = _p["doux"]
	var glyphe := ExpeStyle.label_mono(str(o["glyphe"]), 26, couleur_texte if vide else accent)
	glyphe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyphe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(glyphe)
	var nom := ExpeStyle.label_mono(str(o["nom"]), 10, couleur_texte)
	nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nom.max_lines_visible = 2
	nom.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nom.custom_minimum_size = Vector2(TAILLE_CASE.x - 8.0, 0.0)
	nom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nom)
	if str(o["kind"]) != "equip":
		var qte := ExpeStyle.label_mono("×%d" % int(o["qty"]), 11,
				couleur_texte if vide else _p["eclat"])
		qte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qte.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(qte)
	b.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_select", -14.0)
		st["sel"] = str(o["key"])
		host._refresh_active_panel())
	return b

# ─── Détail ──────────────────────────────────────────────────

static func _detail(host: Village, o: Dictionary) -> Control:
	var cadre := PanelContainer.new()
	cadre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cadre.size_flags_stretch_ratio = 2.2
	cadre.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cadre.add_theme_stylebox_override("panel",
			ExpeStyle.style_neon(_p["vif"], 0.8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	cadre.add_child(vb)
	ExpeStyle.scanlines(cadre, 0.05)   # par-dessus, souris ignorée
	if o.is_empty():
		vb.add_child(_texte(Translations.T("inv.selection"), 12, _p["doux"]))
		return cadre
	match str(o["kind"]):
		"equip":
			_detail_equipement(host, vb, o)
		"mat":
			_detail_materiau(vb, o)
		"conso":
			_detail_conso(vb, o)
	return cadre

static func _texte(t: String, taille: int, couleur: Color) -> Label:
	var l := ExpeStyle.label_mono(t, taille, couleur)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func _detail_equipement(host: Village, vb: VBoxContainer, o: Dictionary) -> void:
	var slot_key := str(o["slot"])
	var nom_slot := Translations.T("inv.slot." + slot_key)
	# Pas de doublon « Arme / ARME » quand la pièce porte le nom de son slot.
	if str(o["nom"]).to_lower() != nom_slot.to_lower():
		vb.add_child(_texte(nom_slot, 11, _p["doux"]))
	if bool(o["vide"]):
		vb.add_child(_texte(Translations.T("inv.slot_vide"), 14, UIColors.SLOT_VIDE))
		return
	var id := str(o["id"])
	var ent := GameData.get_entity(id)
	var couleur := UIColors.tier_color(int(o["tier"]))
	vb.add_child(_titre(str(o["nom"]).to_upper(), _p["base"]))
	vb.add_child(_texte("%s — %s" % [GameData.get_tier_name(int(o["tier"])),
			Translations.T("inv.porte") if bool(o["porte"]) else Translations.T("inv.reserve")],
			11, couleur))
	var stats := ForgePanel._stats_line(GameData.get_effective_stats(id))
	if stats != "":
		vb.add_child(_texte(stats, 12, _p["texte"]))
	var lore := Translations.entity_lore(ent)
	if lore != "":
		vb.add_child(_texte(lore, 11, _p["doux"]))
	# Équiper / Déséquiper : l'échange est géré par GameData (equipment_changed
	# rafraîchit le panneau).
	if bool(o["porte"]):
		var b := ExpeStyle.bouton(Translations.T("inv.desequiper"), _p["base"], 13,
				Vector2(0, 34))
		b.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_select", -8.0)
			GameData.desequiper(slot_key))
		vb.add_child(b)
	else:
		var b := ExpeStyle.bouton(Translations.T("inv.equiper"), _p["vif"], 13,
				Vector2(0, 34))
		b.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_select", -8.0)
			GameData.equiper(id))
		vb.add_child(b)
	# Forge (palier d'XP, évolution, arbre) : s'ouvre depuis la pièce.
	vb.add_child(HSeparator.new())
	vb.add_child(_texte(Translations.T("inv.forge"), 11, _p["vif"]))
	ForgePanel.section_equipement(host, id, vb)

static func _detail_materiau(vb: VBoxContainer, o: Dictionary) -> void:
	vb.add_child(_titre(str(o["nom"]).to_upper(), _p["eclat"]))
	vb.add_child(_texte(Translations.T("inv.qte") % int(o["qty"]), 12, _p["texte"]))
	var lore := Translations.entity_lore(GameData.get_entity(str(o["id"])))
	if lore != "":
		vb.add_child(_texte(lore, 11, _p["doux"]))

static func _detail_conso(vb: VBoxContainer, o: Dictionary) -> void:
	var def := StockConsommables.definition(str(o["id"]))
	vb.add_child(_titre(str(o["nom"]).to_upper(), _p["base"]))
	vb.add_child(_texte(Translations.T("inv.qte") % int(o["qty"]), 12, _p["texte"]))
	if def == null:
		return
	match def.effet:
		Enums.EffetConsommable.DEGATS_CIBLE:
			vb.add_child(_texte(Translations.T("inv.effet.degats") % int(roundf(def.valeur)),
					12, _p["texte"]))
		Enums.EffetConsommable.SOIN_PCT_PV_MAX:
			vb.add_child(_texte(Translations.T("inv.effet.soin") % int(roundf(def.valeur * 100.0)),
					12, _p["vif"]))
	vb.add_child(_texte(Translations.T("inv.conso.aide"), 10, _p["doux"]))
	vb.add_child(HSeparator.new())
	if not def.fabricable():
		vb.add_child(_texte(Translations.T("inv.non_fabricable"), 11, _p["doux"]))
		return
	var couts: PackedStringArray = []
	if def.cout_euren > 0.0:
		couts.append(Translations.T("inv.cout_euren") % int(roundf(def.cout_euren)))
	if def.cout_modules > 0:
		couts.append(Translations.T("inv.cout_modules") % def.cout_modules)
	if not def.cout_materiaux.is_empty():
		couts.append(Translations.noms_quantites(def.cout_materiaux))
	vb.add_child(_texte(Translations.T("inv.cout") % ", ".join(couts), 11, _p["eclat"]))
	var peut := StockConsommables.peut_fabriquer(def)
	var b := ExpeStyle.bouton(Translations.T("inv.fabriquer"),
			_p["vif"] if peut else _p["doux"], 13, Vector2(0, 34))
	b.disabled = not peut
	b.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_select", -8.0)
		StockConsommables.fabriquer(def))
	vb.add_child(b)

static func _titre(t: String, accent: Color) -> Label:
	var l := ExpeStyle.label_neon(t, 15, accent)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
