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
- **UI d'expédition** (lancement, carte, combat, recap, Game Over) : styles UNIQUEMENT
  via les tokens `UIColors.CYBER_*` + factories `ExpeStyle` (peau cyberpunk intérimaire,
  chantier 10) — zéro littéral de style ; rouge réservé à l'Artefact/danger.
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
| Moteur combat TOUR PAR TOUR CTB (Rework ch.1 : file d'initiative `K/VIT`, DoT data-driven, N-vs-N, signaux `ctb_*` ; ch.3 : malus d'embuscade, purge des statuts en fin de combat ; ch.5 : action DEFENDRE (`data/combat_ctb/config_ctb.tres`), signal structuré `evenement`, prédiction de file `prevoir_ordre(n)`) | `systems/combat_ctb/ctb_moteur.gd` + `ctb_combattant.gd` |
| UI de combat CTB JOUABLE (Rework ch.5 : écran scindé placeholder, file d'initiative N=6, Attaquer/Défendre + choix de cible, dégâts flottants, transitions et issue de bataille — pull-based sur un moteur démarré, `facteur_delais = 0` pour les tests ; ch.6 : issue enrichie XP/Euren via `recompenses_fournisseur`) | `scenes/combat_ctb/CombatCtbUi.gd` + `CarteCombattantCtb.gd` |
| Économie de récompense (Rework ch.6) : NIVEAU du héros (XP totale cumulée dans `GameData.player.heros_xp`, niveau DÉRIVÉ, bonus plats injectés par le pont héros AVANT les %) + Euren (`player.euren`, crédité à la SORTIE d'expédition seulement — défaite = rien) + MODULES (ch.12 : `player.modules`, +1 par PREMIÈRE arrivée sur chaque Fin d'étage — max 3/raid, 0 en assaut — crédités à la sortie, mêmes rails ; Euren et Modules se DÉPENSENT via `depenser_euren`/`depenser_modules`). class_name statique, pas autoload ; courbe/gains/multiplicateurs dans `data/progression/*.tres` (provisoires, à calibrer) | `scripts/autoloads/ProgressionHeros.gd` |
| Pont bestiaire existant → combattant CTB (stats telles quelles via `GameData.get_effective_stats`) + pont HÉROS réel (ch.4 : source unique d'agrégation plats + % additifs, reconstruite de l'ancien combat_player — mappings et « laissé derrière » documentés en tête de fichier) | `systems/combat_ctb/ctb_pont.gd` |
| Carte d'expédition free-roam (Rework ch.2 : génération Delaunay connexe seedable, brouillard « absent », 3 étages, Extraire/Continuer, signaux `expe_*` ; ch.3 : nœuds Combat/Attaque surprise = VRAIS combats CTB — run suspendue, PV persistants, défaite = fin immédiate ; ch.7 : TOUS les nœuds réels — Bénédiction = affixe positif de run, Piège = affixe négatif, Coffre = consommables de run (action OBJET en combat, inventaire dans ExpeRun via `consommer()`), purge systématique en fin de run, pools dans `config_noeuds.tres`) | `systems/expedition/expe_run.gd` + `expe_carte.gd` (config + pools : `data/expedition/`) |
| Flux de jeu RÉEL de l'expédition (Rework ch.8) : « Partir en expédition » ouvre la HoloMap → clic Lieu → `ExpeLancementPanel` (destination + palier) → `Village.lancer_expedition()` → `ExpeditionScreen` (écran de jeu, persistance ACTIVE, combats à la main) → recap → retour au QG. Destination → pool : `data/expedition/destinations.tres` (`ExpeDestinationsData`, provisoire : tout sur `pool_defaut`). Vue de carte partagée écran de jeu ↔ sandbox : `ExpeCarteView` — ch.10 : NAVIGATION PAR CHEMIN (clic sur tout nœud découvert atteignable via des nœuds RÉSOLUS — `ExpeRun.chemin_vers`/`atteignables`, trajet séquencé `DELAI_PAS`, nœud inaccessible atténué + non cliquable) | `scenes/expedition/ExpeditionScreen.gd` + `ExpeLancementPanel.gd` + `ExpeCarteView.gd` |
| Peau cyberpunk INTÉRIMAIRE du pipeline expédition (Rework ch.10 — la DA finale appartient à Christophe) : TOKENS de couleur `UIColors.CYBER_*` + factories `ExpeStyle` (police mono système, panneaux à bordure néon, boutons, chips, scanlines sobres `cyber_scanlines.gdshader`). AUCUN littéral de style dans l'UI d'expédition — remplacer la peau = changer ces deux points. Rouge = Artefact/danger UNIQUEMENT (`CYBER_DANGER`) ; palette de rareté inchangée (source des couleurs de palier) | `scripts/autoloads/ExpeStyle.gd` + tokens dans `UIColors.gd` |
| Hub hexagonal + panneaux JRPG (panneau `PANEL_FRACTION`, hub scalé `HUB_PANEL_SCALE`) | `scenes/village/Village.gd` |
| Contenu des panneaux (statiques, `build(host)`) | `scenes/village/panels/` |
| Alarme & assauts de Lieutenants (Rework ch.11) : 6 slots (un par Lieutenant détruit, PREMIER kill seulement — état dans `GameData.player.lieutenants_vaincus`), effets data-driven par niveau (`data/expedition/alarme.tres` : +5 % PV/ATK ennemis par slot + affixes permanents aux paliers 4/5/6), appliqués à la CRÉATION de chaque ennemi (ExpeRun, même endroit que le pont bestiaire — PV re-remplis au pv_max final) ; 6/6 → `EventBus.alarme_sonnee` (déclencheur Pyramide, message différé au retour QG — la 7ᵉ expédition est hors scope) ; jauge diégétique 6 slots sur la HoloMap (`HoloHud._jauge_alarme`, rouge = son métier). ASSAUT : débloqué par Lieu quand ses 3 strates sont complétées (`GameData.expe_completions`, marquées par ExpeRun à la COMPLÉTION seule — extraction/défaite non), option ABSENTE avant (jamais grisée, `ExpeLancementPanel`), expédition d'1 étage, Fin d'étage → nœud BOSS (Lieutenant du Lieu + 2 sbires du pool, `destinations.tres.lieutenants_par_lieu` — 6 placeholders), AUCUNE extraction, palier dédié `palier_assaut.tres` (hors strates), recap distinct, re-kill = récompenses normales sans re-slot | `scripts/autoloads/Alarme.gd` + `scripts/resources/AlarmeConfigData.gd` (config : `data/expedition/alarme.tres`, lieutenants : `data/expedition/lieutenants/`) |
| Sauvegarde (debounce 2 s, flush à la fermeture, écriture atomique) + sanction de mort (Rework ch.9) : flush de RÉFÉRENCE au lancement d'expédition puis écritures SUSPENDUES pendant la run (`suspendre_ecritures`/`reprendre_ecritures` — fermer la fenêtre en run ne sauve rien), `recharger()` (Game Over = ré-application de la dernière sauvegarde), compteur de reconstruction **R-XXX MÉTA-PERSISTANT** (`user://IdleEvolutionMeta.json`, séparé de la partie, init R-001, plafond d'affichage R-999, `nom_reconstruction()` = source UNIQUE du formatage, appliqué à l'entité hero → tous les affichages) | `scripts/autoloads/SaveManager.gd` |
| Quartiers / bâtiments + bonus de village (Chantier 4 ; ch.12 : coûts refondus en EUREN + MODULES — courbe unique data-driven `data/progression/couts_batiments.tres`, plus JAMAIS de ressource de biome ; ROUTES SUPPRIMÉES, quartiers de base ouverts d'emblée) | `scripts/systems/VillageBuildings.gd` |
| Économie du QG (Rework ch.12) : objets de Lieutenants (« Sceau », accordé au PREMIER kill dans `GameData.marquer_lieutenant_vaincu` — `player.objets_lieutenants`, annulé par Game Over comme le slot d'Alarme) + 6 VOIES scellées (une par Lieutenant, ouverture MANUELLE avec l'objet — `GameData.ouvrir_voie`, persistée `player.voies_ouvertes`, quartier placeholder vide) ; compteur « quartiers restaurés » source UNIQUE : `GameData.nb_voies_ouvertes()` (la DA s'y branchera). UI : hex VOIES du hub → `VoiesPanel` (Sceaux possédés + 6 voies + bouton Restaurer) | `scripts/autoloads/GameData.gd` + `scenes/village/panels/VoiesPanel.gd` |
| Forge : palier d'équipement (XP, sans ingrédient) + arbre de nœuds + bonus (Chantier 5) | `scripts/systems/ForgeSystem.gd` |

Autoloads (ordre dans project.godot) : UIColors, EventBus, AudioManager, Translations,
GameData, CycleData, SaveManager, GameSettings, MasterySystem,
AdventureSystem, PassiveSystem, VillageBuildings, ForgeSystem, MasteryRegistry, BiomeMechanics, TooltipOverlay.

⚠ REWORK COMBAT en cours (branche ReworkCombat) : l'ancien moteur temps réel
(CombatResolver / CombatPlayer / CombatScene) a été SUPPRIMÉ. Le moteur CTB
(`systems/combat_ctb/`, sandbox `scenes/combat_ctb/SandboxCtb.tscn`) est branché
aux nœuds d'expédition free-roam depuis le chantier 3 (sandbox
`scenes/expedition/SandboxExpe.tscn` — ExpeRun reçoit avatar + pool + config
combat à la construction). Depuis le CHANTIER 8, l'expédition est BRANCHÉE AU
JEU RÉEL : « Partir en expédition » (panneau ou hub) ouvre la HoloMap, un clic
sur un Lieu ouvre le panneau de lancement (palier de profondeur — toujours sans
effet mécanique), et la run se joue dans `ExpeditionScreen` avec persistance
ACTIVE (XP/Euren déclenchent la sauvegarde — écritures SUSPENDUES pendant la
run depuis le ch.9, flushées à la sortie). Retour au QG à toute sortie
normale ; DÉFAITE (ch.9) = GAME OVER : message « R-XXX est détruit... »
(`EcranMessage`), incrément du compteur méta, rechargement de la dernière
sauvegarde (= l'état du lancement — l'XP créditée pendant la run est perdue),
message « Reconstruction de R-XXX+1 complète. », retour au QG. Fermer le jeu
en pleine run n'est PAS mourir : rien n'est écrit, pas d'incrément — à la
réouverture, l'état est celui du départ, run non entamée.
L'ancienne boucle idle (`AdventureSystem`) n'a PLUS AUCUN point d'entrée UI
(elle est morte avec son moteur : rencontres non résolues) — le système reste
chargé pour ses utilitaires (drops de biome, zones, résumé de cycle) et
`_resolve_victory` / `_resolve_unique_victory` sont conservés pour
réintégration future. L'XP de niveau et l'Euren sont RÉELS depuis le
chantier 6 (XP créditée à chaque victoire, Euren à la sortie), TOUS les
nœuds sont réels depuis le chantier 7 (affixes de run, consommables — drops
d'équipement/matériaux non designés, à venir). Le camp joueur en expédition
= VRAI héros (ch.4 : `CtbPont.combattant_depuis_heros()`, stats effectives
équipement compris, transitoire construit au lancement) ; le sandbox a une
checkbox Héros réel / avatar factice (`avatar.tres`, conservé pour les
tests) et charge la sauvegarde s'il est lancé seul (`SaveManager.est_chargee()`),
en restant DÉBRANCHÉ des déclencheurs de sauvegarde (outil dev, jamais
d'écriture). Laissé derrière par le pont héros (documenté dans ctb_pont.gd) :
bonus de familiarité par ennemi, modificateurs de cycle, effets de règle
Forge, poison passif on-hit. Règle générale : un système remplacé est
SUPPRIMÉ, pas laissé en doublon. Chantier 5 : les combats d'expédition
(jeu réel comme sandbox) sont JOUÉS À LA MAIN par défaut (`CombatCtbUi` ;
sandbox : checkbox « Combat auto » ; ExpeditionScreen : hook de test
`combat_auto`, jamais exposé en UI — le ScreenshotTool et les tests pilotent
ExpeRun directement, toujours en auto).
CHANTIER 12 (rework économique du QG, acté 06/07/2026) : modèle
domaine/housing — Euren + MODULES remplacent les ressources silotées pour
les COÛTS DE BÂTIMENTS (périmètre strict : Forge/équipement et drops de
ressources non touchés, les anciennes ressources existent toujours mais ne
sont plus jamais demandées par un bâtiment). Le QG n'a PLUS de palier de
rareté propre côté accès : Héros, Expéditions et Forge/Atelier sont ouverts
d'emblée (hex Forge tier_min 0, verrou du ForgePanel supprimé, gate de drop
d'AdventureSystem supprimé), les ROUTES sont supprimées (chemins des
quartiers de base présents d'emblée). Les 6 VOIES scellées s'ouvrent avec
l'objet du Lieutenant (premier kill) — action manuelle, quartiers
placeholder vides (contenus = session narration). « Évoluer biomes » est
SUPPRIMÉ (les Lieux n'évoluent plus — décision actée, avertissement
consigné : l'obtention d'équipement liée au palier de biome est de fait
gelée en attendant son rework) ; le panneau Expéditions est REBRANCHÉ (hex
EXPÉDITIONS → panneau, consultation + Évoluer créatures ; hex CARTE →
HoloMap directe ; le départ en expédition reste sur la HoloMap).

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
  statuts purgés en fin de combat ; PV persistants entre les nœuds d'expédition ;
  attaque surprise (« ? » d'expédition) = combat CTB avec malus d'initiative
  ×1.5 (première horloge du camp joueur) ; crit_chance clampée [0;1] AU JET
  seulement (la donnée peut déborder) ; DEFENDRE (ch.5, valeur provisoire
  06/07) = dégâts d'ATTAQUE subis −50 % (`config_ctb.tres`) jusqu'à la
  PROCHAINE activation du défenseur (garde baissée à l'ouverture de son
  activation), DoT jamais réduits, ordre contractuel ATK → mitigation DEF →
  crit → Défendre → plancher MIN_DAMAGE → arrondi, IA sans Défendre.
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
godot --headless --path . res://tests/TestCombatCtb.tscn        # moteur CTB tour par tour (63)
godot --headless --path . res://tests/TestCombatUi.tscn         # écran de combat CTB jouable (21)
godot --headless --path . res://tests/TestRecompenses.tscn      # économie de récompense XP + Euren (48)
godot --headless --path . res://tests/TestExpeNoeuds.tscn       # nœuds réels : affixes + consommables (24)
godot --headless --path . res://tests/TestExpeCarte.tscn        # carte d'expédition + navigation par chemin (53)
godot --headless --path . res://tests/TestExpeCombat.tscn       # combat CTB ↔ nœuds d'expédition + ponts (45)
godot --headless --path . res://tests/TestExpeditionFlow.tscn   # boucle expédition (28)
godot --headless --path . res://tests/TestFluxExpedition.tscn   # flux de jeu réel QG→HoloMap→expédition→crédits persistés + Game Over (65)
godot --headless --path . res://tests/TestGameOver.tscn         # sanction de mort : compteur R-XXX, rechargement, suspension (26)
godot --headless --path . res://tests/TestAlarme.tscn           # Alarme + assauts de Lieutenants : strates, boss, slots, deltas (73)
godot --headless --path . res://tests/TestEconomieQG.tscn       # économie du QG : Modules, Sceaux, voies, panneaux (53)
godot --headless --path . res://tests/TestVillageBuildings.tscn # bâtiments : coûts Euren+Modules, bonus (55)

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
- MÉTA-persistance (chantier 9) : `user://IdleEvolutionMeta.json` — compteur de
  reconstruction R-XXX, SÉPARÉ de la partie (le Game Over recharge la sauvegarde,
  le compteur ne recule jamais). Écrit à chaque incrément (atomique, .bak propre).
- Ne JAMAIS écrire la sauvegarde dans un test : déconnecter les listeners de
  SaveManager (voir le pattern dans l'historique des tests d'intégration).
  EXCEPTIONS : `TestFluxExpedition` (chantier 8), `TestGameOver` (chantier 9)
  et `TestAlarme` (chantier 11), dont l'objet est le round-trip réel — ils
  METTENT DE CÔTÉ les fichiers réels au démarrage (renommés `.avant_test`,
  fichier méta compris) et les RESTAURENT avant de quitter.
- Nom du héros = compteur de reconstruction R-XXX (chantier 9) : JAMAIS de
  formatage `R-%03d` ailleurs que `SaveManager.nom_reconstruction()` — le nom
  est appliqué à l'entité hero (nom_affichage_*), tout le reste en découle.

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
⚠ Chantier 12 : « Évoluer biomes » est SUPPRIMÉ (les Lieux n'évoluent plus,
décision actée) — cette échelle de jalons est DE FAIT gelée (plus aucun moyen
de montée en jeu ; l'obtention d'équipement/mécaniques/zones attendra le
rework « au fil de l'eau » de l'acquisition). La mécanique `entity_evolved`
et les hooks restent en place.

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
