# Chantier 14 — Butin d'expédition (matériaux + ingrédients)

## Contexte

Depuis la mort de la boucle idle (Rework), les expéditions créditent XP, Euren
et Modules — mais AUCUN matériau. Conséquence : les keystones de la Forge
consomment « l'ingrédient rare du biome »… sans source. Ce chantier ferme la
boucle expédition → butin → Forge.

## Arbitrages de design (proposés par Claude, à invalider si besoin)

1. **Deux familles de butin**, appuyées sur les champs EXISTANTS de BiomeData :
   - la **ressource fréquente** du biome (`ressource_frequente_id`) : tombe à
     chaque VICTOIRE de combat (quantité selon le palier de profondeur — le
     palier gagne son premier effet mécanique) et dans les COFFRES ;
   - la **ressource rare** (`ressource_rare_id`) : CHANCE sur chaque victoire
     (montante avec la profondeur), garantie dans les coffres profonds.
2. **L'ingrédient de keystone (Forge) EST la ressource rare du biome**
   (constat d'implémentation : `ForgeSystem.node_ingredient_cost` lit
   `biome.ressource_rare_id`) — pas de troisième famille. La rare a une
   chance par victoire (montante avec la profondeur) et est GARANTIE ×2 sur
   le boss d'assaut, re-kill compris — l'assaut re-jouable devient la source
   fiable d'ingrédients, un rôle économique durable au-delà du premier Sceau.
3. **Crédit à la SORTIE seulement** — mêmes rails qu'Euren/Modules : défaite
   = rien. Le butin embarqué est visible pendant la run (jauge de risque) ;
   c'est la tension d'extraction du genre.
4. **Réglages data-driven** dans `data/expedition/butin.tres`
   (`ButinConfigData`) : quantités par palier, chances de rare, contenu des
   coffres, garantie boss. AUCUNE quantité en dur. Valeurs provisoires — le
   simulateur d'équilibrage (chantier outillage) servira à les calibrer.
5. **Aucune nouvelle ressource inventée** : on réutilise les ressources et
   ingrédients .tres/.json existants, pointés par les biomes.

## Implémentation (fait)

- `ButinConfigData` + `data/expedition/butin.tres` (quantités/chances par
  palier) ; ExpeRun : `butin_accumule`/`butin_credite`, RNG DÉDIÉ dérivé de
  la graine (les tirages de butin ne décalent pas les séquences des runs
  seedées existantes), crédit dans `_terminer` (rails Euren), champs de
  recap, `dernier_combat_recompenses.butin`.
- UI : ligne butin à l'écran d'issue de combat (`ctb.recompenses_butin`) et
  au recap d'expédition (`expe.recap_butin`) — absentes si vide (pilier
  « contenu absent ») ; helper `Translations.noms_quantites`.
- Tests : `TestButin.tscn` (23) — tirages exacts, gates, crédit à la sortie,
  défaite = rien, coffre, boss garanti.
- Le `multiplicateur` de PalierProfondeurData continue de circuler sans
  effet : les quantités par palier du .tres jouent ce rôle pour le butin.

## Périmètre strict

- Pas de drop d'ÉQUIPEMENT : l'équipement progresse par la Forge (ch.13),
  pas par le loot. (Décision : garder UNE seule voie de progression d'objet.)
- Pas de refonte du panneau Forge : seulement la consommation d'ingrédients
  des keystones re-testée avec la nouvelle source.
- L'affichage pendant la run et le recap réutilisent la peau cyberpunk
  (tokens + ExpeStyle), zéro littéral.
