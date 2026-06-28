# Règles de tracé des voiries (HoloMap)

Pour que les routes s'affichent proprement (médiane qui suit la route, virages qui
tournent, carrefours qui s'ouvrent), peindre la voirie (cases **magenta**) sur la
feuille « Carte » en respectant ces règles. Idée directrice :

> **Une route = un rectangle de largeur constante. Virages et carrefours = des blocs carrés qui relient ces rectangles.**

---

## 1. Routes droites, virages à 90°
Les routes sont **horizontales ou verticales**. Les virages se font à **angle droit**
(pas de diagonale, pas d'escalier).

## 2. Largeur constante ET alignée
Une route garde la **même largeur** sur toute sa longueur :
- **1 case** = départementale (1 voie/sens)
- **2 cases** = nationale (2 voies/sens)
- **4 cases** = autoroute (3 voies/sens)

Pour une route 2 ou 4 large, les lignes (ou colonnes) ont la **MÊME longueur** —
ne jamais en prolonger une seule.

```
BON (2-large aligné)        MAUVAIS (désaligné)
R R R R R                   R R R R R
R R R R R                   R R R R .   <- la 2e ligne dépasse
```

## 3. Virage = bloc carré, AUCUN moignon qui dépasse
Au virage, les deux branches se rejoignent en un **bloc carré** de la largeur de la
route (1×1, 2×2, 4×4). Aucune case ne doit dépasser au coin.

```
BON (2-large qui tourne)    MAUVAIS (moignon qui dépasse)
. . R R                     R . R R       <- la case en haut-gauche
. . R R                     R R R R          dépasse du coin
R R R R                     R R R R
R R R R                     R R R R
```

## 4. Carrefours : même largeur, bloc carré
Quand deux routes se croisent (T ou +), elles ont la **même largeur**, et le
croisement forme un **bloc carré** (2×2 pour deux routes 2-large). Éviter de
brancher une route 1-large directement sur une 4-large.

## 5. Tronçon d'au moins 3 cases
Entre deux virages/carrefours, un tronçon droit fait **≥ 3 cases** de long (sinon
ça ne se lit pas comme une route).

## 6. Pas de double usage
Une case de route ne sert **QUE** de route. Ne pas faire longer un immeuble par une
route en partageant des cases : laisse la route distincte des bâtiments (au moins
1 case d'écart, ou sépare avec une bordure medium).

---

## Pourquoi ces règles
Le moteur déduit, par case, le « corridor » (sens H ou V) et sa largeur, puis trace
la médiane au centre et les voies de part et d'autre. Les largeurs variables, les
moignons et les lanes désalignées rendent ce corridor ambigu → médiane qui saute.
En gardant des **rectangles de largeur constante reliés par des blocs carrés**, tout
reste net.

---
---

# Formes des zones (HoloMap)

Pour que chaque zone s'affiche proprement, peindre son emprise (cases colorées) sur
la feuille « Carte » en respectant la **proportion caractéristique de son type**.
Idée directrice :

> **Chaque type de zone a une silhouette. La forme peinte doit respecter la proportion du type ; sinon le rendu n'est pas garanti.**

## Statut de ces règles
- **Strictes** : le moteur les applique **à la lettre** à la génération. Il ne corrige
  pas un dessin qui les viole.
- **L'auteur peint en les respectant.** Si la peinture viole une règle ou crée un
  chevauchement, le moteur n'invente aucune correction : il applique la règle, le
  rendu peut être imparfait, **c'est à l'auteur de corriger l'Excel**. (Même
  philosophie que la voirie : « médiane qui saute » si mal peint.)
- But : **optimiser l'occupation de l'espace** et garantir un beau rendu — les
  proportions servent ça.

## 0. Ce que le moteur sait réellement rendre (vocabulaire)
Le moteur classe chaque case dans une **FAMILLE** d'après sa couleur de fond (plus
proche teinte). Chaque famille a un **rendu dédié** ; le reste de la lecture vient de
la **proportion de l'emprise** et du **code hauteur/forme** tapé dans une case.

