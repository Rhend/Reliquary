# ============================================================
# BirthSequence.gd — Phase d'éclosion du Village (extrait de Village).
#
# Le Village n'existe pas encore : le joueur clique Balance.ECLOSION_CLICS fois
# sur une orbe pour faire éclore l'incarnation. UI minimale (orbe + compteur +
# phrases d'éveil + chuchotements d'ambiance) ; au dernier clic → éclosion en
# T0 + voile chaud + cinématique d'ascension (host.launch_evolution_ritual).
#
# Possède son propre état (orbe, compteur, phrases) ; s'appuie sur le host
# (Village) pour le centrage (_center), le fond d'ambiance (_backdrop), le
# parentage des nœuds et la transition finale. Aucune connexion de signal →
# pas de cycle de vie à gérer (libéré avec le membre _birth du Village).
# ============================================================
class_name BirthSequence
extends RefCounted

const AWAKEN_COLOR   := Color(1.0, 0.86, 0.55)   # doré chaud — âme qui s'éveille
const WHISPER_CHANCE := 0.22
const WHISPER_COUNT  := 10   # nombre de clés birth.whisper.N dans Translations

var _host: Village
var _orb:        ClickOrb        # orbe d'éclosion (juice d'éveil)
var _xp_label:   Label           # compteur de clics sous l'orbe
var _phrase:     Label           # phrase d'éveil affichée actuellement
var _phrase_idx  := 0            # index de la prochaine phrase d'éveil à montrer
var _hatching    := false        # vrai pendant le battement final avant l'éclosion

func _init(host: Village) -> void:
	_host = host

# Phrases d'éveil : seuils fixes, textes lus depuis Translations à l'affichage.
func _phrases() -> Array:
	return [
		[0.25, Translations.T("birth.phrase_25")],
		[0.50, Translations.T("birth.phrase_50")],
		[0.75, Translations.T("birth.phrase_75")],
	]

# Pool des chuchotements d'ambiance (courts) tirés au hasard pendant les clics.
func _whispers() -> Array:
	var out: Array = []
	for i in range(1, WHISPER_COUNT + 1):
		out.append(Translations.T("birth.whisper." + str(i)))
	return out

# Construit l'UI d'éclosion : orbe cliquable + compteur + message (pas d'anneau).
func build() -> void:
	var clics    := int(GameData.village.get("clics_eclosion", 0))
	var needed   := Balance.ECLOSION_CLICS
	var progress := clampf(float(clics) / float(needed), 0.0, 1.0)

	# Ambiance discrète : le fond se réchauffe avec la progression de l'éveil.
	if _host._backdrop:
		_host._backdrop.set_tier(0, UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, progress))

	var orb := ClickOrb.new()
	orb.tier_color   = UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, progress)
	orb.callback     = Callable(self, "_on_click")
	_host._center(orb, Vector2(0.0, -10.0), Vector2(96.0, 96.0))
	orb.pivot_offset = Vector2(48.0, 48.0)
	_host.add_child(orb)
	_orb = orb

	_xp_label = UIHelpers.label("%d / %d" % [clics, needed], 15, UIColors.VILLAGE_NASCENT.lightened(0.3))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host._center(_xp_label, Vector2(0.0, 56.0), Vector2(160.0, 24.0))
	_host.add_child(_xp_label)

	var flavor := UIHelpers.label(Translations.T("birth.flavor"), 12, UIColors.TEXT_MUTED)
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host._center(flavor, Vector2(0.0, 92.0), Vector2(320.0, 44.0))
	_host.add_child(flavor)

	# Reprend la séquence d'éveil là où elle en est : on saute les paliers déjà
	# franchis pour ne pas les rejouer après un rechargement de scène.
	_phrase = null
	_phrase_idx = 0
	_hatching = false
	var bp := _phrases()
	while _phrase_idx < bp.size() \
			and progress + 0.0001 >= float(bp[_phrase_idx][0]):
		_phrase_idx += 1

# ─── Phase d'éclosion : clic ─────────────────────────────────
# Incrémente le compteur de clics ; au dernier, déclenche l'éclosion en T0.
func _on_click() -> void:
	if GameData.village.get("eclos", false) or _hatching:
		return
	var needed   := Balance.ECLOSION_CLICS
	var clics    := int(GameData.village.get("clics_eclosion", 0)) + Balance.ECLOSION_CLIC_VALUE
	GameData.village["clics_eclosion"] = clics
	var progress := clampf(float(clics) / float(needed), 0.0, 1.0)

	if is_instance_valid(_xp_label):
		_xp_label.text = "%d / %d" % [mini(clics, needed), needed]
		_xp_label.add_theme_color_override("font_color",
				UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, progress).lightened(0.2))

	# L'étincelle se réchauffe à mesure que l'âme s'éveille.
	if is_instance_valid(_orb):
		_orb.tier_color = UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, progress)

	# Phrases d'éveil au franchissement des paliers (25 / 50 / 75 %).
	var bp := _phrases()
	while _phrase_idx < bp.size() \
			and progress + 0.0001 >= float(bp[_phrase_idx][0]):
		_show_phrase(bp[_phrase_idx][1], false)
		_phrase_idx += 1

	# Chuchotements d'ambiance : fragments narratifs courts qui surgissent au
	# hasard durant les clics, à une position aléatoire, en fondu entrant/sortant.
	if not _hatching and randf() < WHISPER_CHANCE:
		_show_whisper()

	if clics >= needed:
		# Éveil final : phrase forte + voile chaud, puis éclosion après un battement.
		_hatching = true
		_show_phrase(Translations.T("birth.phrase_100"), true)
		_awaken_flash()
		var tw := _host.create_tween()
		tw.tween_interval(1.8)
		tw.tween_callback(_hatch)

