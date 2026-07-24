# Chantier 15 — Mécaniques fortes de biome rebranchées au combat CTB

## Contexte

Les trois mécaniques fortes (`mecanique_forte_id` des BiomeData : `ambush`,
`poison`, `endurcissement`) sont orphelines depuis la mort de la boucle idle
(`BiomeMechanics` n'est plus consulté par aucun combat). Leur ancien gate —
biome au palier Rare — est GELÉ depuis le chantier 12 (les Lieux n'évoluent
plus). Parallèlement, le palier de profondeur choisi au lancement est
« toujours sans effet mécanique ».

## Arbitrages de design (proposés par Claude, à invalider si besoin)

1. **Le palier de profondeur devient le gate des mécaniques fortes** :
   - **Périphérie** : aucune mécanique (palier d'apprentissage) ;
   - **Enceinte et Noyau** : la mécanique forte du Lieu est ACTIVE dans tous
     les combats de la run (le Noyau pourra la renforcer plus tard — les
     valeurs sont par palier dans le .tres, prêtes).
   Avec le butin croissant du chantier 14, chaque palier a désormais un
   contrat lisible : plus profond = plus risqué (mécanique) + plus rentable.
2. **Le moteur CTB reste agnostique** : il gagne deux hooks GÉNÉRIQUES
   data-driven, et les mécaniques ne sont que des réglages :
   - `modif_degats_camp` — multiplicateur des dégâts d'attaque par camp
     attaquant (endurcissement = ×0.8 sur le camp joueur), appliqué entre le
     crit et Défendre (ordre contractuel documenté) ;
   - `statut_on_hit_camp` — chance de poser un statut sur la cible à chaque
     attaque réussie d'un camp (poison = chance de poser `statut_poison`
     existant sur le héros à chaque coup ennemi), jet via le RNG du moteur
     (déterministe en test).
   - `ambush` réutilise le malus d'initiative EXISTANT (`malus_horloge_
     initiale_joueur`) : en Forêt Enceinte+, tous les combats du Lieu
     l'appliquent (les « ? » restent inchangés).
3. **Réglages dans `data/expedition/mecaniques_biomes.tres`**
   (`MecaniquesBiomesData`) : par mécanique et par palier — chance de
   poison, multiplicateur d'endurcissement, malus d'embuscade. Zéro valeur
   en dur ; `Balance.MONTAGNE_ENDURCISSEMENT_REDUCTION` (valeur de design
   conservée) sert de valeur initiale.
4. **Lisibilité** : l'écran de combat annonce la mécanique active à
   l'ouverture (même voile que l'annonce d'embuscade) ; le panneau de
   lancement l'affiche sur les paliers concernés (le joueur choisit en
   connaissance).
5. `BiomeMechanics` (autoload de l'ancienne boucle) n'est PAS réutilisé :
   règle projet « un système remplacé est supprimé » — il sera retiré quand
   AdventureSystem mourra pour de bon ; le nouveau chemin ne passe pas par lui.

## Implémentation (fait)

- Moteur : hooks `modif_degats_camp` (appliqué APRÈS crit / AVANT Défendre —
  contractuel) et `statut_on_hit_camp` (jet au rng du moteur SEULEMENT si une
  règle existe : les suites seedées sans règle sont bit-à-bit identiques).
- `MecaniquesBiomesData` + `data/expedition/mecaniques_biomes.tres` ;
  ExpeRun : `mecanique_active()` (gate par palier) appliquée à chaque
  `_lancer_combat`, payload `mecanique` dans combat_demarre.
- UI : annonce à l'intro de combat (`ctb.mecanique_lieu` + clés `meca.*`),
  ligne au panneau de lancement (`expe.lancement_mecanique`, absente si le
  biome n'a pas de mécanique).
- Tests : `TestMecaniquesBiomes.tscn` (21) — hooks exacts (10→8, ordre avec
  garde), poison on-hit, gates par palier et par Lieu, embuscade Forêt
  généralisée aux combats normaux (Périphérie intacte).

## Périmètre strict

- Pas de nouvelle mécanique inventée : les trois actées seulement.
- Pas de refonte du choix de palier (UI existante, une ligne ajoutée).
- L'assaut (hors strates, palier dédié) applique la mécanique du Lieu au
  niveau Noyau — le boss se joue avec l'identité du Lieu au maximum.
