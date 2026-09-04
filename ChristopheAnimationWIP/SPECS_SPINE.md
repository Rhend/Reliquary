# 🦴 Intégrer un export Spine dans Reliquary

Fiche pour **Christophe**.
But : un export qui rentre dans le jeu **direct**, sans qu'on ait à le réparer.

> Ce document n'explique pas comment animer. Il explique ce que le **moteur**
> attend de ton export, et pourquoi il refuse parfois de l'afficher.

---

## 🗺️ Le trajet d'un export

```
   SPINE                TON DÉPÔT              LE PROJET               LE JEU
  ┌───────┐          ┌──────────────┐       ┌────────────┐        ┌──────────┐
  │ .skel │          │ Christophe   │       │  assets/   │        │ ShowRoom │
  │ .atlas│  ──────► │ AnimationWIP/│ ────► │ personnages│ ─────► │    +     │
  │ .png  │  export  │  <Perso>/    │  Ben  │     /      │registre│  combat  │
  └───────┘          └──────────────┘       └────────────┘        └──────────┘
                      zone d'échange          zone du jeu
                     (non lue par Godot)       (importée)
```

Tu déposes dans **`ChristopheAnimationWIP/`**. Tu ne touches jamais à `assets/` :
c'est l'étape d'intégration, elle demande de corriger deux ou trois choses et de
vider un cache. Si on pose directement dans `assets/`, Godot importe un asset à
moitié raccordé et crache des erreurs difficiles à lire.

---

## 1️⃣ Ce que le moteur lit vraiment

| Fichier | Rôle | Format attendu |
|---|---|---|
| `<Perso>.skel` | Le squelette : os, slots, skins, animations | **Binaire** (pas le `.json`) |
| `<Perso>.atlas` | La **carte** des images : quelle image, dans quelle page, où | Texte |
| `<Perso>.png`, `_2.png`, `_3.png`… | Les **pages** d'atlas (les pixels) | PNG, `pma:true` |

Les trois sont solidaires. Le `.skel` dit « pose l'attachement `R_H_Idle_Torse` »,
l'`.atlas` dit « il est dans `Relic_3.png`, à tel endroit », et le `.png` fournit
les pixels.

> **Casse un maillon et le personnage se monte, s'anime… et ne dessine rien.**
> C'est la signature de tous les problèmes qui suivent : ça ne plante pas
> franchement, ça devient invisible.

⚠️ Le nombre de pages peut changer d'une livraison à l'autre (Relic est passé de
4 à 5 pages avec les costumes). Ce n'est pas un problème — signale-le juste dans
ton message, qu'on ne cherche pas un fichier qui n'existe plus.

---

## 2️⃣ 🥇 La règle n°1 : l'atlas doit nommer les **VRAIS** `.png`

C'est **le** piège, et il est revenu à chaque livraison.

La première ligne de chaque page, dans le `.atlas`, est le **nom de fichier** que
le moteur ira charger. Elle doit correspondre **au caractère près** aux `.png`
livrés à côté.

```
   ❌ CE QU'ON A REÇU              ✅ CE QU'IL FAUT
   ─────────────────────          ─────────────────────
   Test_Aniamtion.png             Relic.png
   size:4096,4096                 size:4096,4096
   ...                            ...
   Test_Aniamtion_2.png           Relic_2.png
   ...                            ...

   … alors que les fichiers        … et les fichiers
   livrés s'appelaient             livrés s'appellent
   Relic.png, Relic_2.png…         Relic.png, Relic_2.png…
```

Résultat côté jeu : `Resource file not found: Test_Aniamtion.png` × 5, et un
héros invisible.

### Pourquoi ça arrive

Parce que les pages sont nommées **à l'export**, d'après le nom de l'atlas dans
Spine. Si tu exportes sous un nom (`Test_Aniamtion`) puis que tu **renommes les
fichiers à la main** (`Relic.png`), le `.atlas` garde l'ancien nom **à
l'intérieur** : le renommage ne suit pas.

### La règle

> ## 🚫 Ne renomme jamais un fichier après l'export.
> Ré-exporte avec le bon nom.

Le nom d'export doit être le nom du personnage : `Relic`, `FlameBot`, `WorkBot`.
Tu dois obtenir, sans y toucher :

```
Relic.skel   Relic.atlas   Relic.png   Relic_2.png   …
```

