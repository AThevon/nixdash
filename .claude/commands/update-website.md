# update-website

Met a jour le site officiel nixdash-site suite aux changements du package nixdash.

## Instructions

Tu dois effectuer les etapes suivantes :

### 1. Analyser les changements recents sur nixdash

- Lire les commits recents avec `git log --oneline -10`
- Identifier les changements importants (nouvelles features, corrections de bugs, modifications de comportement)
- Lire le fichier `nixdash.sh` et les modules dans `lib/` pour comprendre les fonctionnalites actuelles
- Lire le `README.md` pour voir la documentation actuelle du package

### 2. Naviguer vers le projet nixdash-site

- Aller dans le dossier `../nixdash-site` (par rapport au projet nixdash actuel)
- Verifier que tu es sur la branche main et que le repo est a jour avec `git pull`

### 3. Creer une branche pour les modifications

- Creer une nouvelle branche avec un nom descriptif base sur les changements, par exemple : `update-docs-v0.x.x` ou `sync-website-[feature]`

### 4. Mettre a jour le site web

Analyser et mettre a jour les fichiers suivants selon les changements detectes :

**Constantes** (`src/lib/utils/constants.ts`) :
- Mettre a jour la version dans `SITE_CONFIG`
- Mettre a jour les features `FEATURES` si necessaire
- Mettre a jour les raccourcis `SHORTCUTS` si ils ont change
- Mettre a jour les commandes d'installation `INSTALL_COMMANDS`

**Homepage** (`src/app/page.tsx` et composants dans `src/components/landing/`) :
- Mettre a jour le terminal demo (`TerminalDemo.tsx`) si les menus du hub ont change
- Verifier que les features cards correspondent aux fonctionnalites actuelles

**Documentation** (`src/app/docs/`) :
- `page.tsx` - overview generale
- `installation/page.tsx` - instructions d'installation
- `commands/page.tsx` - documentation des commandes
- `configuration/page.tsx` - options de configuration
- `shortcuts/page.tsx` - raccourcis clavier
- `faq/page.tsx` - questions frequentes

### 5. Verifier le build

- Lancer `npx next build` et verifier qu'il n'y a pas d'erreurs

### 6. Commit et Push

- Faire un commit avec un message clair decrivant les mises a jour
- Pousser la branche sur le remote

### 7. Creer la Pull Request

- Utiliser `gh pr create` pour creer une PR
- Le titre doit etre descriptif (ex: "docs: sync website with nixdash v0.3.0")
- Le body doit lister les changements effectues sur le site

## Notes importantes

- Respecter le MASTER.md (design system) du projet nixdash-site
- Toujours verifier que le site compile correctement avant de creer la PR
- Ne pas modifier le style ou le design sauf si c'est explicitement demande
- Se concentrer sur le contenu et la documentation
- Retourner l'URL de la PR a la fin
