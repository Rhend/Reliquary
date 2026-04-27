# SPEC — Refonte Héro, UI Cycles & Hub Village

## Contexte
Projet : Artefact: Puppet Tale (Godot, GDScript).
Itération sur 3 axes : (1) statut du Héro, (2) lisibilité de l'UI de cycle d'aventure, (3) refonte du Village en hub à 3 boutons.
Les specs ci-dessous sont indépendantes et doivent être implémentées dans l'ordre indiqué en fin de document.

---

## SPEC 1 — Héro hors-système de Maîtrise

### Fonctionnel
- Il existe un et un seul Héro dans le jeu. Pas de sélection, pas de variantes.
- Le Héro **n'a pas** de Maîtrise ni de Rareté propre.
- Le Héro progresse **uniquement** via :
  - l'équipement porté (arme, armure, accessoire)
  - les passifs permanents débloqués par les autres entités (créatures, pièges, événements, équipements)

### Structure de données
- Créer une Resource `HeroData` (`res://data/hero/hero_data.gd`) :
  - `base_hp: int`
  - `base_atk: int`
  - `base_def: int`
  - `equipment: Dictionary` (slots : "weapon", "armor", "accessory")
- Pas de champ `mastery`, pas de champ `rarity` sur le Héro.

### Hors-scope
- Ne PAS créer de système de niveau du Héro.
- Ne PAS créer de progression XP du Héro.
- Ne PAS exposer le Héro dans le Hall des Évolutions.

### Critères de validation
- Le Héro est instanciable depuis une seule Resource.
- Aucune référence `hero.mastery` ou `hero.rarity` dans le code.

---

## SPEC 2 — UI Cycle d'aventure : liserets de camp + FX de tour