Et la 1ʳᵉ ligne de `Relic.atlas` doit dire `Relic.png`.

> ✅ **Ouvre le `.atlas` dans un bloc-notes et regarde cette ligne avant
> d'envoyer.** C'est 5 secondes, et ça nous a coûté une soirée deux fois.

---

## 3️⃣ Les animations : des noms exacts

Le jeu appelle les animations **par leur nom**, écrit en dur dans le code. Une
faute de casse et le geste ne se joue pas — silencieusement, sans erreur.

| Nom exact | Quand | Type |
|---|---|---|
| `Idle` | En permanence, hors action | **Boucle** |
| `Attack_CaC` | Le personnage frappe au corps à corps | One-shot → retour `Idle` |
| `Attack_Shoot` | Attaque à **distance** (héros uniquement pour l'instant) | One-shot → retour `Idle` |
| `Hit` | Le personnage encaisse un coup | One-shot → retour `Idle` |
| `Death` | Le personnage meurt | One-shot, **pose finale TENUE** |

Points à retenir :

- **`Death` ne revient pas au repos.** La dernière image reste à l'écran :
  soigne-la, c'est elle qu'on voit pendant tout le reste du combat.
- **Une animation absente est ignorée**, jamais une erreur. Les ennemis n'ont pas
  `Attack_Shoot` : quand le jeu leur demande un tir, il retombe sur `Attack_CaC`.
  Donc si tu livres 4 animations sur 5, ça tourne — mais le geste manquant ne se
  voit pas, et personne ne s'en aperçoit tout de suite.
- **Le retour au repos est enchaîné par le moteur.** Tu n'as pas à prévoir de
  transition de fin dans `Attack_CaC` ou `Hit` : finis sur la pose de repos, ça
  suffit.

---

## 4️⃣ L'origine du squelette = **les pieds**

Le jeu positionne le personnage par son **point d'appui au sol**. La racine du
squelette doit donc être posée entre les pieds, au niveau du sol.

```
            ╭───╮
            │ o │
           ╱│   │╲
            │   │
            ╱   ╲
        ───●───────  ← origine (0,0) ICI, au sol, entre les pieds
```

Si l'origine est au bassin ou au centre du dessin, le personnage flotte ou
s'enfonce dans le décor, et il faut le rattraper à la main dans le code.

---

## 5️⃣ La taille : le jeu **recadre** tout le monde

Le jeu ne fait pas confiance à la taille déclarée par l'export. Il **mesure** le
squelette au chargement et le met à l'échelle pour qu'il fasse une hauteur
**cible en px** — propre à CHAQUE personnage (voir l'encadré 📌 plus bas,
mise à jour 09/2026 : ce n'est plus la même pour tout le monde).

Deux conséquences pour toi :

**a) Tu n'as pas à viser une taille en pixels.** Travaille à l'échelle qui
t'arrange (Relic fait ~2900 unités, les bots 2500–3000). Le moteur normalise.

**b) ⚠️ Ce qui déborde dans la pose de repos rétrécit le personnage.** La mesure
porte sur la **pose de repos, attachements compris**. Un gros VFX rattaché et
visible dans cette pose est mesuré avec le corps : le personnage est mis à
l'échelle en comptant l'effet, donc **dessiné plus petit**.

```
   SANS VFX au repos                 AVEC VFX au repos
   ┌──────────┐                      ┌────────────────────┐
   │   ╭──╮   │  mesure = le corps   │  ✨    ╭──╮    ✨  │  mesure = tout
   │   │  │   │  → 240 px de perso   │  ✨    │  │    ✨  │  → ~130 px de perso
   │   ╱  ╲   │                      │  ✨    ╱  ╲    ✨  │     et du vide autour
   └──────────┘                      └────────────────────┘
```

Par défaut, garde donc les effets **hors de la pose de repos** : ils apparaissent
dans l'animation d'attaque, c'est leur place, et le personnage est mesuré juste.

#### 🐉 Sauf quand l'effet fait partie du personnage — les boss

Une aura permanente, des flammes qui ne s'éteignent jamais, un halo qui définit la
silhouette : sur un boss, c'est du **dessin**, pas un effet ponctuel. C'est
légitime, et ça ne remet rien en cause.

> ✅ **Fais-le, et signale-le.** « Ce boss a une aura posée au repos » suffit.
> Je règle alors sa hauteur **à la main** pour ce personnage-là, au lieu de laisser
> la mesure automatique compter l'aura comme du corps.

