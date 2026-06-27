# ============================================================
# ScreenshotTool.gd — Outil DEV : capture d'écran de scènes UI.
#
# Lance une scène avec des données factices et sauvegarde des
# captures PNG dans tests/. N'écrit JAMAIS la sauvegarde.
#
#   godot --path . res://tests/ScreenshotTool.tscn
#
# Mode via variable d'environnement SHOT_MODE :
#   "summary" (défaut) — CycleSummaryScreen avec un cycle factice
#   "village"          — hub du village avec pastilles forcées
#   "evolution"        — EvolutionRitual avec une évolution factice
#   "forge"            — panneau Forge (forgeable / XP basse / verrouillé)
# ============================================================
extends Node

# Les scènes capturées sont rendues dans un SubViewport offscreen fixe :
# la taille de la fenêtre OS (DPI, plein écran…) n'influe plus sur les PNG.
var _vp: SubViewport

func _ready() -> void:
	_disable_save_writes()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var mode := OS.get_environment("SHOT_MODE")
	if mode == "":
		mode = "summary"
	match mode:
		"welcome":   await _shoot_welcome()
		"holo":      await _shoot_holo()
		"holo_overlay": await _shoot_holo_overlay()
		"holo_baseball": await _shoot_holo_baseball()
		"village":   await _shoot_village()
		"evolution": await _shoot_evolution()
		"hero":      await _shoot_hero_panel()
		"forge":     await _shoot_forge()
		"adventure": await _shoot_adventure()
		"combat":    await _shoot_combat()
		"tooltip":   await _shoot_tooltip()
		"maxtier_hero":    await _shoot_maxtier_hero()
		"maxtier_forge":   await _shoot_maxtier_forge()
		"maxtier_village": await _shoot_maxtier_village()
		_:           await _shoot_summary()
	get_tree().quit(0)

# Coupe TOUT déclencheur d'écriture de sauvegarde : l'outil simule des
# expéditions (XP, loot) qui marqueraient le flag dirty et, après le
# debounce, ÉCRASERAIENT la sauvegarde du joueur avec l'état simulé.
func _disable_save_writes() -> void:
	for sig: Signal in [EventBus.xp_gained, EventBus.bestiary_updated,
			EventBus.resources_changed, EventBus.entity_evolved,
			EventBus.passive_unlocked, EventBus.equipment_changed,
			EventBus.equipement_evolue, EventBus.village_tier_change]:
		if sig.is_connected(SaveManager._on_progress):
			sig.disconnect(SaveManager._on_progress)
	SaveManager._save_timer.stop()
	SaveManager._save_dirty = false

# ── Capture du récap de cycle ───────────────────────────────
func _shoot_summary() -> void:
	_fake_cycle_data()
	var screen: Control = (load("res://scenes/cycle/CycleSummaryScreen.tscn") as PackedScene).instantiate()
	_vp.add_child(screen)
	await get_tree().create_timer(1.55).timeout
	_capture("res://tests/_shot_summary_mid.png")
	await get_tree().create_timer(7.0).timeout
	_capture("res://tests/_shot_summary_end.png")

# ── Capture du message d'accueil (WelcomeOverlay) ───────────
func _shoot_welcome() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(0.8).timeout
	_capture("res://tests/_shot_welcome.png")

