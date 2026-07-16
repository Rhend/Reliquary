# ============================================================
# ExpeditionScreen — Écran de JEU d'une expédition (Rework Combat,
# chantier 8 : branchement au flux de jeu principal).
#
# Reprend la structure éprouvée du sandbox (carte + brouillard via
# ExpeCarteView partagée, en-tête de run, journal, combats joués À LA MAIN
# dans CombatCtbUi) mais en tant qu'écran du jeu réel :
#   • PERSISTANCE ACTIVE — aucun débranchement de SaveManager (contrairement
#     au sandbox, outil dev qui reste « jamais d'écriture ») : l'XP de niveau
#     créditée aux victoires et l'Euren crédité à la sortie déclenchent la
#     sauvegarde par leurs signaux (chantier 6) ;
#   • vrai héros + configs versionnées, fournis par le Village au lancement
#     (HoloMap → ExpeLancementPanel → Village.lancer_expedition) ;
#   • fin de run (extraction, complétion, défaite) → RECAP placeholder
#     (issue, XP, Euren crédité, purge des affixes/consommables) puis
#     « Retour au QG » → signal `retour_qg(recap)` (le Village libère
#     l'écran). La défaite = extraction sans butin (Game Over/rechargement
#     hors scope, chantier suivant).
#
# Transitions placeholder, DA hors scope (l'UI finale viendra avec sa DA).
# ============================================================
class_name ExpeditionScreen
extends Control

signal retour_qg(recap: Dictionary)

const CONFIG: ExpeCarteConfigData = preload("res://data/expedition/config_carte.tres")
const CONFIG_COMBAT: ExpeCombatConfigData = preload("res://data/expedition/config_combat.tres")

var lieu_id := ""
var palier: PalierProfondeurData
var avatar: CombattantCtbData
var pool: PoolEnnemisData
var graine := 0                     # 0 = aléatoire ; fixé par les tests (reproductible)

# Hook de TEST/outillage UNIQUEMENT (jamais exposé en UI de jeu) :
# auto-résolution des combats — les suites headless ne jouent pas l'écran.
var combat_auto := false

var run: ExpeRun
var _carte_view: ExpeCarteView
var _journal_label: Label
var _journal_scroll: ScrollContainer
var _btn_extraire: Button
var _btn_continuer: Button
var _lbl_etat: Label
var _lbl_heros: Label
var _lbl_run: Label
var _combat_data: Dictionary = {}    # payload du dernier combat_demarre (embuscade…)
var _combat_ui: CombatCtbUi = null
var _recap_final: Dictionary = {}

func _init(p_lieu: String, p_palier: PalierProfondeurData, p_avatar: CombattantCtbData,
		p_pool: PoolEnnemisData, p_graine: int = 0) -> void:
	lieu_id = p_lieu
	palier = p_palier
	avatar = p_avatar
	pool = p_pool
	graine = p_graine

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # écran de jeu : bloque le hub dessous
	_construire_ui()
	_lancer()

func _construire_ui() -> void:
	var fond := ColorRect.new()
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.color = UIColors.BG_DARK
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fond)

	var m := UIHelpers.margin_of(10)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var racine := VBoxContainer.new()
	racine.add_theme_constant_override("separation", 4)
	m.add_child(racine)

	# ── En-tête : Lieu — palier · étage · PV, ligne héros, ligne de run ──
	var lieu := GameData.get_entity(lieu_id)
	var tcolor := UIColors.tier_color(int(lieu.get("maitrise_actuelle", 0)))
	_lbl_etat = UIHelpers.label("", 16, tcolor.lightened(0.25))
	racine.add_child(_lbl_etat)
	_lbl_heros = UIHelpers.label("", 12, Color(0.85, 0.88, 0.95))
	racine.add_child(_lbl_heros)
	_lbl_run = UIHelpers.label("", 12, Color(0.75, 0.85, 1.0))
	racine.add_child(_lbl_run)

	# ── Corps : carte (gauche) + journal (droite) ──
	var corps := HBoxContainer.new()
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	racine.add_child(corps)

	var gauche := VBoxContainer.new()
	gauche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauche.size_flags_stretch_ratio = 2.4
	corps.add_child(gauche)

	_carte_view = ExpeCarteView.new()
	_carte_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_carte_view.deplacement_demande.connect(jouer_deplacement)
	gauche.add_child(_carte_view)

	var choix := HBoxContainer.new()
	gauche.add_child(choix)
	_btn_extraire = Button.new()
	_btn_extraire.text = Translations.T("expe.extraire_btn")
	_btn_extraire.pressed.connect(func() -> void:
		run.extraire()
		_rafraichir())
	choix.add_child(_btn_extraire)
	_btn_continuer = Button.new()
	_btn_continuer.text = Translations.T("expe.continuer_btn")
	_btn_continuer.pressed.connect(func() -> void:
		run.continuer()
		_rafraichir())
	choix.add_child(_btn_continuer)

	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corps.add_child(_journal_scroll)
	_journal_label = Label.new()
	_journal_label.add_theme_font_size_override("font_size", 12)
	_journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_label)

