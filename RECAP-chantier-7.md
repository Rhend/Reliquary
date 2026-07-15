# RECAP — Chantier 7 : Nœuds réels — Bénédictions, Pièges, Coffres et consommables

Branche : `ReworkCombat`. **Fin des stubs d'expédition.** Définitions actées 06/07/2026 appliquées : **Bénédiction = affixe positif pour la durée de la run · Piège = affixe négatif pour la durée de la run · Coffre = consommables utilisables durant la run**. L'action **Objet** du moteur CTB devient fonctionnelle. Tout est provisoire, data-driven en `.tres`, marqué à calibrer.

## 1. Implémenté

- **§1 Affixes de run** : `AffixeData` (bonus % par stat — clés = noms de stats de `CombattantCtbData` —, flag positif/négatif, `resume()` lisible « +15 % ATK »). Actif de l'acquisition à la fin de l'expédition, **purge systématique à toutes les sorties** (extraction, complétion, défaite — journalisée ; le recap garde les ids). Application : ajoutés au **Σ bonus % du combattant joueur à chaque création de combat** (`ExpeRun._lancer_combat` — le combattant est déjà recréé à chaque nœud, donc un affixe acquis en cours de run compte dès le combat suivant, et un affixe pris avant le premier combat compte immédiatement). **Cumul additif universel** inchangé, doublons permis (deux Surtension = ×1.30, pas 1.15²). Pool provisoire : 8 `.tres` (`data/expedition/affixes/`) — Surtension +15 % ATK, Blindage renforcé +15 % DEF, Overclock +10 % VIT, Châssis consolidé +10 % PV max ; Corrosion −10 % DEF, Parasitage −10 % ATK, Servos grippés −8 % VIT, Fuite d'énergie −8 % PV max (noms libres à la relecture DA). Nœud Bénédiction (« ? ») : tirage uniforme du pool positif, annoncé (popup placeholder + journal) ; Piège : idem négatif, subi. **PV max modifié en cours de run** : PV courants conservés en **absolu**, clampés si le pv_max effectif descend (`ajouter_affixe` + à la création de combat ; `pv_max_effectif()` exposé pour l'affichage) — règle la plus simple, sans trancher le point ouvert des niveaux. Affixes **visibles en permanence** (ligne dédiée du sandbox, résumés inclus).
- **§2 Consommables de run** : `ConsommableData` (effet typé `Enums.EffetConsommable`, valeur). Acquis en run, **perdus en fin de run, extraction comprise** (purge avec les affixes). Inventaire de run dans `ExpeRun.inventaire`, **cap en config (0 = illimité, défaut)** — l'excédent d'un coffre est perdu (journalisé). Pool provisoire (`data/expedition/consommables/`) : **Bombe** (`50 × (1 + Σ bonus % ATK du porteur)`, **ignore la DEF**) et **Injection nano-soigneur** (**30 % des PV max**, clampé). **Usage en combat uniquement** : l'action **OBJET** du moteur consomme l'activation (`CtbMoteur._resoudre_objet` — le moteur reste **agnostique de l'inventaire**, qui appartient à l'appelant via `ExpeRun.consommer()`). UI : le bouton Objet **n'EXISTE que si l'inventaire de run est non vide** (créé/retiré à chaque tour joueur — pilier « contenu absent, pas grisé » ; il disparaît quand l'inventaire se vide) ; choix de l'objet (doublons regroupés « ×n ») puis de la cible si l'effet en demande une (boutons + clic sur la carte ennemie, Annuler). Nouveau pattern de branchement : `inventaire_fournisseur` / `sur_objet_utilise` (Callables — l'écran reste générique).
- **§3 Résolution des nœuds** : Coffre (nœud direct ou « ? »), Bénédiction et Piège résolus **réellement** (`_resoudre_coffre` / `_resoudre_affixe`) ; le « ? » conserve sa table 25/25/25/25 (`config_carte.tres` intact). `expe_noeud_resolu` porte le contenu obtenu (clé `contenu` : `affixe_id`+`positif`+`resume`, ou `consommable_ids`) — l'ex-`_resoudre_stub` devient le finaliseur générique `_finaliser_noeud(nd, extra)`. Recap étendu : `affixes` (actifs en fin de run), `consommables_obtenus`, `consommables_utilises` (ids).
- **§4 Données** : `AffixeData`, `ConsommableData`, `ExpeNoeudsConfigData` (pools extensibles, `poids_nb_consommables` {1: 0.6, 2: 0.4}, `cap_inventaire`) — headers `type="Resource" script_class="…"`, aucune valeur en dur. Config par défaut `data/expedition/config_noeuds.tres`, remplaçable sur la run avant `demarrer()` (tests).
- **§5 Sandbox** : ligne permanente « Affixes : … (résumés) · Objets : … ×n », en-tête PV sur `pv_max_effectif()`, popups placeholder (texte flottant central : ✨ vert bénédiction / ☒ rouge piège / 🧰 or coffre) via `noeud_resolu`, Callables d'inventaire branchées sur l'écran de combat.