# ── Capture de la HoloMap 3D (carte lue depuis le gabarit Excel) ──
# Scène 3D autonome dans un SubViewport à monde propre ; on laisse l'intro de
# matérialisation se jouer, puis on capture sous deux angles (yaw 0 et tourné).
func _shoot_holo() -> void:
	var vp3d := SubViewport.new()
	vp3d.size = Vector2i(1280, 720)
	vp3d.own_world_3d = true
	vp3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp3d)
	var holo: HoloMap3D = (load("res://scenes/holomap3d/holo_map_3d.tscn") as PackedScene).instantiate()
	vp3d.add_child(holo)
	await get_tree().create_timer(2.2).timeout   # intro (matérialisation) terminée
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_top.png")
	print("Screenshot -> res://tests/_shot_holo_top.png")
	# Vue tournée (orbite) pour juger le volume des bâtiments.
	holo.tourner(deg_to_rad(35.0))
	holo.plongee_deg = 42.0
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var orbit := vp3d.get_texture().get_image()
	orbit.save_png("res://tests/_shot_holo_orbit.png")
	print("Screenshot -> res://tests/_shot_holo_orbit.png")
	# Zoom ×2.5 sur le cœur de la carte (pyramide / gradins / cylindre).
	var crop := orbit.get_region(Rect2i(440, 150, 420, 320))
	crop.resize(1050, 800, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://tests/_shot_holo_zoom.png")
	print("Screenshot -> res://tests/_shot_holo_zoom.png")
	# Vue de dessus rapprochée du coin nord-est (cylindre « 9c » sur le lac).
	holo._set_yaw(0.0)
	holo.plongee_deg = 60.0
	holo._distance_cible = 9.0
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img2 := vp3d.get_texture().get_image()
	var crop2 := img2.get_region(Rect2i(720, 40, 420, 320))
	crop2.resize(1050, 800, Image.INTERPOLATE_NEAREST)
	crop2.save_png("res://tests/_shot_holo_cyl.png")
	print("Screenshot -> res://tests/_shot_holo_cyl.png")
	# Vue rapprochée des ponts (orbite recentrée sur la zone des ponts).
	holo.distance_min = 1.0
	holo._rig.position = Vector3(-1.8, 0.2, 1.6)
	holo._set_yaw(deg_to_rad(22.0))
	holo.plongee_deg = 27.0
	holo._distance_cible = 2.8
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_pont.png")
	print("Screenshot -> res://tests/_shot_holo_pont.png")
	# Profil de côté d'un pont (silhouette des rampes / et \).
	holo._rig.position = Vector3(-1.84, 0.12, 1.63)
	holo._set_yaw(0.0)
	holo.plongee_deg = 15.0
	holo._distance_cible = 1.5
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_pont_profil.png")
	print("Screenshot -> res://tests/_shot_holo_pont_profil.png")
	# Top-down sur le tour du stade (contour + médiane épurés).
	holo.distance_min = 0.6
	holo._rig.position = Vector3(3.9, 0.1, 1.73)
	holo._set_yaw(deg_to_rad(0.0))
	holo.plongee_deg = 87.0
	holo._distance_cible = 3.2
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_voies.png")
	print("Screenshot -> res://tests/_shot_holo_voies.png")

# ── Preview d'un terrain de baseball (modèle synthétique injecté) ──
func _shoot_holo_baseball() -> void:
	var vp3d := SubViewport.new()
	vp3d.size = Vector2i(1280, 720)
	vp3d.own_world_3d = true
	vp3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp3d)
	var m := HoloXlsxMap.new()
	m.ok = true
	m.grille = 24
	m.taille_case_m = 10.0
	m.hauteur_defaut_m = 3.0
	m.terrains = [{"cells": [], "bbox": Rect2i(5, 5, 14, 14)}]
	var holo: HoloMap3D = HoloMap3D.new()
	holo._excel = m            # modèle pré-injecté (pas de lecture fichier)
	holo.distance_min = 1.0
	vp3d.add_child(holo)
	await get_tree().create_timer(2.2).timeout
	# Vue quasi top-down (lecture du plan) + vue 3/4.
	holo._set_yaw(deg_to_rad(-45.0))
	holo.plongee_deg = 78.0
	holo._distance_cible = 7.2
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_baseball.png")
	print("Screenshot -> res://tests/_shot_holo_baseball.png")
	holo._set_yaw(deg_to_rad(-30.0))
	holo.plongee_deg = 50.0
	holo._distance_cible = 6.5
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	vp3d.get_texture().get_image().save_png("res://tests/_shot_holo_baseball2.png")
	print("Screenshot -> res://tests/_shot_holo_baseball2.png")

# ── Capture du chemin RÉEL en jeu : overlay « Carte » (gabarit Excel) ──
func _shoot_holo_overlay() -> void:
	var overlay := HoloMap3DOverlay.new()
	overlay.titre = "Carte des expéditions"
	overlay.sous_titre = "gabarit Excel"
	overlay.chemin_xlsx = HoloMap3D.CHEMIN_GABARIT_DEFAUT
	overlay.fermable = false
	_vp.add_child(overlay)
	await get_tree().create_timer(2.6).timeout
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("res://tests/_shot_holo_overlay.png")
	print("Screenshot -> res://tests/_shot_holo_overlay.png")

# ── Capture du village avec pastilles de notification ───────
func _shoot_village() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.2).timeout
	for item: HexItem in village._hex_items.values():
		item.has_notification = true
	await get_tree().create_timer(1.0).timeout
	_capture("res://tests/_shot_village_badges.png")

