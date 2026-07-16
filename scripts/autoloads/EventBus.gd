# ============================================================
# EventBus.gd — Bus de signaux central (pattern Observer).
#
# Tous les systèmes communiquent exclusivement via ce nœud :
# un émetteur appelle  EventBus.signal_name.emit(...)
# un récepteur appelle EventBus.signal_name.connect(callback)
#
# Avantage : aucun système ne référence directement un autre,
# ce qui rend l'ajout ou la suppression de systèmes trivial.
# ============================================================
extends Node

# ── Maîtrise & Évolution ────────────────────────────────────

# Émis par MasterySystem chaque fois qu'une entité gagne de l'XP.
@warning_ignore("unused_signal")
signal xp_gained(entity_id: String, amount: float)

# Émis quand une entité a suffisamment d'XP pour monter de tier.
# Note : l'évolution elle-même est toujours déclenchée manuellement.
@warning_ignore("unused_signal")
signal entity_ready_to_evolve(entity_id: String)

# Émis après une évolution réussie, avec le nouveau tier.
@warning_ignore("unused_signal")
signal entity_evolved(entity_id: String, new_tier: int)

# Émis quand une entrée du Hall des Évolutions est créée ou mise à jour.
@warning_ignore("unused_signal")
signal bestiary_updated(enc_id: String)

# Émis à la PREMIÈRE rencontre d'une entité (création de son entrée au
# bestiaire) — sert au suivi des découvertes d'une expédition.
@warning_ignore("unused_signal")
signal entity_discovered(entity_id: String)

# ── Ressources & Forge ──────────────────────────────────────

# Émis par AdventureSystem après un drop de butin.
# drops : Array de { item_id, name, qty }
@warning_ignore("unused_signal")
signal loot_dropped(drops: Array, enemy_name: String)

# Émis par GameData après tout changement d'inventaire (drop, craft, consommation).
@warning_ignore("unused_signal")
signal resources_changed()

# ── Modificateurs de cycle, soin & saignement ──────────────

# Émis par AdventureSystem au lancement d'une aventure avec le modificateur tiré.
@warning_ignore("unused_signal")
signal modifier_activated(modifier: Dictionary)

# Émis quand un événement positif de soin restaure des PV.
# amount = PV effectivement restaurés, new_hp = PV après soin.
@warning_ignore("unused_signal")
signal heal_applied(amount: float, new_hp: float)

# Émis à chaque tick de saignement (infligé par certains pièges).
# damage = dégâts appliqués, new_hp = PV restants, remaining = ticks restants.
@warning_ignore("unused_signal")
signal bleed_ticked(damage: float, new_hp: float, remaining: int)

# ── Passifs ─────────────────────────────────────────────────

# Émis quand un passif est débloqué sur une entité (palier de tier atteint).
@warning_ignore("unused_signal")
signal passive_unlocked(entity_id: String, passive_id: String)

# Émis par PassiveSystem après un recalcul complet des effets actifs.
@warning_ignore("unused_signal")
signal passives_refreshed()

# ── Aventure ────────────────────────────────────────────────

@warning_ignore("unused_signal")
signal adventure_started(biome_id: String)
# Émis quand un Fragment est libéré au passage d'un biome à Rare.
@warning_ignore("unused_signal")
signal fragment_libere(fragment_id: String, biome_id: String)
# Émis quand le Village passe au Tier suivant.
@warning_ignore("unused_signal")
signal village_tier_change(nouveau_tier: int)
# Émis quand un bâtiment de quartier est amélioré ou une route reconstruite
# (Chantier 4) → recalcul des bonus de village + rafraîchissement de l'UI.
@warning_ignore("unused_signal")
signal village_buildings_changed()
# Émis quand un biome secondaire est révélé au passage d'un biome à Légendaire.
@warning_ignore("unused_signal")
signal biome_revele(biome_id: String)
# Émis après la victoire contre une créature Unique d'Abysse.
@warning_ignore("unused_signal")
signal creature_unique_vaincue(biome_id: String, ingredient_id: String, passif_id: String)
# event_data : { type, biome_id, hero_id, [enemy / effect / trap], [ignored] }
@warning_ignore("unused_signal")
signal adventure_event_resolved(event_data: Dictionary)
# result : résumé complet du cycle — cf. AdventureSystem._build_summary()
@warning_ignore("unused_signal")
signal adventure_cycle_ended(result: Dictionary)
@warning_ignore("unused_signal")
signal adventure_stopped()