| Famille | Couleur peinte | Rendu |
|---|---|---|
| **Bâtiment** | gris-bleu `3A4253` | volume (boîte par défaut) à la hauteur tapée |
| **Route** | magenta `D6248F` | voirie (cf. règles de voirie ci-dessus) |
| **Eau** | cyan `17C3C3` | nappe animée + liseré cyan |
| **Parc** | vert olive `5E7349` | champ d'arbres épars, **plat** |
| **Sport** | sable / tan `D2B48C` | **stade complet** (gazon + losange + gradins + projecteurs) |
| **Cimetière** | gris-ardoise `6B7A8F` | **champ de stèles holographiques** en grille + socles |
| **Usine** | brun rouille `8B5E3C` | **hall bas** + toit en dents de scie + cheminée |
| **Casse auto** | orange-rouille `B0560F` | **enclos clôturé** + petites épaves empilées |
| **Supermarché** | ambre `E8A23D` | **volume bas étalé** + bandeau d'enseignes néon |
| **Colline / désert** | ocre `C8A86A` | **ruban de relief** (buttes/dunes) — **bordure uniquement** |
| **Pont** | gris acier `9FB2C4` | ouvrage en hauteur — **feuille « Surélevé » uniquement** |

Une couleur qui ne tombe dans aucune famille → **VIDE** (rien dessiné).

**HAUTEUR + FORME** = le texte tapé dans une case du bloc (ex. `12g`, `6`, `18P`).
Hauteur en mètres ; **5 formes** : `B`=boîte, `P`=pyramide, `C`=cylindre, `D`=dôme,
`G`=gradins. Sans nombre → **hauteur par défaut (3 m)** ; **la hauteur 0 n'existe pas**
(taper un petit nombre, ex. `1`, pour « plat »).

### Contraintes dures (valables pour TOUTES les familles bâties)
- **Forme non-boîte (P/C/D/G) → se dessine sur le RECTANGLE englobant** le bloc. Pour
  un cylindre/dôme/pyramide/gradins **net, peindre un footprint rectangulaire plein**.
  La **boîte** suit les cases telles quelles (emprises en L permises).
- **Hauteur/forme = le code tapé sur UNE case du bloc** (le plus haut gagne si
  plusieurs). Usine/Casse/Supermarché **plafonnent** leur hauteur (zones basses) :
  inutile de taper un grand nombre, il sera écrêté.
- **Deux blocs de même couleur qui se touchent FUSIONNENT.** Pour les séparer (deux
  parcelles distinctes, un « enclos »), poser une **bordure medium/thick** entre eux
  (même mécanisme que la voirie).

## Gradient de richesse (automatique, toutes familles)
Le moteur ternit chaque zone selon sa **distance au centre géométrique** de la grille :
cœur = couleurs vives / néons actifs, périphérie = couleurs ternies / délabrement.
**Aucun marqueur à peindre** — c'est appliqué seul, à toutes les apparences, et ça ne
change **pas la nature** d'une zone (un supermarché reste un supermarché, juste plus
éteint en bord de carte). Réglable côté moteur (rayon du cœur riche, vitesse de chute,
luminosité/désaturation au plus pauvre).

---

## 1. Bâtiment générique — toutes proportions
Famille **Bâtiment**. Du carré minimal au grand bloc, **hauteur libre**, forme libre
(`B`/`P`/`C`/`D`/`G`). Aucune contrainte : type passe-partout.

## 2. Usine désaffectée — large et basse
Famille **Usine** (brun rouille). Footprint **rectangulaire allongé**, **nettement plus
étalé que haut**. Le moteur en fait un **hall** (toit en dents de scie + cheminée),
hauteur **écrêtée** (jamais une tour, même si on tape un grand nombre).

```
BON (hall allongé, bas)        MAUVAIS (carré étroit)
U U U U U U                    U U
U U U U U U                    U U
```
> Le toit en dents de scie se répartit sur le **grand axe** : un hall allongé donne
> plusieurs sheds lisibles ; un carré étroit n'en donne qu'un ou deux.

## 3. Casse auto — enclos plat compact
Famille **Casse** (orange-rouille), footprint **tendant au carré**. Le moteur ceinture
le bloc d'une **clôture basse** et parsème de **petites épaves empilées** → lecture
« enclos ». Hauteur ignorée (toujours basse). Pour bien isoler l'enclos d'un voisin de
même couleur, **bordure medium** autour.

