# RECAP — Chantier 9 : Sanction de mort — Game Over, rechargement, compteur R-XXX

Branche : `ReworkCombat`. Règles actées 06/07/2026 appliquées : **mort de l'avatar = Game Over → retour à la dernière sauvegarde**, **compteur R-XXX méta-persistant** (3 chiffres, départ R-001, plafond d'affichage R-999). Remplace le comportement provisoire « défaite = extraction sans butin » du chantier 8.

## 1. Implémenté

- **§1 Compteur R-XXX méta-persistant** — support choisi : **fichier JSON dédié `user://IdleEvolutionMeta.json`** (`{version, reconstructions}`), géré par SaveManager (qui possède déjà l'I/O et l'écriture atomique) et **séparé de la sauvegarde de partie** : le rechargement ne le fait jamais reculer (testé). Init 1 (R-001), **aucun fichier créé avant le premier Game Over** ; incrément au Game Over avec **écriture immédiate** (il doit survivre au rechargement qui suit et à un crash). Plafond : **l'interne continue de compter au-delà de 999** (au plus simple, la donnée n'est pas perdue), seul l'AFFICHAGE clampe — le nom reste R-999. Formatage `R-%03d` en **un seul point** : `SaveManager.nom_reconstruction()`. **Nom du héros branché à la source unique** : appliqué aux champs `nom_affichage_fr/en` de l'entité `hero` (au boot + à chaque incrément) — Translations.entity_name, HeroPanel, pont CTB (cartes de combat, file d'initiative, journaux) en découlent sans aucun formatage dispersé ; identique FR/EN (matricule, pas un mot).
- **§2 Séquence de Game Over** — défaite en expédition : ① l'écran de combat affiche son issue (existant) ; ② **message 1** « R-004 est détruit... » (compteur COURANT, avant incrément) — `EcranMessage`, widget sobre plein écran partagé (fond noir, texte centré, clic/Entrée/Espace) ; ③ à la confirmation : **incrément méta + rechargement de la dernière sauvegarde** (`SaveManager.recharger()` — l'XP créditée pendant la run disparaît) ; ④ **message 2** « Reconstruction de R-005 complète. » (NOUVEAU compteur) sur le Village, clic → QG (badges + panneau rafraîchis). Message 1 vit sur l'écran d'expédition, message 2 sur le Village (après rechargement) — l'ordre et les compteurs distincts sont testés.
- **§3 Point de sauvegarde de référence** — réponse à la question du spec : **le débounce ne garantit RIEN au lancement** (2 s d'attente, timer possiblement froid) → **flush explicite** `SaveManager.sauvegarder_maintenant()` dans `Village.lancer_expedition()`, juste avant la création de l'écran (donc avant `demarrer()`). Et surtout : les **écritures sont SUSPENDUES pendant toute la run** (voir §2 des écarts) — la « dernière sauvegarde » est GARANTIE être celle du lancement. Conséquence testée : XP créditée en cours de run perdue au Game Over.
- **§4 Abandon** — fermer la fenêtre en pleine run : le flush de fermeture est bloqué par la suspension → **rien n'est écrit, à la réouverture l'état est celui du départ, run non entamée** — pas de Game Over, pas d'incrément (fermer n'est pas mourir). Testé (flush simulé pendant la run → fichier inchangé). Pas de bouton « abandonner » (non designé, conforme).
- **§5 Textes** — `gameover.detruit` / `gameover.reconstruit` (FR + EN), compteur injecté ; placeholders sobres (DA hors scope).

## 2. Écarts / interprétations (aucun silencieux)