func _lancer() -> void:
	run = ExpeRun.new(CONFIG, palier, lieu_id, graine, avatar, pool, CONFIG_COMBAT)
	run.combat_demarre.connect(func(_m: CtbMoteur, data: Dictionary) -> void:
		_combat_data = data)
	run.noeud_resolu.connect(_annoncer_contenu)
	run.terminee.connect(_sur_terminee)
	_carte_view.run = run
	run.demarrer()
	_rafraichir()

# ─── Navigation (vue partagée → intention → run) ─────────────

# Déplacement demandé (clic/flèche de la vue, ou piloté par un test) : joue
# le pas, puis le combat en attente s'il y en a un, et rafraîchit.
func jouer_deplacement(nid: int) -> void:
	if run.est_terminee or run.combat_en_cours != null:
		return
	if run.deplacer_vers(nid):
		_traiter_combat()
	_rafraichir()

# Combat en attente après un déplacement : joué à la main dans l'écran de
# combat (jeu réel) — auto-résolu seulement via le hook de test.
func _traiter_combat() -> void:
	if run.combat_en_cours == null or _combat_ui != null:
		return
	if combat_auto:
		run.combat_en_cours.derouler_auto()
		return
	_combat_ui = CombatCtbUi.new(run.combat_en_cours,
			bool(_combat_data.get("embuscade", false)))
	_combat_ui.recompenses_fournisseur = func() -> Dictionary:
		return run.dernier_combat_recompenses
	_combat_ui.inventaire_fournisseur = func() -> Array:
		return run.inventaire
	_combat_ui.sur_objet_utilise = func(objet: ConsommableData) -> void:
		run.consommer(objet)
	_combat_ui.fermee.connect(func(_recap: Dictionary) -> void:
		_combat_ui.queue_free()
		_combat_ui = null
		_rafraichir())
	add_child(_combat_ui)

# Annonce placeholder (texte flottant) du contenu d'un nœud résolu :
# Bénédiction (vert), Piège (rouge), Coffre (or). Détail au journal.
func _annoncer_contenu(data: Dictionary) -> void:
	if not data.has("contenu"):
		return
	var contenu: Dictionary = data["contenu"]
	var centre := _carte_view.position + Vector2(_carte_view.size.x * 0.5, _carte_view.size.y * 0.45)
	if contenu.has("affixe_id"):
		var positif := bool(contenu.get("positif", true))
		UIHelpers.float_text(self,
				"%s %s (%s)" % ["✨" if positif else "☒", str(contenu["affixe_id"]),
						str(contenu.get("resume", ""))],
				18, Color(0.3, 0.95, 0.45) if positif else Color(0.95, 0.3, 0.25),
				centre, 60.0, true, 2.2)
	elif contenu.has("consommable_ids"):
		var ids: Array = contenu["consommable_ids"]
		UIHelpers.float_text(self, "🧰 %s" % ", ".join(ids.map(func(i): return str(i))),
				18, Color(0.95, 0.8, 0.3), centre, 60.0, true, 2.2)

# ─── Rafraîchissement ────────────────────────────────────────

