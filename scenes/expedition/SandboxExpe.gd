# ============================================================
# SandboxExpe — Scène ISOLÉE de test de la carte d'expédition (chantiers 2-3).
#
# Lançable directement (F6) : expédition complète sur un Lieu FACTICE —
# palier de profondeur sélectionnable, graine rejouable, navigation à la
# souris (clic sur un nœud adjacent) ou au clavier (flèches = nœud adjacent
# le plus proche dans la direction), brouillard de guerre réel (les nœuds
# non découverts ne sont PAS dessinés), choix Extraire / Continuer sur la
# Fin d'étage, journal des événements à droite.
#
# Chantier 3 : les nœuds Combat / Attaque surprise jouent de VRAIS combats
# CTB (avatar factice vs pool du bestiaire) ; PV de l'Avatar persistants
# entre les nœuds, affichés en permanence ; défaite = fin d'expédition
# immédiate.
#
# Chantier 5 : par défaut les combats sont JOUÉS À LA MAIN dans l'écran de
# combat (CombatCtbUi — Attaquer / Défendre, cible au choix, embuscade
# annoncée). La case « Combat auto » restaure l'auto-résolution du chantier 3
# (journal du moteur replié dans celui de la run) ; le ScreenshotTool et les
# suites de test pilotent ExpeRun directement et restent en auto.
#
# Chantier 6 : en-tête de run avec niveau / XP / Euren accumulé, écran
# d'issue de bataille enrichi (XP + Euren du combat), Euren crédité affiché
# en fin de run. Le sandbox se DÉCONNECTE des déclencheurs de sauvegarde
# (progression de test jamais écrite dans la sauvegarde du joueur).
#
# Outil de DEV : pas une UI de jeu (l'UI finale viendra avec sa DA).
# ============================================================
extends Control

const PALIERS: Array[PalierProfondeurData] = [
	preload("res://data/expedition/palier_peripherie.tres"),
	preload("res://data/expedition/palier_enceinte.tres"),
	preload("res://data/expedition/palier_noyau.tres"),
]
const CONFIG: ExpeCarteConfigData = preload("res://data/expedition/config_carte.tres")
const CONFIG_COMBAT: ExpeCombatConfigData = preload("res://data/expedition/config_combat.tres")
const POOL: PoolEnnemisData = preload("res://data/expedition/pool_defaut.tres")
const AVATAR: CombattantCtbData = preload("res://data/combat_ctb/avatar.tres")

var run: ExpeRun
var _carte_view: ExpeCarteView   # rendu + navigation partagés avec l'écran de jeu (chantier 8)
var _journal_label: Label
var _journal_scroll: ScrollContainer
var _btn_extraire: Button
var _btn_continuer: Button
var _opt_palier: OptionButton
var _spin_graine: SpinBox
var _chk_heros: CheckBox
var _chk_combat_auto: CheckBox
var _lbl_etat: Label
var _lbl_run: Label                  # affixes actifs + inventaire (chantier 7)
var _combat_data: Dictionary = {}    # payload du dernier combat_demarre (embuscade…)
var _combat_ui: CombatCtbUi = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Chantier 6 : les combats créditent XP/Euren (signaux de progression).
	# Le sandbox reste un OUTIL : il ne doit JAMAIS écrire la sauvegarde du
	# joueur avec une progression de test — déconnexion des déclencheurs
	# (même pattern que le ScreenshotTool ; la persistance réelle viendra
	# avec le branchement au flux de jeu principal, hors scope).
	for sig: Signal in SaveManager.signaux_progression():
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false
	_construire_ui()
	_lancer()