# Affiche une phrase d'éveil au-dessus de l'orbe : fondu entrant + léger « pop ».
# La phrase précédente s'efface en douceur. Une phrase `final` reste affichée
# (l'éclosion enchaîne par-dessus). Le reste se fond après quelques secondes.
func _show_phrase(text: String, final: bool) -> void:
	if is_instance_valid(_phrase):
		var old := _phrase
		var ot := old.create_tween()   # lié à `old` → auto-tué si `old` est libéré
		ot.tween_property(old, "modulate:a", 0.0, 0.3)
		ot.tween_callback(old.queue_free)

	var lbl := UIHelpers.label(text, 19 if final else 15,
			AWAKEN_COLOR if final else UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, 0.7))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.modulate.a = 0.0
	lbl.scale = Vector2(0.96, 0.96)
	lbl.resized.connect(func() -> void: lbl.pivot_offset = lbl.size * 0.5)
	_host._center(lbl, Vector2(0.0, -150.0), Vector2(480.0, 90.0))
	_host.add_child(lbl)
	_phrase = lbl

	var t_in := lbl.create_tween().set_parallel(true)
	t_in.tween_property(lbl, "modulate:a", 1.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t_in.tween_property(lbl, "scale", Vector2.ONE, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	if not final:
		var t_out := lbl.create_tween()
		t_out.tween_interval(2.9)
		t_out.tween_property(lbl, "modulate:a", 0.0, 0.9)
		t_out.tween_callback(lbl.queue_free)

# Chuchotement d'ambiance : court fragment narratif tiré au hasard, posé à une
# position aléatoire de l'écran (périphérie, hors de l'orbe et des phrases),
# fondu entrant PUIS sortant symétriques avant de se libérer.
func _show_whisper() -> void:
	var pool := _whispers()
	if pool.is_empty():
		return

	var lbl := UIHelpers.label(pool[randi() % pool.size()] as String, 13,
			UIColors.VILLAGE_NASCENT.lerp(AWAKEN_COLOR, 0.45))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.modulate.a    = 0.0
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE   # ne vole pas le clic de l'orbe
	lbl.z_index       = 50

	var w := 300.0
	var h := 40.0
	lbl.position = _random_pos(_host.get_viewport_rect().size, w, h)
	lbl.size     = Vector2(w, h)
	_host.add_child(lbl)

	# Fondu entrant puis sortant SYMÉTRIQUES (même durée, même courbe), avec un
	# court palier visible entre les deux.
	var fade := 0.9
	var tw := lbl.create_tween()   # lié à `lbl` → auto-tué si libéré
	tw.tween_property(lbl, "modulate:a", 0.9, fade).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, fade).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(lbl.queue_free)

# Position aléatoire bornée aux marges de l'écran, en évitant un rectangle
# central (orbe + compteur + phrases d'éveil) pour ne pas brouiller la lecture.
func _random_pos(vp: Vector2, w: float, h: float) -> Vector2:
	var margin := 50.0
	var min_x := margin
	var max_x := maxf(vp.x - w - margin, min_x)
	var min_y := margin
	var max_y := maxf(vp.y - h - margin, min_y)
	var exclusion := Rect2(vp.x * 0.5 - 280.0, vp.y * 0.5 - 200.0, 560.0, 400.0)
	for _i in 12:
		var p := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if not exclusion.intersects(Rect2(p, Vector2(w, h))):
			return p
	return Vector2(min_x, min_y)   # repli (écran trop petit) : coin haut-gauche

# Bref voile chaud sur tout l'écran au moment de l'éveil final.
func _awaken_flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(AWAKEN_COLOR.r, AWAKEN_COLOR.g, AWAKEN_COLOR.b, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 400
	_host.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.22, 0.30).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "color:a", 0.0, 1.30).set_ease(Tween.EASE_IN)
	tw.tween_callback(flash.queue_free)

# Fait éclore le Village en T0, sauvegarde, puis lance la cinématique d'éclosion.
func _hatch() -> void:
	GameData.village["eclos"] = true
	SaveManager.save()
	# entity_id volontairement "village" (absent du catalogue d'entités) : le rituel
	# retombe alors sur le nom passé ("Village"). Passer "hero" affichait "Héros".
	_host.launch_evolution_ritual(Enums.EntityType.VILLAGE, "village", "Village", 0, 0, {"eclosion": true})
