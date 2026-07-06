# RECAP — Chantier 4 : Pont héros réel → combat CTB

Branche : `ReworkCombat`. Le camp joueur des combats CTB d'expédition passe de l'avatar factice au **vrai héros du jeu** : stats effectives complètes, équipement compris (arbitrage acté 06/07/2026). Extension de `CtbPont`, philosophie du chantier 3 conservée : lecture telle quelle, source unique, transitoire jamais sauvé, aucun rééquilibrage.

## ⚠ Constat structurant (écart à la spec, documenté — pas silencieux)

La spec demandait de **consommer** « la source unique existante d'agrégation des stats effectives du héros — celle que l'ancien moteur consomme ». Cette source **n'existe plus** : l'agrégation vivait dans `combat_player.start_combat()` et a été **supprimée avec l'ancien moteur** (commit `8d8f920`, suppression sèche actée). Il ne survit que des briques partielles :
- `GameData.get_effective_stats("hero")` — stats NUES par palier (tables `Balance.HERO_*_PER_TIER`) ;
- `GameData.get_equipment_bonuses()` / `PassiveSystem.get_combat_bonuses()` — bonus PLATS ;
- `VillageBuildings.get_bonus(CH_*_PCT)` / `ForgeSystem.get_stat_bonus(*_pct)` — bonus % ;
- `AdventureSystem.get_max_hp()` — la formule complète, mais pour les seuls PV ;
- `HeroPanel` — une agrégation d'AFFICHAGE partielle (plats seulement, % village/forge absents sauf crit).

