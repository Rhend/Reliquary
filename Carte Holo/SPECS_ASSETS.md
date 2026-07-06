# 🎨 Specs assets — Carte Holographique

Fiche pour **Christophe**.
But : des assets qui s'intègrent **direct**, sans retouche.

> La carte est un **hologramme** : tout en **fil de fer néon**, sur fond noir.
> Pas de réalisme. Pas de textures classiques.

---

## ✅ La règle n°1 (à retenir avant tout)

> ## Peu de polygones. Arêtes franches. Formes simples.

Pourquoi ? Le moteur dessine **les arêtes** du modèle en néon.
- Beaucoup d'arêtes → fouillis illisible. ❌
- Peu d'arêtes nettes → beau dessin. ✅

```
   BON  ✅              MAUVAIS  ❌
   ┌─────┐            ┌─┬─┬─┬─┐
   │     │            ├─┼─┼─┼─┤
   │     │            ├─┼─┼─┼─┤   (trop de lignes,
   └─────┘            └─┴─┴─┴─┘    ça devient sale)
   cube net        cube sur-découpé
```

---

## 📋 Ce qu'il me faut (par priorité)

| Prio | Asset | Format |
|---|---|---|
| 🥇 | **3 à 5 bâtiments-vedettes** (tour, pont, antenne…) | `.glb` |
| 🥇 | **Icônes / enseignes néon** (pour les lieux + façades) | `.png` |
| 🥈 | **Fond du ciel** + filtre de couleur | `.png` |
| 🥈 | **Texture « scanlines / glitch »** (effet écran) | `.png` |
| 🥉 | **Police** cyberpunk | `.ttf` |

---

## 🧊 Modèles 3D — les 7 règles

| # | Règle | Détail |
|---|---|---|
| 1 | **Format** | `.glb` — 1 modèle par fichier |
| 2 | **Peu de polys** | **50 à 600 triangles** (jamais > 1000) |
| 3 | **Arêtes dures** | **Pas de lissage**, pas de bevel, pas de découpe inutile |
| 4 | **Triangulé** | À l'export |
| 5 | **Pas de texture** | Le moteur met ses propres couleurs néon |
| 6 | **Rien de caché** | Pas de faces internes |
| 7 | **Transform propre** | Rotation/échelle remises à zéro, modifs appliquées |

### 📏 Échelle (en mètres réels)

```
1 case de la grille  =  10 m
1 étage / maison     =   3 m
tour de 20 étages    ≈  60 m de haut
emprise 3×3 cases    =  30 × 30 m
```

> 👉 Modélise en **mètres réels**. Le moteur redimensionne tout seul.

### 📍 Pivot & orientation

```
        +Y (haut)
         │
         │   ╱ façade = vers -Z (avant)
       ┌─┴─┐
       │   │
   ────●───── ← pivot ICI : au sol (Y = 0), centré
       sol
```

- Pivot = **au centre, posé sur le sol** (Y = 0).
- Le modèle **monte** vers le haut.
- La **façade** regarde **vers l'avant (-Z)**.

---

## 📁 Où poser les fichiers + nommage

> ⚠️ JAMAIS dans `Carte Holo/` (ce dossier est exclu du jeu exporté).

| Type | Dossier |
|---|---|
| Modèles 3D `.glb` | `assets/props/holomap/` |
| Sprites `.png` (icônes, enseignes, fx) | `assets/sprites/holomap/` |
| Polices `.ttf` | `assets/fonts/` |

**Nommage** : `snake_case`, minuscules, **sans accents, sans espaces**, en français.

```
<famille>_<objet>[_variante].ext

supermarche_panneau_toit.glb      ← le prop n°1
usine_cheminee.glb
icone_lieu_musee.png
icone_lieu_musee_hl.png           ← _hl = version surbrillance
enseigne_bar_neon.png
fx_fumee.png
```

- **Pas de numéro de version** dans le nom (`_v2`, `_final`…) : on **écrase** le
  fichier au ré-export, le nom est l'identifiant stable côté moteur.
- Variantes d'un même objet : suffixe court (`_a`, `_b`, `_hl`).
- Dans le `.glb`, les objets internes gardent leurs noms de rôle (`cadre`, `texte`).

---

## 🎯 Prop n°1 — Panneau sur le toit du supermarché

Il remplacera le panneau procédural actuel (cadre ambre + barres cyan).
Toutes les règles 3D ci-dessus s'appliquent, plus ces précisions :

| Contrainte | Valeur |
|---|---|
| **Dimensions** | face ≈ **10–14 m de large × 4–6 m de haut** (en mètres réels) |
| **Pieds inclus** | béquilles / structure porteuse dans le modèle — le toit est **plat**, le panneau ne doit pas flotter |
| **Budget** | ~**100–300 triangles** (c'est un prop simple) |
| **Pivot** | au **point de contact avec le toit**, centré (Y = 0) |
| **Face lisible** | vers **-Z** (le moteur l'orientera vers la route) |
| **2 objets nommés max** | `cadre` (structure → néon **ambre**) et `texte` (détail → néon **cyan**) — le moteur applique une couleur par objet |

> ⚠️ Chaque arête du modèle devient **une ligne de néon**. Une face plane
> sur-découpée = un quadrillage lumineux moche. Le « texte » de l'enseigne =
> quelques formes géométriques simples (barres, glyphes), pas de vraie typo modélisée.

---

## 🖼️ Sprites 2D (icônes, enseignes, fumée)

| Règle | Valeur |
|---|---|
| **Format** | `.png` transparent |
| **Fond** | **NOIR** (jamais blanc) |
| **Couleur** | claire = lumineuse |
| **Taille** | **128 / 256 / 512 / 1024 px** (carré) |
| **Plusieurs petits** | les ranger en **grille régulière** (atlas) |

> 🔑 Pourquoi fond noir ? Le noir devient **invisible**, le clair **brille**.

À fournir :
- **Icônes de lieux** (pins) → 1 version normale + 1 version surbrillance.
- **Enseignes** → bandeau horizontal (ex. 512 × 128).
- **Fumée / étincelles** → gris doux, bords flous.

---

## 🌃 Ambiance (optionnel)

| Asset | Format | Note |
|---|---|---|
| **Ciel / horizon** | `.png` 2:1 (ex. 2048×1024) | dégradé bleu-nuit + étoiles |
| **Filtre couleur (LUT)** | `.png` | teinte cyan/magenta cyberpunk |
| **Scanlines / glitch** | `.png` carré, gris, tileable | effet « vieil écran » |
| **Police** | `.ttf` / `.otf` | techno, lisible en petit, **licence OK** |

---

## ☑️ Checklist avant d'envoyer

**Modèles 3D**
- [ ] `.glb`, 1 par fichier, **< 1000 triangles**
- [ ] Arêtes dures, **pas de lissage**
- [ ] Échelle réelle (case = 10 m)
- [ ] Pivot au sol, centré, façade vers l'avant
- [ ] Pas de texture, pas de faces cachées

**Sprites**
- [ ] `.png` transparent, **fond noir**
- [ ] Taille carrée (128 / 256 / 512 / 1024)

**Ambiance**
- [ ] Bons formats
- [ ] Police : licence vérifiée

---

## 💡 En une phrase

> **Formes simples + arêtes nettes + fond noir = tout brille bien.**