# ── Combat CTB (Rework Combat — chantier 1) ─────────────────
# (Les anciens signaux combat_started/combat_ended du moteur temps réel ont
#  été supprimés avec lui ; le CTB émet ctb_victoire/ctb_defaite ci-dessous.)

# Émis par CtbMoteur quand tous les ennemis sont à 0 PV.
# recap : { victoire, nb_activations, pv_restants, ennemis_vaincus
# (Array[CombattantCtbData] des tués) } — cf. CtbMoteur._recap(). Le loot et
# l'XP sont calculés en aval par le système d'expédition, hors moteur.
@warning_ignore("unused_signal")
signal ctb_victoire(recap: Dictionary)

# Émis par CtbMoteur quand les PV de l'Avatar tombent à 0. La sanction
# (perte de ressources, compteur R-XXX) est hors scope chantier 1 :
# seul le signal est posé.
@warning_ignore("unused_signal")
signal ctb_defaite(recap: Dictionary)

# ── Carte d'expédition (Rework Combat — chantier 2) ─────────

# Émis à chaque ENTRÉE du joueur sur un nœud non résolu (résolution stub au
# chantier 2 — le branchement réel combat/loot/bénédiction/piège viendra après).
# data : { type (Enums.TypeNoeud), contenu_mystere (Enums.ContenuMystere, -1 si
# non applicable), lieu_id, palier_id, multiplicateur, etage, noeud_id }
@warning_ignore("unused_signal")
signal expe_noeud_resolu(data: Dictionary)

# Émis à la PREMIÈRE arrivée sur le nœud Fin d'étage (ouvre le choix
# Extraire / Continuer — sauf au dernier étage : fin d'expédition directe).
# data : { etage, lieu_id, palier_id }
@warning_ignore("unused_signal")
signal expe_etage_termine(data: Dictionary)

# Émis à la fin d'une expédition (extraction volontaire ou dernier étage
# bouclé). recap : cf. ExpeRun._recap().
@warning_ignore("unused_signal")
signal expe_terminee(recap: Dictionary)

# ── Économie de récompense (Rework Combat — chantier 6) ─────

# Émis à chaque crédit d'XP de NIVEAU du héros (immédiat à la victoire de
# chaque combat — arbitrage 06/07/2026). Distinct de xp_gained (Maîtrise).
@warning_ignore("unused_signal")
signal heros_xp_gagnee(montant: float, xp_totale: float)

# Émis quand le NIVEAU du héros monte (peut sauter plusieurs niveaux en un
# gain). Pour la future UI ; le sandbox journalise « Niveau avant → apres ».
@warning_ignore("unused_signal")
signal heros_niveau_change(avant: int, apres: int)

# Émis quand l'Euren possédé change (crédit à la SORTIE d'expédition
# uniquement — extraction ou complétion ; défaite = rien).
@warning_ignore("unused_signal")
signal euren_change(total: float)

# ── Alarme & assauts de Lieutenants (Rework Combat — chantier 11) ──

# Émis à CHAQUE victoire d'assaut sur le Lieutenant d'un Lieu.
# premier = true si c'est le premier kill (le slot d'Alarme se remplit —
# déclencheur de sauvegarde) ; false = re-kill (récompenses normales, pas
# de re-slot).
@warning_ignore("unused_signal")
signal lieutenant_vaincu(lieu_id: String, premier: bool)

# Émis UNE fois quand le 6e slot d'Alarme se remplit : l'alarme sonne —
# déclencheur de fin de jeu (la voie de la Pyramide s'ouvre ; la 7e
# expédition elle-même est hors scope, seul le déclencheur existe).
@warning_ignore("unused_signal")
signal alarme_sonnee()

# ── Équipement ──────────────────────────────────────────────

# Émis quand un item est équipé ou déséquipé.
@warning_ignore("unused_signal")
signal equipment_changed()
# Émis quand l'équipement d'un biome est obtenu (biome → Peu Commun).
@warning_ignore("unused_signal")
signal equipment_unlocked(equipment_id: String)
# Émis après la forge d'un équipement (passage au palier suivant).
@warning_ignore("unused_signal")
signal equipement_evolue(equipment_id: String, nouveau_palier: int)
# Émis quand un nœud d'arbre de Forge est acheté, ou les points de Forge changent
# (Chantier 5) → recalcul des bonus de Forge + rafraîchissement de l'UI.
@warning_ignore("unused_signal")
signal forge_tree_changed(equipment_id: String)

# ── Sauvegarde ──────────────────────────────────────────────

@warning_ignore("unused_signal")
signal save_completed()
@warning_ignore("unused_signal")
signal load_completed()