Ce que je dois éviter, ce n'est pas l'effet : c'est de le découvrir en voyant un
boss deux fois trop petit sans comprendre pourquoi.

> 📌 **À savoir (mis à jour 09/2026)** : c'est fait — chaque personnage a
> maintenant SA propre hauteur cible, pour que le gabarit porte un vrai message
> (un petit robot lit petit et utilitaire, un colosse lit imposant). C'est un
> **chiffre de design posé côté code** (un % relatif à un personnage étalon),
> **jamais déduit de la taille de ton fichier Spine** — on a essayé de le
> déduire des unités natives de chaque export, ça ne marchait pas : ces unités
> ne reflètent que l'échelle de travail de ton fichier, pas une intention de
> gabarit. **Ne compte donc toujours pas sur ton export pour porter l'échelle
> relative** : rigge à l'échelle qui t'arrange, comme avant. La seule chose
> nouvelle à me dire : l'intention de gabarit d'un nouveau personnage par
> rapport aux autres (« ce monstre doit lire deux fois plus imposant que
> WorkBot », par ex.) — c'est une info que j'ai besoin d'avoir de toi, elle ne
> se lit pas dans le fichier.

---

## 6️⃣ Les skins : deux conventions selon le personnage

### 🤖 Un ENNEMI : les 5 paliers de rareté, **deux formes possibles**

Un ennemi n'a qu'**un seul axe** à gérer : son palier de rareté, de Commun à
Légendaire. Deux façons de le porter — les deux marchent, **dis-moi simplement
laquelle tu as utilisée.**

#### Forme A — une skin par palier *(FlameBot et WorkBot aujourd'hui)*

| Skin | Palier en jeu |
|---|---|
| `FlameBot_Nv1` | Commun |
| `FlameBot_Nv2` | Peu commun |
| `FlameBot_Nv3` | Rare |
| `FlameBot_Nv4` | Épique |
| `FlameBot_Nv5` | Légendaire |

Le jeu pose **une** skin à la fois. C'est la forme la plus simple, garde-la tant
que le monstre n'a pas besoin d'être découpé.

#### Forme B — le personnage découpé, **un slot par pièce**

Quand le monstre est découpé comme le héros, chaque pièce a **son slot**, suffixé
par son palier :

```
WorkBot_Bras_D_Nv1   → le bras droit au palier 1 (Commun)
WorkBot_Bras_D_Nv5   → le même bras au palier 5 (Légendaire)
WorkBot_Tete_Nv4/5   → une tête partagée par les paliers 4 et 5
WorkBot_Socle        → pas de suffixe = commun à tous les paliers
```

C'est **exactement le même contrat de suffixe** que le héros (juste en dessous),
avec une différence qui simplifie tout :

> Le héros **cumule** plusieurs familles (corps + équipement + coiffure + visage).
> L'ennemi, lui, n'a que **les paliers**. Rien à empiler, rien d'exclusif :
> **un seul axe.**

⚠️ Attention au décompte : **5 paliers** pour un ennemi (`_Nv1` … `_Nv5`,
Commun → Légendaire), contre **6 niveaux** d'équipement pour le héros
(`_Nv1` … `_Nv6`). Le suffixe se lit pareil, l'échelle n'est pas la même.

### 🦸 LE HÉROS (Relic) : skins **cumulées** + niveaux portés par les **slots**

Relic est un cas à part, et c'est important de comprendre pourquoi : c'est ce qui
a coûté les cheveux invisibles.

Il n'a **pas** une skin par apparence. Le jeu **empile** plusieurs skins :

| Skin | Rôle | Statut |
|---|---|---|
| `Men_Global` | Le corps | **toujours posée** |
| `Men_Level` | Les pièces d'équipement | **toujours posée** |
| `Men_Level_Hit` | Les pièces de l'animation `Hit` | **toujours posée** |
| `Men_Random_Level_Clothing_1` | Le vêtement | **toujours posée** — *pour l'instant* 🔜 |
| `Men_Random_Level_Hair_1` / `_2` | Les coiffures | **alternatives** — une seule |
| `Men_Random_Face_Accessory_1` / `_2` / `Men_Random_Level_Face_Accessory_3` | Accessoires de visage | **alternatives** — un seul |