# ── Capture de l'écran de combat : combat, piège, bénédiction ──
func _shoot_combat() -> void:
	GameData.get_entity("hero")["crit_chance"] = 1.0   # crits garantis pour la capture
	# 100 % créatures : le tirage naturel ne pollue pas les captures forcées.
	GameData.get_entity("biome_foret")["event_table"] = \
			{"creature": 1.0, "benediction": 0.0, "trap": 0.0}
	AdventureSystem.start_adventure("biome_foret")
	var combat: Control = (load("res://scenes/combat/CombatScene.tscn") as PackedScene).instantiate()
	_vp.add_child(combat)
	await get_tree().create_timer(1.8).timeout
	_capture("res://tests/_shot_combat_fight.png")
	await get_tree().create_timer(1.2).timeout

	# Fige la boucle idle pour des captures déterministes, puis force
	# l'affichage d'un piège et d'une bénédiction (UI seulement).
	AdventureSystem._encounter_timer.stop()
	CombatPlayer.stop()
	var trap := GameData.get_entity("spike_trap").duplicate()
	trap["damage"] = 12
	EventBus.adventure_event_resolved.emit({
		"type": "trap", "biome_id": "biome_foret", "hero_id": "hero", "trap": trap,
	})
	await get_tree().create_timer(0.7).timeout
	_capture("res://tests/_shot_combat_trap.png")
	await get_tree().create_timer(1.2).timeout

	EventBus.adventure_event_resolved.emit({
		"type": "benediction", "biome_id": "biome_foret", "hero_id": "hero",
		"effect": GameData.get_entity("herb_find").duplicate(),
	})
	await get_tree().create_timer(0.7).timeout
	_capture("res://tests/_shot_combat_bene.png")
	AdventureSystem.is_running = false

# ── Capture du panneau Héros (HeroDoll) ─────────────────────
func _shoot_hero_panel() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	# Injection APRÈS le boot (load_save écraserait l'état forcé) :
	# 2 équipements obtenus → leurs slots visibles, l'Arme reste cachée.
	for eid: String in ["equipment_anneau", "equipment_armure"]:
		GameData.get_entity(eid)["est_debloque"] = true
	village._open_panel("hero")
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_hero_panel.png")
	# Zoom ×3 sur la zone du pantin (moitié haute du panneau droit).
	var img := _vp.get_texture().get_image()
	var w := img.get_width()
	var zone := Rect2i(int(w * 0.58), 0, int(w * 0.40), int(img.get_height() * 0.45))
	var crop := img.get_region(zone)
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://tests/_shot_hero_doll_zoom.png")
	print("Screenshot -> res://tests/_shot_hero_doll_zoom.png")

# ── Capture du panneau Forge ────────────────────────────────
# Trois états en une capture : Anneau forgeable (bouton actif englobant
# l'aperçu de transformation), Armure en manque d'XP/ingrédients (bouton
# désactivé), Arme verrouillée (Montagne sous le palier Peu Commun).
func _shoot_forge() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	# Injection APRÈS le boot du Village : load_save() écraserait sinon
	# ces états forcés avec la sauvegarde réelle du joueur.
	GameData.village["maitrise_actuelle"] = 1
	for bid: String in ["biome_foret", "biome_marecage", "biome_montagne"]:
		GameData.get_entity(bid)["est_decouvert"] = true
	for eid: String in ["equipment_anneau", "equipment_armure"]:
		GameData.get_entity(eid)["est_debloque"] = true
	# Anneau : XP pleine + ingrédients au complet → bouton Forger actif.
	GameData.get_entity("equipment_anneau")["xp_maitrise_actuelle"] = 99999.0
	for req in GameData.get_forge_recipe("equipment_anneau", 1):
		GameData.player["resources"][req["ingredient_id"]] = int(req["quantite"])
	village._open_panel("forge")
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_forge_panel.png")

# ── Capture du panneau Expéditions ──────────────────────────
# Biome sélectionné (liseré or + luciole) avec accordéon déplié :
# header « nom | palier XP | Entités x/y », pill « ! Prochain palier ».
func _shoot_adventure() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	village.adv_selected_biome_id = "biome_foret"
	village._open_panel("adventure")
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_adventure_panel.png")

# ── Capture du rituel d'évolution à 3 moments clés ──────────
func _shoot_evolution() -> void:
	GameData.pending_evolution = {
		"entity_type": "creature",
		"entity_id":   "creature_foret_surface",
		"entity_name": "Rat des Égouts",
		"from_tier":   1,
		"to_tier":     2,
	}
	# SHOT_ENTITY=equipment → variante équipement forgé (Anneau T0→T1).
	if OS.get_environment("SHOT_ENTITY") == "equipment":
		GameData.pending_evolution = {
			"entity_type": "equipment",
			"entity_id":   "equipment_anneau",
			"entity_name": "Anneau de Forêt",
			"from_tier":   0,
			"to_tier":     1,
		}
	var ritual: Control = (load("res://scenes/village/EvolutionRitual.tscn") as PackedScene).instantiate()
	_vp.add_child(ritual)
	await get_tree().create_timer(1.6).timeout
	_capture("res://tests/_shot_evo_rise.png")
	await get_tree().create_timer(1.1).timeout
	_capture("res://tests/_shot_evo_reveal.png")
	await get_tree().create_timer(2.3).timeout
	_capture("res://tests/_shot_evo_celebrate.png")

