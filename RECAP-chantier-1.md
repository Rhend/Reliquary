# RECAP — Chantier 1 : Moteur de combat tour par tour (squelette)

Branche : `ReworkCombat`. Moteur livré seul, testable en scène isolée, sans expédition ni UI finale.

## 1. Implémenté

- **§1 Initiative CTB** : horloge logique pure (aucun temps réel, aucun timer). `prochaine_action = K / VIT` avec `K = Balance.CTB_K = 1000` (exposée pour calibrage). Activation du plus bas ; réarmement `+= K / VIT courante` → un buff VIT en cours de combat agit dès le réarmement suivant. VIT double = deux activations pour une (testé). Égalité d'horloge : camp joueur d'abord — Avatar, puis pets par ordre de liste, puis ennemis par ordre de liste (testé).
- **§2 Activation = 1 action** : trois types prévus dans l'architecture (`Enums.ActionCtb.ATTAQUER / COMPETENCE / OBJET`), seul ATTAQUER est fonctionnel. Compétence/Objet : aucune UI, aucun contenu — le moteur les accepte et consomme l'activation avec un log « non implémenté » (aucun bouton n'existera tant que le contenu n'existe pas). Le moteur est **pull-based** (`activer_suivant()` puis `jouer(action)`) : l'input joueur peut attendre indéfiniment entre les deux, tous les autres combattants sont en attente.
- **§3 Dégâts** : `ATK × (1 − 0.5 × DEF / (DEF + 40))` via `Balance.mitigated_damage` (formule héritée déjà en place, constantes `DEF_REDUCTION_CAP/HALF` inchangées), jet de crit par coup (`Crit%` → `× CritMult`), arrondi entier, plancher `Balance.MIN_DAMAGE`. Stats finales = `StatStacker.final_stat` (cumul additif universel, règle inchangée).
- **§4 Statuts DoT** : hook générique data-driven (`StatutCtbData` : timing début/fin, `stacks_max`, `duree_activations`, `degats_pct_atk` du poseur). Durée en activations de la cible, décrémentée à chaque tick. Timing DÉBUT (Saignement) et FIN (Poison/Brûlure) implémentés et testés. **Poison** seul doté de valeurs (`data/combat_ctb/statut_poison.tres`) : 5 % ATK poseur / stack / tick, max 3 stacks, cumul additif des stacks parallèles, durée **2 activations par stack — provisoire, à recalibrer** (transposition de l'ancien temps réel). Brûlure et Saignement : hook posé, **aucun .tres créé** (rien inventé ; le timing DÉBUT est testé avec un statut synthétique de test).
- **§5 Camps** : architecture N-vs-N (jusqu'à 3 par camp côté contenu ; le moteur ne borne pas en dur côté joueur, le sandbox borne l'adverse à 3). Contenu livré : Avatar seul vs 1-3 ennemis factices. Rangées statiques implicites : aucun positionnement, aucune notion front/arrière.
- **§6 Fins** : PV Avatar à 0 → défaite **immédiate** (même si des pets vivaient), signal seul (sanction hors scope). Tous ennemis à 0 → victoire + `_hook_post_victoire()` vide (point de rebranchement de l'ex-régen). Signaux : locaux (`victoire`/`defaite` sur le moteur) **et** EventBus (`ctb_victoire`/`ctb_defaite`), avec un recap `{victoire, nb_activations, pv_restants}`.
- **§7 Données** : `CombattantCtbData` et `StatutCtbData` (Resources) ; tous les `.tres` portent le header `type="Resource" script_class="…"`. Le runtime (`CtbCombattant`) référence la ressource sans dupliquer ses champs — il ne stocke que PV courants, horloge, bonus %, stacks.
- **§8 Livrable de test** : `scenes/combat_ctb/SandboxCtb.tscn` lançable directement — Avatar vs 1-3 ennemis paramétrables (Resources exportées dans l'inspecteur, stats éditables, `.tres` duplicables), déroulé automatique, journal complet imprimé en console + affiché à l'écran (activations avec valeur d'horloge, dégâts, crits, poses et ticks de statuts, réarmements, morts, fin). Option `graine_rng` pour un combat reproductible. + Suite automatisée `tests/TestCombatCtb.tscn` (32 assertions) branchée à la CI.

## 2. Écarts à la spec

- **Aucun écart fonctionnel.** Deux transpositions littérales à noter :
  - « camp adverse 1 à 3 » : la limite est appliquée au niveau du contenu/sandbox (`ennemis.slice(0, 3)`), pas en dur dans le moteur — l'architecture N-vs-N reste générique pour les chantiers suivants.
  - Le jet de critique utilise le RNG du moteur (`CtbMoteur.rng`), seedable — nécessaire pour des tests déterministes ; comportement par défaut identique (aléatoire).

## 3. Décisions techniques prises (non couvertes par la spec)

- **API pull-based en deux temps** : `activer_suivant()` (sélection + ticks DÉBUT) puis `jouer(action)` (action + ticks FIN + réarmement). C'est ce qui permet « l'input joueur sans limite de durée » sans timer ni await dans le moteur.
- **Mort au tick DÉBUT** : l'activation est **consommée** — pas d'action, pas de ticks FIN, pas de réarmement (`activer_suivant()` retourne `null`, on ré-appelle). À arbitrer si un design ultérieur préfère « le mourant joue quand même ».
- **Fin de combat = arrêt immédiat** : plus aucun tick ni réarmement après le signal (un poison « en attente » ne tue pas un vainqueur).
- **Dégâts d'un stack figés à la pose** (`% × ATK finale du poseur au moment de la pose`) : évite les références à un poseur mort et les re-calculs ; à confirmer si un design veut des DoT qui suivent les buffs du poseur.
- **Dépassement de `stacks_max`** : le stack le plus ancien est **remplacé** (aligné sur l'ancien poison de biome), plutôt que la pose refusée.
- **Tick groupé par statut** : les stacks parallèles d'un même statut sont sommés puis appliqués en une fois (un arrondi par tick, plancher 1) — cumul additif exact, journal lisible (« Poison ×3 : 15 dégâts »).
- **Égalité d'horloge** : tolérance flottante 1e-9, départage par `(camp, ordre d'insertion)` — l'Avatar est par convention le **premier ajouté** au camp joueur (`ordre 0`, assert au démarrage).
- **Nommage** : `CtbMoteur`, `CtbCombattant`, `CombattantCtbData`, `StatutCtbData`, `Enums.CampCtb/ActionCtb/TimingStatut`, signaux EventBus `ctb_victoire/ctb_defaite`, dossier `systems/combat_ctb/` (l'ancien moteur `systems/combat/` reste intact et branché au jeu).
- **Journal** : `PackedStringArray` sur le moteur (le moteur n'imprime jamais lui-même) ; noms via `nom_journal()` (log de dev — l'UI finale passera par Translations).
- **Garde-fou** : `MAX_ACTIVATIONS = 500` sur le déroulé automatique (combat sans issue → arrêt propre, testé).
- GameData ne charge pas `data/combat_ctb/` (dossiers explicites) : les données CTB sont chargées par leurs consommateurs — à brancher dans GameData quand le moteur remplacera l'ancien.

## 4. Fichiers créés / modifiés

**Créés**
- `systems/combat_ctb/ctb_moteur.gd` — moteur CTB (file, actions, DoT, fins)
- `systems/combat_ctb/ctb_combattant.gd` — état runtime d'un combattant
- `scripts/resources/CombattantCtbData.gd` — stats nues (.tres)
- `scripts/resources/StatutCtbData.gd` — paramètres d'un statut DoT (.tres)
- `data/combat_ctb/avatar.tres`, `ennemi_lent.tres`, `ennemi_moyen.tres`, `ennemi_rapide.tres` — combattants factices
- `data/combat_ctb/statut_poison.tres` — Poison (seul statut doté de valeurs)
- `scenes/combat_ctb/SandboxCtb.tscn` + `SandboxCtb.gd` — scène isolée de test
- `tests/TestCombatCtb.tscn` + `TestCombatCtb.gd` — suite automatisée (32 assertions)

**Modifiés**
- `scripts/resources/Enums.gd` — `CampCtb`, `ActionCtb`, `TimingStatut`
- `scripts/autoloads/Balance.gd` — `CTB_K = 1000`
- `scripts/autoloads/EventBus.gd` — `ctb_victoire`, `ctb_defaite`
- `.github/workflows/tests.yml` — TestCombatCtb ajouté à la CI
- `CLAUDE.md` — ligne d'architecture + commande de test

## 5. Résultats de test

`TestCombatCtb` : **32/32** ; les 7 autres suites du projet restent vertes (aucune régression : ScriptsLoad 107/107, CombatResolver 55/55, ExpeditionFlow 28/28, TierCap 22/22, DropSystem 29/29, HoloXlsx, HoloTraffic).

Vérifié par assertions : cadence VIT double (4 activations vs 1), égalité d'horloge (Avatar → ennemis en ordre de liste, sur deux vagues), réarmement à la VIT courante (buff en combat → 50 + 1000/40 = 75), formule de dégâts exacte (20 ATK vs 40 DEF = 15), crit forcé (×2), cumul additif (20 × (1+0.16+0.09) = 25), poison : aucun tick au début / tick à la fin / expiration après 2 activations / 3 stacks max / cumul 3×5=15, hook DÉBUT (tick avant l'action), mort au tick DÉBUT (activation consommée, combat continue), action non implémentée (activation perdue, horloge réarmée), signaux défaite/victoire (local + EventBus, recap), garde-fou 500.

Extrait du journal du sandbox (Avatar vs Rôdeur, poison de démo sur chaque coup de l'Avatar) :

```
Avatar rejoint le combat (joueur) — PV 100, horloge initiale 50.0
Rôdeur rejoint le combat (adverse) — PV 50, horloge initiale 50.0
► Avatar s'active (horloge 50.0)          ← égalité 50/50 : avantage joueur
    ⚔ Avatar frappe Rôdeur : 20 dégâts (PV Rôdeur : 30)
    ⟳ Avatar réarme son horloge → 100.0
    ✚ Poison posé sur Rôdeur par Avatar (1 stack)
► Rôdeur s'active (horloge 50.0)
    ⚔ Rôdeur frappe Avatar : 9 dégâts (PV Avatar : 91)
    ▸ Rôdeur subit Poison ×1 : 1 dégâts (PV 29)   ← tick à la FIN de SON activation
    ⟳ Rôdeur réarme son horloge → 100.0
[…]
► Avatar s'active (horloge 150.0)
    ⚔ Avatar frappe Rôdeur : 20 dégâts (PV Rôdeur : 0)
    ☠ Rôdeur est vaincu
═ VICTOIRE — tous les ennemis sont vaincus (activation 5)
```

## 6. Questions ouvertes

1. **Mort au tick DÉBUT** : l'activation est consommée (le mourant ne joue pas). OK, ou le Saignement doit-il laisser jouer le tour avant la mort ?
2. **DoT figé à la pose** : les dégâts d'un stack sont calculés sur l'ATK du poseur au moment de la pose. Alternative : ATK courante à chaque tick (suit les buffs/debuffs du poseur, mais réfère un poseur potentiellement mort). À trancher avant de designer Brûlure/Saignement.
3. **`stacks_max` dépassé** : remplacement du plus ancien (choix hérité). Refus de pose possible à la place.
4. **Après la mort d'une cible d'action jouée**, la victoire coupe les ticks FIN de l'attaquant : confirmer qu'aucun design futur (ex. Brûlure qui doit tuer un avatar vainqueur in extremis) ne l'exigera.
5. **K = 1000** : valeur initiale de spec, aucune calibration faite. Les horloges affichées (50, 100…) conviennent-elles comme échelle lisible pour la future UI de file d'initiative ?
6. **Fin d'expédition / enchaînement des combats** : le recap `{victoire, nb_activations, pv_restants}` est minimal — dire ce que le chantier 2 attendra dedans (loot ? XP ? état des statuts ?) pour l'étendre au bon moment.
