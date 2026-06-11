# IdleEvolution — Guide projet pour Claude Code

Idle RPG de complétion sous **Godot 4.6** (GL Compatibility), GDScript, 1280×720.
Scène principale : `res://scenes/village/village.tscn`. Branche de travail : `dev`.

## Règles d'or (à respecter dans toute modification)

- **Data-driven** : tout contenu de jeu = un `.tres` dans `data/` (jamais hardcodé).
- **Équilibrage** : uniquement dans `scripts/autoloads/Balance.gd` (class_name, pas autoload).
- **Communication inter-systèmes** : uniquement via `EventBus` (aucun référencement direct).
- **Strings magiques interdits** : types d'entités → `Enums.EntityType.*`, effets de
  bénédiction → `Enums.BlessEffect.*` (seuls effets supportés : HEAL, XP_BONUS).
- **Noms affichés** : champ `nom_affichage_fr` (exception : les passifs utilisent `name`).
- **Couleurs de rareté** : `UIColors.tier_color(tier)`. Toutes les couleurs dans UIColors.
- **Textes UI** : via `Translations.T("clé")` (FR + EN) — pas de français en dur.
- **UI 100 % en code** : factories dans `UIHelpers` (class_name statique), widgets
  dans `scenes/village/widgets/`.
- **Pas de Luck** : la mécanique a été supprimée volontairement (2026-06). Ne pas réintroduire.

## Architecture

| Rôle | Fichier |
|---|---|
| Source de vérité runtime (charge .tres → dict `entities`) | `scripts/autoloads/GameData.gd` |
| Constantes d'équilibrage (XP, combat, drops, cadence) | `scripts/autoloads/Balance.gd` |
| Bus de signaux (pattern Observer) | `scripts/autoloads/EventBus.gd` |
| Boucle idle (timer, rencontres, CycleStats, drops) | `scripts/systems/AdventureSystem.gd` |
| Progression de Maîtrise (XP, plafonds, évolution manuelle) | `scripts/systems/MasterySystem.gd` |
| Effets de passifs (bonus plats + conditionnels) | `scripts/systems/PassiveSystem.gd` |
| Résolution de combat instantanée VIT-based (statique, pure) | `systems/combat/combat_resolver.gd` |
| Playback cosmétique des CombatStep | `systems/combat/combat_player.gd` |
| Hub hexagonal + panneaux JRPG (panneau `PANEL_FRACTION`, hub scalé `HUB_PANEL_SCALE`) | `scenes/village/Village.gd` |
| Contenu des panneaux (statiques, `build(host)`) | `scenes/village/panels/` |
| Sauvegarde (debounce 2 s, flush à la fermeture, écriture atomique) | `scripts/autoloads/SaveManager.gd` |

Autoloads (ordre dans project.godot) : UIColors, EventBus, Translations, GameData,
CycleData, SaveManager, GameSettings, MasterySystem, CombatPlayer, AdventureSystem,
PassiveSystem, MasteryRegistry, BiomeMechanics, TooltipOverlay.

## Conventions spécifiques

- **Panels ↔ Village** : HeroPanel/AdventurePanel/ForgePanel reçoivent le nœud Village
  (`host`) et n'utilisent QUE son API publique : `rp_content`, `make_evolve_btn()`,
  `show_banner()`, `village_tier()`, `adv_selected_biome_id`,
  `start_selected_expedition()`, `panel_ui_state()`, `launch_evolution_ritual()`.
- **Rafraîchir un panneau ouvert** = `_refresh_active_panel()` — JAMAIS `_open_panel()`
  (comportement toggle : il le fermerait).
- **Sections repliables** : `UIHelpers.collapsible_section(titre, couleur, ouvert,
  host.panel_ui_state())` pour que l'état survive aux reconstructions.
- `combat_ended` porte `remaining_hero_hp` ; le résumé de cycle porte `hero_id`.
- Évolution : TOUJOURS manuelle (action joueur via `MasterySystem.evolve_entity`).
- L'XP s'accumule au-delà des plafonds (jamais perdue) ; plafond créature dépend du
  tier du biome + de la zone (`Balance.CREATURE_CAP_*`).
- Paliers : Commun(0) → Peu Commun(1) → Rare(2) → Épique(3) → Légendaire(4) → Unique(5).
  Créatures max T4, équipements max T2 (`Balance.ENTITY_MAX_TIER`).
