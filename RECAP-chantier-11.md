# RECAP — Chantier 11 : Système d'Alarme et assauts de Lieutenants

Branche : `ReworkCombat`. Dernier système de la base (règles actées 06/07/2026) : suivi de complétion Lieu × strate, assauts de Lieutenants (expédition 1 étage à nœud Boss), 6 slots d'Alarme qui renforcent TOUS les ennemis, jauge sur la HoloMap, 6/6 = l'alarme sonne (déclencheur Pyramide — la 7ᵉ expédition reste hors scope). Toutes les valeurs sont PROVISOIRES, data-driven, à calibrer.

## 1. Implémenté

### Complétion par Lieu × strate

- `GameData.player["expe_completions"]` (lieu_id → { palier_id: true }) — sauvegarde de PARTIE.
- Marquage par **ExpeRun uniquement à la COMPLÉTION** (fin du dernier étage) : `_terminer` ne marque ni extraction anticipée, ni défaite, ni assaut (hors strates). API : `marquer_strate_completee` / `strate_completee` / `nb_strates_completees` (0-3).
- **Panneau de lancement** : marqueurs placeholder par palier (◆ complétée / ◇ non) sous les boutons radio — le « sentiment de complétion » acté.

### Assaut de Lieutenant

- **Déblocage** : l'option Assaut d'un Lieu n'apparaît que 3/3 strates complétées ET Lieutenant mappé (`destinations.tres.lieutenants_par_lieu`) — **ABSENTE avant, jamais grisée** (règle pilier). Bouton rouge (`CYBER_DANGER` : l'assaut du Lieutenant est un danger) → signal `lancer_assaut` → `Village.lancer_expedition(lieu, PALIER_ASSAUT, 0, true)`.
- **Forme** : `ExpeRun.est_assaut` + `lieutenant` (définis avant `demarrer()`, pattern `cfg_noeuds`) — génération de carte NORMALE, `nb_etages_effectif()` = 1, le nœud de Fin d'étage devient `TypeNoeud.BOSS` (visible d'emblée, navigation normale). **Aucune extraction** : `choix_ouvert` n'est jamais vrai (le nœud Boss remplace la Fin d'étage qui l'ouvrait) ; issues possibles = victoire ou défaite (Game Over normal).
- **Combat de boss** : composition FIXE Lieutenant + `NB_SBIRES_ASSAUT = 2` sbires tirés du pool du Lieu — moteur et UI existants TELS QUELS (aucune mécanique de boss — viendra avec les compétences).
- **Victoire** : `GameData.marquer_lieutenant_vaincu(lieu)` — premier kill → slot rempli + signal `lieutenant_vaincu(lieu, premier)` (déclencheur de sauvegarde, ajouté à `signaux_progression`) ; re-kill → signal `premier=false`, pas de re-slot, XP/Euren normaux. Fin d'assaut immédiate après le nœud Boss.
- **Recap distinct** : champs `est_assaut` / `lieutenant_id` / `premier_kill` dans le recap d'ExpeRun ; l'écran affiche « ASSAUT ACCOMPLI » + « Lieutenant vaincu : X » + slot rempli (x/6) ou « déjà vaincu — récompenses normales ».
- **Palier** : `data/expedition/palier_assaut.tres` (id `palier_assaut`, nom « Assaut », ×1.0) circule dans les signaux — un assaut est hors strates, documenté.
- **6 Lieutenants placeholder** (`data/expedition/lieutenants/*.tres`, « Lieutenant du <Lieu> », stats élevées à calibrer) — les 3 Lieux secondaires sont mappés d'avance (injoignables tant que leurs zones n'existent pas sur la HoloMap).

### Effets de l'Alarme (tous les combats, toutes les expéditions)

- `Alarme` (class_name statique, pattern Balance) + `AlarmeConfigData` → `data/expedition/alarme.tres` : `pct_par_slot` = **+5 % PV et ATK par slot** (cumul additif StatStacker) ; `affixes_par_palier` = **4 : Blindage renforcé (+15 % DEF), 5 : Surtension (+15 % ATK), 6 : Overclock (+10 % VIT)** — réutilisation d'`AffixeData` du pool existant, CUMULATIF (à 6 : les trois). « Permanents » = tant que le palier est atteint, pas liés à une run.
- **Application à la création de chaque combattant ennemi dans ExpeRun** (même endroit que le pont bestiaire — Lieutenant compris) : le moteur CTB reste agnostique. Le camp joueur n'est JAMAIS touché.

### Jauge HoloMap + 6/6

