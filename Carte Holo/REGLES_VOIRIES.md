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
