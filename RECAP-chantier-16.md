# Chantier 16 — Compétences du héros en combat CTB

## Contexte

Le combat se jouait avec Attaquer/Défendre/Objet ; `ActionCtb.COMPETENCE`
était « prévue par l'architecture, sans contenu ». Le simulateur
d'équilibrage a montré qu'aucun soin n'existe entre les nœuds (PV
persistants) : le full-clear est hors de portée — il manquait un outil de
gestion des PV et un vrai choix offensif par activation.

## Arbitrages de design (proposés par Claude, à invalider si besoin)

1. **Les compétences appartiennent au COMBATTANT** (`CombattantCtbData.
   competences`) : le moteur est générique (un futur ennemi pourrait en
   porter), l'IA actée ne les joue JAMAIS (règle « IA sans Défendre »
   étendue) — donc aucun effet sur les runs auto (simulateur, tests).
2. **Cooldown en ACTIVATIONS du lanceur** : posé à l'usage (valeur .tres),
   décrémenté à l'OUVERTURE de chaque activation du lanceur. Pas de coût en
   ressource (pas de mana inventée).
3. **Deux compétences de dotation** (data-driven,
   `data/progression/competences_heros.tres`, pattern équipement de départ) :
   - **Frappe lourde** — ATTAQUE_MULT ×1.6, cooldown 3. Pipeline d'attaque
     COMPLET (mitigation, crit, règles de Lieu, Défendre, plancher) : une
     frappe lourde critique multiplie les deux ; l'événement « attaque »
     standard déclenche le zoom-duel.
   - **Second souffle** — SOIN_PCT_PV_MAX 25 %, cooldown 4. LA réponse
     mesurée au problème des PV persistants : soigner coûte une activation
     (l'ennemi joue pendant ce temps) — c'est un arbitrage, pas un cadeau.
4. **Effets typés** (`Enums.EffetCompetence` — jamais de string magique) ;
   garde-fous moteur : compétence non possédée ou en recharge = activation
   perdue journalisée (l'UI ne propose que le légal).
5. **UI** : un bouton par compétence du combattant actif, recréés à chaque
   tour ; GRISÉ « (n) » en recharge (état temporaire d'un contenu possédé —
   la règle « absent, pas grisé » vise le contenu non débloqué) ; ABSENTS si
   le combattant n'en a pas. Ciblage partagé avec Attaquer/Objet.

## Implémentation (fait)

- `CompetenceCtbData`, `DotationCompetencesData`, deux .tres de contenu ;
  `CtbCombattant.cooldowns` + helpers ; moteur : décrément à l'ouverture
  d'activation, `_resoudre_competence`, `_resoudre_attaque(mult)` ;
  CtbPont : dotation sur le combattant transitoire du héros.
- UI : boutons + ciblage + événements `competence`/`soin` (flottants).
- Tests : `TestCompetences.tscn` (21) — dégâts exacts, composition avec les
  règles de Lieu, soin clampé, cycle de cooldown, garde-fous, dotation,
  boutons (présents/grisés/absents).

## Périmètre strict

- 2 compétences seulement (pas de surdesign) ; valeurs provisoires, à
  calibrer au simulateur (qui ne les joue pas — politique IA).
- Pas de compétences ennemies (données prêtes, IA hors scope).
- Pas d'acquisition en jeu (Forge/équipements plus tard) : dotation fixe.
