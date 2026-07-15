# RECAP — Chantier 6 : Économie de récompense — XP et Euren

Branche : `ReworkCombat`. Gagner un combat rapporte désormais : **XP de niveau du héros** (système RPG classique, acté 06/07/2026 — créditée **immédiatement à chaque victoire**) et **Euren** (monnaie commune, actée 06/07/2026 — accumulé en run, **crédité à la sortie d'expédition uniquement**, défaite = rien). Toutes les valeurs sont **provisoires, data-driven en `.tres`, à calibrer**. Consommables de Coffre et Bénédiction/Piège réels : hors scope (chantier suivant).

## 1. Implémenté

- **§1 XP du héros** : chaque ennemi vaincu rapporte son `xp_reward` du bestiaire (**lu tel quel** dans `stats_par_palier` au palier de Maîtrise courant de la créature — champ absent → 0, pas le défaut 10 hérité de la boucle idle). Crédit **immédiat à la victoire de chaque combat** (`ExpeRun._crediter_victoire` → `ProgressionHeros.gagner_xp`) ; la montée de niveau en cours de run est possible et journalisée (« ⭐ Niveau 1 → 2 »). Courbe et gains en `.tres` (`data/progression/heros_progression.tres`) : seuil d'XP **totale cumulée** pour atteindre le niveau n = `round(100 × n^1.5)`, niveau plancher 1, l'XP ne se perd jamais (règle projet) ; gains plats par niveau au-delà du 1er : +2 PV max, +1 ATK, +0.5 DEF, +0.5 VIT (fractions cumulées, jamais arrondies dans les données). Les bonus s'injectent dans `CtbPont.combattant_depuis_heros()` **à la même position que les autres plats, AVANT les %** — l'empilement additif universel est inchangé. Niveau **dérivé** de l'XP totale (aucun champ redondant) ; XP persistée via `GameData.player["heros_xp"]` (auto).
- **§2 Euren** : `euren = base (10) × multiplicateur du palier de Maîtrise de la créature` — le calcul vit dans la **config** (`data/progression/euren.tres`, multiplicateurs ×1…×6, progression simple provisoire), **aucun champ au bestiaire** (il sera remplacé). Accumulé dans la run (`euren_accumule`, visible en permanence au sandbox), **crédité à la sortie seulement** : extraction et complétion créditent, **défaite ne crédite rien** (l'accumulé est perdu ; l'XP déjà créditée aux victoires précédentes reste acquise). Persisté via `GameData.player["euren"]` (auto). Aucun puits de dépense (hors scope).
- **§3 Recap et signaux** : recap d'expédition étendu — `xp_gagnee` (total run, information), `euren_gagne` (accumulé), `euren_credite` (0 si défaite). Nouveaux signaux EventBus : `heros_xp_gagnee(montant, totale)`, `heros_niveau_change(avant, apres)` (la future UI), `euren_change(total)` — tous trois déclencheurs de sauvegarde.
- **§4 Affichage sandbox (placeholder)** : en-tête de run « Nv 1 · XP 30/283 · Euren (run) 40 » (+ « crédité : n » en fin de run) ; l'écran d'issue de bataille du chantier 5 affiche « +X XP · +Y Euren » via `CombatCtbUi.recompenses_fournisseur` (Callable optionnelle — l'écran reste générique, il ne connaît ni l'expédition ni l'économie) ; ligne de journal de montée de niveau.
- **§5 Données** : `ProgressionHerosData` + `EurenConfigData` (headers `type="Resource" script_class="…"`), instances dans `data/progression/`. Aucune valeur en dur ; logique dans `ProgressionHeros` (class_name statique, pattern Balance — pas d'autoload ajouté).

## 2. Écarts / interprétations (aucun silencieux)

- **« XP requise pour atteindre le niveau n »** interprétée comme un seuil d'XP **TOTALE CUMULÉE** (formule littérale : atteindre n exige `round(100 × n^1.5)` d'XP totale), pas un coût par niveau. Conséquence : niveau 2 à 283 d'XP totale, niveau 3 à 520, niveau 4 à 800. Testé sur ces seuils exacts ; **à confirmer au calibrage** (question ouverte n° 1).
- **« Le nouveau niveau compte au prochain combat »** : en l'état il compte au prochain **LANCEMENT d'expédition** — cohérent avec « construit au lancement » (chantier 4) ; le combattant d'une run en cours ne change ni à chaud ni entre les nœuds (testé). **Recalcul entre nœuds : analysé, NON implémenté** (demandé par la spec) — cf. § 3.
- **Test « suites existantes intactes »** : intactes fonctionnellement, mais TestExpeCarte / TestExpeCombat reçoivent le bloc standard de **déconnexion des déclencheurs de sauvegarde** (leurs victoires d'ExpeRun émettent désormais des signaux de progression — règle : un test n'écrit jamais la sauvegarde). Aucune assertion existante modifiée.
- **Baseline TestCombatUi** : 13 → **14** (+1 : récompenses sur l'écran d'issue — non exigée par la spec de test, ajoutée pour couvrir le §4).

## 3. Décisions techniques prises

- **Recalcul entre nœuds (analyse demandée, sans implémentation)** : `ExpeRun._lancer_combat` recrée déjà un `CtbCombattant` neuf à chaque nœud depuis `avatar_data` — reconstruire `avatar_data` via `CtbPont.combattant_depuis_heros()` à chaque combat serait ~4 lignes + un flag « l'avatar est le vrai héros ». **Le point non trivial** : les PV persistants (`pv_avatar`) sont absolus — un `pv_max` qui monte en cours de run oblige à choisir (conserver les PV absolus ? au prorata ? soigner du delta ?). C'est un choix de design, pas de code — d'où l'arbitrage « au prochain lancement » conservé tel quel.
- **Niveau dérivé de l'XP totale** (jamais stocké) : une seule source de vérité, pas de drift possible entre XP et niveau ; la détection de montée = comparaison avant/après crédit.
- **`SaveManager.signaux_progression()`** : la liste des déclencheurs de sauvegarde devient une **source unique** (elle était dupliquée en dur dans ScreenshotTool, TestForge, TestVillageBuildings — toute nouvelle entrée l'aurait rendue fausse). Les 3 sites + les 2 suites d'expédition itèrent cette liste.
- **SandboxExpe déconnecté des déclencheurs de sauvegarde** : le sandbox charge la vraie sauvegarde (héros réel) — sans garde-fou, un playtest y aurait **écrit l'XP/Euren de test dans la sauvegarde du joueur**. Règle projet appliquée (outil = jamais d'écriture) ; la persistance réelle viendra avec le branchement au flux de jeu principal (question ouverte n° 3).
- **Ennemi hors bestiaire** (combattant fabriqué en test) → aucune récompense, silencieusement (l'économie est indexée sur le bestiaire tant qu'il existe).
- **Défaite** : les ennemis tués dans le combat PERDU ne rapportent rien (l'XP n'est créditée qu'à la **victoire**) — ils restent listés dans `ennemis_vaincus` du recap (information existante du chantier 3).
- **Multiplicateur de palier de profondeur** (`PalierProfondeurData`) : toujours **sans effet** — il ne s'applique pas aux récompenses (mécanisme non décidé, statu quo chantier 2).

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/ProgressionHerosData.gd` + `data/progression/heros_progression.tres` — courbe (base 100, exposant 1.5) + gains par niveau
- `scripts/resources/EurenConfigData.gd` + `data/progression/euren.tres` — base 10 + multiplicateurs par palier (×1…×6)
- `scripts/autoloads/ProgressionHeros.gd` — niveau/XP/Euren (class_name statique, état dans GameData.player)
- `tests/TestRecompenses.gd` + `.tscn` — nouvelle suite (en CI)

**Modifiés**
- `scripts/autoloads/EventBus.gd` — `heros_xp_gagnee`, `heros_niveau_change`, `euren_change`
- `scripts/autoloads/GameData.gd` — `player.heros_xp` / `player.euren` (persistance auto)
- `scripts/autoloads/SaveManager.gd` — `signaux_progression()` (source unique) + 3 nouveaux déclencheurs
- `systems/combat_ctb/ctb_pont.gd` — bonus plats de niveau dans l'agrégation héros (avant les %)
- `systems/expedition/expe_run.gd` — crédit XP à la victoire, Euren accumulé/crédité, recap étendu, journal
- `scenes/combat_ctb/CombatCtbUi.gd` — `recompenses_fournisseur` (écran d'issue enrichi)
- `scenes/expedition/SandboxExpe.gd` — en-tête niveau/XP/Euren, fournisseur de récompenses, déconnexion sauvegarde
- `scripts/autoloads/Translations.gd` — `ctb.recompenses`, `ctb.entete_heros` (FR + EN)
- `tests/ScreenshotTool.gd`, `tests/TestForge.gd`, `tests/TestVillageBuildings.gd` — liste des signaux via `signaux_progression()`
- `tests/TestExpeCarte.gd`, `tests/TestExpeCombat.gd` — déconnexion des déclencheurs (nouveaux signaux)
- `tests/TestCombatUi.gd` — +1 assertion (récompenses sur l'issue)
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 5, décomptes runtime) : ScriptsLoad 109, CTB 55, CombatUi 13, ExpeCarte 39, ExpeCombat 45.**

Ce chantier :
- `TestRecompenses` **48** (nouvelle suite, en CI) — courbe : seuils exacts (283/520/800), plancher niveau 1, multi-niveaux en un gain (1 → 4 pour +700), signaux (xp émis, niveau non émis sous le seuil, `heros_niveau_change(1,4)` une fois) ; pont : deltas exacts +3×gain × (1+pct) sur PV/ATK/DEF/VIT (fractions non arrondies), crit inchangé ; expédition : XP créditée immédiatement = Σ `xp_reward` des vaincus (recalcul indépendant), Euren accumulé = Σ base×mult (config), **pas crédité en cours de run**, `dernier_combat_recompenses` (écran d'issue) ; pas-à-chaud : combattant de run inchangé après niveau up, pont reconstruit au lancement suivant le reflète, journal « Niveau 1 → 2 » ; les trois sorties : défaite = 0 crédité + accumulé perdu + XP conservée, extraction crédite (signal `euren_change` une fois), complétion crédite en flux réel 3 étages ; persistance : round-trip `_save_player`/`_load_player` sans disque, niveau re-dérivé (520 → 3) ;
- `TestCombatUi` **14** (+1 : « +30 XP · +20 Euren » affiché sur l'écran d'issue) ;
- `TestScriptsLoad` **113/113** (+4 : ProgressionHerosData, EurenConfigData, ProgressionHeros, TestRecompenses) ;
- suites inchangées toutes vertes : CTB 55, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, TierCap 22, Drops 29, Forge, VillageBuildings, HoloXlsx, HoloTraffic ; **boot sans erreur**.

Contrôle visuel (rendu réel, `SHOT_MODE=expe`) : en-tête « Étage 1/3 — PV 97/150 · Nv 1 · XP 30/283 · Euren (run) 40 », journal « ✧ +10 XP (héros : 30 / 283) », « ◈ +10 Euren (run : 40 — crédité à la sortie) ».

## 6. Questions ouvertes

1. **Interprétation de la courbe** : seuil d'XP totale cumulée (choisi, formule littérale) vs coût par niveau — à confirmer au calibrage (les deux se règlent dans le même `.tres`).
2. **Recalcul du combattant entre nœuds** (niveau up « au prochain combat » au sens strict) : le code est trivial, le design des PV persistants face à un `pv_max` qui monte ne l'est pas — trancher à quel chantier ?
3. **Persistance depuis le sandbox** : déconnectée par sécurité (outil). Le playtest actuel ne fait donc pas progresser la vraie partie — assumé jusqu'au branchement au flux principal ?
4. **Multiplicateurs Euren** ×1…×6 linéaires et base 10 : purement provisoires ; le multiplicateur de palier de PROFONDEUR (expédition) doit-il un jour s'appliquer aux récompenses ?
5. **Affichage des fractions** (DEF/VIT +0.5/niveau) : l'agrégation reste en float (voulu) ; la dette d'affichage HeroPanel (chantier 4, question 5) englobera l'arrondi de présentation.
