# Transmission ClaudeDesktop — Chantier 10 + retours de playtest

Branche `ReworkCombat`, commits `5cc6001` → `a956425`. Détail complet : `RECAP-chantier-10.md` (+ addendum playtest) ; captures avant/après : `docs/recap-ch10/`.

## Chantier 10 livré (2 volets)

1. **Peau cyberpunk intérimaire** sur tout le pipeline expédition (lancement, carte, combat, recap, Game Over). Tous les choix visuels vivent en **2 points remplaçables** pour la DA de Christophe : tokens couleurs `UIColors.CYBER_*` + factories `ExpeStyle` (police mono système, panneaux à bordure néon, boutons, chips, scanlines sobres). Cyan dominant / magenta en contrepoint (camp adverse), **rouge réservé Artefact/danger**, palette de rareté inchangée (source unique des couleurs de palier).
2. **Navigation par chemin** (règle actée) : clic sur n'importe quel nœud révélé atteignable via des nœuds résolus, trajet séquencé visible (pas de téléportation), nœuds traversés inertes (aucun re-déclenchement), nœud inaccessible atténué + non cliquable. BFS dans `ExpeRun.chemin_vers` / `atteignables` ; l'adjacence clavier reste un sous-ensemble (chemin de longueur 1).

## Retours de playtest Rhend — tous livrés

- **Fonds biome du combat RESTAURÉS** (leur remplacement cyberpunk était une erreur — le reste de la peau validé « bien mieux aligné à la DA ») : la peau n'habille que le chrome, par-dessus les biomes.
- **File d'initiative encadrée sur fond opaque** (`CYBER_BG`) : se détache du biome visuel.
- **Sol de scène + emplacements de personnages** : ligne d'horizon + bande (`CYBER_SOL`), ellipse d'emplacement par combattant, placeholders de sprites = **boules de lumière** (`EnergyBoule`) aux accents de camp, éteintes à la mort. Les futurs sprites se poseront sur les mêmes points d'appui (`_pieds`).
- **Hex « Expéditions » du hub → ouvre la HoloMap DIRECTEMENT** (plus de détour par le panneau) ; panneau de lancement **agrandi** (640 px), DA validée.

## Arbitrage acté (Rhend)

Le panneau Expéditions (consultation des biomes + boutons **Évoluer** biomes/créatures) n'a plus d'accès depuis le hub → rebranchement **reporté au rework du QG**. D'ici là : évolution des biomes/créatures inaccessible en jeu (assumé), pastille d'alerte du hex Expéditions possiblement allumée sans destination.

## État des tests

ScriptsLoad 125, ExpeCarte 53 (+14 navigation), FluxExpedition 65, GameOver 26, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCombat 45, ExpeditionFlow 28 — toutes vertes ; boot 30 s sans erreur.

## Points en attente

- Validation **Christophe** : direction cyan/magenta, intensité des scanlines (réglables au token).
- `DELAI_PAS` du trajet (0,12 s/pas) à calibrer en jouant.
- **Dette bloquante du futur chantier drops** (arbitrage ch.9) : dès qu'une run mute autre chose que XP/Euren, reset complet de GameData avant `SaveManager.recharger()`.
- Rework QG : rebrancher le panneau Expéditions (cf. arbitrage ci-dessus).