## 4. Supermarché / hypermarché — bas et très étalé
Famille **Supermarché** (ambre), footprint **large, peu haut**. Le moteur pose un
**volume bas** + un **bandeau d'enseignes néon** sur la façade `+Z` (le bas de l'emprise).
> **Le parking n'est jamais généré automatiquement** : le moteur ne dessine **que** ce
> qui est peint. Peindre soi-même le parking à côté (cases de la famille voulue).

## 5. Cimetière — champ plat étendu, régulier
Famille **Cimetière** (gris-ardoise) sur une **emprise vaste et régulière, d'un seul
tenant**. Le moteur sème **une stèle holographique lumineuse par case**, alignée en
grille, sur un socle plat → mémorial numérique. **Hauteur ignorée** (stèles fixes).

```
BON (champ régulier d'un tenant)   MAUVAIS (cases éparses)
K K K K K                          K . K . K
K K K K K                          . K . K .
K K K K K                          K . K . K
```

## 6. Stade / arène — empreinte massive et compacte
Famille **Sport** (sable/tan). **Tendance carrée ou ovale, ramassée (jamais allongée)**.
Le moteur ajuste un **stade complet** (gazon, losange, gradins en bol, projecteurs,
tableau) à l'emprise. Pour une **arène générique** étagée, utiliser plutôt la famille
**Bâtiment + forme `G`** (gradins ; footprint rectangulaire obligatoire, cf. §0).

```
BON (ramassé, ~carré)          MAUVAIS (allongé = ne lit pas « stade »)
S S S S S                      S S S S S S S S S S
S S S S S                      S S S S S S S S S S
S S S S S
```

## 7. Parc — organique, irrégulier permis
Famille **Parc**. **Seul type où l'irrégularité est un atout** : emprise libre, contours
irréguliers bienvenus, **hauteur nulle**. Le moteur sème les arbres **case par case** →
n'importe quelle forme d'emprise fonctionne.

## 8. Eau (fleuve / lac) — continue, jamais en gouttes
Famille **Eau**. **Continuité obligatoire** : cases **adjacentes d'un seul tenant**.
- **Fleuve** = **ruban allongé** qui traverse.
- **Lac** = **masse large**.

```
BON (ruban continu)            MAUVAIS (gouttes éparses)
. E E E E E E .                E . . E . . E .
. . E E E E . .                . . E . . E . .
```
> Notes rendu : chaque case d'eau isolée reçoit son propre liseré → des gouttes
> donnent des taches sales. **Et** : un **code (hauteur/forme) tapé sur une case d'eau
> n'est PAS de l'eau haute** — il crée une **tour posée sur l'eau** (cas « 9c » sur le
> lac). Ne taper un code sur l'eau que si l'on veut volontairement cette tour.

## 9. Colline / désert — ruban de relief de BORDURE
Famille **Colline** (ocre `C8A86A`). Le moteur en fait un **ruban de buttes/dunes** qui
**cadre la ville**. Règle stricte : **périphérie uniquement**.
- Peindre un **cadre épais** (2–4 cases) le long des **bords** de la grille.
- **Ne pas en mettre au centre** : une butte ocre au milieu de la ville casse la lecture
  (le moteur la dessine quand même — c'est à l'auteur de l'éviter).
- Emprise **continue** le long du bord (comme l'eau) ; les hauteurs varient seules
  (dunes organiques), aucun code à taper.

```
BON (cadre de bord, 3 cases)       MAUVAIS (butte au centre)
O O O O O O O O                    . . . . . . . .
O . . . . . . O                    . . . O O . . .
O . ville . . O                    . . . O O . . .
O O O O O O O O                    . . . . . . . .
```

---

## Pourquoi ces règles
Le moteur classe chaque case dans une famille de couleur, regroupe les blocs par
adjacence (séparés par les bordures medium), et applique un **rendu dédié** par famille
+ la hauteur/forme tapée. La lecture « usine », « cimetière », « supermarché »… repose
sur **la famille (couleur) ET la proportion de l'emprise** : une proportion fausse (hall
en tour, stade allongé, cimetière épars, colline au centre) sort un rendu faux. Les
formes non-boîte exigent un footprint rectangulaire parce qu'elles se calent sur le
rectangle englobant ; les blocs de même couleur se séparent par bordure pour ne pas
fusionner. Le gradient de richesse, lui, ne dépend que de la **distance au centre** et
s'applique tout seul. C'est le pendant, côté volumes, de la règle de voirie
« rectangles nets reliés par des blocs carrés ».
