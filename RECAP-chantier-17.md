# Chantier 17 — Lieux secondaires révélés par les voies du QG

## Contexte

Deux trous qui se comblent mutuellement : les voies 2-6 du QG étaient des
placeholders vides, et la carte portait 4 zones dupliquées `biome_montagne`
(IDs d'autoring provisoires). Les Lieux secondaires du design (Collines,
Ville Fantôme, Cimetière — topographie en arbre actée) n'avaient plus de
mécanisme de révélation depuis le gel de l'évolution des biomes (ch.12,
l'ancienne règle « révélé au Légendaire du parent » était morte avec).

## Arbitrages de design (proposés par Claude, à invalider si besoin)

1. **1 Sceau = 1 voie = 1 nouveau district explorable** : les voies 2-4
   révèlent respectivement Collines, Ville Fantôme, Cimetière
   (`data/progression/voies.tres`, appliqué par `ouvrir_voie_suivante` —
   flag `est_decouvert` persisté, reculé par le Game Over avec le compteur
   de voies, cohérent). Détruire un Lieutenant ouvre littéralement un
   quartier de la ville — la boucle Assaut → Sceau → carte s'auto-alimente.
   Les voies 5-6 restent des placeholders (session narration).
2. **Mapping carte par le DÉCOR existant** (aucun redessin) :
   zone au décor cimetière (47,10) → Cimetière ; l'usine abandonnée (6,45)
   → Ville Fantôme ; la casse (6,9) → Collines (« dunes de ferraille ») ;
   le bloc de bâtiments du centre (27,27) reste Montagne. Édition
   chirurgicale du xlsx (3 cellules d'ID : I13, I49, AZ15 — feuille Carte),
   sauvegarde de l'original conservée, instantané re-baké.
3. **Identité héritée de la branche parente** (arbre acté Forêt→Collines,
   Montagne→Ville Fantôme, Marécage→Cimetière) : `biome_secondaire_id`
   renseigné sur les parents, et la MÉCANIQUE FORTE héritée (Collines =
   ambush, Ville Fantôme = endurcissement, Cimetière = poison) — provisoire,
   des mécaniques propres pourront les remplacer.
4. **Ressources de butin propres** (boucle ch.14 immédiatement active) :
   Collines = dent de gobelin / défense de sanglier (jsons existants
   inutilisés) ; Ville Fantôme = herbe magique / ectoplasme (nouveau) ;
   Cimetière = os de corail / relique funéraire (nouveau). La rare = futur
   ingrédient de keystone quand la Forge couvrira ces slots.
5. **Slots d'équipement du mapping de référence** : Collines=Ceinture,
   Ville Fantôme=Bouclier, Cimetière=Talisman (cardinalité 6 biomes ↔ 6
   slots). Sans effet immédiat (équipements placeholders, hook de déblocage
   gelé) — la donnée est prête.
6. **Ennemis : pool par défaut** (comme les 3 Lieux du VS — `pools_par_lieu`
   vide est le statu quo assumé) ; les Lieutenants des 3 Lieux étaient déjà
   mappés (placeholders ch.11). Créatures propres = contenu futur.
7. **VoiesPanel annonce la destination** (« Accès : Collines ») AVANT
   l'ouverture — règle « le joueur voit ce qu'il débloque avant de
   valider » ; une fois ouverte : « District révélé sur la HoloMap ».

## Implémentation (fait)

- 3 `BiomeData` (.tres, est_decouvert=false) + 2 ressources json ;
  `VoiesConfigData` + `voies.tres` ; révélation dans
  `GameData.ouvrir_voie_suivante` (émet `entity_discovered`) ; VoiesPanel.
- xlsx : 3 cellules repointées (script python minimal zip+XML, original
  copié en scratchpad), `bake_holomap` relancé, TestHoloXlsx vert.
- Tests : `TestLieuxSecondaires.tscn` (50) — entités, zones du gabarit
  (6 ids uniques), ordre de révélation, destinations, butin + mécanique
  héritée, affichage des voies.

## Périmètre strict

- Pas de créatures/pièges/bénédictions propres aux nouveaux Lieux (pool
  défaut) ; pas d'équipements réels pour les 3 nouveaux slots ; pas de
  contenu voies 5-6. La 7ᵉ expédition (Pyramide, alarme 6/6) reste hors
  scope.
