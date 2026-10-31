# All of Create Aeronautics – pack packwiz

Modpack NeoForge 1.21.1 (21.1.250) du serveur, synchronisé avec [packwiz](https://packwiz.infra.link/).

## Installation côté joueur (Windows)

1. Installer le modpack **All of Create Aeronautics** dans ATLauncher (ou créer une instance NeoForge 21.1.250 / Minecraft 1.21.1 dans Prism Launcher) et le lancer une fois.
2. Fermer le launcher.
3. Télécharger et lancer [installer.bat](https://milograbie.github.io/aeronautics-pack/client/installer.bat), puis choisir l'instance.

Le script installe packwiz, synchronise les mods et configure le launcher pour qu'ils soient mis à jour à chaque lancement.

## Installation manuelle

1. Télécharger [packwiz-installer-bootstrap.jar](https://github.com/packwiz/packwiz-installer-bootstrap/releases) dans le dossier de l'instance.
2. Ajouter en commande de pré-lancement :

```
java -jar packwiz-installer-bootstrap.jar -s client https://milograbie.github.io/aeronautics-pack/pack.toml
```
