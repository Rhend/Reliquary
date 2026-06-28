# Specs assets — Carte Holographique (HoloMap 3D)

> Fiche technique à destination de **Christophe** (et de toute personne fournissant des
> assets pour la carte). But : que les assets s'intègrent **sans friction** dans le moteur
> existant, qui est **100 % procédural, wireframe émissif, en GL Compatibility (Godot 4.6)**.
>
> Idée directrice :
> **« On ne plaque pas du réalisme sur un hologramme. On fournit de la géométrie propre et
> des sprites émissifs sur fond noir, pensés pour briller en fil de fer. »**

---

## 0. Comprendre le rendu (à lire avant de modéliser)

La carte n'est PAS un rendu classique texturé. Chaque volume est dessiné de **deux façons
simultanées** :

1. **Arêtes en fil de fer** (`PRIMITIVE_LINES`) — trait néon émissif. **Ce sont les arêtes
   de la géométrie qui forment le dessin.** Plus la topologie est propre, plus le wireframe
   est lisible.
2. **Faces pleines insérées** (triangles, légèrement rétractées à 96 % via `FACE_INSET`) —
   remplissage semi-transparent émissif, pour que le volume ne soit pas creux et que les
   arêtes ressortent par-dessus.

**Conséquence directe pour le modeleur :**
- La **silhouette et les arêtes = le dessin final**. Une face lisse subdivisée en 200 tris
  produit un wireframe illisible (un fouillis de triangles). On veut **peu de polygones, des
  arêtes franches, une topologie qui raconte la forme**.
- **Pas de smoothing / pas de normales douces** sur les angles : on veut des arêtes dures
  (hard edges) partout. Un cube reste 12 arêtes visibles, pas un blob.
- **Pas de bevel décoratif** ni de boucles de subdivision « pour faire joli » : chaque
  arête en plus est une ligne néon en plus à l'écran.

---

## 1. Ce qui a le plus d'impact (priorités)

| Prio | Asset | Pourquoi | Format |
|---|---|---|---|
| **P1** | 3–5 **meshes landmarks** low-poly | Donne une identité à la ville (le procédural ne fait que des silhouettes génériques) | `.glb` |
| **P1** | **Atlas d'enseignes / pins néon** (sprites) | Débloque les **lieux cliquables** (chantier en attente) + enseignes de façade | `.png` |
| **P2** | **Skybox / fond d'horizon** + LUT de color-grading | Ambiance globale, gradient cyberpunk | `.png` / `.exr` |
| **P2** | Texture **scanlines / glitch** pour le post-process | Le shader `holo_post` est prêt mais sans texture (à 0) | `.png` |
| **P3** | **Police** cyberpunk émissive | Enseignes, labels de lieux, HUD | `.ttf` / `.otf` |
| **P3** | **Sprites de particules** (fumée, étincelles, motes) | Améliore les effets aujourd'hui 100 % procéduraux | `.png` |

---

## 2. Meshes 3D — specs strictes

### Format & livraison
- **Format : `.glb`** (glTF binaire). Un fichier par modèle. Pas de `.blend`, `.fbx`, `.obj`.
- **Triangulé** à l'export (pas de n-gons). Quads en modélisation OK, mais export triangulé.
- **Une seule mesh par fichier** (pas de hiérarchie complexe ; un `MeshInstance` racine).

### Budget polygones
- **Bâtiments / landmarks : 50 à 600 triangles.** En dessous de 1000 dans tous les cas.
- Raison : chaque arête devient une ligne néon. Au-delà, le wireframe sature et le coût grimpe
  (GL Compatibility, cible aussi machines modestes).

### Topologie / style
- **Hard edges partout**, pas de smoothing groups, pas de normales adoucies.
- **Pas de bevels, pas de loop cuts décoratifs.** Les détails se font par la **silhouette**,
  pas par la densité de maillage.
- Formes **anguleuses, lisibles de loin** (esthétique « blueprint / hologramme »).
- **Pas de faces internes** ni de géométrie cachée (tout sera vu en transparence émissive).
- Surfaces planes = **une face** (ne pas trianguler-subdiviser un mur plat).

### Échelle, pivot, orientation (TRÈS IMPORTANT)
Le moteur travaille en **mètres réels** puis renormalise toute la carte pour tenir dans le
cadrage caméra (`taille_cellule = TAILLE_MONDE_CIBLE / grille`). Donc **modéliser à l'échelle
réelle** ; l'échelle absolue dans Godot est gérée par le moteur.

- **1 unité Blender = 1 mètre.**
- **Repères du monde de jeu :**
  - **1 case de la grille Excel = 10 m** (`taille_case_m`).
  - **1 étage / hauteur de maison ≈ 3 m** (`hauteur_defaut_m`).
  - Donc une tour de 20 étages ≈ **60 m de haut** ; une emprise de 3×3 cases = **30×30 m**.
- **Empreinte au sol = multiple de 10 m** quand c'est possible (le modèle se cale alors sur
  des cases entières de la grille).
- **Pivot : au CENTRE de l'empreinte au sol, posé sur Y = 0** (le bas du modèle touche le
  sol ; le modèle « pousse » vers +Y). PAS de pivot au centre du volume, PAS sous le sol.
- **Axes (convention glTF / Godot) : +Y vers le haut, -Z vers l'avant** (la « façade »
  principale regarde -Z). Appliquer rotation + échelle avant export (transform = identité).
