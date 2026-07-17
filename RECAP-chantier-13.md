# RECAP — Chantier 13 : Équipement de départ + voies à ordre fixe (correctif du Chantier 12)

Branche : `ReworkCombat`. Décisions actées (06/07/2026) qui SUPERSÈDENT deux arbitrages du chantier 12 : **l'équipement complet de rareté Commun est présent dès le début de partie**, et **les voies s'ouvrent dans un ordre fixe 1→6, 1 Sceau libre (interchangeable) = 1 voie, la voie 1 étant l'Atelier/Forge** — l'Atelier n'est donc plus accessible d'emblée ; la progression d'équipement passe par son amélioration à la Forge, débloquée au premier Sceau.

## 1. Implémenté

### Équipement de départ (partie neuve)

- **Dotation data-driven** : `data/progression/equipement_depart.tres` (`EquipementDepartData`, liste d'ids) → `GameData.appliquer_equipement_depart()` : chaque équipement de la liste est débloqué (`est_debloque`) et équipé dans son slot (rareté Commun = palier 0 des .tres, inchangés).
- **Retenus** : les 3 équipements Commun EXISTANTS du VS — `equipment_arme` (Lame de Pierre, slot Arme), `equipment_anneau` (Anneau de Forêt, slot Anneau), `equipment_armure` (Carapace des Marais, slot Armure). **Aucun équipement inventé.**
- **⚠ Slots sans équipement Commun existant** (signalés, règle du chantier) : Ceinture, Bouclier, Talisman — leurs .tres sont des placeholders SANS CONTENU (nom vide, stats vides, biomes post-VS, ex-gel Couturier). Ils restent inertes et NON dotés ; un id vide/inconnu dans la config est ignoré avec warning, jamais comblé en silence.
- **Application : PARTIE NEUVE UNIQUEMENT** — appelée par `SaveManager.load_save()` dans la branche « aucune sauvegarde utilisable » (fichier absent, ou illisible ET sans backup : la partie repart de zéro → elle est neuve). Une sauvegarde existante n'est JAMAIS touchée (chargée telle quelle, testé).
- **Suppression de `reconcile_equipment_unlocks`** (système remplacé) : le rattrapage « biome < Peu Commun → équipement REPRIS » aurait dépouillé la dotation à CHAQUE chargement (les biomes, figés à Commun depuis le ch.12, ne montent plus). Le hook `unlock_biome_equipment` (branché sur `entity_evolved`) reste en place, simplement plus jamais tiré.
- **Pont CTB inchangé** (exigence du chantier vérifiée en test) : `CtbPont.combattant_depuis_heros` lisait déjà `GameData.get_equipment_bonuses()` — les stats de partie neuve incluent la dotation sans une ligne de modification (deltas exacts testés : ATK +3, DEF +2, PV +15, VIT ×1.10).

### Voies à ordre fixe, Sceaux interchangeables (refonte du modèle ch.12)

- **État refondu** : `player["voies_ouvertes"]` passe de dict lieu_id→true à **COMPTEUR int** (0-6). **`SAVE_VER` 13 → 14**, migration `_migrate_v13_to_v14` (ancien dict de n voies → compteur n), versions acceptées toujours 11+.
- **Règle** : ouvrir la voie n exige voies 1..n-1 ouvertes + **1 Sceau LIBRE** (`sceaux_libres()` = Sceaux possédés − voies ouvertes). API GameData : `NB_VOIES`/`VOIE_ATELIER`, `nb_sceaux()`, `sceaux_libres()`, `voie_ouverte(numero)`, `atelier_ouvert()`, `peut_ouvrir_voie_suivante()`, `ouvrir_voie_suivante()` (la seule écriture — impossible structurellement d'ouvrir la voie 2 avant la 1). Signal `EventBus.voie_ouverte(numero: int)` (ex-lieu_id).
- **`objets_lieutenants` CONSERVÉ tel quel** (provenance narrative par Lieu, accordé au premier kill — rails du ch.12 intacts, Game Over compris) ; les Sceaux se DÉPENSENT comme un compteur interchangeable.
- **`nb_voies_ouvertes()` reste la source unique** du compteur « quartiers restaurés » (rien ne change pour la DA).
- **`VoiesPanel` adapté** : compteur x/6, « Sceaux libres : n » + liste des Sceaux (provenance), 6 cartes DANS L'ORDRE — restaurée (voie 1 : « Atelier restauré — la Forge est ouverte ») / SUIVANTE mise en avant (bordure accentuée ; bouton « Restaurer la voie » si Sceau libre, sinon « 1 Sceau libre requis ») / verrouillée (« ouvrez d'abord la voie précédente »). La voie 1 est nommée « Atelier (Forge) », les 2-6 « Quartier scellé » génériques.

### Atelier re-scellé (annule l'ouverture d'emblée du ch.12)

- **Hex Forge ABSENT** (jamais grisé — règle pilier) tant que la voie 1 n'est pas ouverte : nouveau filtre `Village._hex_disponible(d, village_maitrise)` (statique, pur, testé directement) = gate tier_min existant + `GameData.atelier_ouvert()` pour `forge`. Quartiers de base d'emblée : **Avatar (Héros) et Expéditions seulement**. Le quartier/district Forge suit (pas de lien/boule sans hex).
- **ForgePanel** : verrou propre indexé sur la voie 1 (message « L'Atelier est scellé — restaurez la voie 1 ») en défense en profondeur — PAS sur les défunts paliers de Village.
- **Ouverture de la voie 1** → le listener `voie_ouverte` du Village RECONSTRUIT le hub (l'hex apparaît) et rouvre le panneau courant (pattern du changement de langue) ; les autres voies ne font que rafraîchir. Pastille de l'hex VOIES = `peut_ouvrir_voie_suivante()`.

## 2. Écarts / interprétations (aucun silencieux)

- **3 slots dotés sur 6** : Ceinture/Bouclier/Talisman n'ont AUCUN équipement Commun existant (placeholders sans contenu) — signalé ici comme demandé, rien inventé. « Chaque slot est équipé » se lit donc « chaque slot COUVERT par l'existant » ; les 3 slots restants suivront leurs biomes post-VS.
- **Partie « neuve » = aucune sauvegarde utilisable** : le cas « fichier corrompu sans backup » reçoit AUSSI la dotation (le joueur repart factuellement de zéro, sa copie de quarantaine `.corrupt` est préservée) — sans elle, cette partie-là démarrerait nue, pire que le crash.
- **`reconcile_equipment_unlocks` supprimé plutôt qu'amendé** : sa moitié « livrer si biome ≥ Peu Commun » est morte avec l'évolution des biomes, sa moitié « reprendre sinon » devenait un bug actif contre la dotation. Testé : la dotation persistée survit à save + reload avec biomes à Commun.
- **Ordre fixe = compteur, pas une liste ordonnée de Lieux** : le modèle « quelle voie correspond à quel Lieutenant » disparaît de l'ÉTAT (seule la voie 1 a un contenu connu — l'Atelier ; les 2-6 sont indifférenciées jusqu'à la session narration). La provenance des Sceaux, elle, reste tracée par Lieu.
- **Migration plutôt que clé neuve** : `voies_ouvertes` garde son nom (dict→int, `SAVE_VER` 14) — une sauvegarde v13 avec n voies « par Lieu » garde n voies ouvertes (les n premières de l'ordre fixe). Testé unitairement.
- **`voie_ouverte(lieu_id)` / `ouvrir_voie(lieu_id)` supprimés** (système remplacé) — seuls les tests du ch.12 les consommaient, adaptés (cf. §5).

## 3. Décisions techniques prises

- **Dotation appelée par `load_save`** (pas `GameData._ready`) : les autoloads démarrent aussi dans les tests et le sandbox — seule la décision « partie neuve vs partie chargée » de SaveManager sait quand doter ; un outil qui ne charge pas la sauvegarde ne dote rien.
- **`Village._hex_disponible` statique** : le filtre du hub devient testable headless sans instancier le hub (les suites l'appellent directement) ; un futur gate d'hex se range au même endroit.
- **Rebuild du hub ciblé sur la voie 1** : seules les ouvertures qui changent l'ANNEAU reconstruisent (l'hex Forge est le seul cas aujourd'hui) — les autres voies font un simple refresh du panneau.
- **`EventBus.voie_ouverte(numero)`** : le numéro suffit à tous les consommateurs (rebuild si == VOIE_ATELIER, refresh sinon) ; la provenance du Sceau dépensé n'existe plus au moment de l'ouverture (interchangeable).

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/resources/EquipementDepartData.gd` + `data/progression/equipement_depart.tres` — dotation de départ
- `tests/TestEquipementDepart.gd` + `.tscn` — 27 assertions (5 tests, cf. §5)
- `RECAP-chantier-13.md`

**Modifiés**
- `scripts/autoloads/GameData.gd` — `appliquer_equipement_depart()`, voies refondues (compteur, ordre fixe, `atelier_ouvert`, `ouvrir_voie_suivante`, Sceaux libres), `reconcile_equipment_unlocks` SUPPRIMÉ
- `scripts/autoloads/SaveManager.gd` — `SAVE_VER` 14, migration v13→v14 (voies dict→int), dotation sur partie neuve, appel reconcile retiré
- `scripts/autoloads/EventBus.gd` — `voie_ouverte(numero: int)`
- `scenes/village/Village.gd` — `_hex_disponible` (hex Forge absent sans voie 1), listener voie_ouverte (rebuild hub à la voie 1), badge voies = `peut_ouvrir_voie_suivante`
- `scenes/village/panels/ForgePanel.gd` — verrou voie 1 (défense en profondeur)
- `scenes/village/panels/VoiesPanel.gd` — refonte ordre fixe (voie suivante mise en avant, Sceaux libres, noms voie 1/génériques)
- `scripts/autoloads/Translations.gd` — clés voies remaniées (+6 : sceaux_libres, nom_atelier, nom_generique, suivante_hint, verrouillee, atelier_restaure ; −1 : scellee_hint) + `forge.scelle`, FR+EN
- `tests/TestEconomieQG.gd` — tests 8-10 adaptés (cf. §5)
- `.github/workflows/tests.yml` (+TestEquipementDepart), `CLAUDE.md` (SAVE_VER, note ch.13, table, biomes, tests)

## 5. Tests

**Nouvelle suite `TestEquipementDepart` : 27/27** (protocole fichiers réels mis de côté) :
1. Config : 3 ids existants, équipements réels (nom non vide, Commun T0), slots distincts ;
2. Partie neuve (aucun fichier) → `load_save` équipe arme/anneau/armure (débloqués) ; ceinture/bouclier/talisman restent vides (placeholders — documenté) ;
3. Pont CTB : stats de partie neuve AVEC équipement, deltas exacts vs héros nu (ATK +3, DEF +2, PV +15, VIT ×1.10) — pont non modifié ;
4. Save + reload (biomes à Commun) → la dotation N'EST PAS reprise (le piège reconcile est mort) ;
5. Sauvegarde existante SANS équipement → reload n'ajoute rien (dotation jamais appliquée à une partie en cours).

**`TestEconomieQG` adapté : 65/65** (**changements de comportement du ch.12 — attendus, listés**) :
- Test 8 « voies par Lieu » → « ordre fixe » : refus sans Sceau ; avec 2 Sceaux rien n'est ouvert tant qu'on ne clique pas, la 1re ouverture est TOUJOURS la voie 1 (signal `[1]`), puis la 2 (`[1, 2]`), la 3 refusée à 0 Sceau libre ; round-trip du compteur ; migration v13→v14 testée unitairement.
- Test 9 « Atelier ouvert d'emblée » → « Atelier SCELLÉ » (inversion) : hex Forge ABSENT même Village T5 sans voie 1 (`_hex_disponible`), verrou du panneau, puis hex présent + panneau fonctionnel après ouverture de la voie 1.
- Test 10 panneau VOIES : bouton Restaurer conditionné au Sceau LIBRE (plus à l'objet du Lieu), voie 1 nommée Atelier, re-rendu après ouverture (restaurée, plus de bouton à 0 Sceau libre).
- Tests 1-7 et 11 (Modules, Sceau au premier kill, Game Over, coûts, panneau Expéditions) : INCHANGÉS.

**Baselines runtime** — toutes les suites vertes après chantier :
`TestScriptsLoad` **133/133** (+2 : EquipementDepartData, TestEquipementDepart) ; **TestEconomieQG 65** (65 ≠ 53 du ch.12 : suite adaptée + assertions ajoutées — attendu) ; **TestEquipementDepart 27** (nouveau) ; CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 53, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26, Alarme 73, TierCap 22, Drops 29, Forge 29, VillageBuildings 55, HoloXlsx, HoloTraffic — **inchangées** ; **boot 30 s sans erreur**. CI : TestEquipementDepart ajouté au workflow.

**Manuel restant** : partie neuve → panneau Héros (3 slots équipés en Commun, 3 vides) → hex Forge ABSENT → premier assaut → Sceau (pastille VOIES) → « Restaurer la voie » → l'hex Forge apparaît → panneau Forge fonctionnel.

## 6. Questions ouvertes

1. **Slots Ceinture/Bouclier/Talisman** : à doter quand leurs équipements existeront (biomes post-VS) — une ligne dans `equipement_depart.tres` suffira.
2. **Contenu des voies 2-6** : session narration/PNJ (l'ordre fixe rend le séquencement narratif trivial — la voie n peut recevoir son contenu sans toucher au modèle).
3. **Onboarding Forge** : l'hex apparaît « d'un coup » à la voie 1 (rebuild du hub) — une mise en scène (animation d'éclosion du quartier) est une affaire de DA.