> 🔜 **Le vêtement rejoindra les alternatives.** Aujourd'hui il n'y en a qu'un, donc
> il est simplement toujours posé. Dès qu'un deuxième arrive, la famille bascule dans
> la même logique que les coiffures et les accessoires : **une seule à la fois**.
> Le `_1` du nom est déjà là pour ça — continue de numéroter (`_Clothing_2`, `_3`…),
> et signale-le à la livraison du deuxième : c'est ce jour-là qu'il faut me le dire,
> pas avant.

Et les **6 niveaux d'équipement** ne sont pas des skins : chaque pièce a **son
slot**, suffixé par son niveau.

```
   R_H_Idle_Tete_Nv3          → la tête du niveau 3
   R_H_Idle_Pentalon_Nv4/5    → un pantalon partagé par les niveaux 4 et 5
   R_H_Idle_Manche_G_Nv1_2_3  → une manche partagée par les niveaux 1, 2 et 3
   R_H_Idle_Torse             → pas de suffixe = commun à tous les niveaux
```

Le moteur **lit ce suffixe littéralement** pour ne garder que les pièces du niveau
affiché et retirer les autres. Donc :

> ## ⚠️ Le suffixe `_Nv<n>` est un **contrat**, pas une convention d'atelier.
> `_NV3`, `_nv3`, `_Nv 3`, `Nv3` sans le `_` → le moteur ne reconnaît rien, et la
> pièce reste affichée à **tous** les niveaux, par-dessus les autres.

Les deux notations de partage (`_Nv4/5` et `_Nv1_2_3`) sont comprises. Reste
cohérent, mais tu peux utiliser l'une ou l'autre.

### 🆕 Quand tu ajoutes une famille (les cheveux, par exemple)

Une nouvelle skin **n'apparaît pas toute seule**. Le jeu pose la liste des skins
qu'on lui a **écrite** ; ce qui n'y est pas n'existe pas.

C'est exactement ce qui s'est passé le 25/08 : les deux skins de coiffure étaient
irréprochables dans l'export, mais personne n'avait dit au jeu de les poser →
Relic est resté chauve, **sans la moindre erreur**.

> ✅ **Quand tu ajoutes une famille de skins, écris-le dans ton message de
> livraison.** Une ligne suffit : « nouvelle famille `Hair_1`/`Hair_2`, exclusives
> entre elles ». C'est la seule chose que le code ne peut pas deviner.

Et précise toujours si les nouvelles skins sont **cumulables** (elles s'ajoutent
au reste) ou **exclusives** (une à la fois) : les deux coiffures posées ensemble
donneraient deux chevelures superposées.

---

## 7️⃣ Nommer sans faute

Tous ces noms sont lus par du code, jamais par un humain qui corrigerait au vol.

| Règle | ✅ | ❌ |
|---|---|---|
| Casse exacte | `Attack_CaC` | `attack_cac`, `Attack_CAC` |
| Pas d'accent, pas d'espace | `R_H_Idle_Tete_Nv3` | `R_H_Idle_Tête Nv3` |
| Nom du perso identique partout | `WorkBot_2.png` | `WorkBott_2.png` ← (vrai, livraison des bots) |
| Numéros de page sans trou | `_2`, `_3`, `_4` | `_2`, `_4` |

---

## 8️⃣ Où déposer ta livraison

```
ChristopheAnimationWIP/
├── Relic.skel  Relic.atlas  Relic*.png       ← le héros
└── Ennemis_Usine/
    ├── FlameBot.skel  FlameBot.atlas  ...    ← un dossier par lot
    └── WorkBot.skel   WorkBot.atlas   ...
```

Un **dossier par lot** (ou par personnage), avec les trois types de fichiers
ensemble. Ce dossier est invisible pour Godot — c'est voulu : rien de ce que tu
déposes ne peut casser le jeu tant que ce n'est pas intégré.

---

## 9️⃣ Ce qui se passe ensuite (côté Benjamin)

Pour que tu saches où ça coince, quand ça coince :

1. **Copie** de `ChristopheAnimationWIP/<Perso>/` vers `assets/personnages/…`
2. **Vérification des noms de pages** dans le `.atlas` (cf. règle n°1)
3. **Purge du cache d'import** de Godot — l'importeur ne rejoue pas toujours
   l'import d'un `.skel`/`.atlas` remplacé, et on inspecte alors l'**ancien**
   squelette en croyant regarder le nouveau
