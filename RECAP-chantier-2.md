# RECAP — Chantier 2 : Carte d'expédition (génération, navigation, brouillard)

Branche : `ReworkCombat`. Modèle free-roam type Dicefolk livré : génération + navigation + brouillard + 3 étages + extraction. Résolution des nœuds = stubs (signal typé + log), branchement CTB à venir.

## 1. Implémenté

- **§1 Structure** : une expédition = 1 Lieu (id libre, factice au sandbox) + 1 palier de profondeur (`PalierProfondeurData` : Périphérie ×1.0 / Enceinte ×1.5 / Noyau ×2.0, `.tres` provisoires à calibrer). Le multiplicateur **circule** dans chaque signal `expe_noeud_resolu` et dans le recap, sans effet réel (testé). 3 étages (`nb_etages` en config) ; Fin d'étage → choix **Extraire** (signal `expe_terminee` avec recap) ou **Continuer** (étage suivant généré) ; au 3ᵉ étage, Fin d'étage = fin d'expédition immédiate (testé).
- **§2 Carte** : N ∈ [8;12] nœuds (bornes data-driven, testées sur 100 graines), posés spatialement en 2D (rejet à distance minimale), adjacence par **triangulation de Delaunay** puis élagage aléatoire d'arêtes **sous garantie de connexité** (une arête n'est retirée que si le graphe reste connexe → connexité par construction, testée sur 100 graines). Entrée = nœud le plus à gauche, Fin = le plus à droite. Déplacement libre le long des arêtes, un nœud à la fois, retour en arrière autorisé (testé) ; nœud résolu = inerte, traversable, jamais re-déclenché (testé). Génération **seedable** (`graine_rng`), reproductibilité testée par empreinte complète (positions + types + arêtes).
- **§3 Brouillard** : Fin d'étage `decouvert` dès l'initialisation (position + type, testé) ; tout autre nœud non découvert est **absent du modèle d'affichage** (`noeuds_visibles()` ne le retourne pas, le sandbox ne le dessine pas — ni grisé ni silhouetté, testé) ; révélation par adjacence à l'arrivée sur un nœud (testé) ; le « ? » affiche « ? » à la révélation et son contenu (`contenu_mystere = -1` tant que non entré) n'est **tiré qu'à l'entrée** (testé).
- **§4 Types & proportions** : Combat 50 / « ? » 30 / Coffre 20 et « ? » → 25/25/25/25, tous en `.tres` (`ExpeCarteConfigData`), aucune valeur en dur. Vérifiés statistiquement : 300 générations (types, ±5 pts) et 4 000 tirages (« ? », ±5 pts).
- **§5 Stubs** : chaque entrée sur un nœud non résolu émet `EventBus.expe_noeud_resolu` (+ signal local) avec `{type, contenu_mystere, lieu_id, palier_id, multiplicateur, etage, noeud_id}` ; résolution = log + marquage `resolu`. `EventBus.expe_etage_termine` à la première arrivée sur une Fin d'étage, `EventBus.expe_terminee` avec recap à la fin — nommage `expe_*` aligné sur `ctb_*` / `adventure_*`.
- **§6 Données** : `ExpeCarteConfigData` + `PalierProfondeurData`, headers `type="Resource" script_class="…"`, aucun champ dupliqué dans le runtime (les nœuds ne stockent que leur état : découvert/résolu/contenu).
- **§7 Livrables** : `scenes/expedition/SandboxExpe.tscn` (palier sélectionnable, graine rejouable, clic souris sur nœud adjacent + flèches clavier, boutons Extraire/Continuer, journal complet à droite, brouillard réel au rendu) + `tests/TestExpeCarte.tscn` (**39 assertions**, branchée CI).

## 2. Écarts à la spec

- Aucun écart fonctionnel. Une **interprétation** à valider (spec silencieuse) : atteindre la Fin d'étage **n'est pas modal** — le choix Extraire/Continuer est ouvert tant que le joueur est SUR le nœud ; il peut repartir explorer (le choix se referme) et revenir (il se rouvre, sans re-résolution). Cohérent avec le free-roam « retour en arrière autorisé » ; cf. Questions ouvertes n° 1.

## 3. Décisions techniques prises