func _construire_ui() -> void:
	var racine := HBoxContainer.new()
	racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(racine)

	# ── Colonne gauche : contrôles + carte ──
	var gauche := VBoxContainer.new()
	gauche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauche.size_flags_stretch_ratio = 2.4
	racine.add_child(gauche)

	var barre := HBoxContainer.new()
	gauche.add_child(barre)
	_opt_palier = OptionButton.new()
	for p in PALIERS:
		_opt_palier.add_item("%s (×%.1f)" % [p.nom_journal(), p.multiplicateur])
	barre.add_child(_opt_palier)
	_spin_graine = SpinBox.new()
	_spin_graine.min_value = 0
	_spin_graine.max_value = 999999
	_spin_graine.value = 1337
	_spin_graine.tooltip_text = "Graine RNG (0 = aléatoire)"
	barre.add_child(_spin_graine)
	var btn_go := Button.new()
	btn_go.text = "⟳ Relancer l'expédition"
	btn_go.pressed.connect(_lancer)
	barre.add_child(btn_go)
	_chk_heros = CheckBox.new()
	_chk_heros.text = "Héros réel"
	_chk_heros.button_pressed = true
	_chk_heros.tooltip_text = "Coché : le vrai héros (stats effectives, équipement compris,\n" \
			+ "via CtbPont.combattant_depuis_heros). Décoché : avatar factice (avatar.tres)."
	_chk_heros.toggled.connect(func(_on: bool) -> void: _lancer())
	barre.add_child(_chk_heros)
	_chk_combat_auto = CheckBox.new()
	_chk_combat_auto.text = "Combat auto"
	_chk_combat_auto.button_pressed = false
	_chk_combat_auto.tooltip_text = "Décoché : les combats se jouent à la main (écran de combat).\n" \
			+ "Coché : auto-résolution (comportement chantier 3 — captures, calibrage)."
	barre.add_child(_chk_combat_auto)
	_lbl_etat = Label.new()
	barre.add_child(_lbl_etat)

	# Affixes actifs + inventaire de run, visibles en permanence (chantier 7).
	_lbl_run = Label.new()
	_lbl_run.add_theme_font_size_override("font_size", 12)
	_lbl_run.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	gauche.add_child(_lbl_run)

	_carte_view = ExpeCarteView.new()
	_carte_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_carte_view.deplacement_demande.connect(_jouer_deplacement)
	gauche.add_child(_carte_view)

	var choix := HBoxContainer.new()
	gauche.add_child(choix)
	_btn_extraire = Button.new()
	_btn_extraire.text = "▲ EXTRAIRE (fin d'expédition)"
	_btn_extraire.pressed.connect(func() -> void:
		run.extraire()
		_rafraichir())
	choix.add_child(_btn_extraire)
	_btn_continuer = Button.new()
	_btn_continuer.text = "▼ CONTINUER (étage suivant)"
	_btn_continuer.pressed.connect(func() -> void:
		run.continuer()
		_rafraichir())
	choix.add_child(_btn_continuer)

	# ── Colonne droite : journal ──
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	racine.add_child(_journal_scroll)
	_journal_label = Label.new()
	_journal_label.add_theme_font_size_override("font_size", 12)
	_journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_label)

func _lancer() -> void:
	if _combat_ui != null:
		_combat_ui.queue_free()
		_combat_ui = null
	var palier: PalierProfondeurData = PALIERS[maxi(_opt_palier.selected, 0)]
	run = ExpeRun.new(CONFIG, palier, "lieu_factice_sandbox", int(_spin_graine.value),
			_avatar_choisi(), POOL, CONFIG_COMBAT)
	run.combat_demarre.connect(func(_m: CtbMoteur, data: Dictionary) -> void:
		_combat_data = data)
	# Popup placeholder à l'obtention d'un contenu de nœud (affixe/coffre).
	run.noeud_resolu.connect(_annoncer_contenu)
	_carte_view.run = run
	run.demarrer()
	_rafraichir()

# Déplacement demandé par la vue (clic sur un nœud adjacent, flèches).
func _jouer_deplacement(nid: int) -> void:
	if run.est_terminee or run.combat_en_cours != null:
		return
	if run.deplacer_vers(nid):
		_traiter_combat()
	_rafraichir()

# Annonce placeholder (texte flottant au centre de la carte) du contenu d'un
# nœud résolu : Bénédiction (vert), Piège (rouge), Coffre (or). Le détail
# complet reste au journal.
func _annoncer_contenu(data: Dictionary) -> void:
	if not data.has("contenu"):
		return
	var contenu: Dictionary = data["contenu"]
	var centre := Vector2(_carte_view.size.x * 0.5, _carte_view.size.y * 0.45) \
			+ _carte_view.position
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

