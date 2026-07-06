# RECAP — Chantier 3 : Branchement combat CTB ↔ nœuds d'expédition

Branche : `ReworkCombat`. Les nœuds Combat et Attaque surprise jouent de VRAIS combats CTB (moteur du chantier 1) au sein d'une run free-roam (chantier 2). Coffre / Bénédiction / Piège restent des stubs.

## 1. Implémenté

- **§1 Nœud Combat** : l'entrée sur un nœud Combat lance un combat CTB — la run est **suspendue** (`ExpeRun.combat_en_cours` porte le moteur démarré, tout déplacement est refusé) et reprend sur la carte à la victoire (nœud résolu, signal `noeud_resolu` enrichi d'un dict `combat` — cf. §6). Le combat est pull-based comme le moteur : l'appelant le déroule (`derouler_auto()` au sandbox/tests, activation par activation pour la future UI). Ennemis tirés d'un **pool par Lieu** (`PoolEnnemisData` : ids du bestiaire dark fantasy existant, tirage uniforme AVEC remise par slot), nombre par **tirage pondéré data-driven** 1 → 50 % / 2 → 35 % / 3 → 15 % (`data/expedition/config_combat.tres`, à calibrer).
- **§1 Pont de données** (`systems/combat_ctb/ctb_pont.gd`) : conversion bestiaire → `CombattantCtbData` transitoire, stats lues TELLES QUELLES via `GameData.get_effective_stats` (source unique existante : palier de Maîtrise courant, descente de palier, fallbacks crit Balance), **aucun rééquilibrage, aucune duplication de champs** (le combattant est construit au lancement du combat, jamais sauvé). Mapping documenté ci-dessous et en tête de fichier.
- **§2 Palier de profondeur** : AUCUN effet (mécanisme non décidé) — le multiplicateur continue de circuler dans `expe_noeud_resolu`, `combat_demarre` et le recap, comme au chantier 2. Rien d'implémenté.
- **§3 Attaque surprise** : un « ? » qui révèle `ATTAQUE_SURPRISE` lance un combat identique au nœud Combat avec `CtbMoteur.malus_horloge_initiale_joueur` : **première horloge de chaque combattant du camp joueur × 1.5** (provisoire, `config_combat.tres`), réarmement suivant normal (testé : 50→75 puis 75+50=125). Journal : « ⚡ EMBUSCADE ! Première horloge du camp joueur ×1.5 » + horloges affichées.
- **§4 Persistance** : `ExpeRun.pv_avatar` — PV pleins au lancement (provisoire), réinjectés à l'entame de chaque combat (`cb.pv`), mémorisés à la sortie ; **aucune régénération**. **Statuts purgés en fin de combat** dans le moteur lui-même (`CtbMoteur._purger_statuts`, victoire ET défaite, journalisé) — la règle actée est maintenant du code, plus une convention.
- **§5 Défaite** : PV Avatar à 0 → fin d'expédition immédiate. Le nœud perdu n'est PAS résolu. Recap : `defaite=true`, `complete=false`, `extraction=false` + champs existants. Sanction hors scope — seul le signal existe (`terminee` / `EventBus.expe_terminee`).
- **§6 Recap étendu** : `nb_combats` (défaite comprise), `defaite`, `ennemis_vaincus` (références `CombattantCtbData` cumulées sur la run — celles des combats perdus comprises). Le payload `noeud_resolu` d'un nœud gagné porte `combat = {embuscade, nb_activations, ennemis_vaincus}` pour le futur chantier loot/XP.
- **§7 Données** : `PoolEnnemisData` (id + `creature_ids`), `ExpeCombatConfigData` (`poids_nb_ennemis` en Dictionary — un format 4+ s'ouvre en ajoutant une clé —, `malus_horloge_embuscade`), `data/expedition/pool_defaut.tres` (Rat des Égouts / Grenouille Géante / Loup des Cimes) + `config_combat.tres`. Headers `type="Resource" script_class="…"`, aucun champ dupliqué dans le runtime.
- **§8 Livrables** : `SandboxExpe` mis à jour — combats auto-résolus à l'entrée du nœud, journal complet du moteur replié dans celui de la run (préfixe `│`), **PV Avatar affichés en permanence** (« Étage 1/3 — PV 34/100 »), état « ☠ DÉFAITE » distinct. Nouvelle suite `tests/TestExpeCombat.tscn` (**40 assertions**, branchée CI).

## Mapping champ à champ bestiaire → CTB (obligatoire, §1)

`GameData.get_effective_stats(id)` → `CombattantCtbData` :

| Source (stats effectives) | CTB | Note |
|---|---|---|
| `hp` | `pv_max` | seule clé renommée |
| `atk` / `def` / `vit` | `atk` / `def` / `vit` | telles quelles |
| `crit_chance` / `crit_multiplier` | idem | fallbacks `Balance.CRIT_*` (règle existante de get_effective_stats) |
| `id`, `nom_affichage_fr/en` (entité) | idem | noms de BASE (nom par palier = affaire d'UI via Translations, `nom_journal()` n'est qu'un log de dev) |

Champs **sans équivalent CTB, ignorés** : `xp_reward` (dans stats_par_palier — consommé en aval au chantier loot/XP), `loot_table`, `ingredients_drop_ids` (drops hors moteur), `maitrise_actuelle` / `xp_maitrise_*` (servent à CHOISIR la ligne de stats, pas transposés), `noms_par_palier_*`, `lore_*`, `lore_par_palier_*` (UI), `est_unique`, `zone_associee`, `biome_id` (sélection amont), `passif_debloque_id` (progression de Maîtrise).

## 2. Écarts à la spec

- **Aucun écart fonctionnel.** Deux points d'interprétation :
  - « La run est suspendue pendant le combat » : la suspension est un ÉTAT (`combat_en_cours` + refus de déplacement), pas un blocage — le moteur étant pull-based, c'est l'appelant qui déroule le combat (auto au sandbox, la future UI fera jouer le joueur). C'est la même architecture que le moteur lui-même.
  - « Pool par Lieu » : les Lieux réels n'existant pas encore, le rattachement Lieu → pool est fait EN AMONT par l'appelant (le pool est injecté dans `ExpeRun` à la construction, comme l'avatar). Un seul pool provisoire est fourni (`pool_defaut.tres`).

## 3. Décisions techniques prises

- **Signature d'`ExpeRun` étendue** (avatar, pool, config combat REQUIS à la construction — pas de mode « sans combat ») : une run sans combattant n'a plus de sens au chantier 3 ; les anciens appels ne compilent plus (cassage volontaire, TestScriptsLoad le détecte).
- **Combats reproductibles dans une run seedée** : le RNG du moteur (crits) est seedé depuis le RNG de la run (`m.rng.seed = rng.randi()`).
- **Payload `combat` sur `noeud_resolu`** (non demandé, anticipation minimale) : le chantier loot/XP aura besoin des vaincus PAR NŒUD, pas seulement de l'agrégat du recap — les données existaient déjà dans le recap du moteur, elles sont juste transmises.
- **Purge des statuts DANS le moteur** (pas dans ExpeRun) : la règle « aucun DoT ne persiste » est une propriété du combat, pas de l'expédition — tout futur consommateur du moteur l'obtient gratuitement.
- **Signal `combat_demarre` local seulement** (pas d'EventBus) : les fins de combat passent déjà par `EventBus.ctb_victoire/ctb_defaite` ; un signal global de début sera ajouté quand un consommateur existera (UI).
- **Journal unifié** : le journal du moteur est replié dans celui de la run à la fin du combat (préfixe `│`) — un seul flux lisible au sandbox et dans les tests.
- **Fuite RefCounted évitée** : les lambdas de fin de combat ne capturent PAS le moteur (une lambda qui référence le moteur dans son propre signal = cycle jamais libéré, la connexion one-shot qui ne tire pas restant vivante). Vérifié : plus aucun « ObjectDB instances leaked » en sortie de test.
- `TestExpeCarte` adapté (39 assertions inchangées) : helper `_pas()` (déplacement + auto-résolution du combat éventuel) + avatar de test surpuissant — la suite teste la CARTE, les combats y sont gagnés d'office ; le combat est testé par TestExpeCombat.

## 4. Fichiers créés / modifiés

**Créés**
- `systems/combat_ctb/ctb_pont.gd` — pont bestiaire → CombattantCtbData (mapping en tête de fichier)
- `scripts/resources/PoolEnnemisData.gd`, `scripts/resources/ExpeCombatConfigData.gd`
- `data/expedition/pool_defaut.tres`, `data/expedition/config_combat.tres`
- `tests/TestExpeCombat.tscn` + `.gd` — 40 assertions

**Modifiés**
- `systems/expedition/expe_run.gd` — combats réels (suspension, PV persistants, défaite, recap agrégé, signal `combat_demarre`)
- `systems/combat_ctb/ctb_moteur.gd` — `malus_horloge_initiale_joueur` + `_purger_statuts()` en fin de combat
- `scenes/expedition/SandboxExpe.gd` — avatar/pool/config injectés, auto-résolution, PV affichés, état défaite
- `tests/TestExpeCarte.gd` — helper `_pas()` + avatar surpuissant (39 assertions inchangées)
- `tests/ScreenshotTool.gd` — mode `expe` : auto-résolution des combats rencontrés
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 2 + addendums) : ScriptsLoad 101, CTB 33, ExpeCarte 39.**
Ce chantier : `TestExpeCombat` **40/40** (nouvelle suite) ; ScriptsLoad **105/105** (+4 : PoolEnnemisData, ExpeCombatConfigData, CtbPont, TestExpeCombat) ; CTB **33** et ExpeCarte **39** inchangés ; toutes les autres suites vertes (ExpeditionFlow 28, TierCap 22, Drops 29, Holo ×2) ; boot sans erreur. Aucun autre compteur n'a bougé.

Vérifié par assertions : conversion bestiaire → CTB identique champ à champ (4 créatures dont Gorlab, comparée à `get_effective_stats` — indépendant de la sauvegarde locale ; entité inconnue → null) ; embuscade (horloge 50→75 côté joueur, 50 côté adverse, réarmement normal 75+50=125, journal) ; purge des statuts (stacks longue durée sur les DEUX camps, vides après victoire, journal) ; nœud Combat (suspension réelle : déplacement refusé, nœud non résolu avant victoire, signal `combat_demarre`, reprise après) ; attaque surprise (« ? » forcé → malus ×1.5 sur le moteur + payload `combat.embuscade`) ; PV persistants (avatar lent → dégâts garantis au combat 1, entame du combat 2 exactement aux PV sortants) ; défaite (avatar moribond → `defaite=true/complete=false/extraction=false/nb_combats=1`, nœud non résolu, déplacements coupés) ; agrégat (9 nœuds intérieurs 100 % Combat × 2 ennemis = 18 `CombattantCtbData` au recap) ; pondération 50/35/15 (3 000 tirages, ±5 pts) ; stubs Coffre/Bénédiction/Piège inchangés (aucun combat, payload sans clé `combat`).

Contrôle visuel (captures `tests/_shot_expe_init.png` / `_shot_expe_explore.png`, sandbox réel) : combats contre le bestiaire (Rat des Égouts, Grenouille Géante) joués et journalisés à l'entrée des nœuds, PV persistants visibles dans l'en-tête (« PV 10/100 ») et repris d'un combat à l'autre (victoire à 34 PV → combat suivant entamé à 34), « ? » → Piège résolu en stub.

## 6. Questions ouvertes

1. **Tirage dans le pool** : uniforme avec remise (3 fois la même créature possible dans un combat). OK, ou prévoir une pondération par créature dans `PoolEnnemisData` (et/ou un « sans remise ») ?
2. **`pv_restants` du recap moteur est indexé par id de données** : deux ennemis issus de la même créature s'y écrasent (seule l'entrée de l'avatar est consommée aujourd'hui). À durcir si un chantier futur veut les PV par instance d'ennemi.
3. **Valeur du malus d'embuscade** (×1.5 sur la première horloge) : forme actée, valeur provisoire — calibrage en playtest ?
4. **Défaite = nœud non résolu** : sans enjeu tant que défaite = fin d'expédition ; si une mécanique de fuite/survie apparaît, décider si le nœud redevient déclenchable.
5. **Avatar injecté dans ExpeRun** : le sandbox utilise `data/combat_ctb/avatar.tres` (factice). Le vrai héros (stats + équipement + passifs → CombattantCtbData, probablement via un CtbPont étendu) arrive avec quel chantier ?
