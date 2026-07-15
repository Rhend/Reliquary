# RECAP — Chantier 5 : UI de combat CTB (jouable)

Branche : `ReworkCombat`. Le combat CTB devient **jouable** : écran scindé placeholder (camp joueur / camp adverse, Lieu cosmétique en fond), file d'initiative visible (N=6), actions **Attaquer / Défendre** au tour du joueur (choix de cible), activations ennemies séquencées, dégâts flottants, annonce d'embuscade, transitions de début/fin de bataille avec issue affichée. Défendre est implémenté **côté moteur** (valeur en `.tres`). DA finale hors scope — tout en placeholder propre.

## 0. Inventaire préalable — ce qui a survécu de l'ancienne UI de combat

Le commit `8d8f920` a supprimé **tout** `scripts/combat/` (CombatScene 1 208 lignes, CombatBar, CombatFighter, CombatVS, CombatStinger, CombatLog, CombatStats, CombatLootBanner, CombatZoneMechanic) et `scenes/combat/CombatScene.tscn`.

**Réutilisable tel quel (et réutilisé)** :
- `BiomeBackground` + `biome_background.gdshader` — fond animé avec **découpe diagonale intégrée** (`set_split`, conçue pour le séparateur VS de l'ancien écran) et presets `city`/`forest`/`marsh`/`mountain` → c'est le fond placeholder du Lieu, scindé Ville (joueur) / biome (adverse).
- `UIHelpers.float_text` — le mécanisme historique des dégâts flottants de CombatRing, explicitement mutualisé à sa création → flottants de dégâts / crits / ticks de DoT.
- `UIColors` — palette de combat complète survivante : `HP_*`, `DMG_BY_*`/`DMG_HEAVY_*`, `MECH_AMBUSH`, `POISON`, `SHIELD`, `LOG_VICTORY`/`LOG_DEFEAT`, `PANEL_BG_DARK`.
- `AudioManager` — sons placeholder nommés (`attack`, `ui_select`, `trap_appear`, `summary_victory`/`summary_defeat`).

**Adaptable : rien.** Tout le reste de l'ancienne UI était couplé aux signaux du moteur temps réel supprimé (jauges ATB honnêtes, steps de CombatPlayer, événements de cycle) — le « ressusciter » aurait signifié restaurer du code mort attaché à un moteur disparu.

**À reconstruire (reconstruit dans ce chantier)** : l'écran lui-même (cartes de combattants, barre d'actions, séparateur diagonal placeholder, bandeau d'embuscade, transitions) — plus du **neuf sans équivalent ancien** : la file d'initiative (l'ATB n'en avait pas), les boutons d'action et le choix de cible (l'ancien combat était entièrement automatique).

**Assets de fond de Lieu** : aucun asset dédié n'a jamais existé — les « fonds » étaient déjà les presets procéduraux de BiomeBackground. Rien à récupérer au-delà.

## 1. Implémenté

- **§1 Structure d'écran** : `CombatCtbUi` (`scenes/combat_ctb/`, 100 % code) — scindé en diagonale (deux BiomeBackground `set_split` + bande diagonale placeholder dessinée, l'ancien CombatVS étant supprimé), camp joueur à gauche / adverse à droite, **jusqu'à 3 cartes par camp** (`CarteCombattantCtb`, N-vs-N acté — le camp joueur n'a que le héros aujourd'hui).
- **§2 File d'initiative** : `CtbMoteur.prevoir_ordre(n)` — simulation **pure** des horloges (réarmement à la VIT courante, même départage d'égalité que la vraie file, activation ouverte = déjà consommée), **sans valeurs numériques** exposées. L'UI affiche N=6 puces recalculées après chaque action ; les changements de VIT en cours de combat s'y reflètent.
- **§3 Activation du joueur** : le moteur pull-based attend l'input (aucun timer) — boutons **Attaquer** (choix de cible parmi les ennemis vivants : boutons nominatifs + clic sur la carte ennemie, Annuler) et **Défendre**. **Aucun bouton Objet ni Compétence** (contenu absent, pas grisé — testé). Activations ennemies auto-résolues avec pauses courtes (0,55 s + 0,35 s, `facteur_delais`).
- **§4 Défendre (moteur + UI)** : `Enums.ActionCtb.DEFENDRE` fonctionnel — dégâts d'**attaque** subis × (1 − `defendre_reduction_degats`) (**0.5 provisoire**, `data/combat_ctb/config_ctb.tres`, nouveau `ConfigCtbData`) de la mise en garde jusqu'à la **prochaine activation du défenseur** (garde baissée à l'ouverture de son activation, avant les ticks DÉBUT). Ordre d'application **contractuel et testé** : ATK → mitigation DEF → critique → Défendre → plancher MIN_DAMAGE → arrondi. Les ticks de DoT ne sont **pas** réduits (dégâts figés à la pose — règle actée ; cf. question ouverte n° 1). État visible : flag `en_defense` + pill « 🛡 Garde » sur la carte + flottant à la pose. Disponible pour les deux camps ; l'IA (`action_auto`) ne l'utilise pas (hors scope).
- **§5 Lisibilité** : PV en barres + valeurs des deux côtés (couleur par fraction), pills de statuts par combattant (type ×stacks + durée restante max en activations), dégâts flottants **distincts** (normal / « CRIT ! » avec punch / tick de DoT violet préfixé du statut), embuscade **annoncée à l'ouverture** (bandeau rouge + son). Nouveau signal moteur `evenement` (structuré : attaque/crit/garde/tick/pose/défense) — l'UI ne parse jamais le journal texte.
- **§6 Transitions** : fondu noir + titre à l'entrée (annonce d'embuscade intégrée) ; en fin de bataille l'**issue s'affiche** (VICTOIRE / DÉFAITE + « Cliquer pour continuer ») avant le retour à la carte.
- **§7 Branchement** : `SandboxExpe` joue les combats **à la main par défaut** ; checkbox « Combat auto » = auto-résolution du chantier 3. L'UI n'est ouverte que par les chemins d'input du sandbox (jamais via le signal `combat_demarre`) → le ScreenshotTool et les suites, qui pilotent `ExpeRun` directement, sont **intouchés**. La défaite affiche l'écran d'issue puis laisse les signaux existants faire (Game Over hors scope). `ExpeRun` : zéro modification (l'injection pull-based du chantier 3 suffisait).
- **§8 Livrable de test** : cf. § Résultats. Nouveau mode `SHOT_MODE=combat` du ScreenshotTool (4 captures réelles).

