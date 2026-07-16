# RECAP — Chantier 10 : UI d'expédition — habillage cyberpunk + navigation par chemin

Branche : `ReworkCombat`. Deux volets : **peau cyberpunk intérimaire cohérente** sur tout le pipeline expédition (la DA finale appartient à Christophe — ce chantier livre des TOKENS remplaçables, pas la DA définitive), et **navigation par chemin** sur la carte (règle actée).

## 1. Implémenté

### Volet habillage

- **Tokens centralisés** (à remplacer par la DA de Christophe — AUCUN littéral dispersé) :
  - **Couleurs** : `UIColors.CYBER_*` (section dédiée de `scripts/autoloads/UIColors.gd`) — fond quasi-noir bleuté (`CYBER_BG`), panneaux (`CYBER_BG_PANEL`/`_2`), accents néon **cyan dominant** (`CYBER_ACCENT`, camp joueur/chrome) et **magenta** (`CYBER_ACCENT_2`, camp adverse), `CYBER_OK` (positif), `CYBER_BUTIN` (or), textes, grille/arêtes de carte, couleurs des 5 types de nœuds. **`CYBER_DANGER` = alias de `TIER_UNIQUE`** : le rouge reste réservé à l'Artefact/danger (mort, défaite, piège) — jamais décoratif.
  - **Styles/factories** : `scripts/autoloads/ExpeStyle.gd` (class_name statique, pattern Balance/UIHelpers) — `police_mono()` (SystemFont Consolas/Cascadia/monospace : typographie technique diégétique, le héros est un matricule R-XXX), `label_mono`, `style_panneau` (bordure fine lumineuse + halo doux, angles quasi-droits), `bouton`/`habiller_bouton` (néon, y compris les boutons créés dynamiquement — cibles, objets), `style_chip` (file d'initiative, pills), `scanlines` (shader `scenes/ui/cyber_scanlines.gdshader` — une ligne sur deux + léger vignettage, PAS de glitch permanent), `accent_camp`.
- **Périmètre couvert** (tout le pipeline) : `ExpeLancementPanel` (modal, paliers radio néon), `ExpeditionScreen` (fond, en-têtes mono, carte encadrée, journal encadré, Extraire = `CYBER_OK` / Continuer = accent), `ExpeCarteView` (fond + grille technique, arêtes cyan, nœuds en anneau + cœur coloré par type, étiquettes mono), `CombatCtbUi` (fond scindé cyberpunk **remplaçant les presets BiomeBackground** : moitiés teintées cyan/magenta + bande diagonale ; barre d'actions en panneau néon ; file d'initiative en chips par camp ; boutons Attaquer/Défendre/Objet/cibles ; intro/issue mono — VICTOIRE = `CYBER_OK`, DÉFAITE = `CYBER_DANGER`), `CarteCombattantCtb` (bordure au camp, nom/PV mono — barres de PV et états inchangés : infos de jeu), popups de nœuds (bénédiction `CYBER_OK` / piège `CYBER_DANGER` / coffre `CYBER_BUTIN`), recap de fin de run, `EcranMessage` (cadre fin à l'accent, Game Over rouge danger / reconstruction `CYBER_OK`).
- **Palette de rareté INTACTE** : les couleurs de palier (destination du lancement, en-tête du Lieu) viennent toujours de `UIColors.tier_color` — aucune seconde palette.
- **Lisibilité prioritaire** : barres de PV (dégradés existants), pills de statuts, or de ciblage (`SELECTION_GOLD`), couleurs de dégâts flottants — tous conservés tels quels (infos de jeu, pas des décorations).

### Volet navigation par chemin (règle actée)

- **`ExpeRun.chemin_vers(nid)`** : BFS depuis la position du joueur qui ne TRAVERSE que des nœuds **résolus** ; la destination (découverte) peut être non résolue — l'y déplacer déclenche sa résolution normale. **`ExpeRun.atteignables()`** : ensemble des nids joignables (un seul BFS — feedback UI).
- **Vue** : clic possible sur **n'importe quel nœud découvert atteignable** ; nœud visible sans chemin résolu = **atténué (alpha réduit) + curseur normal + clic ignoré** ; nœud atteignable = curseur main + halo fin d'invitation (non résolus). Flèches clavier inchangées (adjacence = chemin de longueur 1, sous-ensemble).
- **Trajet séquencé** : les hôtes (`ExpeditionScreen.jouer_deplacement`, miroir SandboxExpe) déroulent le chemin pas à pas avec `ExpeCarteView.DELAI_PAS` (0,12 s) entre les étapes — le joueur voit le trajet, pas de téléportation ; les nœuds traversés sont inertes par règle existante (aucun re-déclenchement, testé) ; garde anti-réentrance `_trajet_en_cours`. Un chemin de longueur 1 reste **entièrement synchrone** (aucune attente — les tests pas à pas existants inchangés).
- **Fin d'étage** : visible d'emblée mais atteignable **seulement** via un chemin résolu (testé).

## 2. Écarts / interprétations (aucun silencieux)

- **Fond scindé du combat** : les presets `BiomeBackground` (« city »/« forest », placeholder cosmétique de l'ancien moteur) sont REMPLACÉS par le fond cyberpunk — c'était l'élément le plus dissonant avec la peau. `BiomeBackground` lui-même est intact (utilisé ailleurs — hors périmètre).
- **SandboxExpe non habillé** (contrôles dev bruts) : c'est un outil, pas une UI de jeu — mais il bénéficie automatiquement de la vue de carte et de l'écran de combat habillés (partagés), et reçoit la navigation par chemin (miroir).
- **`modulate` grisé des cartes de combattant mort** : conservé tel quel (facteur d'atténuation d'état, pas une couleur de palette).
- **Correction au passage** : un Label `autowrap` dans la chaîne de conteneurs centrés d'`EcranMessage` gonflait la hauteur du cadre au premier layout (constaté sur capture) — autowrap retiré (messages d'une ligne).
- **Popup de nœud** : le texte flottant peut chevaucher brièvement d'autres flottants (mise en scène de capture) — comportement placeholder existant, hors périmètre.

## 3. Décisions techniques prises

- **Tokens = 2 points de remplacement** : couleurs dans `UIColors.CYBER_*`, styles/police/effets dans `ExpeStyle` — consigné en règle d'or dans CLAUDE.md (zéro littéral de style dans l'UI d'expédition).
- **Le BFS vit dans ExpeRun** (règle de jeu : qu'est-ce qui est atteignable), la vue ne fait que l'afficher, les hôtes séquencent (UI). La vue reste passive (signal d'intention inchangé).
- **`atteignables()` en un BFS** (composante résolue + frontière découverte) recalculé à chaque `rafraichir()` — cartes ≤ 12 nœuds, négligeable.
- **`habiller_bouton` séparé de `bouton`** : les boutons créés dynamiquement (cibles/objets du combat) passent par le même point de style.
- **Scanlines sous les voiles** de transition/issue (jamais au-dessus des overlays modaux ajoutés ensuite).
- Piège GDScript consigné : `as` a une précédence PLUS BASSE que `==` — `x == [..] as Array[int]` caste la comparaison, pas le tableau (parenthéser).

## 4. Fichiers créés / modifiés

**Créés**
- `scripts/autoloads/ExpeStyle.gd` — factories de la peau (police mono, panneaux, boutons, chips, scanlines)
- `scenes/ui/cyber_scanlines.gdshader` — effet scanlines sobre
- `docs/recap-ch10/avant/` + `apres/` — captures avant/après (9 + 9, cf. §5)

**Modifiés**
- `scripts/autoloads/UIColors.gd` — section tokens `CYBER_*`
- `systems/expedition/expe_run.gd` — `chemin_vers()`, `atteignables()` (navigation par chemin)
- `scenes/expedition/ExpeCarteView.gd` — clic sur tout nœud atteignable, curseur/atténuation inaccessibles, halo d'invitation, grille + peau, `DELAI_PAS`
- `scenes/expedition/ExpeditionScreen.gd` — trajet séquencé (`jouer_deplacement` multi-pas, `_trajet_en_cours`), peau (fond, en-têtes mono, cadres carte/journal, boutons, recap, popups, message 1 en `CYBER_DANGER`)
- `scenes/expedition/SandboxExpe.gd` — trajet séquencé miroir
- `scenes/expedition/ExpeLancementPanel.gd` — peau (modal néon, paliers radio, PARTIR/Annuler)
- `scenes/combat_ctb/CombatCtbUi.gd` — fond scindé cyberpunk (`_dessiner_fond`), barre d'actions, chips de file, boutons, intro/issue, scanlines
- `scenes/combat_ctb/CarteCombattantCtb.gd` — accents de camp, mono, chips de statuts
- `scenes/ui/EcranMessage.gd` — cadre néon + mono + scanlines, correction autowrap
- `scenes/village/Village.gd` — accent du message 2 → token
- `tests/TestExpeCarte.gd` — +14 assertions navigation (3 nouveaux tests)
- `tests/ScreenshotTool.gd` — mode `flux` (lancement / recap / Game Over)
- `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 9 + addendum, décomptes runtime) : ScriptsLoad 124, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26.**

Ce chantier :
- `TestExpeCarte` **53** (+14, 3 nouveaux tests) — chemin de longueur 1 = adjacence (`[voisin]`), destination à 2 pas via un résolu → chemin complet `[voisin, deux_pas]`, nœud visible sans chemin résolu NON atteignable, cible = position → refus, nœud non découvert → refus ; **trajet multi-nœuds joué dans le VRAI `ExpeditionScreen`** (séquencé `DELAI_PAS`, position finale correcte, UNE seule résolution — aucun re-déclenchement en traversée —, destination résolue normalement) ; Fin d'étage visible d'emblée mais atteignable par chemin résolu seulement (arrivée par chemin → choix ouvert) ;
- `TestScriptsLoad` **125/125** (+1 : ExpeStyle) ;
- suites inchangées **toutes vertes aux décomptes baseline** : CTB 63, CombatUi 21 (aucune assertion visuelle — rien à adapter), Recompenses 48, ExpeNoeuds 24, ExpeCombat 45, ExpeditionFlow 28, **FluxExpedition 65** (adjacence = chemin synchrone : la navigation par chemin est bien un sur-ensemble), GameOver 26, TierCap, Drops, Forge, VillageBuildings, HoloXlsx, HoloTraffic ; **boot 30 s sans erreur**.

**Captures avant/après** (validation Rhend/Christophe) : `docs/recap-ch10/avant/` et `docs/recap-ch10/apres/` — 9 vues du pipeline : `_shot_expe_lancement` (panneau de lancement), `_shot_expe_init`/`_shot_expe_explore` (carte, affixes/objets, popup), `_shot_ctb_embuscade`/`_shot_ctb_tour_joueur`/`_shot_ctb_cibles`/`_shot_ctb_issue` (combat), `_shot_expe_recap` (fin de run), `_shot_gameover` (message 1). Généré par `SHOT_MODE=expe|flux|combat` (mode `flux` ajouté ce chantier).

**Manuel restant : passe visuelle complète en jeu réel** (lancement → carte → trajet multi-nœuds au clic → combat → recap → Game Over) — les captures donnent l'essentiel, le ressenti en mouvement (trajet séquencé, curseurs) se juge en jouant.

## 6. Questions ouvertes

1. **Direction cyan/magenta** : contrepoint magenta pour le camp adverse — à valider par Christophe (le token se change en une ligne).
2. **Scanlines** : intensité 0,10 par défaut — trop/pas assez ? Paramètre du shader, réglable au token.
3. **Police monospace système** (Consolas/Cascadia) : suffisant en intérim ; la DA apportera-t-elle une fonte embarquée (les builds export sur d'autres OS retomberont sur la fallback système) ?
4. **DELAI_PAS = 0,12 s** par pas de trajet : à calibrer en jouant (ressenti).
5. **SandboxExpe** : ses contrôles dev restent bruts — l'habiller n'a pas de valeur joueur, mais si les captures de calibrage doivent être « propres », un mode presentation pourrait venir plus tard.
