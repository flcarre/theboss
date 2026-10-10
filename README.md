# The Boss

Une app macOS qui surveille tes agents de code (Claude Code, Codex, Cursor, Pi, omp), sous forme de jeu
en pixel art façon Pokémon DS, dans la direction artistique des jeux TBFC. Tu es le boss : tu marches
dans ton bureau, puis dans l'open space où chaque session d'agent est un robot à son poste.

## Ce que fait l'app

| Dans le jeu | Fonction |
|---|---|
| Open space : un robot par session | Statut en direct de chaque agent : au travail (il tape), attend ton feu vert (il fait signe, bulle « ! »), terminé (il somnole) |
| Parler à un robot | Tâche, dernier ordre, action en attente ; journal de la conversation, retour à la session, dossier, commande de reprise |
| Écran mural de l'open space | Vue d'ensemble de tous les agents des 12 dernières heures, filtrable par statut |
| Ordinateur du boss | Limites des forfaits (Claude, Codex, Cursor) et tokens consommés par jour |
| Bibliothèque | Fichiers cachés qui pilotent les agents : CLAUDE.md, AGENTS.md, règles Cursor, skills, hooks, sous-agents, commandes, réglages |
| Bannette à courrier | Suggestions avec preuves et diff exact : règles apprises de tes corrections, réglages cassés à réparer ; appliquer, garder pour plus tard, ignorer |
| Tableau blanc | Stats : corrections pour 100 prompts par jour, tendance (le setup s'améliore ou se dégrade) |
| Armoire d'archives | Modèle du domaine local, une source de vérité par projet : intention, conventions écrites, décisions apprises, travaux récents, divergences entre CLAUDE.md et AGENTS.md ; export vers `.boss/domain.md` avec diff |
| Barre des menus, Dock, notifications | Compteurs, alerte quand un robot attend ou finit |

Tout reste en local : l'app lit `~/.claude`, `~/.codex`, `~/.cursor`, `~/.pi` et `~/.omp`, et range
l'historique des prompts dans `~/Library/Application Support/TheBoss/boss.sqlite`. Les limites Claude
viennent de l'API d'Anthropic avec le jeton de Claude Code lu dans le trousseau (via `security`) ;
celles de Codex sont lues dans ses journaux. La reformulation des règles par Claude est optionnelle et
passe par Claude Code en local.

## Commandes

```bash
./scripts/bundle.sh                       # construit build/TheBoss.app (release, signé ad hoc)
open build/TheBoss.app
./scripts/test.sh                         # tests du cœur (Swift Testing)
swift run TheBoss                         # lance en debug
python3 scripts/make_demo_home.py build/demo-home && BOSS_HOME=build/demo-home swift run TheBoss
python3 scripts/fetch_pixellab.py         # retélécharge les sprites PixelLab (design/pixellab.json)
python3 scripts/make_icon.py              # régénère l'icône
```

Commandes de jeu : flèches ou WASD pour marcher, Maj pour courir, Espace ou Entrée pour parler,
Échap pour le menu. ⌘1 à ⌘5 ouvrent directement les écrans. La souris marche aussi : clique un robot
ou un meuble.

`BOSS_SCRIPT` pilote l'app pour les tests visuels (`wait:2;room:openSpace;snap:open;quit`, voir
`Sources/TheBoss/DebugDriver.swift`) et `BOSS_SNAP_DIR` choisit où écrire les captures.

## Structure

```
Sources/BossCore/    Données : sessions (Claude, Codex, Pi, omp, Cursor), usage, inventaire des règles,
                     détection des corrections, suggestions et diff, SQLite, stats
Sources/TheBoss/     App SwiftUI + SpriteKit : Engine/ (salles, personnages, scène), UI/ (HUD, dialogues, écrans)
Sources/TheBoss/Assets/  Sprites PixelLab (personnages, meubles), assets TBFC (sols, émotes, UI, police PixelifySans OFL)
Tests/BossCoreTests/ Tests du cœur
design/pixellab.json Identifiants PixelLab de chaque sprite
```

## Direction artistique

Pixel DS de TBFC (`../TBFC/docs/art-direction.md`) : case de 64 px, personnages PixelLab en toile de
128 px vue « low top-down », contours sombres, 4 à 5 teintes par matière, affichage au plus proche
voisin. Le boss est un humain lambda, les agents sont des robots : orange pour Claude Code, blanc et
sarcelle pour Codex, noir pour Cursor, violet pour Pi, vert pour omp.