4. **Déclaration dans le registre** (`data/personnages/spine_personnages.tres`) :
   chemins, skins, nombre de niveaux. Pour un monstre livré aux conventions, c'est
   **une entrée, et rien d'autre à toucher**
5. **Contrôle** : outil de vérification automatique, puis ShowRoom pour juger à l'œil

---

## 🔟 La ShowRoom : voir ton travail dans le jeu

Une vitrine dev est branchée dans le jeu (bouton **ShowRoom** en haut à gauche du
QG). C'est le meilleur endroit pour juger une livraison — et pour me dire ce qui
ne va pas.

| Touche | Effet |
|---|---|
| `Tab` | Vue libre (tout le monde côte à côte) ↔ vue combat (cadrage réel) |
| `←` `→` | Changer de monstre |
| `↑` `↓` | Changer de palier de rareté |
| `H` | Changer le niveau d'équipement du héros |
| `V` | Changer l'accessoire de visage |
| `B` | Éclairage (Nuit / Studio / Jour / Blanc) |
| `I` `A` `T` `X` `M` | Jouer : repos · mêlée · tir · coup reçu · mort |
| glisser / molette / `R` | Déplacer · zoomer · recadrer |
| `Échap` | Retour au QG |

En vue libre, le **héros est affiché en premier** (repère de mise en scène) ;
l'étalon de TAILLE, lui, est **WorkBot** (09/2026) — c'est par rapport à lui que
les autres gabarits sont réglés en %.

---

## ✅ Checklist avant d'envoyer

| ✔ | Contrôle |
|---|---|
| ☐ | Export **binaire** (`.skel`), pas `.json` |
| ☐ | Fichiers nommés d'après le personnage, **sans renommage manuel après export** |
| ☐ | 1ʳᵉ ligne de chaque page du `.atlas` = le nom réel du `.png` (ouvrir et regarder) |
| ☐ | Animations présentes et bien orthographiées : `Idle`, `Attack_CaC`, `Hit`, `Death` (+ `Attack_Shoot` pour le héros) |
| ☐ | `Death` finit sur une pose propre — elle reste à l'écran |
| ☐ | Origine du squelette **entre les pieds, au sol** |
| ☐ | VFX visible dans la pose de repos : seulement si c'est **voulu** (boss) — et dans ce cas, **signalé** |
| ☐ | Ennemi : les 5 paliers, en **skins** `<Perso>_Nv1` … `_Nv5` **ou** en **slots** `…_Nv1` … `_Nv5` — dis lequel |
| ☐ | Héros : suffixes de slot `_Nv1` … `_Nv6`, sans faute de casse |
| ☐ | Message de livraison : **ce qui est nouveau**, et si c'est cumulable ou exclusif |

---

## 📕 Étude de cas — la livraison « cheveux » du 25/08/2026

Trois défauts dans un seul envoi. Aucun n'était une faute de dessin : les trois
étaient des questions de **plomberie**.

| # | Le défaut | Ce que ça donnait | Le signal |
|---|---|---|---|
| 1 | Pages d'atlas nommées `Test_Aniamtion*.png` | **Aucune texture** chargée, héros invisible | 15 lignes de `Resource file not found` |
| 2 | Deux skins de coiffure jamais déclarées au jeu | Relic **chauve** — le travail livré ne s'affichait pas | ❗ **aucun** : c'est le plus dangereux |
| 3 | Taille déclarée par l'export : **573** unités pour un squelette qui en mesure **2917** | Héros **5× plus grand** que les monstres | ❗ aucun non plus, juste l'œil |

Ce qu'on en tire, de ton côté comme du mien :

- **Toi** : ne pas renommer après export, et **dire ce qui est nouveau** dans la
  livraison. Le défaut n°2 n'apparaît dans aucun log — seulement à l'œil, et
  seulement si on sait qu'il faut chercher des cheveux.
- **Moi** : le jeu ne croit plus la taille déclarée par l'export, il **mesure** le
  squelette (défaut n°3 réglé pour de bon), et un test automatique compare
  désormais la hauteur rendue de chaque personnage — un perso hors d'échelle fait
  échouer la vérification au lieu de se voir trois jours plus tard.

---

*Une question, un cas qui ne rentre pas dans ces règles, une convention qui te
gêne pour animer : dis-le. Ces règles servent le pipeline, pas l'inverse — la
plupart peuvent bouger si elles te coûtent du temps de dessin.*