- Zones : Surface(0) / Profondeur(1, biome Rare+) / Abysse(2, biome Légendaire+) —
  zone FIXE par cycle, déterminée au lancement.

## Tests et validation

```bash
# Les 3 suites (chacune quitte avec un code ≠ 0 en cas d'échec) :
godot --headless --path . res://tests/TestScriptsLoad.tscn      # compile tous les scripts
godot --headless --path . res://tests/TestCombatResolver.tscn   # unités combat (24)
godot --headless --path . res://tests/TestExpeditionFlow.tscn   # boucle expédition (28)

# Boot rapide sans erreur :
godot --headless --path . --quit-after 30
```

- CI GitHub Actions (`.github/workflows/tests.yml`) lance ces 3 suites à chaque push.
- Après l'ajout d'un `class_name` — y compris quand il arrive via `git pull` sur une
  autre machine — lancer `godot --headless --path . --import` (ou Projet → Recharger
  le projet dans l'éditeur). Le cache `.godot/global_script_class_cache.cfg` est local
  et non versionné ; sans ça : « Parse Error: Could not find type … ».
- TOUJOURS lancer TestScriptsLoad après un refactor : il détecte les identifiants
  disparus (constantes, signaux) dans tous les scripts, autoloads chargés.
- `GameData._validate_entities()` warne au boot si un `.tres` est incomplet.
- **Simuler des clics dans un test headless** : la fenêtre racine fait **64×64 px**
  (la taille du projet est ignorée) → tout clic au-delà tombe hors fenêtre et le
  picking GUI échoue silencieusement. Faire d'abord
  `get_tree().root.size = Vector2i(1280, 720)`, puis `root.push_input(ev)`
  (motion + press + release) fonctionne.

## Sauvegarde

- `user://IdleEvolutionSave.json` (`%APPDATA%/Godot/app_userdata/IdleEvolution/`),
  `SAVE_VER = 13`, versions acceptées 11+. À chaque écriture l'ancienne sauvegarde
  devient `.bak` (rechargé automatiquement si la principale est illisible) ; un
  fichier illisible est copié en `.corrupt` au lieu d'être écrasé en silence.
- `save()` REFUSE d'écrire si `load_save()` n'a jamais tourné alors qu'une
  sauvegarde existe — un outil/test qui émet des signaux de progression sans
  passer par le Village ne peut plus détruire la progression du joueur.
- Étendre : nouvelle donnée joueur → `GameData.player` (auto) ; nouveau flag d'entité
  → `SaveManager.PERSISTED_FLAGS` ; nouvel état système → `_save_systems()/_load_systems()`.
- Ne JAMAIS écrire la sauvegarde dans un test : déconnecter les listeners de
  SaveManager (voir le pattern dans l'historique des tests d'intégration).

## ⚠ Flags de dev à désactiver avant release

- `Balance.ECLOSION_CLIC_VALUE = 25` → remettre à 1 (accélère l'éclosion pour les tests).
- `Village.DEBUG_TIER_BUTTONS = true` → boutons Tier ± en bas à gauche (modifient
  réellement GameData.village).
- `CombatScene.LOG_ENABLED = false` → journal de combat désactivé volontairement
  (le code est conservé ; remettre true pour le réactiver).

## Biomes (VS initiaux)

| Biome | Mécanique forte (Rare+) | Slot équipement | Unique |
|---|---|---|---|
| Forêt Sombre (`biome_foret`) | ambush (1er ennemi frappe avant) | Anneau | Oscar |
| Marécage Putride (`biome_marecage`) | poison (coups héros empoisonnent) | Armure | Cavalier Sans Tête |
| Montagne (`biome_montagne`) | endurcissement (dégâts héros −20 %) | Arme | Gorlab |

Progression d'un biome : T0 découverte → **T1 Peu Commun : son équipement est
obtenu (à T0) et auto-équipé** (`Balance.EQUIPMENT_UNLOCK_BIOME_TIER`,
`GameData.unlock_biome_equipment`) → T2 Rare : mécanique forte → T4 Légendaire :
biome secondaire révélé. Le joueur démarre SANS équipement.

Biomes secondaires (révélés au Légendaire du parent) : Collines, Ville Fantôme, Cimetière.
Ambiances visuelles : presets dans `BiomeBackground.PRESETS` (+ `accent_for_biome()`
utilisé par le séparateur VS).