- **Modèle centré sur (0,0)** dans le plan horizontal.

### Matériaux / textures sur les meshes
- **Aucune texture nécessaire, aucun matériau PBR.** Le moteur réassigne ses propres
  shaders émissifs (`holo_line` pour les arêtes, `holo_face` pour les faces).
- Si tu veux suggérer des **zones de couleur différentes** (ex. néon d'accent sur une partie),
  sépare-les en **groupes de faces nommés** (material slots distincts, même sans vraie
  texture) — on pourra mapper un slot → une teinte. Sinon, un seul slot suffit.
- **Pas de modificateurs non appliqués** (Mirror, Array, Subsurf…) : tout appliqué à l'export.

### Liste de modèles souhaités (exemples)
- Gratte-ciel / tour signature, spire ou antenne centrale de la ville.
- Pont haubané ou pont levant (pour le calque « Surélevé »).
- Château d'eau, grue de chantier, pylône électrique, cheminée industrielle.
- Véhicule héro / dirigeable / drone (props mobiles éventuels).

---

## 3. Sprites 2D / billboards — specs

Énorme rapport qualité/coût. Tout en **émissif sur fond NOIR pur transparent**.

### Format & dimensions
- **`.png`, fond transparent (alpha)**, couleur sur **fond noir** (`#000000`), pas blanc :
  le compositing est additif/émissif, le noir = invisible, le clair = lumineux.
- **Dimensions power-of-two** : 128, 256, 512, 1024 px de côté.
- **Atlas** quand plusieurs petits éléments : une grille régulière (ex. 4×4 cases de 256 px
  dans un 1024²), cases de **taille identique**, marge interne pour éviter le bleeding.

### Familles de sprites
- **Pins / icônes de lieux** (chantier « Lieux cliquables ») : pictos holographiques nets,
  lisibles à petite taille, style ligne fine + glow. Prévoir un **état neutre** + un **état
  surbrillance** (sélection).
- **Enseignes néon de façade** : logos fictifs, idéogrammes, flèches, typographies courtes.
  Format **bandeau horizontal** (ex. 512×128) pour se plaquer sur les façades.
- **Fumée / volutes / nuages doux** : niveaux de gris doux, bords flous (multiplie déjà un
  shader `holo_fumee`).
- **Particules** : étincelle, point lumineux (mote), éclat glitch — petits (64–128 px).

---

## 4. Environnement — skybox, LUT, post-process

- **Fond d'horizon / skybox** : dégradé **bleu-nuit cyberpunk** + champ d'étoiles + brume
  basse. Livrer soit un **panorama équirectangulaire** (`.exr` ou `.png`, ratio 2:1, ex.
  2048×1024), soit un **simple dégradé vertical** (256×1024) si on reste sur un fond plat.
- **LUT de color-grading** : table de correspondance couleur standard (**texture 256×16 ou
  PNG « Hald CLUT » 512²**) pour teinter toute la scène d'un coup. Ambiance visée :
  cyans/magentas saturés au cœur, désaturation froide en périphérie (épouse le **gradient de
  richesse** déjà calculé par le moteur selon la distance au centre).
- **Texture post-process** pour `holo_post` : **scanlines** fines + grain + motif de
  **glitch/distorsion** (PNG tileable, 512² ou 1024², niveaux de gris).

---

## 5. Police

- **`.ttf` ou `.otf`**, licence utilisable dans un jeu distribué (vérifier les droits).
- Style **cyberpunk / techno**, lisible en petit (labels de lieux, HUD), idéalement
  **monospace ou condensée**. Prévoir au moins **latin complet + chiffres + ponctuation**.
- Éviter les fontes trop fines (le glow émissif les mange).

---

## 6. Checklist de livraison (à cocher avant d'envoyer)

**Meshes :**
- [ ] `.glb` triangulé, 1 modèle par fichier, < 1000 tris.
- [ ] Hard edges partout, aucun smoothing, aucun bevel décoratif.
- [ ] Échelle en mètres réels (case = 10 m, étage = 3 m).
- [ ] Pivot au centre de l'empreinte, posé sur Y = 0, façade vers -Z.
- [ ] Transform appliqué (rotation/échelle = identité), modificateurs appliqués.
- [ ] Pas de faces internes/cachées, pas de texture PBR.

**Sprites :**
- [ ] `.png` alpha, couleur sur fond NOIR, dimensions power-of-two.
- [ ] Atlas en grille régulière si plusieurs éléments.

**Environnement / police :**
- [ ] Skybox/LUT/post aux formats indiqués.
- [ ] Police avec licence vérifiée.

---

## 7. Pourquoi ces contraintes (récap)

Le moteur dessine **les arêtes** de la géométrie en néon + des **faces translucides
insérées**, sans aucune texture sur les volumes. Donc : **peu de polygones, arêtes franches,
silhouette lisible** = le dessin est beau ; à l'inverse une mesh dense/lisse = un wireframe
sale. Les sprites sont composités en **émissif** → fond noir obligatoire. L'échelle réelle
(case 10 m, étage 3 m) garantit que les modèles se calent sur la grille avant la
renormalisation caméra. C'est le pendant « assets » des règles déjà en vigueur côté gabarit
(`REGLES_VOIRIES.md`) : **des formes nettes et normalisées pour un rendu net.**
