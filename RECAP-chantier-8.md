# RECAP — Chantier 8 : Branchement au flux de jeu principal

Branche : `ReworkCombat`. Le pipeline expédition (chantiers 2-7) sort du sandbox : **QG → HoloMap → expédition → retour au QG**, avec **persistance réelle**. Flux acté 06/07/2026 appliqué : **« Partir en expédition » ouvre la HoloMap** — destination et lancement s'y choisissent.

## 0. Inventaire préalable (état AVANT ce chantier)

**Points d'entrée expédition existants :**
- Panneau Expéditions, bouton « ⚔ PARTIR EN EXPÉDITION » (visible seulement biome sélectionné) → `Village.start_selected_expedition()` → `AdventureSystem.start_adventure()` (**ancienne boucle idle**) + bannière « Combat en refonte ». **Seul point d'entrée UI de l'ancienne boucle.**
- Hex « Carte » du hub (`_go_map`) et bouton « 🗺 CARTE » du panneau → `open_expedition_map()` → HoloMap.

**Ce que la HoloMap savait faire :** overlay 3D persistant (veille ↔ réveil), Lieux découverts posés en pins cliquables (zone à ID d'entité) ; un clic (`lieu_selectionne`) **sélectionnait le biome dans le panneau Expéditions et fermait la carte** — un rail de sélection pour l'ancienne boucle, ni palier, ni lancement.

**Restes de l'ancienne boucle idle (morte avec son moteur) :**
- `AdventureSystem` : rencontres créature constatées **non résolues** (`_combat_non_resolu`) ; pièges/bénédictions et XP de Maîtrise encore actifs si la boucle était lancée. `stop_adventure` / `start_unique_combat` sans appelant UI. `_resolve_victory` / `_resolve_unique_victory` conservés pour réintégration.
- `CycleSummaryScreen` + `CycleData` : **orphelins en jeu** depuis la suppression de l'ancien moteur (seuls le ScreenshotTool et TestExpeditionFlow les utilisent).

**Ce chantier :** REMPLACE le rail `start_selected_expedition` → boucle idle (devient : ouvre la HoloMap) et le rail `lieu_selectionne` → sélection de biome (devient : panneau de lancement) ; AJOUTE l'écran d'expédition réel ; LAISSE INTACTS `AdventureSystem` (utilitaires drops/zones/résumé + fonctions conservées), `CycleSummaryScreen`/`CycleData` (orphelins assumés, listés), le sandbox (outil dev, jamais d'écriture), le QG/Forge/bâtiments (gelés). **Supprimé au-delà du strict rail remplacé : rien**, hormis 3 clés de traduction orphelines (listées §4).

## 1. Implémenté

- **§1 Flux de lancement** : `start_selected_expedition()` ouvre la HoloMap (le bouton du panneau Expéditions est désormais **toujours disponible** — la destination ne dépend plus de la sélection de biome, l'encadré « choisir un biome » a disparu). Clic sur un Lieu → **`ExpeLancementPanel`** (modal au-dessus de la carte, z 450) : destination (nom/couleur de palier de l'entité), **choix du palier de profondeur** (Périphérie/Enceinte/Noyau, radio, Périphérie par défaut — toujours **aucun effet mécanique**, le paramètre circule), PARTIR / Annuler (Annuler = retour carte ; Échap pris en charge par le rail du Village). PARTIR → `Village.lancer_expedition(lieu, palier, graine=0)` : **vrai héros** (`CtbPont.combattant_depuis_heros`), pool résolu par la destination, HoloMap mise en veille, écran d'expédition (z 500).
- **§1b Architecture destination → pool** : `ExpeDestinationsData` (`data/expedition/destinations.tres`) — `pools_par_lieu` (lieu_id → PoolEnnemisData, **vide** : les 6 Lieux différenciés n'existent pas) + `pool_defaut` en repli. Différencier un Lieu = 1 entrée de dict dans le .tres, zéro code.
- **§2 Écran d'expédition réel** : `ExpeditionScreen` — structure du sandbox reprise (carte + brouillard, en-tête Lieu/palier/étage/PV + ligne héros Nv/XP/Euren + ligne affixes/objets, journal, Extraire/Continuer, combats **à la main** dans `CombatCtbUi` avec fournisseurs récompenses/inventaire), mais **persistance ACTIVE** (aucun débranchement de SaveManager — les signaux XP/Euren du chantier 6 déclenchent la sauvegarde debouncée). Transitions placeholder (le hub reste dessous). Hook de test `combat_auto` (jamais exposé en UI).
- **§2b Vue de carte PARTAGÉE** : le rendu/navigation de la carte (dessin des nœuds, brouillard, clic + flèches) est extrait de SandboxExpe dans **`ExpeCarteView`** (vue passive : signal `deplacement_demande`, l'hôte décide) — utilisée par l'écran de jeu ET le sandbox (pas de doublon ; étiquettes de nœuds passées à `Translations.T`).
- **§3 Retour et persistance** : fin de run (extraction / complétion / **défaite = extraction sans butin**) → **recap placeholder** (issue, étage atteint, combats, XP gagnée, Euren crédité, purge affixes/consommables) → « ⌂ RETOUR AU QG » → le Village libère l'écran, badges + panneau rafraîchis. **Choix du hub de retour : le QG (Village)** — l'écran est un overlay du Village et la HoloMap est en veille ; elle reste à un clic (plus naturel qu'un retour forcé sur la carte). Défaite en combat : l'écran de combat affiche d'abord son issue (clic), le recap vient ensuite.
- **§4 Cohabitation** : QG/Forge/bâtiments intacts. `AdventureSystem` n'a **plus aucun point d'entrée UI** ; le bloc « expédition en cours » de l'AdventurePanel (gated `is_running`) devient inerte — laissé en place.
- **§5 Tests** : nouvelle suite **`TestFluxExpedition`** (46, en CI) — voir §5.

## 2. Écarts / interprétations (aucun silencieux)

- **Le bouton « PARTIR EN EXPÉDITION » du panneau ne nomme plus le biome** (`adv.start_btn_named` supprimé) et **l'encadré « choisir un biome » a disparu** : la destination se choisit sur la carte, un bouton gated par la sélection aurait été un faux verrou. La sélection de biome du panneau reste (consultation/accordéon) et **suit** la destination cliquée sur la carte.
- **Retour au QG plutôt qu'à la HoloMap** (le spec laissait le choix) — documenté §1/§3.
- **Échap pendant une expédition : neutralisé** (ni Paramètres ni fermeture) — la sortie passe par le recap ; l'abandon volontaire en cours de run n'est pas designé (hors scope, avec le Game Over).
- **Fermer la fenêtre en pleine run** : l'XP déjà créditée est flushée par SaveManager, la run elle-même n'est PAS persistée (pas de reprise) — l'Euren accumulé non crédité est perdu, cohérent avec « crédit à la sortie seulement ». Consigné en question ouverte.
- **`TestFluxExpedition` écrit réellement la sauvegarde** (c'est l'objet du round-trip) : exception unique à la règle « jamais d'écriture dans un test », encadrée par un protocole de protection (fichiers réels renommés `.avant_test` au démarrage — le flux part d'une partie neuve, déterministe — puis restaurés avant de quitter, échecs compris). Règle amendée dans CLAUDE.md.

## 3. Décisions techniques prises

- **Le Village orchestre, les widgets émettent** : `ExpeLancementPanel` n'ouvre rien lui-même (`lancer`/`annule`), `ExpeditionScreen` émet `retour_qg(recap)` — pas de référence montante, pattern des overlays existants.
- **`lancer_expedition(lieu, palier, graine=0)` public** : même rail pour le bouton PARTIR (graine 0 = aléatoire) et les tests (graine fixée = run reproductible, RNG Godot déterministe multi-plateforme).
- **`ExpeCarteView` passive** (signal d'intention, pas d'accès à la run en écriture) : le sandbox garde ses hooks dev, l'écran de jeu ses règles, un seul dessin.
- **Priorité d'Échap étendue** (Village) : expédition > modal de lancement > HoloMap > Paramètres > panneau.
- **Test 7 (sandbox sans écriture) exécuté EN DERNIER** : SandboxExpe déconnecte les déclencheurs de SaveManager pour tout le process.
- Test : le Village s'instancie comme **enfant du nœud de test** (la racine est « busy » pendant `_ready` → `add_child` sur root échoue et rien n'entre dans l'arbre).

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/ExpeDestinationsData.gd` + `data/expedition/destinations.tres`
- `scenes/expedition/ExpeCarteView.gd`, `ExpeLancementPanel.gd`, `ExpeditionScreen.gd`
- `tests/TestFluxExpedition.gd` + `.tscn` — nouvelle suite (en CI)

**Modifiés**
- `scenes/village/Village.gd` — `start_selected_expedition` → HoloMap ; `lieu_selectionne` → `_ouvrir_lancement_expedition` ; `lancer_expedition` / `_sur_retour_expedition` ; priorité d'Échap ; vars `_expe_lancement` / `_expedition_screen` + `DESTINATIONS`
- `scenes/village/panels/AdventurePanel.gd` — bouton de départ toujours visible (ouvre la carte), suppression du placeholder « choisir un biome » et du renommage du bouton par sélection
- `scenes/expedition/SandboxExpe.gd` — rendu/navigation délégués à `ExpeCarteView` (aucun changement de comportement)
- `scripts/autoloads/Translations.gd` — section `expe.*` (FR+EN), helper `resource_name(res)` (nom localisé des Resources à `nom_affichage_fr/en`) ; **supprimé** (orphelines) : `adv.combat_wip`, `adv.biome_placeholder`, `adv.start_btn_named`
- `.github/workflows/tests.yml`, `CLAUDE.md`

**Laissé intact (assumé, cf. §0)** : `AdventureSystem` (plus d'entrée UI ; utilitaires + `_resolve_*` conservés), `CycleSummaryScreen`/`CycleData` (orphelins en jeu), bloc « expédition en cours » de l'AdventurePanel (inerte), SandboxExpe/SandboxCtb (outils dev).

## 5. Résultats de test

**Baseline (rappel — chantier 7, décomptes runtime) : ScriptsLoad 117, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28.**

Ce chantier :
- **`TestFluxExpedition` 46** (nouvelle suite, en CI) — flux complet dans le VRAI jeu : Village instancié → `start_selected_expedition` ouvre la HoloMap (et l'ancienne boucle idle n'est PAS lancée) → clic Lieu → panneau de lancement (3 paliers, Périphérie présélectionnée, Annuler = retour carte) → PARTIR (boutons réels pressés) → écran créé, HoloMap en veille, **vrai héros** (`id == "hero"`), pool résolu par la destination, palier choisi (Enceinte) circulant dans la run → run jouée (BFS sur la carte, combats auto via hook, héros invincible — la mécanique de crédit est l'objet, pas le duel) → sortie → XP/Euren crédités et **round-trip par le VRAI fichier de sauvegarde** (flush → relecture JSON → valeurs identiques), purge vérifiée, recap affiché, retour au QG (écran libéré) ; **défaite** (graine 424242, héros à 1 PV) → aucun crédit, XP/Euren inchangés, recap défaite, retour sans Game Over ; **sandbox** : déclencheurs de sauvegarde tous déconnectés, progression émise sans marquer dirty, timer arrêté ;
- `TestScriptsLoad` **122/122** (+5 : ExpeDestinationsData, ExpeCarteView, ExpeLancementPanel, ExpeditionScreen, TestFluxExpedition) ;
- suites inchangées **toutes vertes aux décomptes baseline** : CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, TierCap 22, Drops 29, Forge 29, VillageBuildings 55, HoloXlsx, HoloTraffic ; **boot 30 s sans erreur** ;
- sauvegarde réelle du joueur **vérifiée intacte** après la suite (protocole `.avant_test` → restauration).

(NB : TestXPSystem / TestXPMotifs / TestBackgrounds sont des outils visuels sans `quit()` — jamais en CI, inchangés.)

**Manuel restant : une expédition complète jouée à la main dans le jeu réel** (HoloMap → combat à la main → extraction → recap → QG) — le flux est couvert par la suite, la passe manuelle valide le ressenti (à faire au prochain lancement de l'éditeur).

## 6. Questions ouvertes

1. **Abandon en cours de run** (fermeture de la fenêtre, futur bouton « abandonner » ?) : actuellement la run est perdue (XP créditée conservée, Euren accumulé perdu) — à trancher avec le Game Over/rechargement (chantier suivant).
2. **Retour au QG vs HoloMap** : QG choisi (documenté) — si le rythme de jeu réel montre qu'on relance surtout des expéditions en chaîne, basculer le retour sur la carte est trivial (`_sur_retour_expedition`).
3. **Bloc « expédition en cours » de l'AdventurePanel** (gated `is_running`, inerte) et `CycleSummaryScreen`/`CycleData` : à supprimer avec le rework des bâtiments/QG ou lors de la réintégration des utilitaires d'AdventureSystem ?
4. **Un seul écran à la fois** : relancer une expédition depuis le recap (sans repasser par le QG) — utile ? (une ligne dans `_sur_retour_expedition`).
5. **`graine` exposée au joueur** un jour (défis quotidiens, partage de runs) ? Le paramètre existe déjà de bout en bout.
