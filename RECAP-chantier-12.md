# RECAP — Chantier 12 : Économie du QG — Modules, coûts Euren, voies de Lieutenants

Branche : `ReworkCombat`. Rework économique du QG acté (06/07/2026), modèle domaine/housing : deux devises — **Euren** (existant) + **Module** (nouveau, rare) — remplacent les ressources silotées pour les coûts de bâtiments ; les **voies** (nouveaux quartiers) s'ouvrent par l'objet unique de chaque Lieutenant ; le QG n'a plus de palier de rareté propre côté accès (quartiers de base ouverts d'emblée). Toutes les valeurs sont PROVISOIRES, data-driven, à calibrer.

## 1. Implémenté

### Le Module (nouvelle devise)

- **Drop déterministe** : `+1` à la **PREMIÈRE arrivée sur chaque nœud de Fin d'étage** (`ExpeRun.modules_accumules`, incrémenté dans `_finaliser_noeud` — la première arrivée EST la résolution, les retours sur une Fin résolue sont inertes par construction, aucun compteur « déjà vu » nécessaire). Max 3 par raid de 3 étages ; un **assaut n'a pas de Fin d'étage** (remplacée par le Boss) → 0 Module.
- **Crédit à la SORTIE uniquement** (extraction ou complétion — défaite = rien), mêmes rails que l'Euren : `ExpeRun._terminer` → `ProgressionHeros.crediter_modules`. État brut `GameData.player["modules"]` (persisté automatiquement) ; signal `EventBus.modules_change` ajouté aux déclencheurs de sauvegarde.
- **Visible** : en-tête de run (`ctb.entete_heros` étendu « · Modules (run) %d », ExpeditionScreen + SandboxExpe) et recap de fin (`expe.recap_modules`). Recap d'ExpeRun : champs `modules_gagnes` / `modules_credites`.

### Objets de Lieutenants (clés de voies)

