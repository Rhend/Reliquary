# Déclarer un LIEU d'expédition (HoloMap)

Un **lieu** = une zone explorable, reliée à son entité par un **ID**. Idée directrice :

> **Écris l'ID (ex. `biome_foret`) dans UNE cellule de la zone → elle devient explorable.
> Sans ID = décor inerte.**

Tout se fait sur la feuille **« Carte »**. **Plus de couleurs de tier, plus de feuille « Lieux ».**

---

## Le geste principal : l'ID dans une cellule

Dans **n'importe quelle cellule** de la zone, tape l'**ID de l'entité** :

```
┌───────────────┐
│ biome_foret   │   ← l'ID, dans une case de la zone
│               │
└───────────────┘
```

- L'ID est un **texte de type identifiant** (lettres, `_`), ex. `biome_foret`.
- Il ne doit pas ressembler à un **code hauteur/forme** (`15P`, `9`, `12G`, `P`).
- Tu peux mettre l'**ID** dans une cellule **ET** un **code hauteur/forme** dans une AUTRE
  cellule de la même zone : ils cohabitent sans interférence.
  Exemple : `biome_foret` + `15P` dans deux cellules = pyramide de 15 m, explorable.

---

## La bordure : NEUTRE, juste pour délimiter

Une bordure (trait **épais**, couleur quelconque — **aucune couleur signifiante**) sert
**UNIQUEMENT** à séparer **deux zones de même fond collées**.

```
même apparence, 2 lieux distincts → une bordure neutre au milieu
┌─────┬─────┐
│ ░░░ │ ▓▓▓ │   (sinon le moteur les verrait comme une seule zone)
└─────┴─────┘
```

Si tes zones ont déjà des apparences différentes (ou sont séparées par du vide / une
route), **pas besoin de bordure**.

---

## Le reste vient de l'entité (`.tres`), pas d'Excel

Comme l'ID pointe vers une entité, ces infos viennent du **jeu**, pas de la carte :

| Info | Source |
|---|---|
| **Tier** (couleur du pin / des piliers) | l'entité — **démarre Commun, évolue en jeu** |
| **Nom** + **lore** (tooltip) | l'entité (`nom_affichage_fr`) |
| **Découverte** (lieu visible ou non) | état de jeu (découvert ou non) |

- **Non découvert** : le bâtiment/décor **reste visible**, mais **aucun** pin / clic /
  contour. Rien ne dit que c'est un lieu.
- **Découvert** : pin + tooltip + **piliers d'énergie** au survol + clic → expédition.

---

## IDs disponibles

| ID à taper | Lieu |
|---|---|
| `biome_foret` | Forêt Sombre |
| `biome_marecage` | Marécage Putride |
| `biome_montagne` | Montagne |

> Un ID **sans entité** correspondante → lieu **ignoré** (signalé dans la console). On
> n'invente jamais un lieu à partir d'un ID inconnu.

---

## ☑️ Checklist d'un lieu

- [ ] Une **zone d'apparence** peinte sur la feuille **Carte**
- [ ] (si besoin) une **bordure neutre** pour la séparer d'une zone de même fond collée
- [ ] L'**ID de l'entité** (ex. `biome_foret`) tapé dans **UNE cellule** de la zone

---

## 💡 En une phrase

> **L'ID dans une cellule = un lieu cliquable. La bordure ne sert qu'à délimiter.**