## 2. Écarts à la spec (aucun silencieux)

- **« Dégâts subis réduits de 50 % » précisé en « dégâts d'ATTAQUE »** : les ticks de DoT ne sont pas réduits par la garde — cohérent avec « DoT figé à la pose » (règle actée 06/07) et le standard JRPG. Testé et documenté ; **à confirmer** (question ouverte n° 1).
- **Valeur Défendre dans un NOUVEAU `.tres`** (`ConfigCtbData` → `config_ctb.tres`, réglages globaux du moteur) plutôt que dans `ExpeCombatConfigData` (réglages d'une expédition) : Défendre existe quel que soit le contexte d'invocation du moteur. Remplaçable avant `demarrer()` (testé).
- **Test manuel** : je ne peux pas « jouer à la main » — le combat complet est joué **via l'UI** par la suite TestCombatUi (pressions de boutons réelles, embuscade comprise) + 4 captures de rendu réel jointes. Le playtest humain dans le sandbox reste à faire.
- **Baseline TestCombatCtb** : le recap 4 annonçait 35 ; le décompte runtime réel avant ce chantier était **36** lignes d'assertion (méthodo de comptage différente — une assertion conditionnelle). Les baselines ci-dessous sont des décomptes runtime.

## 3. Décisions techniques prises

- **Signal `evenement` structuré sur CtbMoteur** : l'UI reçoit des dictionnaires typés (dégâts chiffrés, crit, garde, mort) au lieu de parser le journal — le journal texte reste la référence de dev, inchangé.
- **`prevoir_ordre` est pur** (aucune mutation) et gère l'activation OUVERTE (entre `activer_suivant()` et `jouer()`) en la considérant consommée — exactement ce que l'UI affiche pendant l'attente d'input. Approximation assumée : exact tant que rien ne meurt et qu'aucune VIT ne change (recalcul après chaque action).
- **La garde expire à l'OUVERTURE de l'activation du défenseur** (avant les ticks DÉBUT) — « jusqu'à la prochaine activation » sans ambiguïté, testé.
- **`CombatCtbUi` est une boucle asynchrone pull-based** sur un moteur déjà démarré ; `facteur_delais` (1.0 jeu, 0.0 tests headless : aucun délai, fermeture sans clic) ; signal `fermee(recap)` — l'appelant libère l'écran et garde la main sur la suite.
- **Piège Godot documenté** : `set_anchors_preset` seul CONSERVE les offsets courants → écran 0×0 quand il est ajouté à un SubViewport (ScreenshotTool). Tous les plein-écrans de l'UI utilisent `set_anchors_and_offsets_preset`.
- **`UIHelpers.clear_children_now`** (nouveau) : détachement immédiat pour les conteneurs reconstruits plusieurs fois par frame (file d'initiative, pills) — `queue_free` seul laissait des doublons transitoires (12 puces au lieu de 6, vu en test).
- **Garde anti-press-hors-tour** : `_sur_attaquer` ignore un press quand aucune activation joueur n'est ouverte (le bouton est masqué ; seul un `pressed.emit()` programmatique pouvait le déclencher — vu en capture).
- **SandboxExpe** : garde anti-double-écran (flèche clavier pendant un combat ouvert), payload `combat_demarre` mémorisé pour l'annonce d'embuscade.

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/ConfigCtbData.gd` + `data/combat_ctb/config_ctb.tres` — réglages globaux du moteur (réduction Défendre)
- `scenes/combat_ctb/CombatCtbUi.gd` — écran de combat jouable
- `scenes/combat_ctb/CarteCombattantCtb.gd` — carte d'un combattant (PV, statuts, garde, ciblage)
- `tests/TestCombatUi.gd` + `.tscn` — nouvelle suite (en CI)

**Modifiés**
- `scripts/resources/Enums.gd` — `ActionCtb.DEFENDRE`
- `systems/combat_ctb/ctb_moteur.gd` — Défendre, signal `evenement`, `prevoir_ordre`, config `.tres`
- `systems/combat_ctb/ctb_combattant.gd` — flag `en_defense`
- `scripts/autoloads/Translations.gd` — clés `ctb.*` (FR + EN)
- `scripts/autoloads/UIHelpers.gd` — `clear_children_now`
- `scenes/expedition/SandboxExpe.gd` — combats joués à la main par défaut + checkbox « Combat auto »
- `tests/TestCombatCtb.gd` — +19 assertions (Défendre, prédiction de file)
- `tests/ScreenshotTool.gd` — mode `combat`
- `.github/workflows/tests.yml` — étape TestCombatUi
- `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 4 + addendum) : ScriptsLoad 105, CTB 35 (36 en décompte runtime, cf. § 2), ExpeCarte 39, ExpeCombat 45.**

Ce chantier (décomptes runtime) :
- `TestScriptsLoad` **109/109** (+4 : ConfigCtbData, CombatCtbUi, CarteCombattantCtb, TestCombatUi) ;
- `TestCombatCtb` **55** (+19) — Défendre : réduction exacte (100 → 50), expiration à la prochaine activation du défenseur (dégâts pleins ensuite), cumul mitigation DEF (100 → 75 → 38) et crit (→ 925), plancher ≥ 1 après garde, DoT non réduit sous garde, IA sans Défendre, valeur `.tres` par défaut et remplacée, signaux `evenement` (defense/defense_fin/attaque avec `garde`) ; prédiction de file : identique à l'ordre réel sur combats seedés (initial + en cours), pendant une activation ouverte, après buff de VIT en cours de combat, sous embuscade ;
- `TestCombatUi` **13** (nouvelle suite) — annonce d'embuscade à l'ouverture, boutons Attaquer/Défendre visibles au tour du joueur, **aucun bouton Objet/Compétence**, file de 6 puces dans l'ordre exact de `prevoir_ordre`, Défendre puis combat complet joué via l'UI jusqu'à la victoire, issue affichée, `fermee(recap)` émis une fois, pills de statut (« Poison ×2 (2) ») et de garde sur la carte, auto-résolution sans UI intacte ;
- suites inchangées toutes vertes : ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, TierCap 22, Drops 29, HoloXlsx, HoloTraffic ; **boot sans erreur**.

Contrôle visuel (rendu réel, `SHOT_MODE=combat`) : `tests/_shot_ctb_embuscade.png` (transition d'entrée + annonce), `_shot_ctb_tour_joueur.png` (écran scindé Ville/biome, file de 6, cartes PV, pill Poison ×2, « Au tour de Avatar », boutons), `_shot_ctb_cibles.png` (rangée de choix de cible + flottants), `_shot_ctb_issue.png` (VICTOIRE + « Cliquer pour continuer », carte ennemie grisée à 0 PV).

## 6. Questions ouvertes

1. **Défendre vs DoT** : la garde ne réduit que les dégâts d'attaque (arbitrage de ce chantier, cohérent avec « DoT figé à la pose »). À confirmer ou amender au calibrage.
2. **Défendre côté IA ennemie** : hors scope acté — à quel chantier (avec l'IA avancée) ?
3. **File prédite et aléas futurs** : la prédiction ignore morts et changements de VIT à venir (recalculée après chaque action). Suffisant, ou signaler l'incertitude dans l'UI finale ?
4. **Loot/XP des combats d'expédition** : les payloads portent déjà le recap `combat` — prochain chantier ?
5. **SandboxCtb (chantier 1)** reste un déroulé automatique à journal — le brancher aussi sur `CombatCtbUi`, ou le laisser comme outil moteur pur ?
6. **N=6** et les pauses (0,55 s / 0,35 s) : valeurs de proposition, à calibrer au playtest.