- **`HoloHud._jauge_alarme`** : 6 slots sous le crochet haut-droit du HUD « table tactique », remplis en ROUGE (le danger est le métier de cette jauge — exception actée), label « ALARME x/6 », pulsation douce à 6/6. Redessinée chaque frame → toujours fidèle (source unique `GameData.nb_lieutenants_vaincus()`).
- **6/6** : `EventBus.alarme_sonnee` émis UNE fois (au 6ᵉ premier kill) ; le Village le mémorise (`_alarme_a_annoncer` — le signal part en pleine run) et affiche au retour au QG un `EcranMessage` rouge « L'ALARME SONNE — LA VOIE DE LA PYRAMIDE S'OUVRE ». Le déclencheur SEUL existe.

### Persistance

- `expe_completions` + `lieutenants_vaincus` dans `GameData.player` → sauvegarde de PARTIE (automatique). `lieutenant_vaincu` ajouté aux signaux de progression (un slot rempli déclenche la sauvegarde — hors run, en run les écritures restent suspendues et flushées à la sortie).
- **Game Over** : la sauvegarde de lancement capture l'état d'avant l'assaut ; `recharger()` ré-applique le fichier (`_load_player` merge overwrite — les clés sont toujours présentes) → un Lieutenant tué PENDANT une run perdue est annulé (cohérent : l'assaut perdu n'a pas eu lieu — **vérifié en test, pas contourné**). Commentaire de `recharger()` mis à jour (les runs mutent désormais ces états).

## 2. Écarts / interprétations (aucun silencieux)

- **Correction au passage (bug réel découvert)** : `CtbCombattant._init` fige `pv = stat_finale("pv_max")` À LA CRÉATION — les bonus % d'Alarme ajoutés ensuite n'existaient que sur le plafond, jamais sur les PV de départ. `Alarme.appliquer` re-remplit `cb.pv = cb.stat_finale("pv_max")` (un ennemi est toujours créé frais). Testé (PV de départ pleins aux 7 paliers).
- **Annonce 6/6 différée au retour au QG** : le signal part pendant la run (victoire de boss, écran de combat ouvert) — empiler l'EcranMessage à cet instant chevaucherait combat + recap. L'alarme ne peut sonner QUE sur une victoire d'assaut (sortie normale immédiate), le différé est donc sans trou.
- **Marqueurs de strates dans le texte des boutons ?** Non — ligne de marqueurs dédiée sous les boutons radio (placeholder lisible, les boutons gardent leur seul rôle de choix).
- **`lieutenants_par_lieu` embarque les 3 Lieux secondaires** dès maintenant (mappés, injoignables) — évite un angle mort le jour où leurs zones HoloMap arrivent ; l'alternative (3 seulement) aurait fait de `null` un état ambigu (« pas encore » vs « jamais »).
- **Jauge dans `HoloHud`** (HUD 2D de la table tactique) plutôt qu'un objet 3D de la scène : placeholder acté, diégétique « état d'alerte », remplaçable d'un bloc quand la DA arrivera.

## 3. Décisions techniques prises

- **`Alarme.niveau()` = `GameData.nb_lieutenants_vaincus()`** — aucune donnée dupliquée, la jauge, les effets et le recap lisent la même source.
- **Affixes d'Alarme appliqués comme bonus %** sur le combattant (mêmes rails que les affixes de run du joueur) — pas d'objet « affixe posé » côté moteur ; `Alarme.affixes_actifs()` sert l'UI/les tests.
- **`marquer_lieutenant_vaincu` retourne `premier`** et émet TOUJOURS `lieutenant_vaincu` (premier=false au re-kill) — l'appelant n'a pas à re-demander l'état ; `alarme_sonnee` n'est émis qu'au passage 5→6 (jamais re-émis, testé).
- **Assaut = paramètre de `lancer_expedition`** (pas une seconde fonction) : le flux (flush de référence, suspension, écran, retour) est STRICTEMENT le même — seule la construction de la run diffère.
- **`ExpeLancementPanel` précharge `destinations.tres`** (même ressource que le Village) : le panneau décide seul de l'affichage de l'option, le Village re-vérifie au lancement (défense en profondeur).

## 4. Fichiers créés / modifiés

**Créés (commit précédent « chap 11 en cours de dev » — socle repris tel quel)**
- `scripts/autoloads/Alarme.gd`, `scripts/resources/AlarmeConfigData.gd`, `data/expedition/alarme.tres`
- `data/expedition/palier_assaut.tres`, `data/expedition/lieutenants/*.tres` (6)
- Socle GameData (état + API), EventBus (2 signaux), Enums (`TypeNoeud.BOSS`), ExpeDestinationsData (`lieutenants_par_lieu`), ExpeRun (assaut : 1 étage, nœud Boss, composition, kill)