# ── Capture du TooltipOverlay (autoload racine, hors SubViewport) ──
# Village en fond + tooltip représentatif (titre + lore + corps), langue EN
# pour vérifier la localisation. Zoom ×2 sur la zone du tooltip.
func _shoot_tooltip() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameSettings.language = "en"
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(village)
	await get_tree().create_timer(1.2).timeout

	var biome := GameData.get_entity("biome_foret")
	TooltipOverlay.show_for(
			Translations.entity_name(biome, "biome_foret"),
			"Max zone: Surface\nMechanic: Ambush\nNext rank — Rare: frees a Memory Fragment · activates the Ambush mechanic · unlocks the Depths zone",
			UIColors.tier_color(2),
			Translations.entity_lore(biome))
	await get_tree().create_timer(0.6).timeout
	# Fige le suivi de souris et place le tooltip au centre pour la capture.
	TooltipOverlay.set_process(false)
	TooltipOverlay._panel.global_position = Vector2(460.0, 200.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/_shot_tooltip.png")
	print("Screenshot -> res://tests/_shot_tooltip.png")
	var crop := img.get_region(Rect2i(420, 160, 520, 400))
	crop.resize(1040, 800, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://tests/_shot_tooltip_zoom.png")
	print("Screenshot -> res://tests/_shot_tooltip_zoom.png")

# ── Garde-fou « Palier Max atteint » (plafond dur T2) ───────
# Trois modes indépendants (un process chacun) : héros / forge / hub Village
# forcés au plafond global pour visualiser la mention de palier max.

func _shoot_maxtier_hero() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	GameData.get_entity("hero")["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	for eid: String in ["equipment_anneau", "equipment_armure"]:
		var eq := GameData.get_entity(eid)
		eq["est_debloque"] = true
		eq["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	village._open_panel("hero")
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_maxtier_hero.png")

func _shoot_maxtier_forge() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	GameData.village["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	for bid: String in ["biome_foret", "biome_marecage", "biome_montagne"]:
		GameData.get_entity(bid)["est_decouvert"] = true
	for eid: String in ["equipment_anneau", "equipment_armure"]:
		var eq := GameData.get_entity(eid)
		eq["est_debloque"] = true
		eq["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	village._open_panel("forge")
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_maxtier_forge.png")

func _shoot_maxtier_village() -> void:
	var village: Node = (load("res://scenes/village/village.tscn") as PackedScene).instantiate()
	_vp.add_child(village)
	await get_tree().create_timer(1.0).timeout
	GameData.village["maitrise_actuelle"] = Balance.GLOBAL_MAX_TIER
	village._rebuild_hub()
	await get_tree().create_timer(1.2).timeout
	_capture("res://tests/_shot_maxtier_village.png")

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(path)
	print("Screenshot -> ", path)

# Résumé de cycle factice : XP réparties réalistes, butin, une évolution dispo.
func _fake_cycle_data() -> void:
	var detail_xp := {
		"creature_foret_surface": 0.0,
		"spike_trap":             0.0,
		"herb_find":              0.0,
	}
	# Donne à chaque entité une XP cohérente (barre partiellement remplie).
	var gains := {}
	for eid: String in ["hero", "biome_foret", "passive_combat_mastery",
			"equipment_anneau"] + detail_xp.keys():
		var e := GameData.get_entity(eid)
		if e.is_empty():
			continue
		var tier := int(e.get("maitrise_actuelle", 0))
		var idx: int = mini(tier + 1, GameData.xp_thresholds.size() - 1)
		var threshold := float(GameData.xp_thresholds[idx])
		var frac := 1.15 if eid == "creature_foret_surface" else 0.55
		e["xp_maitrise_actuelle"] = threshold * frac
		gains[eid] = threshold * 0.40
	for eid: String in detail_xp:
		detail_xp[eid] = gains.get(eid, 25.0)

	GameData.get_entity("biome_foret")["est_decouvert"] = true

	CycleData.last_cycle_summary = {
		"victory":              true,
		"interrupted":          false,
		"biome_id":             "biome_foret",
		"hero_id":              "hero",
		"modifier":             {},
		"xp_total":             412.0,
		"xp_hero":              gains.get("hero", 120.0),
		"xp_biome":             gains.get("biome_foret", 90.0),
		"xp_passives_total":    gains.get("passive_combat_mastery", 30.0),
		"xp_passives_detail":   {"passive_combat_mastery": gains.get("passive_combat_mastery", 30.0)},
		"xp_entities_detail":   detail_xp,
		"loot_total":           7,
		"loot_detail":          {"res_fourrure": 6, "ingredient_oscar": 1},
		"xp_equip_detail":      {"equipment_anneau": gains.get("equipment_anneau", 20.0)},
		"combats_won":          9,
		"events":               11,
		"events_total":         12,
		"new_discoveries":      ["creature_foret_surface", "spike_trap", "herb_find"],
		"unique_beaten":        false,
	}
