# The Boss

Une app de bureau pour macOS, Windows et Linux qui surveille tes agents de code (Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor, Pi, omp),
sous forme de jeu en pixel art façon Pokémon DS. Tu es le boss, un renard en sweat à capuche : tu marches dans
ton bureau, puis dans l'open space où chaque session d'agent est un robot à son poste, avec sur son bureau
une plaque qui dit sur quoi il bosse. L'app est en anglais par défaut, en français dans les réglages.

## Ce que fait l'app

| Dans le jeu | Fonction |
|---|---|
| Open space : un robot par session | Statut en direct de chaque agent : au travail (il tape), attend ton feu vert (il fait signe, bulle « ! »), terminé (il somnole) |
| Parler à un robot | Tâche, dernier ordre, action en attente ; journal de la conversation, retour à la session, dossier, commande de reprise |
| Fouet (touche F) | Un robot au travail tape deux fois plus vite un moment, un robot qui attend t'emmène à sa session pour valider |
| Écran mural de l'open space | Vue d'ensemble de tous les agents des 12 dernières heures, filtrable par statut |
| Ordinateur du boss | Limites des forfaits (Claude, Codex, Cursor) et tokens consommés par jour |
| Bibliothèque | Fichiers cachés qui pilotent les agents : CLAUDE.md, AGENTS.md, règles Cursor, skills, hooks, sous-agents, commandes, réglages |
| Bannette à courrier | Suggestions avec preuves et diff exact : règles apprises de tes corrections, réglages cassés à réparer ; appliquer, garder pour plus tard, ignorer |
| Tableau blanc | Stats : corrections pour 100 prompts par jour, tendance (le setup s'améliore ou se dégrade) |
| Armoire d'archives | Modèle du domaine local, une source de vérité par projet : intention, conventions écrites, décisions apprises, travaux récents, divergences entre CLAUDE.md et AGENTS.md ; export vers `.boss/domain.md` avec diff |
| Barre des menus ou zone de notification, badge, notifications | Compteurs, alerte quand un robot attend ou finit |

Tout reste en local : l'app lit `~/.claude`, `~/.codex`, `~/.gemini`, `~/.copilot`, `~/.cursor`, `~/.pi` et `~/.omp`, et range
l'historique des prompts dans `boss.sqlite`, dans le dossier de données de l'OS (`~/Library/Application Support/TheBoss`
sur macOS, `~/.local/share/TheBoss` sur Linux, `%APPDATA%\TheBoss` sur Windows). Les limites Claude viennent de l'API
d'Anthropic avec le jeton de Claude Code, lu dans le trousseau sur macOS (via `security`) et dans
`~/.claude/.credentials.json` ailleurs ; celles de Codex sont lues dans ses journaux. La reformulation des règles par
Claude est optionnelle et passe par Claude Code en local.

## Télécharger

Les exécutables sont sur le site (section Download) et sur https://github.com/flcarre/theboss-releases/releases :
`TheBoss-macOS.dmg` (Apple Silicon et Intel), `TheBoss-Windows-setup.exe`, `TheBoss-Linux.AppImage` et `TheBoss-Linux.deb`.
Ils ne sont pas encore signés : au premier lancement, clic droit → Ouvrir sur macOS, « Informations complémentaires →
Exécuter quand même » sous Windows.

## Commandes

```bash
cd app && npm install                     # une fois
npm run tauri dev                         # lance l'app en dev (rechargement à chaud du front)
npm run tauri build                       # installeurs de la plateforme courante dans target/release/bundle
npm run dev                               # front seul dans un navigateur, avec des données fictives (http://localhost:1420)
cargo test -p boss-core                   # tests du cœur (depuis la racine)
python3 scripts/make_demo_home.py build/demo-home && BOSS_HOME=$PWD/build/demo-home npm --prefix app run tauri dev
python3 scripts/fetch_pixellab.py         # retélécharge les sprites PixelLab (design/pixellab.json)
python3 scripts/make_icon.py              # régénère l'icône et les icônes de l'app
python3 scripts/import_chatgpt.py         # convertit les images ChatGPT de design/chatgpt/generated/ au format du jeu
```

Rust s'installe avec `mise use -g rust@stable` (ou rustup). Sous Linux il faut aussi WebKitGTK :
`sudo apt install libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev patchelf`.

Nouveaux assets avec ChatGPT : donne `design/chatgpt/requests.json` à ChatGPT, range les PNG qu'il renvoie
dans `design/chatgpt/generated/` sous le nom indiqué (`file`), puis lance `scripts/import_chatgpt.py`. Le script ramène
chaque image à sa taille native en pixels, limite la palette et rend la transparence nette.

Commandes de jeu : flèches ou WASD pour marcher, Maj pour courir, Espace ou Entrée pour parler, F pour
fouetter, Échap pour le menu. ⌘1 à ⌘6 (Ctrl+1 à Ctrl+6 sous Windows et Linux) ouvrent directement les écrans,
⌘, (Ctrl+,) les réglages. La souris marche aussi : clique un robot ou un meuble.

## Publier une version

1. Monte la version dans `app/package.json` (l'app et les installeurs la lisent là), commite.
2. Lance `mise exec rust -- ./scripts/release.sh`. Tout se construit sur ce Mac, sans GitHub Actions :
   - `scripts/build-macos.sh` : `.dmg` universel (Apple Silicon et Intel) ;
   - `scripts/build-windows.sh` : `.exe` NSIS, compilé avec `cargo-xwin` ; `makensis` tourne dans Docker
     (`scripts/tools/makensis`) car celui de Homebrew plante sur macOS ;
   - `scripts/build-linux.sh` : `.AppImage` et `.deb`, construits dans un conteneur Ubuntu 22.04 x86_64 (émulé, donc lent).
   Le script pousse ensuite le tag `vX.Y.Z` et publie les installeurs dans le repo public `flcarre/theboss-releases`
   avec des noms fixes : les liens du site (`releases/latest/download/...`) pointent toujours sur la dernière version.
3. Prérequis, une fois : Docker lancé, `brew install llvm lld`, `cargo install --locked cargo-xwin`,
   `rustup target add x86_64-apple-darwin x86_64-pc-windows-msvc` (via `mise exec rust --`).

## Site vitrine

`site/` contient le site de présentation (Next.js, export statique, en anglais) avec un bureau jouable dans le
navigateur : le renard marche, parle aux robots et fait claquer le fouet. `cd site && npm install && npm run dev`
pour le lancer, `npm run build` pour l'export dans `site/out`. Le projet Vercel `theboss` est branché sur ce repo
(dossier racine `site`) : chaque push sur `main` redéploie https://theboss-iota.vercel.app. Après un changement de sprites dans le jeu,
`python3 site/scripts/import_game_assets.py` recopie les objets, murs et personnages et refait les planches
d'animation du site. Les captures de `site/public/assets/screens` viennent de l'app nourrie de données fictives,
avec des limites d'usage simulées.

## Structure

```
core/                Cœur Rust (crate boss-core) : sessions (Claude, Codex, Gemini, Copilot, Pi, omp, Cursor), usage,
                     inventaire des règles, détection des corrections, suggestions et diff, SQLite, stats, lanceur de sessions
core/tests/          Tests du cœur
shared/fr.json       Traductions françaises, partagées par le cœur et l'interface
app/src-tauri/       Coquille Tauri : boucles de rafraîchissement, commandes, icône de barre système, notifications
app/src/game/        Moteur du jeu en canvas : salles, personnages, fouet
app/src/ui/          Interface React : HUD, dialogues, menu, écrans
app/public/assets/   Sprites PixelLab (personnages, meubles, icônes) ; sols, bulles et effets sont dessinés en code
design/pixellab.json Identifiants PixelLab de chaque sprite
scripts/             build-macos/windows/linux.sh, release.sh (installeurs construits en local)
```

## Direction artistique

Pixel art inspiré des jeux Pokémon sur DS : case de 64 px, personnages PixelLab en toile de 128 px vue « low
top-down », contours sombres, 4 à 5 teintes par matière, affichage au plus proche voisin. Tous les assets sont
propres à The Boss (PixelLab ou dessinés en code), aucun n'est repris d'un autre projet. Les robots : orange pour
Claude Code, blanc et sarcelle pour Codex, blanc et bleu pour Gemini, gris et violet pour Copilot, noir pour
Cursor, violet pour Pi, vert pour omp. Texte en SF Pro Rounded (ou la police arrondie du système) pour la lisibilité.