### Contexte
Le combat est résolu de manière **instantanée par la logique** (toute la séquence d'échanges est calculée en une frame), puis **rejouée cosmétiquement** par un lecteur visuel à cadence définie. Les FX décrits ci-dessous vivent dans la couche cosmétique uniquement et n'ont aucun impact sur la résolution.

### Architecture combat : résolveur + lecteur

Découplage obligatoire en deux couches.

**Couche 1 — `CombatResolver` (logique pure)**
- Prend en entrée `HeroData` + `CreatureData`.
- Retourne une séquence `Array[CombatStep]` où chaque step contient :
  - `attacker: String` ("hero" | "enemy")
  - `damage: int`
  - `target_hp_after: int`
  - `is_killing_blow: bool`
- Le résolveur calcule **tout** en une frame, jusqu'à la mort d'un des deux combattants.
- Aucune notion de temps, aucun signal, aucune animation.

**Couche 2 — `CombatPlayer` (cosmétique)**
- Reçoit la séquence du résolveur.
- Joue les steps un par un à une cadence définie (`step_duration` en secondes).
- Émet des signaux à chaque step pour piloter l'UI/FX :
  - `step_started(step: CombatStep)`
  - `step_ended(step: CombatStep)`
  - `combat_finished(winner: String)`
- C'est ici qu'on applique l'accélération x1/x2/x4.

**Cadence**
- `BASE_STEP_DURATION = 0.8` (secondes par échange)
- Multiplicateurs vitesse : `1.0`, `0.5` (x2), `0.25` (x4)
- Durée effective d'un step = `BASE_STEP_DURATION * speed_multiplier`

### FX 1 — Liseret de camp (statique)
- Panel Héro : liseret violet (`#8B5CF6` placeholder)
- Panel Ennemi : liseret rouge (`#DC2626` placeholder)
- **Toujours visible** pendant le combat, ne change jamais.
- Implémentation : `StyleBoxFlat.border_color` constant.

### FX 2 — Indicateur d'attaquant actif (Glow + Halo diffus)

Le panel de l'attaquant du step en cours reçoit un **double effet** dans la couleur de son camp (violet pour Héro, rouge pour Ennemi) :

**Glow (intensification du liseret)**
- Le liseret existant s'illumine : couleur plus saturée + légère augmentation d'épaisseur (ex : 2px → 4px).
- Effet net, contour précis.

**Halo diffus**
- Lueur diffuse autour du panel, **plus large et plus floue** que le glow.
- Même teinte que le camp, mais opacité plus basse (~40-50%).
- Étend la présence visuelle du panel actif sans masquer le contenu.

**Timing du FX d'attaquant**
- **Apparition** : au `step_started` du panel attaquant. Tween 0.1s pour une montée fluide.
- **Maintien** : pendant toute la durée du step (jusqu'au prochain `step_started`).
- **Disparition** : au `step_started` du step suivant (= switch d'attaquant) OU à `combat_finished`. Tween 0.1s.

**Implémentation suggérée**
- Glow : modifier `StyleBoxFlat` du panel via tween (border_color + border_width).
- Halo : `CanvasItem` enfant du panel avec un `ColorRect` ou texture flou en mode additif, animé via tween d'opacité.
- Centraliser les couleurs dans `res://ui/theme/combat_colors.gd` :
  - `HERO_BORDER_COLOR`, `ENEMY_BORDER_COLOR`
  - `HERO_GLOW_COLOR`, `ENEMY_GLOW_COLOR` (versions saturées)
  - `HERO_HALO_COLOR`, `ENEMY_HALO_COLOR` (versions diffuses, alpha bas)

### FX 3 — Impact côté receveur (Shake + nombre de dégâts)

À chaque step, **après** l'apparition du FX d'attaquant, le panel du receveur joue :

**Shake**
- Translation rapide du panel sur l'axe X (et léger Y).
- Amplitude : ~6-8 pixels.
- Durée : 0.15s.
- Easing : oscillation amortie (3-4 oscillations).

**Pop de dégâts**
- Un `Label` apparaît sur le panel receveur affichant `-X` (X = dégâts du step).
- Position : zone supérieure du panel (placeholder ajustable).
- Animation :
  - Apparition instantanée
  - Translation verticale vers le haut (~30 pixels)
  - Fade out sur 0.6s
- Couleur : rouge vif (`#FF3B3B` placeholder), légèrement plus saturé si `is_killing_blow`.
- Taille : police plus grande si `is_killing_blow`.

**Timing**
- Déclenché à `step_started`.
- Si la cadence est accélérée (x2/x4), les durées du shake et du pop sont **proportionnelles** au `step_duration` effectif (pour que le FX reste lisible et ne se chevauche pas avec le step suivant).

### Contrôle de cadence (UI)

Bouton/toggle dans l'UI de cycle d'aventure :
- 3 vitesses : x1, x2, x4
- Persiste entre les cycles (sauvegardé dans les paramètres joueur)
- Modifie le `speed_multiplier` du `CombatPlayer`

**Implémentation**
- Singleton `GameSettings` (autoload) avec champ `combat_speed: float`.
- `CombatPlayer` lit cette valeur au début de chaque step.

### Structure de données récap

```gdscript
# res://systems/combat/combat_step.gd
class_name CombatStep extends Resource
@export var attacker: String  # "hero" | "enemy"
@export var damage: int
@export var target_hp_after: int
@export var is_killing_blow: bool

# res://systems/combat/combat_resolver.gd
class_name CombatResolver
static func resolve(hero: HeroData, enemy: CreatureData) -> Array[CombatStep]

# res://systems/combat/combat_player.gd
class_name CombatPlayer extends Node
signal step_started(step: CombatStep)
signal step_ended(step: CombatStep)
signal combat_finished(winner: String)
func play(steps: Array[CombatStep]) -> void
```

### Hors-scope
- Pas de système d'initiative / vitesse différentielle entre Héro et ennemi pour le moment. Premier step = Héro par défaut.
- Pas d'animation de sprite des combattants (juste FX sur les panels).
- Pas de son pour l'instant.

### Critères de validation
1. Lancer un combat : tous les échanges sont calculés instantanément par `CombatResolver`, puis joués séquentiellement par `CombatPlayer`.
2. À chaque step, le panel de l'attaquant s'illumine (glow + halo de sa couleur de camp).
3. Le panel du receveur shake et affiche les dégâts en pop.
4. Quand l'attaquant change, le FX précédent disparaît avant que le nouveau apparaisse.
5. Le bouton vitesse x1/x2/x4 modifie la cadence sans casser les FX (ils restent proportionnels et lisibles).
6. Les liserets violet/rouge restent visibles en permanence sous tous les autres FX.

---

## SPEC 3 — UI Cycle d'aventure : panel de rencontre unifié

### Fonctionnel
Le panel de rencontre affiche **un seul événement à la fois**. Il est remplacé à chaque nouvel événement généré par la boucle.

Trois types d'affichage selon le type d'événement :

**Combat (70%)**
- Affichage géré par SPEC 2 (panels Héro vs Ennemi avec liserets et FX).
- Stats visibles : HP, ATK, DEF de chaque camp.
- Log de combat court intégré au panel.

**Piège (15%)**
- Affichage dans le **panel de rencontre** (PAS dans le bandeau sous les affrontements).
- Contenu :
  - Nom du piège
  - Icône
  - **Description claire de l'effet** (ex : "Vous perdez 15 HP", "DEF réduite de 20% pendant 30s")
  - Indicateur visuel "Piège" (couleur/icône distinctive)
- Durée d'affichage : jusqu'à génération de l'événement suivant.

**Événement positif (15%)**
- Affichage dans le **panel de rencontre**.
- Contenu :
  - Nom de l'événement
  - Icône
  - **Description claire du bénéfice** (ex : "+50 HP", "+10% ATK pendant 60s", "Gain de 20 ressources")
  - Indicateur visuel "Bonus" (couleur/icône distinctive)
- Durée d'affichage : jusqu'à génération de l'événement suivant.

### Structure de données
- Resource de base `EventData` avec sous-classes :
  - `CombatEventData`
  - `TrapEventData` (champ `effect_description: String`)
  - `PositiveEventData` (champ `effect_description: String`)
- Le panel de rencontre est un seul `Control` (`EncounterPanel`) qui swap son contenu via une méthode `display_event(event: EventData)`.

### Hors-scope
- Le bandeau sous les affrontements ne reçoit PLUS les pièges ni les événements positifs.
- Si ce bandeau servait uniquement à afficher pièges/événements, le supprimer.

### Critères de validation
- Lancer un cycle, observer 10 événements consécutifs : chaque événement (combat, piège, bonus) s'affiche dans le panel de rencontre, jamais dans le bandeau.
- Les descriptions d'effet sont lisibles sans avoir à passer la souris sur quoi que ce soit.

---

## SPEC 4 — Village : refonte en hub à 3 boutons

### Fonctionnel
La scène `Village` affiche 3 boutons principaux d'accès :

1. **Hall des Évolutions** → ouvre la scène/UI de progression globale (voir SPEC 5)
2. **Le Forgeron** → ouvre la scène/UI de crafting (voir SPEC 6)
3. **L'Aventure** → ouvre la sélection de biome (voir SPEC 7)

### Structure de données
- Scène `res://scenes/village/village.tscn`
- Chaque bouton ouvre une scène dédiée (pas une popup) :
  - `res://scenes/village/evolution_hall.tscn`
  - `res://scenes/village/forge.tscn`
  - `res://scenes/village/adventure_select.tscn`

### Critères de validation
- Les 3 boutons sont visibles à l'ouverture du Village.
- Chaque bouton ouvre la scène correspondante et permet le retour au Village.

---

## SPEC 5 — Hall des Évolutions

### Fonctionnel
Écran qui liste **toutes les entités du jeu** soumises au système de Maîtrise/Rareté :
- Créatures
- Pièges
- Événements (positifs)
- Équipements
- (Toute autre entité avec Maîtrise — à confirmer dans une itération ultérieure)

Pour chaque entité affichée :
- Nom
- Icône / portrait
- Rareté actuelle
- Barre de Maîtrise (progression vers le prochain palier)
- Seuil suivant (valeur numérique)
- Bouton "Évoluer" si seuil atteint (déclenchement manuel)

### Découverte
Les entités **non découvertes** apparaissent en :
- **Silhouette "???"** + slot numéroté (ex : "Créatures 1/3 découvertes", slots vides visibles)
- Pas d'info sur la rareté ou la maîtrise tant que non découvertes.

### Structure de données
- L'écran lit un singleton `MasteryRegistry` (autoload) qui contient l'état de toutes les entités.
- L'évolution déclenche un signal `entity_evolved(entity_id: String, new_rarity: int)`.

### Critères de validation
- Toutes les entités découvertes sont visibles avec leur Maîtrise.
- Les non-découvertes apparaissent en silhouette numérotée.
- Cliquer sur "Évoluer" change la rareté visible immédiatement.

---

## SPEC 6 — Le Forgeron

### Fonctionnel
Écran de crafting organisé en **catégories par type d'équipement** :
- Arme
- Armure
- Accessoire

UI proposée :
- Onglets ou boutons de catégorie en haut.
- Liste des recettes de la catégorie active.
- Pas de scroll global obligatoire — la catégorie sélectionnée filtre la liste.

Pour chaque recette :
- Nom de l'équipement
- Icône
- Coût en ressources
- Bouton "Crafter" (grisé si ressources insuffisantes)

### Structure de données
- Resource `RecipeData` :
  - `equipment_type: String` ("weapon" | "armor" | "accessory")
  - `output_equipment_id: String`
  - `cost: Dictionary` (resource_id → amount)
- L'écran lit un registre `RecipeRegistry` (autoload).

### Critères de validation
- 3 onglets fonctionnels (Arme/Armure/Accessoire).
- Chaque onglet ne montre que les recettes de sa catégorie.
- Crafter une recette consomme les ressources et ajoute l'équipement à l'inventaire.

---

## SPEC 7 — L'Aventure : sélection de biome + panel de contenu

### Fonctionnel
Écran en deux parties :

**Partie gauche : liste des biomes débloqués**
- Bouton/carte par biome (avec nom + icône).
- Click sur un biome → met à jour la partie droite.

**Partie droite : panel de contenu du biome sélectionné**
Affiche tout ce qui est présent dans le biome :
- Créatures (max 3)
- Pièges
- Événements positifs
- Équipements lootables

Pour chaque entité :
- **Si découverte** : nom, icône, niveau de Maîtrise actuel, barre de progression, rareté actuelle.
- **Si non découverte** : silhouette "???" + slot numéroté (ex : slot 2/3 créatures).

**Bouton "Partir à l'aventure"** en bas du panel → lance le cycle dans le biome sélectionné.

### Structure de données
- Resource `BiomeData` :
  - `id: String`
  - `display_name: String`
  - `creature_pool: Array[CreatureData]` (taille max 3)
  - `trap_pool: Array[TrapData]`
  - `positive_event_pool: Array[PositiveEventData]`
  - `equipment_pool: Array[EquipmentData]`
- L'état "découvert" de chaque entité est stocké dans `MasteryRegistry` (champ `discovered: bool` par entité).

### Critères de validation
- Sélectionner un biome met à jour le panel à droite sans recharger la scène.
- Les entités découvertes affichent leur barre de maîtrise en temps réel.
- Les non-découvertes sont en silhouette avec slot numéroté.
- Le bouton "Partir" lance bien le cycle dans le biome choisi.

---

## Ordre d'implémentation recommandé
1. SPEC 1 (Héro) — fondation, tout dépend de ça
2. SPEC 4 (Village hub) — squelette de navigation
3. SPEC 5 (Hall des Évolutions) — lit MasteryRegistry
4. SPEC 7 (Aventure) — réutilise MasteryRegistry
5. SPEC 2 + SPEC 3 (UI Cycle) — peut se faire en parallèle
6. SPEC 6 (Forgeron) — dernier, dépend de RecipeRegistry pas encore défini