- **Config globale unique** (`data/expedition/config_carte.tres`) plutôt que par étage ou par palier : rien dans la spec ne varie encore par étage ; si un chantier futur veut des étages plus denses en profondeur, on passera à un tableau de configs sans toucher au générateur (il reçoit déjà la config en paramètre).
- **Adjacence par Delaunay + élagage sous connexité** : donne des cartes planaires naturelles (pas d'arêtes qui se croisent) ; l'élagage (probabilité `elagage_aretes`, en config) évite le graphe trop dense. Secours chaîne séquentielle si la triangulation dégénère.
- **Entrée/Fin = extrémités horizontales** : destination lointaine et lisible, sens de lecture gauche → droite.
- **Deux paramètres de layout ajoutés à la config** (`distance_min_noeuds`, `elagage_aretes`) par prudence « rien en dur » ; les dimensions du rectangle (10×6, cosmétiques) restent des constantes de `ExpeCarte`.
- **Un RNG unique par run** (graine posée à la création d'`ExpeRun`) : génération des 3 étages ET tirages « ? » reproductibles d'un seul tenant.
- **Nommage** : `ExpeCarte` / `ExpeNoeud` / `ExpeRun` (`systems/expedition/`), `Enums.TypeNoeud` / `Enums.ContenuMystere`, signaux `expe_*`.
- Comme pour le CTB : GameData ne charge pas `data/expedition/` (dossiers explicites) — les consommateurs chargent leurs `.tres` directement.

## 4. Fichiers créés / modifiés

**Créés**
- `systems/expedition/expe_carte.gd` — génération (positions, Delaunay, élagage, types)
- `systems/expedition/expe_noeud.gd` — état d'un nœud (découvert / résolu / contenu)
- `systems/expedition/expe_run.gd` — run : navigation, brouillard, étages, stubs, recap
- `scripts/resources/ExpeCarteConfigData.gd`, `scripts/resources/PalierProfondeurData.gd`
- `data/expedition/config_carte.tres`, `palier_peripherie.tres`, `palier_enceinte.tres`, `palier_noyau.tres`
- `scenes/expedition/SandboxExpe.tscn` + `.gd` — scène isolée jouable
- `tests/TestExpeCarte.tscn` + `.gd` — 39 assertions

**Modifiés**
- `scripts/resources/Enums.gd` — `TypeNoeud`, `ContenuMystere`
- `scripts/autoloads/EventBus.gd` — `expe_noeud_resolu`, `expe_etage_termine`, `expe_terminee`
- `tests/ScreenshotTool.gd` — mode `SHOT_MODE=expe` (captures brouillard init/explore)
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Résultats de test

`TestExpeCarte` : **39/39**. Toutes les autres suites vertes (ScriptsLoad 101/101, CTB 33, ExpeditionFlow 28, TierCap 22, Drops 29, Holo ×2), boot sans erreur.

Vérifié : connexité (100 graines), bornes N (100 graines), proportions types (300 générations, écarts < 5 pts), proportions « ? » (4 000 tirages, écarts < 1 pt), reproductibilité par empreinte (même graine = carte identique), brouillard initial exact (Entrée + voisins + Fin, rien d'autre), révélation par adjacence, « ? » tiré à l'entrée seulement, retour en arrière, inertie (aucune re-résolution), refus de déplacement non adjacent, extraction étage 1 (recap `extraction=true`), enchaînement 3 étages (`etage_termine` ×3, fin immédiate au 3ᵉ, recap `complete=true`), choix refermé/rouvert, circulation du palier (payload ×1.5).

Contrôle visuel (captures `tests/_shot_expe_init.png` / `_shot_expe_explore.png`) : état initial = 3 nœuds affichés sur 9 (Entrée + 1 voisin + Fin), exploration = révélation progressive, « ? résolu », nœuds inertes assombris, journal lisible.

## Addendum — Arbitrages design validés (06/07/2026)

Les 6 questions ouvertes ci-dessous ont été tranchées (aucune modification de code) :
1. Fin d'étage **non modale** confirmée : le choix se referme au départ du nœud, se rouvre au retour, sans re-résolution.
2. Entrée des étages 2-3 **sans continuité spatiale** — conservé ; le raccord visuel est une question de DA, reportée.
3. `elagage_aretes` : calibrage en playtest, rien à faire.
4. Révélation du « ? » résolu sur la carte : reportée au chantier UI finale, comportement actuel conservé.
5. **Attaque surprise : distinction mécanique actée** — combat CTB avec **malus d'initiative côté joueur** ; valeurs et forme exacte du malus à designer au chantier de branchement combat (rien d'implémenté).
6. Recap d'expédition : rien à ajouter ; extension au chantier loot / sanction de mort.

Note de baseline (règle de process) : les compteurs de ce recap se lisent contre la baseline **post-addendums du chantier 1** — 94 scripts chargés (suppression de l'ancien moteur temps réel, −13) et CTB 33 assertions (recap `ennemis_vaincus`, +1) — d'où ScriptsLoad 101/101 après les +7 scripts de ce chantier. Désormais, tout recap rappelle en une ligne la baseline si elle a bougé via un addendum entre deux chantiers.

## 6. Questions ouvertes

1. **Fin d'étage non modale** (décision de ce chantier) : le joueur peut repartir explorer après avoir atteint la Fin, et revenir choisir. Confirmer, ou rendre le choix définitif à la première arrivée ?
2. **Position de l'Entrée aux étages 2-3** : chaque étage régénère une carte complète avec sa propre Entrée (pas de continuité spatiale avec la Fin de l'étage précédent). OK, ou faut-il un raccord visuel (Entrée = position de la Fin précédente) ?
3. **Densité d'arêtes** (`elagage_aretes = 0.5`) : sensation de labyrinthe vs autoroute — à calibrer en playtest ; le paramètre est en config.
4. **Le « ? » résolu doit-il révéler son contenu sur la carte après coup** (actuellement : étiquette « ? résolu » au sandbox, contenu visible au journal) ? Question d'UI finale.
5. **Attaque surprise** : contenu du « ? » qui déclenchera un combat CTB — faut-il une distinction mécanique avec un nœud Combat normal (embuscade, malus d'initiative) ? À designer avant le chantier de branchement.
6. **Recap d'expédition** : contient `{lieu_id, palier_id, multiplicateur, extraction, complete, etage_atteint, noeuds_resolus, mysteres_resolus}` — dire ce que la sanction de mort / le loot en attendront pour l'étendre.