- **Suspension des écritures pendant la run** (non demandée textuellement, NÉCESSAIRE) : depuis le chantier 8, chaque victoire déclenche la sauvegarde debouncée → sans suspension, une sauvegarde de MI-RUN devenait « la dernière sauvegarde » et la sanction était vide (« ni pendant la run ») ; le flush de fermeture écrivait aussi l'état de mi-run, contredisant le §4 (« à la réouverture, l'état est celui du départ »). Implémentation : `suspendre_ecritures()` au lancement (après le flush de référence), le **dirty est conservé** ; `reprendre_ecritures(flush=true)` à la sortie normale (les crédits de la run — XP + Euren de sortie — sont écrits immédiatement), `reprendre_ecritures(false)` au Game Over (rien à écrire, on recharge). Le fichier MÉTA n'est pas concerné (écrit en direct).
- **`recharger()` = ré-application du fichier sur l'état runtime** (pas de reset complet de GameData ni de changement de scène) : suffisant aujourd'hui — depuis la sauvegarde de lancement, une run ne mutate que `heros_xp`/`euren` (crédités par signaux ; les drops d'expédition n'existent pas). Documenté dans le code : à re-évaluer quand une run mutera d'autres états (drops, découvertes).
- **Méta illisible** → warning + compteur reparti à R-001 (pas de quarantaine `.corrupt` comme la sauvegarde de partie — fichier de 2 clés, enjeu faible). Consigné en question ouverte.
- **`_write_text_atomic` : backup dérivé du chemin** (`path + ".bak"`) au lieu de la constante `BACKUP_PATH` — sans quoi l'écriture du méta aurait fait tourner le fichier méta DANS le backup de la sauvegarde de partie. Comportement identique pour la sauvegarde (même chemin résultant), le méta gagne son propre `.bak`.
- **`sauvegarder_maintenant()` bloqué pendant une suspension** (garde) : n'arrive pas dans le flux réel (appelé avant de suspendre) — évite qu'un appel futur mal placé consomme le dirty en silence.

## 3. Décisions techniques prises