**Décision** : `CtbPont.combattant_depuis_heros()` **reconstruit l'agrégation à l'identique** (formule extraite de l'historique git de `combat_player.start_combat()`, vérifiée ligne à ligne) et devient la **nouvelle source unique**. C'est « la bonne » au sens de la spec parce que c'est littéralement celle de l'ancien moteur : stat nue + bonus plats (équipement, passifs), puis × (1 + Σ bonus %) via StatStacker (village + Forge, empilement additif, jamais de produit séquentiel) — le même pipeline que `get_max_hp()` applique aux PV.

## 1. Implémenté

- **§1 Pont héros** : `CtbPont.combattant_depuis_heros()` → `CombattantCtbData` transitoire (id `hero`, noms de l'entité), construit au **lancement de l'expédition** — un changement d'équipement compte au prochain lancement, jamais en cours de run. Équipement inclus (plats atk/def/hp + `attack_speed_pct` → % VIT, comme dans l'ancien moteur).
- **§2 PV à l'entrée** : provisoire conservé — PV pleins au lancement (`ExpeRun.demarrer`), persistance intra-expédition du chantier 3 inchangée.
- **§3 Ce qui ne passe pas le pont** : cf. tableau « laissé derrière » ci-dessous — seuls les bonus de STATS passent, tout le reste est tracé en tête de `ctb_pont.gd`.
- **§4 Branchement** : `ExpeRun` inchangé (l'injection du chantier 3 était prête, seul l'appelant change). `SandboxExpe` : **héros réel par défaut** (checkbox « Héros réel » ; décochée → avatar factice `avatar.tres`, conservé tel quel) ; lancé seul (F6), le sandbox **charge la sauvegarde** pour refléter la vraie partie (`SaveManager.est_chargee()`, nouvel accesseur public — jamais de rechargement par-dessus une partie en cours ; le sandbox n'émet aucun signal de progression, donc aucune écriture possible).
- **§5 Livrables** : stats du héros visibles au journal de la run (`✦ Héros — PV 150, ATK 61, DEF 16, VIT 23, crit 6 % ×1.80`) ; +5 assertions dans `TestExpeCombat` (45 au total).

## Mapping champ à champ héros → CTB (même format que le chantier 3)

| Source (agrégation reconstruite) | CTB |
|---|---|
| (hp nue + `passifs.hp_bonus` + `équip.hp`) × (1 + hp_pct village+forge) | `pv_max` |
| (atk nue + `passifs.atk_bonus` + `équip.atk`) × (1 + atk_pct) | `atk` |
| (def nue + `passifs.def_bonus` + `équip.def`) × (1 + def_pct) | `def` |
| vit nue × (1 + `équip.attack_speed_pct`/100 + forge `atb_pct`) | `vit` |
| crit nue + (village `crit_pct` + forge `crit_pct`) — en POINTS, non clampé (verbatim ancien moteur) | `crit_chance` |
| crit_multiplier nue | `crit_multiplier` |
| id `hero`, `nom_affichage_fr/en` de l'entité | idem |

**Laissé derrière** (volontairement, documenté en tête de `ctb_pont.gd`) :
- `GameData.get_mastery_combat_bonus(enemy_id)` — bonus plat d'ATK par familiarité avec **l'ennemi** : dépend de chaque combat, impossible à figer dans un combattant construit au lancement de l'expédition (à réintroduire côté moteur si le design le confirme) ;
- `atk_mult` / `def_mult` — modificateurs de **cycle** de la boucle idle (AdventureSystem), étrangers à l'expédition free-roam ;
- `ForgeSystem.combat_rules()` — effets de **règle** Forge (def_ignore, gauge_start, crit_mult, cond_atk_hp_above, residual), pas des stats (§3 de la spec) ;
- poison passif on-hit (`PassiveSystem.get_passive_combat_effects`) — effet non-stat (§3).

## 2. Écarts à la spec

- **La source à consommer n'existait plus** (cf. constat en tête) : reconstruite verbatim au lieu d'être consommée — c'est le seul écart, et il est structurel, pas fonctionnel : les chiffres sont ceux que l'ancien moteur aurait produits, hors éléments par-combat listés ci-dessus.

## 3. Décisions techniques prises

- **La source unique vit dans CtbPont** (pas dans GameData/AdventureSystem) : c'est le seul consommateur combat aujourd'hui. `AdventureSystem.get_max_hp()` (PV seuls, boucle idle) et l'affichage `HeroPanel` ne sont PAS touchés — hors scope, mais cf. question ouverte n° 5 sur leur alignement futur.
- **`SaveManager.est_chargee()`** : accesseur public en lecture pour que le sandbox charge la sauvegarde une seule fois, sans exposer l'état interne en écriture.
- **Fallback sûr au sandbox** : héros introuvable (`null`) → avatar factice, jamais de crash d'outil de dev.
- **Stats du combattant joueur loggées par `ExpeRun.demarrer()`** (pas par le sandbox) : visibles aussi dans les tests et pour toute future UI.

## 4. Fichiers créés / modifiés

**Créés** — aucun (extension de fichiers existants ; compteur ScriptsLoad inchangé).

**Modifiés**
- `systems/combat_ctb/ctb_pont.gd` — `combattant_depuis_heros()` + documentation source/mapping/laissé derrière
- `systems/expedition/expe_run.gd` — ligne de journal avec les stats complètes du combattant joueur
- `scripts/autoloads/SaveManager.gd` — accesseur `est_chargee()`
- `scenes/expedition/SandboxExpe.gd` — checkbox Héros réel (défaut) / factice, chargement de la sauvegarde, PV max affichés depuis `run.avatar_data`
- `tests/TestExpeCombat.gd` — `_test_pont_heros()` (+5 assertions)
- `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 3 + addendum) : ScriptsLoad 105, CTB 33, ExpeCarte 39, ExpeCombat 40.**
Ce chantier : `TestExpeCombat` **45/45** (+5 : pont héros) ; ScriptsLoad **105/105 inchangé** (aucun nouveau script) ; CTB 33 et ExpeCarte 39 inchangés ; toutes les autres suites vertes (ExpeditionFlow 28, TierCap 22, Drops 29, Holo ×2) ; boot sans erreur. Aucun autre compteur n'a bougé.

Vérifié par assertions : héros CTB identique champ à champ à l'agrégation **recalculée indépendamment dans le test** depuis les mêmes systèmes (sans équipement PUIS avec Lame de Pierre + Anneau de Forêt — ATK et VIT changent au lancement suivant) ; identité (id `hero`, nom de l'entité) ; avatar factice `avatar.tres` disponible et inchangé (valeurs versionnées). **Indépendance vis-à-vis de la sauvegarde locale** : les tests ne chargent jamais la sauvegarde et manipulent `GameData.player["equipped"]` en direct (aucun signal → aucune écriture possible), état remis en place strictement ; les suites existantes injectent déjà leurs propres avatars.

Contrôle visuel (captures sandbox, `tests/_shot_expe_init.png`) : expédition lancée avec le héros réel de la sauvegarde locale — journal « ✦ Héros — PV 150, ATK 61, DEF 16, VIT 23, crit 6 % ×1.80 » (distinct du factice 100/20/5/20 : équipement et progression comptent), en-tête « PV 150/150 », checkbox « Héros réel » cochée.

## Addendum — Arbitrages design validés (06/07/2026)

Les 5 questions ouvertes ci-dessous ont été tranchées (une seule modification de code : point 4) :
1. Bonus de familiarité : **non réintroduit** — devenir post-pivot non designé, parké ; réintroduction éventuelle décidée avec le rework des bonus.
2. Effets de règle Forge : chantier dédié ultérieur, rien à faire.
3. Poison passif on-hit : rattaché au futur chantier fonctions bâtiments/passifs, via le hook `StatutCtbData`.
4. **Clamp `crit_chance` [0;1] implémenté au niveau du moteur, AU MOMENT DU JET** (`CtbMoteur._resoudre_attaque`) — la donnée reste non clampée (un excès reste visible dans les stats). +2 assertions : `TestCombatCtb` passe de 33 à **35** (crit 5.0 → 100 % au jet ; crit négative → 0 %). Suites revalidées, tout vert.
5. HeroPanel : dette consignée, alignement sur la source unique au chantier UI.

L'écart documenté (source d'agrégation reconstruite dans CtbPont) est validé tel quel. Baseline après ce chantier + addendum : **ScriptsLoad 105, CTB 35, ExpeCarte 39, ExpeCombat 45**.

## 6. Questions ouvertes

1. **Bonus de familiarité** (`get_mastery_combat_bonus`, plat d'ATK par ennemi rencontré) : le seul bonus de stats de l'ancien moteur qui ne peut pas passer un pont figé au lancement. Le réintroduire côté moteur CTB (bonus par combat) — et à quel chantier ?
2. **Effets de règle Forge** (def_ignore, gauge_start, crit_mult, Saignée…) : pensés pour l'ATB temps réel. À re-designer pour le CTB (gauge_start ≈ horloge initiale réduite ? crit_mult où ?) — chantier dédié ?
3. **Poison passif on-hit** (Contact Venimeux) : candidat naturel au hook statuts DoT data-driven du CTB (`StatutCtbData`). Quand ?
4. **`crit_chance` non clampé** (verbatim ancien moteur : base + points village/forge, ni plancher ni plafond). Un clamp \[0;1\] est-il souhaité au niveau du moteur ?
5. **`HeroPanel` affiche une agrégation partielle** (plats seulement ; % village/forge absents sauf crit) : l'écran Héros sous-affiche les stats réelles de combat. Aligner l'affichage sur `CtbPont.combattant_depuis_heros()` (la source unique) — quel chantier ?