# Héros RÉEL de la partie courante (défaut) ou avatar factice (tests/calibrage).
# Lancé seul (F6), le sandbox charge la sauvegarde pour refléter la vraie
# partie — jamais deux fois par-dessus une partie en cours ; il n'émet aucun
# signal de progression (rien à écrire).
func _avatar_choisi() -> CombattantCtbData:
	if _chk_heros == null or not _chk_heros.button_pressed:
		return AVATAR
	if not SaveManager.est_chargee():
		SaveManager.load_save()
	var heros := CtbPont.combattant_depuis_heros()
	return heros if heros != null else AVATAR

# Combat en attente après un déplacement : joué à la main dans l'écran de
# combat (défaut) ou auto-résolu si « Combat auto » est coché (le journal du
# moteur est replié dans celui de la run à la fin du combat, dans les deux
# cas). Le ScreenshotTool pilote ExpeRun directement : jamais d'UI chez lui.
func _traiter_combat() -> void:
	if run.combat_en_cours == null or _combat_ui != null:
		return
	if _chk_combat_auto.button_pressed:
		run.combat_en_cours.derouler_auto()
		return
	_combat_ui = CombatCtbUi.new(run.combat_en_cours,
			bool(_combat_data.get("embuscade", false)))
	# Écran d'issue enrichi (chantier 6) : XP et Euren du combat gagné.
	_combat_ui.recompenses_fournisseur = func() -> Dictionary:
		return run.dernier_combat_recompenses
	# Consommables de run (chantier 7) : l'inventaire vit dans ExpeRun.
	_combat_ui.inventaire_fournisseur = func() -> Array:
		return run.inventaire
	_combat_ui.sur_objet_utilise = func(objet: ConsommableData) -> void:
		run.consommer(objet)
	_combat_ui.fermee.connect(func(_recap: Dictionary) -> void:
		_combat_ui.queue_free()
		_combat_ui = null
		_rafraichir())
	add_child(_combat_ui)

func _rafraichir() -> void:
	_carte_view.rafraichir()
	_btn_extraire.visible = run.choix_ouvert
	_btn_continuer.visible = run.choix_ouvert and run.etage < CONFIG.nb_etages
	var pv := "PV %d/%d" % [int(roundf(run.pv_avatar)), int(roundf(run.pv_max_effectif()))]
	# En-tête héros (chantier 6, placeholder) : niveau, XP x/y, Euren de la run.
	var heros := Translations.T("ctb.entete_heros") % [ProgressionHeros.niveau(),
			int(roundf(ProgressionHeros.xp_totale())),
			int(roundf(ProgressionHeros.seuil_prochain_niveau())),
			int(roundf(run.euren_accumule))]
	if run.est_terminee:
		var credit := " — ◈ crédité : %d" % int(roundf(run.euren_credite))
		_lbl_etat.text = "  %s — %s · %s%s" % [
				"☠ DÉFAITE" if run.defaite else "✔ Expédition terminée", pv, heros, credit]
	else:
		_lbl_etat.text = "  Étage %d/%d — %s · %s" % [run.etage, CONFIG.nb_etages, pv, heros]
	# Ligne de run (chantier 7) : affixes actifs (résumés) + inventaire.
	var morceaux: PackedStringArray = []
	if not run.affixes.is_empty():
		var noms_affixes: PackedStringArray = []
		for a: AffixeData in run.affixes:
			noms_affixes.append("%s (%s)" % [a.nom_journal(), a.resume()])
		morceaux.append("Affixes : " + ", ".join(noms_affixes))
	if not run.inventaire.is_empty():
		var comptes: Dictionary = {}
		for c: ConsommableData in run.inventaire:
			comptes[c.nom_journal()] = int(comptes.get(c.nom_journal(), 0)) + 1
		var noms_conso: PackedStringArray = []
		for nom: String in comptes:
			noms_conso.append(nom if comptes[nom] == 1 else "%s ×%d" % [nom, comptes[nom]])
		morceaux.append("Objets : " + ", ".join(noms_conso))
	_lbl_run.text = "  " + "  ·  ".join(morceaux) if not morceaux.is_empty() else ""
	_journal_label.text = "\n".join(run.journal)
	await get_tree().process_frame   # attendre la mesure du label avant de scroller en bas
	_journal_scroll.scroll_vertical = int(_journal_scroll.get_v_scroll_bar().max_value)

# (Rendu de la carte et navigation clic/flèches : extraits dans ExpeCarteView
#  — chantier 8, vue partagée avec l'écran de jeu réel ExpeditionScreen.)
