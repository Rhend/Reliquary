# IdleEvolution — Guide projet pour Claude Code

Idle RPG de complétion sous **Godot 4.6** (GL Compatibility), GDScript, 1280×720.
Scène principale : `res://scenes/village/village.tscn`. Branche de travail : `dev`.

## Règles d'or (à respecter dans toute modification)

- **Data-driven** : tout contenu de jeu = un `.tres` dans `data/` (jamais hardcodé).
- **Équilibrage** : uniquement dans `scripts/autoloads/Balance.gd` (class_name, pas autoload).
- **Communication inter-systèmes** : uniquement via `EventBus` (aucun référencement direct).
- **Strings magiques interdits** : types d'entités → `Enums.EntityType.*`, effets de
  bénédiction → `Enums.BlessEffect.*` (effets supportés : HEAL, XP_BONUS, HASTE — la
  Hâte stocke un modificateur de vitesse en attente ; il sera traduit en buff VIT
  temporaire par l'intégration du moteur CTB).
- **Noms affichés** : TOUJOURS via `Translations.entity_name(entity)` (et le lore via
  `Translations.entity_lore`, les effets de passifs via `Translations.effect_desc`).
  Champs sources : `nom_affichage_fr`/`nom_affichage_en`, `lore_fr`/`lore_en`
  (passifs : `name` + `nom_affichage_en`). Ne JAMAIS lire `nom_affichage_fr` en dur dans l'UI.
- **Noms par palier** : `noms_par_palier_fr`/`_en` (Dictionary palier→nom) dans les
  `.tres` — palier absent → hérite du palier inférieur défini le plus proche ; dict
  vide → `nom_affichage_*`. Nom à un palier précis : `Translations.entity_name_at(entity, tier)`
  (utilisé par le rituel d'ascension pour révéler le nouveau nom au morph).
- **Couleurs de rareté** : `UIColors.tier_color(tier)`. Toutes les couleurs dans UIColors.
- **Textes UI** : via `Translations.T("clé")` (FR + EN) — pas de français en dur.
- **UI 100 % en code** : factories dans `UIHelpers` (class_name statique), widgets
  dans `scenes/village/widgets/`.
- **Pas de Luck** : la mécanique a été supprimée volontairement (2026-06). Ne pas réintroduire.

## Architecture

| Rôle | Fichier |
|---|---|
| Source de vérité runtime (charge .tres → dict `entities`) | `scripts/autoloads/GameData.gd` |
| Constantes d'équilibrage (XP, combat, drops, cadence) | `scripts/autoloads/Balance.gd` |
| Bus de signaux (pattern Observer) | `scripts/autoloads/EventBus.gd` |
| Boucle idle (timer, rencontres, CycleStats, drops) | `scripts/systems/AdventureSystem.gd` |
| Progression de Maîtrise (XP, plafonds, évolution manuelle) | `scripts/systems/MasterySystem.gd` |
| Effets de passifs (bonus plats + conditionnels) | `scripts/systems/PassiveSystem.gd` |
| Moteur combat TOUR PAR TOUR CTB (Rework ch.1 : file d'initiative `K/VIT`, DoT data-driven, N-vs-N, signaux `ctb_*`) | `systems/combat_ctb/ctb_moteur.gd` + `ctb_combattant.gd` |
| Carte d'expédition free-roam (Rework ch.2 : génération Delaunay connexe seedable, brouillard « absent », 3 étages, Extraire/Continuer, signaux `expe_*` — nœuds = stubs) | `systems/expedition/expe_run.gd` + `expe_carte.gd` (config : `data/expedition/`) |
| Hub hexagonal + panneaux JRPG (panneau `PANEL_FRACTION`, hub scalé `HUB_PANEL_SCALE`) | `scenes/village/Village.gd` |
| Contenu des panneaux (statiques, `build(host)`) | `scenes/village/panels/` |
| Sauvegarde (debounce 2 s, flush à la fermeture, écriture atomique) | `scripts/autoloads/SaveManager.gd` |
| Quartiers / routes / bâtiments + bonus de village (Chantier 4) | `scripts/systems/VillageBuildings.gd` |
| Forge : palier d'équipement (XP, sans ingrédient) + arbre de nœuds + bonus (Chantier 5) | `scripts/systems/ForgeSystem.gd` |

Autoloads (ordre dans project.godot) : UIColors, EventBus, AudioManager, Translations,
GameData, CycleData, SaveManager, GameSettings, MasterySystem,
AdventureSystem, PassiveSystem, VillageBuildings, ForgeSystem, MasteryRegistry, BiomeMechanics, TooltipOverlay.

⚠ REWORK COMBAT en cours (branche ReworkCombat) : l'ancien moteur temps réel
(CombatResolver / CombatPlayer / CombatScene) a été SUPPRIMÉ. Le moteur CTB
(`systems/combat_ctb/`, sandbox `scenes/combat_ctb/SandboxCtb.tscn`) n'est PAS
encore branché à l'expédition : les rencontres créature sont constatées mais
NON résolues (`AdventureSystem._combat_non_resolu`) — ni dégâts, ni XP de
combat, ni drops. `_resolve_victory` / `_resolve_unique_victory` sont conservés
pour l'intégration. Règle générale : un système remplacé est SUPPRIMÉ, pas
laissé en doublon.

Forge (Chantier 5) : l'équipement évolue par XP (MasterySystem, buffer DÉSACTIVÉ pour
l'équipement) — PLUS d'ingrédient pour le palier (`recettes_evolution` est mort). Le
passage de palier ouvre une strate de l'arbre + octroie des points (lot + conversion de
l'XP excédentaire). Les nœuds (`data/forge_trees/*.tres`, `ForgeTreeData`) s'achètent aux
points sous connexité + gate de strate ; seuls les keystones consomment l'ingrédient rare
du biome. Bonus % par stat via l'agrégateur additif ; effets de règle fournis au combat.
UI : `ForgePanel` (palier/points) + `ForgeTreeOverlay` (arbre spatial).

Audio : tout passe par `AudioManager` (autoload). Bruitage ponctuel =
`AudioManager.play_sfx("nom", volume_db)` ; sons nommés générés en procédural
dans `_build_library()` (provisoire, remplaçables par des fichiers). Bus
`Music`/`SFX` créés au runtime (pas de default_bus_layout.tres).

## Conventions spécifiques

- **Panels ↔ Village** : HeroPanel/AdventurePanel/ForgePanel reçoivent le nœud Village
  (`host`) et n'utilisent QUE son API publique : `rp_content`, `make_evolve_btn()`,
  `show_banner()`, `village_tier()`, `adv_selected_biome_id`,
  `start_selected_expedition()`, `panel_ui_state()`, `launch_evolution_ritual()`.
- **Rafraîchir un panneau ouvert** = `_refresh_active_panel()` — JAMAIS `_open_panel()`
  (comportement toggle : il le fermerait).
- **Sections repliables** : `UIHelpers.collapsible_section(titre, couleur, ouvert,
  host.panel_ui_state())` pour que l'état survive aux reconstructions.
- Fins de combat CTB : `EventBus.ctb_victoire` / `ctb_defaite` portent le recap
  `{victoire, nb_activations, pv_restants, ennemis_vaincus}` (loot/XP calculés en
  aval par l'expédition, hors moteur) ; le résumé de cycle porte `hero_id`.
- Règles CTB actées (06/07/2026) : mort au tick DÉBUT = activation consommée ;
  DoT figé à la pose (ATK courante = futur paramètre de .tres si besoin) ;
  stacks_max dépassé = remplacement du plus ancien ; AUCUN tick post-victoire ;
  statuts purgés en fin de combat ; PV persistants entre les nœuds d'expédition.
- Évolution : TOUJOURS manuelle (action joueur via `MasterySystem.evolve_entity`).
- L'XP s'accumule au-delà des plafonds (jamais perdue) ; plafond créature dépend du
  tier du biome + de la zone (`Balance.CREATURE_CAP_*`).
- Paliers : Commun(0) → Peu Commun(1) → Rare(2) → Épique(3) → Légendaire(4) → Unique(5).
  Créatures max T4, équipements max T2 (`Balance.ENTITY_MAX_TIER`).
- Zones : Surface(0) / Profondeur(1, biome Rare+) / Abysse(2, biome Légendaire+) —
  zone FIXE par cycle, déterminée au lancement.

## Tests et validation

```bash
# Les 3 suites (chacune quitte avec un code ≠ 0 en cas d'échec) :
godot --headless --path . res://tests/TestScriptsLoad.tscn      # compile tous les scripts
godot --headless --path . res://tests/TestCombatCtb.tscn        # moteur CTB tour par tour (33)
godot --headless --path . res://tests/TestExpeCarte.tscn        # carte d'expédition (39)
godot --headless --path . res://tests/TestExpeditionFlow.tscn   # boucle expédition (28)

# Boot rapide sans erreur :
godot --headless --path . --quit-after 30
```

- CI GitHub Actions (`.github/workflows/tests.yml`) lance ces 3 suites à chaque push.
- Après l'ajout d'un `class_name` — y compris quand il arrive via `git pull` sur une
  autre machine — lancer `godot --headless --path . --import` (ou Projet → Recharger
  le projet dans l'éditeur). Le cache `.godot/global_script_class_cache.cfg` est local
  et non versionné ; sans ça : « Parse Error: Could not find type … ».
- TOUJOURS lancer TestScriptsLoad après un refactor : il détecte les identifiants
  disparus (constantes, signaux) dans tous les scripts, autoloads chargés.
- `GameData._validate_entities()` warne au boot si un `.tres` est incomplet.
- **Simuler des clics dans un test headless** : la fenêtre racine fait **64×64 px**
  (la taille du projet est ignorée) → tout clic au-delà tombe hors fenêtre et le
  picking GUI échoue silencieusement. Faire d'abord
  `get_tree().root.size = Vector2i(1280, 720)`, puis `root.push_input(ev)`
  (motion + press + release) fonctionne.

## Sauvegarde

- `user://IdleEvolutionSave.json` (`%APPDATA%/Godot/app_userdata/IdleEvolution/`),
  `SAVE_VER = 13`, versions acceptées 11+. À chaque écriture l'ancienne sauvegarde
  devient `.bak` (rechargé automatiquement si la principale est illisible) ; un
  fichier illisible est copié en `.corrupt` au lieu d'être écrasé en silence.
- `save()` REFUSE d'écrire si `load_save()` n'a jamais tourné alors qu'une
  sauvegarde existe — un outil/test qui émet des signaux de progression sans
  passer par le Village ne peut plus détruire la progression du joueur.
- Étendre : nouvelle donnée joueur → `GameData.player` (auto) ; nouveau flag d'entité
  → `SaveManager.PERSISTED_FLAGS` ; nouvel état système → `_save_systems()/_load_systems()`.
- Ne JAMAIS écrire la sauvegarde dans un test : déconnecter les listeners de
  SaveManager (voir le pattern dans l'historique des tests d'intégration).

## ⚠ Flags de dev à désactiver avant release

- `Balance.ECLOSION_CLIC_VALUE = 25` → remettre à 1 (accélère l'éclosion pour les tests).
- `Village.DEBUG_TIER_BUTTONS = true` → boutons Tier ± en bas à gauche (modifient
  réellement GameData.village).
- `HoloMap3D.FLICKER_NEON = false` → grésillement des néons désactivé volontairement
  (idée validée, application à retravailler ; le shader `holo_neon` garde le code).
- `holo_decor.PROP_NEON` (true par défaut) → false = props artistes de la holomap
  dessinés BRUTS (lignes plates sans shader néon) pour calibrer la DA. Le néon des
  props = `_mat_prop` (émission moitié des enseignes, sans cœur blanc).

## Biomes (VS initiaux)

| Biome | Mécanique forte (Rare+) | Slot équipement | Unique |
|---|---|---|---|
| Forêt Sombre (`biome_foret`) | ambush (1er ennemi frappe avant) | Anneau | Oscar |
| Marécage Putride (`biome_marecage`) | poison (coups héros empoisonnent) | Armure | Cavalier Sans Tête |
| Montagne (`biome_montagne`) | endurcissement (dégâts héros −20 %) | Arme | Gorlab |

Progression d'un biome : T0 découverte → **T1 Peu Commun : son équipement est
obtenu (à T0) et auto-équipé** (`Balance.EQUIPMENT_UNLOCK_BIOME_TIER`,
`GameData.unlock_biome_equipment`) → T2 Rare : mécanique forte → T4 Légendaire :
biome secondaire révélé. Le joueur démarre SANS équipement.

Biomes secondaires (révélés au Légendaire du parent) : Collines, Ville Fantôme, Cimetière.
Ambiances visuelles : presets dans `BiomeBackground.PRESETS` (+ `accent_for_biome()`
utilisé par le séparateur VS).

## Carte holographique (HoloMap3D)

Carte 3D data-driven lue d'un gabarit Excel (`Carte Holo/carte_holomap.xlsx`) par
`scenes/holomap3d/HoloXlsxMap.gd` (ZIPReader + XMLParser, zéro dépendance). `HoloMap3D.gd`
orchestre ; rendu découpé en modules `build/holo_*.gd` — pattern `static func famille(h)`
avec `h` = le nœud HoloMap3D passé **NON typé** (sinon cycle preload↔class_name) ; **toute
locale issue de `h.*` doit être typée explicitement**. Modules : `holo_geo` (helpers purs),
`holo_env` (ambiance), `holo_ville` (voirie/bâti/ponts/autoroutes), `holo_decor` (décor +
prison), `holo_sureleve` (ouvrages surélevés + croix rouge), `holo_props` (props .glb de
l'artiste → arêtes dures néon, sauf objet `fond` = plaque sombre opaque (`_mat_prop_fond`) ;
échelle dynamique proportionnelle au toit (`PROP_EMPRISE_TOIT`) ; assets dans
`assets/props/holomap/`, specs et nommage dans `Carte Holo/SPECS_ASSETS.md` ; secours
procédural conservé si le .glb manque ; vérifier un .glb reçu : `tools/inspect_glb.gd`).

**Apparence = couleur de FOND** (nearest-match d'un centroïde de `_FAMILLES`). **Hauteur /
forme / altitude / ID = texte de la cellule.** Bordures medium/thick = séparateurs neutres
(regroupement en blocs 4-connexes). Un ID alphabétique dans une case → la zone devient un
LIEU explorable (tier/nom/lore/découverte viennent de l'entité visée par l'ID).

Feuille **Carte** : bâtiment `3A4253`, route `D6248F`, eau `17C3C3`, parc `5E7349`,
sport `D2B48C`, cimetière `6B7A8F`, usine `8B5E3C`, casse `B0560F`, supermarché `E8A23D`,
colline `C8A86A`, parking `B5B5B8`, **prison `5A5E66`** (enceinte + miradors + cour +
champ de force), commissariat `2B5A9E`, **grand parc urbain `3FA06B`** (émeraude vif,
≠ parc-arbres olive : pelouse animée + allées + bassin + kiosques), **université
`9E3B5A`** (campus : corps + ailes + amphi-dôme + esplanade + panneaux), **musée
`6B4A8E`** (colonnade + fronton + verrière + hologrammes d'exposition).

Feuille **Surélevé** (ouvrages en hauteur, altitude = chiffre tapé dans la cellule) :
pont `9FB2C4`, autoroute `D6248F`, **passerelle `7FD8A0`**, **héliport `F2D43D`**,
**spots `BFF0FF`**, **téléphérique `E8843D`**, **antennes `B89CE8`**, **enseignes `F58FD4`**.

**Règles verticalité :**
- Altitude **TOUJOURS saisie par l'auteur**, jamais déduite.
- **Classification PAR FEUILLE** (`_SURELEVE_ONLY` / `_CARTE_ONLY` passés à `_classer`) :
  une couleur surélevé-only ne peut pas être classée sur la Carte (sinon une case bâtie
  peinte dans une teinte proche deviendrait un trou qui scinde le bloc). Toujours raisonner
  par feuille en ajoutant une couleur.
- **Validation croisée Surélevé ↔ Carte** (`HoloXlsxMap._valider_verticalite`, index bâti
  `bati_sous()`) : héliport (carré ≥ 4×4, bâti dessous, toit assez large, altitude = sommet),
  passerelle (altitude cohérente + porte percée par bâtiment relié), spots / antennes (bâti
  dessous). Les spots **forcent le toit plat** du bâti (`toit_plat`, honoré dans `holo_ville.batiments`).
- **CROIX ROUGE `E02020`** (réservée au feedback, l'auteur ne la peint jamais) : posée
  à chaque contrainte violée (endroit + altitude fautifs), plutôt qu'une correction
  silencieuse. C'est la convention universelle de signalement.
- **Tailles minimales DURES (Carte)** : chaque apparence spécifique a une emprise
  minimale (`HoloXlsxMap._TAILLES_MIN`, consignée dans la feuille « Contraintes
  tailles » du gabarit — ex. usine 2×4, prison 3×3, stade/grand parc/université/musée
  4×4). En dessous — ou prison NON rectangulaire, stade plus allongé que 3:2 — le bloc
  n'est PAS rendu : `_valider_tailles_min` le retire de sa famille et pose une croix
  rouge à la place (jamais de version simplifiée). Les autres conseils de forme
  (usine allongée, université/musée plus larges que profonds) restent souples.

⚠ Le `.xlsx` peut être re-sauvegardé par Excel/OneDrive en arrière-plan (octets qui
changent en cours de session) → `git checkout --` le fichier avant de comparer des
compteurs de classification. Test du lecteur + validation : `tests/TestHoloXlsx.tscn`.

**Build sans .xlsx (instantané baké)** : le gabarit Excel est un outil d'AUTORING —
il n'est JAMAIS exporté (`Carte Holo/*` exclu dans `export_presets.cfg` ; le joueur
ne doit ni le voir ni pouvoir le modifier). Le build charge à la place
`data/holomap/carte_holomap.snapshot` (état parsé figé, versionné, embarqué via
`include_filter` `*.snapshot`). `HoloXlsxMap.charger()` : xlsx présent (dev) → parse
live ; absent (build) → `charger_snapshot()`. **Après CHAQUE édition de la carte,
re-baker** : `godot --headless --path . --script res://tools/bake_holomap.gd` —
TestHoloXlsx (CI) échoue si l'instantané n'est plus à jour.