## 2. Écarts / interprétations (aucun silencieux)

- **« Σ bonus % ATK du héros » (Bombe)** : interprété comme le Σ des bonus % **portés par le combattant CTB** (= les affixes de run — les % permanents village/Forge sont déjà cuits dans l'ATK nue du transitoire par le pont, ils ne sont pas re-comptables au moteur sans le coupler à l'expédition). Provisoire, à calibrer ; c'est le seul sens implémentable sans casser la frontière moteur/expédition.
- **Bénédiction/Piège n'existent que comme contenus de « ? »** (pas de nœud direct — `Enums.TypeNoeud` n'a jamais eu ces types) : conforme à l'existant chantier 2, aucun nouveau type de nœud créé.
- **Popup placeholder** : texte flottant central (sandbox) plutôt qu'une boîte modale — annonce + journal détaillé, DA hors scope.

## 3. Décisions techniques prises

- **L'inventaire vit dans ExpeRun, le moteur reste agnostique** : `_resoudre_objet` résout l'effet de l'objet qu'on lui tend ; le décrément passe par `ExpeRun.consommer()`, appelé par l'UI **au moment de la validation** de l'action (`_valider_action`). Testable sans UI (les tests moteur tendent l'objet directement).
- **Bouton Objet : existence conditionnelle, pas visibilité** — le nœud Button n'est pas dans l'arbre quand l'inventaire est vide (l'assertion « aucun bouton Objet » du chantier 5 reste **forte** : elle scanne tous les Buttons, visibles ou non, sans inventaire).
- **`_finaliser_noeud(nd, extra)`** remplace `_resoudre_stub` (les stubs n'existent plus) : payload générique fusionné (`combat` ou `contenu`), signaux inchangés.
- **Clamp PV à double détente** : à l'acquisition d'un affixe (`ajouter_affixe` — visible immédiatement dans l'en-tête) ET à la création de combat (`minf(pv_avatar, stat_finale("pv_max"))`) — idempotent.
- **`cfg_noeuds` = var à défaut versionné** (pas un 8e paramètre de constructeur) : remplaçable avant `demarrer()`, même pattern que `CtbMoteur.config`.
- Test moteur Bombe sur fraction binaire exacte (+50 %) : `50 × 1.15` vaut 57.499999… en flottant (arrondi 57, pas 58) — le comportement du moteur est correct, le seuil de test évitait d'être un pile-ou-face IEEE.

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/AffixeData.gd`, `ConsommableData.gd`, `ExpeNoeudsConfigData.gd`
- `data/expedition/affixes/` (8 `.tres`), `data/expedition/consommables/` (2 `.tres`), `data/expedition/config_noeuds.tres`
- `tests/TestExpeNoeuds.gd` + `.tscn` — nouvelle suite (en CI)

**Modifiés**
- `scripts/resources/Enums.gd` — `EffetConsommable`
- `systems/combat_ctb/ctb_moteur.gd` — action OBJET (`_resoudre_objet`), événement `objet`
- `systems/combat_ctb/ctb_combattant.gd` — `somme_bonus_pct()`
- `systems/expedition/expe_run.gd` — affixes, inventaire, résolutions réelles, purge, recap/payloads étendus
- `scenes/combat_ctb/CombatCtbUi.gd` — bouton Objet conditionnel, choix objet/cible, flottants, Callables
- `scenes/expedition/SandboxExpe.gd` — ligne affixes/objets, popups placeholder, `pv_max_effectif`, branchements
- `scripts/autoloads/Translations.gd` — `ctb.objet`, `ctb.choisir_objet` (FR + EN)
- `tests/TestCombatCtb.gd` (+8), `tests/TestCombatUi.gd` (+7), `tests/ScreenshotTool.gd` (mise en scène)
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 6 + addendum, décomptes runtime) : ScriptsLoad 113, CTB 55, CombatUi 14, Recompenses 48, ExpeCarte 39, ExpeCombat 45.**

Ce chantier :
- `TestExpeNoeuds` **24** (nouvelle suite, en CI) — affixe appliqué au combattant du combat suivant (ATK 200 → 230 exact, VIT 60 → 55.2, positif et négatif coexistent), cumul additif de deux affixes identiques (260, pas 1.15²), Bénédiction obtenue / Piège subi via de **vrais** nœuds « ? » forcés (payload `contenu` vérifié), PV absolus conservés quand pv_max monte / clampés quand il descend (100 → 80, additif +10 −30), Coffre crédite l'inventaire (poids {2: 1} → 2), cap = excédent perdu, `consommer()` (décrément, doublons distincts, absent → false, trace au recap), purge aux **trois** sorties ;
- `TestCombatCtb` **63** (+8) — Bombe : dégâts exacts `50 × (1 + Σ atk %)`, DEF ignorée, activation consommée, événement `objet` ; Nano-soigneur : 30 % pv_max, clamp au max ; OBJET sans objet = activation perdue proprement ;
- `TestCombatUi` **21** (+7) — bouton Objet EXISTE au tour du joueur si inventaire non vide, rangée de choix d'objet, Bombe jouée via l'UI (50 dégâts, DEF ignorée), `sur_objet_utilise` décrémente, bouton **disparu** à inventaire vide (aucun nœud résiduel dans l'arbre), combat terminé proprement ;
- `TestScriptsLoad` **117/117** (+4 : AffixeData, ConsommableData, ExpeNoeudsConfigData, TestExpeNoeuds) ;
- suites inchangées toutes vertes : Recompenses 48, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, TierCap 22, Drops 29, Forge, VillageBuildings, HoloXlsx, HoloTraffic ; **boot sans erreur**.

Contrôle visuel (rendu réel, `SHOT_MODE=expe`) : ligne « Affixes : Parasitage (−10 % ATK), Surtension (+15 % ATK), Corrosion (−10 % DEF) · Objets : Bombe ×2 » — le **Parasitage a été subi NATURELLEMENT** via un « ? » Piège pendant la marche de capture (flux réel constaté en rendu), popup flottante visible.

## 6. Questions ouvertes

1. **Cible du scaling de la Bombe** : Σ % du combattant CTB (affixes de run) — si le design veut TOUS les % du héros (village/Forge), il faudra passer l'info au moteur (couplage à arbitrer).
2. **Cap d'inventaire** : 0 (illimité) par défaut — une valeur réelle viendra avec le puits d'Euren (achat de consommables) ?
3. **Excédent de coffre perdu** (cap atteint) : ou faut-il empêcher le tirage / proposer un choix ? Provisoire assumé.
4. **Affixes et prédiction de file** : un affixe VIT modifie l'ordre — la file prédite le reflète déjà (VIT courante), rien à faire ; consigné pour mémoire.
5. **Popup placeholder** (texte flottant) : suffisant jusqu'à la DA, ou une vraie modale d'annonce dès le prochain chantier UI ?