- **Premier kill → objet** : accordé DANS `GameData.marquer_lieutenant_vaincu` (même moment, même persistance que le slot d'Alarme — donc même annulation par le Game Over qui recharge la sauvegarde, testé). État `player["objets_lieutenants"]` (lieu_id → true), jamais consommé ; re-kill → rien.
- **Placeholder « Sceau · <Lieu> »** (clé `voies.sceau` — nommage réel à la session narration), affiché sobrement dans le panneau VOIES (section « Sceaux de Lieutenants »). Un Lieu non découvert s'affiche « ??? » (ne jamais trahir un biome caché).

### Coûts des bâtiments : Euren + Modules

- **Courbe UNIQUE data-driven** : `data/progression/couts_batiments.tres` (`BatimentsCoutsData`) — Délabré→T0 : 100/0, →T1 : 160/0, →T2 : 260/1, →T3 : 420/2, →T4 : 670/3, →T5 : 1070/4 (géométrie ×1,6 conservée ; les Modules entrent à T2 comme la ressource rare avant eux).
- `VillageBuildings.building_cost` → `{ euren, modules }` ; `can_afford` lit les soldes `ProgressionHeros` ; `upgrade_building` débite via `depenser_euren`/`depenser_modules` (garde-fou : jamais de solde négatif). **Plus JAMAIS de ressource de biome demandée par un bâtiment** (les ressources existent toujours en jeu — drops non touchés, rework au fil de l'eau).
- **UI** : `BuildingPanel._cost_block` affiche ◈ Euren / ◧ Modules avec solde have/need (ligne Modules absente quand le palier n'en demande pas).
- Supprimés de `Balance` : `BUILDING_COST_STEPS`, `BUILDING_COST_BASE/GROWTH`, `VILLAGE_ROUTE_COSTS`, `FORGE_HUB_UNLOCK_VILLAGE_TIER` (conservés : `BUILDING_TIER_DELABRE`, `BUILDING_MAX_TIER`).

### Routes : SUPPRIMÉES (neutralisation documentée)

- Système entier retiré (« un système remplacé est supprimé ») : `route_built`/`route_cost`/`can_rebuild_route`/`rebuild_route` (VillageBuildings), `BuildingPanel.build_route_section` + ses appels (Hero/Adventure/ForgePanel), `Village.animate_route_creation`/`refresh_hub_after_route`/`_grow_link`, clés `building.route.*`, clé `village["routes"]` (une vieille sauvegarde peut encore la porter — inerte via le merge tolérant, pas de bump `SAVE_VER` : rien de lu n'est renommé).
- Les filaments/boules/quartiers du hub apparaissent **d'emblée** pour les 3 quartiers de base ; la révélation reste un clic (boule d'énergie), inchangée.

### Quartiers de base + 6 voies scellées

- **Atelier (Forge) ouvert d'emblée** : hex `FORGE` à `tier_min 0`, verrou interne de `ForgePanel` (« Village < T1 → mur ») supprimé (+ clés `forge.locked.*`), gate de drop d'`AdventureSystem._drop_biome_resources` supprimé (le legacy droppe toujours). Renames « Avatar »/« Atelier » NON faits (hors scope — chantier DA ; libellés actuels conservés).
- **6 voies scellées**, une par Lieutenant (source data-driven : `destinations.tres.lieutenants_par_lieu` — mêmes 6 clés que l'Alarme). `GameData.ouvrir_voie(lieu)` : refuse sans objet ou si déjà ouverte, persiste `player["voies_ouvertes"]`, émet `EventBus.voie_ouverte` (déclencheur de sauvegarde). **Action manuelle « prêt → clic »** (pilier conservé) — jamais automatique.
- **Compteur source UNIQUE** : `GameData.nb_voies_ouvertes()` — l'évolution visuelle du QG (DA, hors scope) s'y branchera.
- **UI placeholder** : nouvel hex `VOIES` (🔒, tier_min 0) → `VoiesPanel` : compteur x/6, Sceaux possédés, une carte par voie (« Voie scellée » grise / bouton « Restaurer la voie » avec objet / « Quartier restauré — contenu à venir »). Pastille de notification sur l'hex quand un Sceau attend son clic.

### Panneau Expéditions rebranché (point ouvert 23 refermé)

- Hex `EXPÉDITIONS` → **rouvre le panneau** (consultation + Évoluer créatures) ; le départ reste sur la HoloMap (gros bouton « Partir en expédition » du panneau, ou hex `CARTE` → HoloMap directe, conservé).
- **« Évoluer biomes » SUPPRIMÉ** (les Lieux n'évoluent plus — décision actée, avertissement re-consigné ci-dessous) : plus de bouton dans l'accordéon, plus de pastille « adventure » pour un biome prêt (créatures seulement).

## 2. Écarts / interprétations (aucun silencieux)

- **⚠ Avertissement re-consigné (« Évoluer biomes »)** : sans montée de palier de biome, l'échelle T1 équipement / T2 mécanique forte / T4 biome secondaire est DE FAIT gelée — plus AUCUN moyen en jeu d'obtenir l'équipement des biomes. Assumé par l'arbitrage (l'acquisition d'équipement sera retravaillée au fil de l'eau) ; les hooks (`entity_evolved`, `unlock_biome_equipment`) restent en place. Noté dans CLAUDE.md.
- **Objet = état dédié, pas un alias du slot d'Alarme** : `objets_lieutenants` duplique aujourd'hui `lieutenants_vaincus` (accordés au même instant) mais reste un état distinct — le jour où l'objet devient consommable / narratif, la séparation est déjà là. Le grant vit DANS `marquer_lieutenant_vaincu` (un seul point de vérité du « premier kill »).
- **Où affiche-t-on les voies ?** Spec : « point d'accès au plus simple selon l'UI existante ». Choix : un hex `VOIES` dédié sur l'anneau (le pattern hub existant — aucune plomberie nouvelle) plutôt qu'une section enfouie dans un panneau existant. Placeholder assumé, remplaçable d'un bloc à la session narration.
- **Drop de Module logué dans `_finaliser_noeud`** (pas un système séparé) : la « première arrivée » est déjà exactement la résolution du nœud — tout compteur parallèle aurait créé une seconde source de vérité.
- **`_test_module_defaite`** : la défaite peut survenir un étage plus loin que prévu selon la carte (voisinage direct entrée→fin) — l'assertion accepte `modules_gagnes ≥ 1` avec toujours `modules_credites == 0` (l'objet du test).
- **TestVillageBuildings réécrit** (l'ancien testait la courbe en ressources et les routes, mortes) et **ajouté à la CI** avec TestEconomieQG (il n'y était pas — il couvre désormais la moitié « achat » du chantier).
- **BuildingData.biome_principal_id / biomes_additionnels conservés en donnée** mais documentés INERTES (plus lus par les coûts) — les retirer des .tres aurait touché les 10 bâtiments pour zéro gain ; une future thématisation peut s'en resservir.

## 3. Décisions techniques prises

- **Modules dans `ProgressionHeros`** (avec l'Euren) : une seule maison pour les soldes/crédits/débits de devises ; `VillageBuildings` ne touche jamais `player` directement pour payer.
- **`depenser_*` retourne bool et garde le solde ≥ 0** — `can_afford` reste la vérification d'appel, le débit re-vérifie (défense en profondeur, testé « refus »).
- **`upgrade_building` n'émet plus `resources_changed`** (aucune ressource ne bouge) : `village_buildings_changed` + `euren_change`/`modules_change` couvrent rafraîchissement et sauvegarde.
- **Dette « point ouvert 22 » (`recharger()`) réévaluée : COUVERTE.** Une run mute désormais aussi `modules` / `objets_lieutenants` — clés toujours présentes dans la sauvegarde de lancement (player dupliqué intégralement, défauts dans `GameData.player`), donc écrasées par le merge overwrite au rechargement. Testé (Modules perdus en défaite, objet annulé par Game Over). Commentaire de `recharger()` mis à jour.
- **`voie_ouverte` signal + refresh** : le Village écoute et rafraîchit le panneau actif + les pastilles — `VoiesPanel` reste sans état (pattern des autres panels).
- **`couts_batiments.tres` dans `data/progression/`** (avec `euren.tres`, `heros_progression.tres`) : c'est la maison de l'économie depuis le chantier 6 — Balance garde les constantes de gameplay, les tunables d'économie du rework vivent en .tres (pattern des chantiers 6/7/11).

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/BatimentsCoutsData.gd` + `data/progression/couts_batiments.tres` — courbe Euren + Modules
- `scenes/village/panels/VoiesPanel.gd` — panneau VOIES (Sceaux + 6 voies)
- `tests/TestEconomieQG.gd` + `.tscn` — 53 assertions (11 tests, cf. §5)
- `RECAP-chantier-12.md`

**Modifiés**
- `scripts/autoloads/GameData.gd` — état `modules`/`objets_lieutenants`/`voies_ouvertes`, grant de l'objet au premier kill, API objets/voies + `nb_voies_ouvertes()` (source unique), clé `village["routes"]` retirée
- `scripts/autoloads/ProgressionHeros.gd` — Modules (solde/crédit/débit) + `depenser_euren`
- `scripts/autoloads/EventBus.gd` — signaux `modules_change`, `voie_ouverte`
- `scripts/autoloads/SaveManager.gd` — 2 signaux de progression ajoutés, commentaire `recharger()` (dette réévaluée)
- `scripts/autoloads/Balance.gd` — courbe ressources / routes / gate Forge SUPPRIMÉS
- `scripts/systems/VillageBuildings.gd` — coûts Euren+Modules, routes supprimées, débits via ProgressionHeros
- `scripts/systems/AdventureSystem.gd` — gate de drop « avant la Forge » supprimé
- `scripts/resources/BuildingData.gd` — assignation de biome documentée inerte
- `systems/expedition/expe_run.gd` — Modules (accumulation Fin d'étage, crédit sortie, recap, journal)
- `scenes/expedition/ExpeditionScreen.gd` / `SandboxExpe.gd` — Modules en en-tête + recap
- `scenes/village/Village.gd` — hex FORGE tier_min 0, hex VOIES + panneau + badge, `_go_adventure` → panneau, routes retirées (liens d'emblée), listener `voie_ouverte`
- `scenes/village/panels/BuildingPanel.gd` — bloc de coût devises, section route supprimée
- `scenes/village/panels/ForgePanel.gd` — verrou Village supprimé (`_build_locked` mort)
- `scenes/village/panels/HeroPanel.gd` / `AdventurePanel.gd` — appels route supprimés ; AdventurePanel : bouton Évoluer biome supprimé
- `scripts/autoloads/Translations.gd` — clés Modules/devises/voies FR+EN ; `building.route.*` et `forge.locked.*` supprimées
- `tests/TestVillageBuildings.gd` — réécrit pour les coûts Euren+Modules (55 assertions)
- `.github/workflows/tests.yml` (+TestEconomieQG, +TestVillageBuildings), `CLAUDE.md`

## 5. Tests

**Nouvelle suite `TestEconomieQG` : 53/53** (protocole fichiers réels mis de côté — le round-trip est l'objet) :
1. Raid bouclé (3 étages) → 3 Modules accumulés ET crédités, recap exact ;
2. Revisite de la Fin d'étage inerte ; rien de crédité en cours de run ; extraction → 1 crédité ;
3. Défaite → Modules accumulés PERDUS (0 crédité, solde intact) ;
4. Assaut → 0 Module (pas de Fin d'étage) ;
5. Persistance des Modules (round-trip disque réel) ;
6. Sceau au premier kill d'un VRAI assaut ; re-kill → pas de double ;
7. Game Over : objet gagné pendant la run perdue ANNULÉ par rechargement ;
8. Voies : refus sans objet, ouverture au clic avec objet (signal unique), refus du double, compteur, round-trip disque ;
9. Atelier ouvert d'emblée (hex T0 + panneau Forge rendu sans mur) ;
10. Panneau VOIES : 6 voies, bouton Restaurer présent/absent selon l'objet, clic → ouverte ;
11. Expéditions : biome gorgé d'XP → AUCUN bouton Évoluer ; créature prête → bouton présent.

**`TestVillageBuildings` réécrit : 55/55** — courbe .tres exacte (table actée), coût commun à tous les bâtiments, aucune ressource de biome, achat réussi/refusé selon soldes avec débit exact (Euren seul à T0, Euren+Module à T2), gelé/registre, agrégation de bonus inchangée, rendu BuildingPanel.

**Baselines runtime** — toutes les suites vertes après chantier :
`TestScriptsLoad` **131/131** (+3 : BatimentsCoutsData, VoiesPanel, TestEconomieQG) ; CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 53, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26, Alarme 73, TierCap 22, Drops 29, Forge 29, HoloXlsx, HoloTraffic — **inchangées** ; **boot 30 s sans erreur**. CI : TestEconomieQG et TestVillageBuildings ajoutés au workflow. (`TestXPSystem`/`TestXPMotifs` : anciens tests sans `quit()` — jamais en CI, inchangés.)

**Manuel restant : la boucle complète en jeu réel** — raid → Modules à l'en-tête et au recap → amélioration d'un bâtiment (débit visible) → assaut → Sceau → hex VOIES (pastille) → ouverture d'une voie. Les 108 assertions couvrent la mécanique, le ressenti se juge en jouant.

## 6. Questions ouvertes

1. **Différenciation des coûts par impact de bâtiment** : courbe unique conservée (point ouvert hérité du chantier 4, inchangé).
2. **Solde d'Euren/Modules visible au QG hors panneau bâtiment** : aujourd'hui have/need s'affiche dans le bloc de coût — un affichage permanent (en-tête de hub ?) est une affaire de DA.
3. **Acquisition d'équipement** : gelée de fait avec « Évoluer biomes » (cf. §2) — à traiter au rework acquisition/drops (au fil de l'eau).
4. **Contenus des 6 quartiers** : session narration/PNJ (placeholders en place, `nb_voies_ouvertes()` prêt pour la DA).

## Addendum — Arbitrages design validés (06/07/2026)

Les 4 questions ouvertes ont été tranchées — **aucune modification de code** (statu quo intégral) :
1. **Courbe unique de coûts** : CONSERVÉE. La différenciation par impact reste un point ouvert hérité, non prioritaire.
2. **Solde Euren/Modules permanent au QG** : chantier DA/UI. Le have/need du bloc de coût suffit d'ici là.
3. **Acquisition d'équipement** : consignée point ouvert **PRIORITAIRE** côté design — le trou est acté et connu (aucune acquisition possible en partie neuve). Un chantier dédié viendra après la session de design ; **ne rien improviser d'ici là** — les hooks conservés (`entity_evolved`, `unlock_biome_equipment`) sont la bonne décision.
4. **Contenus des 6 quartiers** : session narration/PNJ. Placeholders et `nb_voies_ouvertes()` sont les bons points d'ancrage.

Baseline inchangée après addendum : **ScriptsLoad 131, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 53, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26, Alarme 73, EconomieQG 53, VillageBuildings 55.**
