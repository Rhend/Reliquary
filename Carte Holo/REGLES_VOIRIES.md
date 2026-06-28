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
Le moteur **ne connaît pas** de type « usine », « cimetière », « supermarché »… Il lit
seulement, par case :

1. **Une APPARENCE** = la couleur de fond, classée dans **6 familles** :

   | Famille | Couleur peinte | Rendu |
   |---|---|---|
   | **Bâtiment** | gris-bleu | volume (boîte par défaut) à la hauteur tapée |
   | **Route** | magenta | voirie (cf. règles de voirie ci-dessus) |
   | **Eau** | cyan | nappe animée + liseré cyan |
   | **Parc** | vert olive | champ d'arbres épars, **plat** |
   | **Sport** | sable / tan | **stade de baseball complet** (gazon + losange + gradins + projecteurs) |
   | **Pont** | gris acier | ouvrage en hauteur — **feuille « Surélevé » uniquement** |

   Une couleur qui ne tombe dans aucune famille → **VIDE** (rien dessiné).

2. **Une HAUTEUR + une FORME** = le texte tapé dans une case du bloc (ex. `12g`,
   `6`, `18P`). Hauteur en mètres ; **5 formes** seulement :
   `B`=boîte, `P`=pyramide, `C`=cylindre, `D`=dôme, `G`=gradins.
   Sans nombre → **hauteur par défaut (3 m)** ; **la hauteur 0 n'existe pas** (taper
   un petit nombre, ex. `1`, pour « plat »).

### Contraintes dures (valables pour TOUS les bâtiments)
- **Forme non-boîte (P/C/D/G) → se dessine sur le RECTANGLE englobant** le bloc. Pour
  un cylindre/dôme/pyramide/gradins **net, peindre un footprint rectangulaire plein**
  (sinon la forme flotte au-dessus de cases vides). La **boîte** suit les cases telles
  quelles (emprises en L permises).
- **Hauteur/forme = le code tapé sur UNE case du bloc** (le plus haut gagne si
  plusieurs).
- **Deux blocs de même couleur qui se touchent FUSIONNENT.** Pour les séparer (deux
  bâtiments distincts, un « enclos »), poser une **bordure medium/thick** entre eux
  (même mécanisme que la voirie).

---

## 1. Bâtiment générique — toutes proportions
Famille **Bâtiment**. Du carré minimal au grand bloc, **hauteur libre**, forme libre
(`B`/`P`/`C`/`D`). Aucune contrainte : type passe-partout.

## 2. Usine désaffectée — large et basse
Famille **Bâtiment**, forme `B`. Footprint **rectangulaire allongé**, **nettement plus
étalé que haut** (hauteur basse, ex. `2`). **Jamais une tour.**

```
BON (hall allongé, bas)        MAUVAIS (carré haut = lit comme une tour)
B B B B B B  (h=2)             B B
B B B B B B                    B B  (h=18)
```
> Note rendu : pas de primitive « hall industriel » ; l'effet vient **uniquement** de
> la proportion large+basse. Une boîte fine et haute lira « gratte-ciel ».

## 3. Casse auto — enclos plat compact
Famille **Bâtiment**, forme `B`, footprint **tendant au carré**, **hauteur quasi nulle**
(`1`). Entourer d'une **bordure medium** pour la lecture « enclos ».
> Ajustement technique : **les épaves au sol ne sont pas modélisées**. Le rendu réel est
> une **dalle basse** ceinturée — c'est l'enclos plat qui porte la lecture, pas un détail
> de carcasses.

## 4. Supermarché / hypermarché — bas et très étalé
Famille **Bâtiment**, forme `B`, footprint **large, peu haut** (`2`).
> **Le parking n'est jamais généré automatiquement** : le moteur ne dessine **que** ce
> qui est peint. Peindre soi-même le parking à côté (cases de la famille voulue) si on
> en veut un.

## 5. Cimetière — champ plat étendu, régulier
Peindre en famille **Parc** (recommandé) sur une **emprise vaste et régulière, d'un seul
tenant**.
> Ajustement technique **important** : **« stèles fines en grille » n'est pas rendu** (pas
> de primitive de stèles). Le rendu honnête le plus proche est un **champ plat** : soit
> Parc (arbres épars), soit une **dalle Bâtiment basse** (`1`) si l'on veut une surface
> nue. Choisir selon l'effet voulu, mais **ne pas attendre une grille de stèles**.

## 6. Stade / arène — empreinte massive et compacte
**Tendance carrée ou ovale, ramassée (jamais allongée)**, hauteur moyenne. Deux rendus
possibles — choisir explicitement :
- **Famille Sport** (sable/tan) → **stade de baseball complet** (gazon, losange,
  gradins en bol, projecteurs, tableau). L'ellipse s'ajuste à l'emprise.
- **Famille Bâtiment + forme `G`** (gradins) → **arène générique** en gradins étagés
  (footprint **rectangulaire** obligatoire, cf. §0).

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

## 9. Colline / désert (bordure) — NON SUPPORTÉ aujourd'hui
**Aucune famille « colline » ni « désert » n'existe** sur la feuille Carte (le relief
procédural a été retiré ; la carte est 100 % data-driven).
> ⚠ **Piège** : la seule couleur sable/tan est la famille **Sport** → peindre du
> « désert » sable produirait un **stade de baseball**, pas une étendue aride.
>
> Tant qu'une famille dédiée + son rendu de relief n'existent pas, **ne pas peindre de
> colline/désert**. (Feature à ajouter côté moteur si on la veut : nouvelle famille de
> couleur + builder de ruban de relief en périphérie.)

---

## Pourquoi ces règles
Le moteur **n'a aucune sémantique de type** : il classe chaque case dans 1 des 6
familles de couleur, regroupe les bâtiments par adjacence, et leur applique la
hauteur + la forme tapées. Toute la lecture « usine », « stade », « cimetière » repose
donc **sur la proportion de l'emprise et le code de forme/hauteur** — pas sur un type
caché. Respecter la silhouette de chaque type, c'est donner au moteur les seules
informations qu'il sait traduire ; une proportion fausse (tour étalée, stade allongé,
désert sable) sort un rendu faux ou un autre objet. Les formes non-boîte exigent un
footprint rectangulaire parce qu'elles se calent sur le rectangle englobant ; les blocs
de même couleur se séparent par bordure pour ne pas fusionner. C'est le pendant, côté
volumes, de la règle de voirie « rectangles nets reliés par des blocs carrés ».