- **Le méta vit dans SaveManager** (pas un nouvel autoload) : il possède l'écriture atomique, les chemins, le cycle de vie de la persistance — un système de fichiers de plus chez lui, zéro API dupliquée.
- **Message 1 déclenche `retour_qg(recap)`** (signal existant) : le Village branche sur `recap.defaite` — pas de nouveau signal, l'écran d'expédition reste ignorant du méta/rechargement.
- **`EcranMessage`** (scenes/ui/) : widget générique confirme-une-fois, réutilisé pour les deux messages (et réutilisable par la future narration).
- **Chargement lazy du méta** (`_charger_meta()` à la première lecture) + application du nom au boot de SaveManager (GameData le précède dans l'ordre des autoloads).
- Tests : le méta réel est lu par les autoloads AVANT la protection des fichiers → les suites **réinitialisent l'état interne** (compteur 1) après la mise de côté.

## 4. Fichiers créés / modifiés

**Créés**
- `scenes/ui/EcranMessage.gd` — écran de message sobre plein écran (séquence Game Over)
- `tests/TestGameOver.gd` + `.tscn` — nouvelle suite (en CI)

**Modifiés**
- `scripts/autoloads/SaveManager.gd` — fichier méta R-XXX (`META_PATH`, `nom_reconstruction`, `compteur_reconstruction`, `incrementer_reconstruction`, `_appliquer_nom_hero` au boot), `sauvegarder_maintenant()`, `recharger()`, suspension (`suspendre_ecritures`/`reprendre_ecritures`, gardes dans `save()`/`_flush_save()`), backup atomique dérivé du chemin
- `scenes/village/Village.gd` — flush de référence + suspension au lancement ; `_sur_retour_expedition` branche défaite → `_terminer_game_over()` (incrément, reprise sans flush, rechargement, message 2) ; reprise + flush à la sortie normale
- `scenes/expedition/ExpeditionScreen.gd` — `_afficher_fin` : défaite → message 1 (compteur avant incrément) au lieu du recap
- `scripts/autoloads/Translations.gd` — `gameover.detruit` / `gameover.reconstruit` (FR + EN)
- `tests/TestFluxExpedition.gd` — protocole de protection ÉTENDU au fichier méta (+ `.bak`), sauvegarde de lancement, suspension (flush simulé sans effet), test 6 réécrit en séquence Game Over complète (2 messages dans l'ordre, compteurs distincts, XP de run perdue, nom à jour partout, méta round-trip)
- `.github/workflows/tests.yml`, `CLAUDE.md`

## 5. Résultats de test

**Baseline (rappel — chantier 8 + addendum, décomptes runtime) : ScriptsLoad 122, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 46.**

Ce chantier :
- **`TestGameOver` 26** (nouvelle suite, en CI) — formatage `R-%03d` (R-001/R-042/R-999), plafond : interne 1000 mais nom R-999, première partie sans fichier méta (aucun créé avant le premier Game Over), incrément → écriture immédiate + **round-trip disque réel** (relecture forcée), fichier méta séparé (ne contient pas la partie), nom héros = source unique (Translations + pont CTB, ré-appliqué à l'incrément), `recharger()` restaure heros_xp/euren SANS faire reculer le méta, suspension (flush et `sauvegarder_maintenant` bloqués, dirty conservé, reprise avec flush) ;
- **`TestFluxExpedition` 65** (+19) — sauvegarde de lancement (fichier = état exact du départ), écritures suspendues pendant la run (flush « fermeture » simulé → fichier inchangé), nom du héros en combat = R-XXX, crédits flushés à la reprise (plus de dirty en attente), **séquence Game Over complète** : compteur non incrémenté par l'extraction, message 1 « R-001 est détruit... » AVANT incrément, confirmation → écran libéré + compteur R-002 + message 2 « Reconstruction de R-002 complète. » sur le Village, XP de run PERDUE au rechargement, Euren intact, nom R-002 partout (entité + prochain transitoire), méta survivant à un rechargement supplémentaire + round-trip disque ;
- `TestScriptsLoad` **124/124** (+2 : EcranMessage, TestGameOver) ;
- suites inchangées **toutes vertes aux décomptes baseline** : CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, TierCap, Drops, Forge, VillageBuildings, HoloXlsx, HoloTraffic ; **boot 30 s sans erreur** ;
- sauvegarde ET méta réels du joueur **vérifiés intacts** après les suites (protocole `.avant_test` étendu).

**Manuel restant : mourir en jeu réel** (lire la séquence des deux messages, vérifier l'état restauré et le nouveau matricule au panneau Héros) — le flux est couvert par la suite, la passe manuelle valide le ressenti.

## 6. Questions ouvertes

1. **Méta illisible** : repart à R-001 avec warning — faut-il une quarantaine `.corrupt` comme la sauvegarde de partie (enjeu faible, 2 clés) ?
2. **Interne au-delà de 999** conservé dans le fichier — un usage futur (stats, succès) ou figer à 999 ?
3. **Messages placeholder** : l'`EcranMessage` est prêt à accueillir la narration de la reconstruction (dialogues Reliquaire, hors scope) — remplacer les textes ou enrichir l'écran à ce moment-là.
4. **`recharger()` par ré-application** : à re-évaluer dès qu'une run mutera d'autres états que heros_xp/euren (drops d'équipement/matériaux à venir) — un reset complet de GameData avant ré-application deviendra nécessaire.
5. **Suspension globale** : aujourd'hui seule une run d'expédition suspend ; si un système hors expédition progresse pendant une run un jour (idle village ?), sa progression serait différée au retour — acceptable ou à raffiner ?

## Addendum — Arbitrages design validés (06/07/2026)

Les 5 questions ouvertes ont été tranchées — **aucune modification de code** :
1. **Méta illisible → R-001 + warning** : conservé, pas de quarantaine — enjeu faible assumé.
2. **Compteur interne au-delà de 999** : conservé dans le fichier. Usage futur possible (stats, succès), l'affichage clampe.
3. **Messages placeholder** : conservés. L'`EcranMessage` sera enrichi/remplacé au chantier narration (dialogues Reliquaire), pas avant.
4. **`recharger()` par ré-application** : assumé. **Consigné comme dette BLOQUANTE du futur chantier drops** : dès qu'une run mute autre chose que XP/Euren, reset complet de GameData avant ré-application.
5. **Suspension limitée aux runs** : acceptable — aucun système ne progresse hors expédition (l'idle est abandonné). À rouvrir seulement si ça change.

L'écart « suspension des écritures pendant la run » est **validé** — il était nécessaire à la cohérence de la sanction.

Baseline inchangée après addendum : **ScriptsLoad 124, CTB 63, CombatUi 21, Recompenses 48, ExpeNoeuds 24, ExpeCarte 39, ExpeCombat 45, ExpeditionFlow 28, FluxExpedition 65, GameOver 26.**