func _rafraichir() -> void:
	_carte_view.rafraichir()
	_btn_extraire.visible = run.choix_ouvert
	_btn_continuer.visible = run.choix_ouvert and run.etage < CONFIG.nb_etages
	var lieu := GameData.get_entity(lieu_id)
	_lbl_etat.text = "⚔ %s — %s · %s · %s" % [
			Translations.entity_name(lieu, lieu_id),
			Translations.resource_name(palier),
			Translations.T("expe.etage") % [run.etage, CONFIG.nb_etages],
			Translations.T("expe.pv") % [int(roundf(run.pv_avatar)),
					int(roundf(run.pv_max_effectif()))]]
	_lbl_heros.text = Translations.T("ctb.entete_heros") % [ProgressionHeros.niveau(),
			int(roundf(ProgressionHeros.xp_totale())),
			int(roundf(ProgressionHeros.seuil_prochain_niveau())),
			int(roundf(run.euren_accumule))]
	# Ligne de run : affixes actifs (résumés) + inventaire (chantier 7).
	var morceaux: PackedStringArray = []
	if not run.affixes.is_empty():
		var noms_affixes: PackedStringArray = []
		for a: AffixeData in run.affixes:
			noms_affixes.append("%s (%s)" % [Translations.resource_name(a), a.resume()])
		morceaux.append(Translations.T("expe.affixes") % ", ".join(noms_affixes))
	if not run.inventaire.is_empty():
		var comptes: Dictionary = {}
		for c: ConsommableData in run.inventaire:
			var nom := Translations.resource_name(c)
			comptes[nom] = int(comptes.get(nom, 0)) + 1
		var noms_conso: PackedStringArray = []
		for nom: String in comptes:
			noms_conso.append(nom if comptes[nom] == 1 else "%s ×%d" % [nom, comptes[nom]])
		morceaux.append(Translations.T("expe.objets") % ", ".join(noms_conso))
	_lbl_run.text = "  ·  ".join(morceaux)
	_journal_label.text = "\n".join(run.journal)
	await get_tree().process_frame   # attendre la mesure du label avant de scroller en bas
	_journal_scroll.scroll_vertical = int(_journal_scroll.get_v_scroll_bar().max_value)

# ─── Fin de run : recap placeholder puis retour au QG ────────

func _sur_terminee(recap: Dictionary) -> void:
	_recap_final = recap
	_rafraichir()
	# Défaite EN COMBAT : l'écran de combat affiche d'abord son issue (clic
	# joueur pour le fermer), le recap d'expédition vient ensuite.
	if _combat_ui != null:
		_combat_ui.fermee.connect(func(_r: Dictionary) -> void:
			_afficher_recap(recap), CONNECT_ONE_SHOT)
	else:
		_afficher_recap(recap)

func _afficher_recap(recap: Dictionary) -> void:
	var voile := ColorRect.new()
	voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voile.color = Color(0.0, 0.0, 0.0, 0.62)
	add_child(voile)

	var defaite := bool(recap.get("defaite", false))
	var extraction := bool(recap.get("extraction", false))
	var accent := Color(0.90, 0.30, 0.28) if defaite else Color(0.35, 0.90, 0.55)

	var boite := PanelContainer.new()
	boite.custom_minimum_size = Vector2(420, 0)
	boite.add_theme_stylebox_override("panel", UIHelpers.card_style(accent, 0.92, 1.0, 2, 10))
	boite.resized.connect(func() -> void:
		boite.position = (size - boite.size) * 0.5)
	add_child(boite)

	var m := UIHelpers.margin_of(18)
	boite.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	m.add_child(vb)

	var cle_issue := "expe.issue_defaite" if defaite \
			else ("expe.issue_extraction" if extraction else "expe.issue_complete")
	var titre := UIHelpers.label(Translations.T(cle_issue), 20, accent)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(titre)
	vb.add_child(HSeparator.new())

	var nb_affixes := (recap.get("affixes", []) as Array).size()
	var nb_conso := (recap.get("consommables_obtenus", []) as Array).size() \
			- (recap.get("consommables_utilises", []) as Array).size()
	var lignes: Array[String] = [
		Translations.T("expe.recap_etage") % int(recap.get("etage_atteint", 1)),
		Translations.T("expe.recap_combats") % int(recap.get("nb_combats", 0)),
		Translations.T("expe.recap_xp") % int(roundf(float(recap.get("xp_gagnee", 0.0)))),
		Translations.T("expe.recap_euren") % int(roundf(float(recap.get("euren_credite", 0.0)))),
		Translations.T("expe.recap_purge") % [nb_affixes, maxi(nb_conso, 0)],
	]
	for l in lignes:
		var lbl := UIHelpers.label(l, 13, Color(0.85, 0.88, 0.95))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lbl)

	vb.add_child(HSeparator.new())
	var btn := Button.new()
	btn.text = Translations.T("expe.retour_btn")
	btn.custom_minimum_size = Vector2(200, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(retour)
	vb.add_child(btn)

# API publique (bouton du recap, ou piloté par un test) : quitte l'écran —
# le Village libère l'écran et reprend la main au QG.
func retour() -> void:
	retour_qg.emit(_recap_final)