**Créés (ce chantier)**
- `tests/TestAlarme.gd` + `.tscn` — 73 assertions (13 tests, cf. §5)
- `RECAP-chantier-11.md`

**Modifiés (ce chantier)**
- `systems/expedition/expe_run.gd` — marquage de strate à la complétion (ni extraction, ni défaite, ni assaut), recap `est_assaut`/`lieutenant_id`/`premier_kill`, `_nom_type` Boss
- `scripts/autoloads/Alarme.gd` — PV re-remplis au pv_max final (correction, cf. §2)
- `scripts/autoloads/SaveManager.gd` — commentaire de `recharger()` (nouveaux états mutés en run)
- `scenes/expedition/ExpeLancementPanel.gd` — marqueurs de strates, option Assaut (absente avant 3/3), signal `lancer_assaut`
- `scenes/expedition/ExpeditionScreen.gd` — mode assaut (`est_assaut`/`lieutenant` → run), étage x/1, recap d'assaut distinct
- `scenes/expedition/ExpeCarteView.gd` — nœud BOSS (couleur `CYBER_DANGER` + étiquette)
- `scenes/village/Village.gd` — `PALIER_ASSAUT`, lancement d'assaut, annonce 6/6 différée au retour QG
- `scenes/holomap3d/HoloHud.gd` — jauge d'Alarme 6 slots
- `scripts/autoloads/Translations.gd` — 9 clés FR + 9 EN (strates, assaut, recap, alarme)
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Tests

**Nouvelle suite `TestAlarme` : 73/73** (protocole fichiers réels mis de côté — le round-trip est l'objet) :
1. Données (6 Lieutenants mappés + lisibles, palier Assaut, config +5 %/slot, 3 affixes) ;
2. Complétion de strate (bouclée = oui ; extraction = non ; défaite = non ; 3 paliers = 3/3 idempotent) ;
3. Panneau de lancement (2/3 → option ABSENTE ; 3/3 → présente ; clic → `lancer_assaut`) ;
4. Assaut : 1 étage, Boss remplace la Fin d'étage (visible, unique) ; jamais de Boss en expédition normale ;
5. Aucune extraction (`extraire()` inopérant, choix jamais ouvert, victoire = fin immédiate, recap est_assaut+complete) ;
6. Composition EXACTE boss + 2 sbires du pool ;
7. Premier kill → slot + signal `premier=true` + recap + **round-trip disque réel** ;
8. Re-kill → pas de re-slot, `premier=false`, XP/Euren normaux ;
9. Deltas % EXACTS paliers 0-6 (pv/atk/def/vit, affixes 4/5/6 cumulatifs, PV de départ pleins) ;
10. Alarme dans une expédition NORMALE (×1.15 à 3 slots ; camp joueur intact) ;
11. Game Over : kill pendant run perdue ANNULÉ par rechargement ;
12. 6/6 : `alarme_sonnee` émis une fois, jamais re-émis ;
13. Jauge : HoloHud instanciable headless, source unique GameData.

**Baselines runtime** — toutes les suites vertes après chantier :
`TestScriptsLoad` **128/128** (+3 : Alarme, AlarmeConfigData, TestAlarme) ; CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 53, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26, TierCap 22, Drops 29, HoloXlsx, HoloTraffic — **inchangées** ; **boot 30 s sans erreur**. CI : TestAlarme ajouté au workflow.

**Manuel restant : un assaut complet en jeu réel** (3 strates d'un Lieu → option Assaut sur le panneau → run 1 étage → boss → recap d'assaut → jauge HoloMap à 1/6) — les 73 assertions couvrent la mécanique, le ressenti se juge en jouant.

## 6. Questions ouvertes

1. **Nom de la jauge** : « ALARME x/6 » en label brut — la DA (Christophe) décidera de la forme diégétique finale (enseigne ? hologramme au-dessus de la Pyramide ?).
2. **Stats des Lieutenants** (~320 PV / 34 ATK) : premières valeurs « élevées », à calibrer en playtest — data-driven, un `.tres` par Lieu.
3. **Alarme et sbires d'assaut** : l'Alarme renforce AUSSI le boss et ses sbires (cohérent « tous les ennemis ») — si les re-kills deviennent trop durs à 6/6, exclure le nœud Boss serait une ligne dans ExpeRun.
4. **Bonus one-shot des Lieutenants** : toujours gelés (hors scope acté) — le hook naturel existe (`premier_kill` au recap).
