# Déclarer un LIEU d'expédition (HoloMap)

Un **lieu** = un **biome** posé sur la carte, sur lequel le joueur peut cliquer pour
lancer son expédition. Idée directrice :

> **Un lieu = une ZONE entourée d'une bordure de couleur (= son tier) + l'id du biome
> tapé dans UNE case de la zone.**

Tout se fait sur la feuille **« Carte »**. **Pas de feuille séparée à tenir.**

---

## ⚠️ La règle de fiabilité (à retenir avant tout)

Le moteur ne lit **que les bordures en VRAIE couleur RGB**.

```
   BON  ✅                              MAUVAIS  ❌
   Accueil → Bordures →                Barre rapide → petite flèche
   « Autres bordures… » →              à côté de l'icône Bordures →
   onglet Bordure → Couleur →          « Couleurs du thème »
   Couleurs standard / Autres…
   (= couleur RGB fixe)                (= couleur de THÈME → ignorée)
```

- Bordure en **couleur de thème** → traitée comme du **décor**, jamais comme un lieu.
- Bordure **noire** (séparation de bâtiments) → décor, **jamais** un lieu.
- Toujours passer par **« Autres bordures… → Couleur »** pour une vraie RGB.

---

## Les 2 gestes pour un lieu

### 1️⃣ Entourer la zone (bordure = tier)

Entoure la zone d'une bordure **fermée** (les 4 côtés font le tour), style **épais**,
dans la **couleur de son tier** :

| Tier | Couleur | RGB à saisir (R, G, B) |
|---|---|---|
| Commun | gris | **154, 160, 166** |
| Peu Commun | vert | **46, 204, 113** |
| Rare | bleu | **59, 130, 246** |
| Épique | violet | **139, 92, 246** |
| Légendaire | or | **224, 165, 38** |
| Unique | rouge | **177, 18, 38** |

> 💡 La détection **tolère** une variation de teinte : les **couleurs exactes affichées
> en jeu** pour chaque rareté passent aussi. En cas de doute, prends celles ci-dessus.

```
Zone bordée FERMÉE  ✅           Bordure OUVERTE  ❌
┌───────────┐                   ┌───────────
│  ░░░░░░░  │                   │  ░░░░░░░
│  ░░░░░░░  │                   │  ░░░░░░░     (un côté manque
└───────────┘                   └───────────   → pas reconnu)
```

### 2️⃣ Écrire l'id du biome dans une case de la zone

Dans **n'importe quelle case** à l'intérieur de la bordure, tape l'**id du biome** :

```
┌───────────────┐
│ biome_foret   │   ← l'id, dans une case de la zone
│               │
└───────────────┘
```

- C'est l'id qui relie le lieu à la **bonne expédition**.
- L'id contient toujours un **underscore** (`biome_foret`, `biome_marecage`…) → le
  moteur le reconnaît tout seul et ne le confond pas avec un code de hauteur (`12g`).
- Un seul id par zone suffit. Tu peux mettre la hauteur/forme dans une **autre** case.

> 🔑 Le **fond** des cases (bâtiment, parc…) ne change pas : l'apparence reste, la
> bordure + l'id s'**ajoutent** par-dessus.

---

## Ce que le JEU décide (et pas l'Excel)

Comme un lieu **est** un biome, ces infos viennent de l'**état de jeu**, pas de la carte :

| Info | Source réelle |
|---|---|
| **Découverte** (le lieu apparaît ou non) | le biome est-il **découvert en jeu** ? |
| **Tier** (couleur du pin/contour) | maîtrise actuelle du biome |
| **Nom** + **lore** (tooltip) | fiche du biome dans le jeu |

Conséquences :
- Un biome **non découvert** → le décor **reste visible**, mais **aucun pin, aucun clic,
  aucun contour**. Rien ne dit que c'est un lieu.
- La **couleur de bordure** sert surtout à **repérer et délimiter** la zone. Si elle ne
  correspond pas au tier réel du biome, **le jeu gagne** (un avertissement est logué).

---

## ☑️ Checklist d'un lieu

- [ ] Une **bordure fermée** (4 côtés) autour de la zone, sur la feuille **Carte**
- [ ] Couleur de la bordure = **vraie RGB** (via « Autres bordures… → Couleur »), pas un thème
- [ ] Couleur = le **tier** voulu (cf. table)
- [ ] L'**id du biome** (ex. `biome_foret`) tapé dans **une case** de la zone

---

## 💡 En une phrase

> **Bordure de couleur fermée (vraie RGB) + l'id du biome dans une case = un lieu cliquable.**

---

> *Note : la feuille « Lieux » du classeur n'est plus utilisée par le moteur (méthode
> « id dans la case »). Tu peux l'ignorer ou la garder comme aide-mémoire.*
