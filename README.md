# php2shell-check

Vérifie, puis applique, le correctif **php2shell** sur vos runtimes PHP : paquets système, binaires, conteneurs Docker (FrankenPHP inclus) et serveurs distants en SSH.

![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational?logo=linux&logoColor=white)
![CVE-2026-109618](https://img.shields.io/badge/CVE-2026--109618-critical-red)
![CVE-2026-109619](https://img.shields.io/badge/CVE-2026--109619-critical-red)

## English TL;DR

Bash scripts that tell you, host by host and image by image, whether your PHP runtimes carry the fix for **php2shell** (CVE-2026-109618 and CVE-2026-109619, two critical RCE flaws in PHP core, CVSS v4.0 9.2, PHP security release of 2026-10-21 14:00 UTC), and that help you apply it. The fixed version is read live from php.net, nothing is hardcoded per environment. Output is in French, the scripts are read-only except `apply.sh`, `docker-bump.sh` and `frankenphp-selfbuild.sh`.

```bash
git clone https://github.com/MakFly/php2shell-check.git
cd php2shell-check
./check.sh                          # this host: packages, binaries, containers
./servers-check.sh                  # every SSH target listed in servers.txt
./docker-scan.sh ~/code             # Dockerfiles and compose files of a folder
```

Exit code `0` means everything is patched, `1` means at least one runtime is vulnerable or unknown. Linux only (GNU `date`, bash 4+, `curl`).

## Pourquoi / contexte

**php2shell** regroupe deux failles d'exécution de code à distance dans le cœur de PHP : **CVE-2026-109618** et **CVE-2026-109619** (CVSS v4.0 9.2). Le correctif est livré par la release de sécurité PHP du **21 octobre 2026, 14:00 UTC**.

Aucun contournement par configuration n'est confirmé : **seule la mise à jour de PHP corrige**. Ces scripts répondent à trois questions : qui est encore vulnérable, comment le corriger, et que surveiller en attendant.

## Fonctionnalités

Rien n'est codé en dur pour un environnement :

- **Version corrigée** : lue en direct sur php.net, par branche (8.2 à 8.5). Tant que la release n'est pas publiée, les scripts répondent `[??]`, jamais `[OK]`.
- **Branches en fin de vie** (7.x, 8.0, 8.1) : détectées via la liste `supported_versions` de php.net et signalées `[VULN]`, car elles n'auront aucun fix.
- **Paquets de distribution** : Debian/Ubuntu et RHEL rétroportent le fix sans changer le numéro de version. Le paquet est donc jugé sur son changelog (CVE citées) **ou** sur sa version upstream (Alpine, Sury, Remi).
- **Docker** : conteneurs `php` et FrankenPHP, et tags figés repérés d'après la date du dernier push sur Docker Hub.

## Prérequis

- Linux, avec GNU `date`, bash 4+ et `curl`.
- `docker` : optionnel, utile seulement pour les conteneurs et les images.
- `ssh` pour `servers-check.sh`.
- Testé sur Ubuntu, Debian 13, Alpine et Rocky Linux 9. **Pas testé sur macOS.**

## Installation

```bash
git clone https://github.com/MakFly/php2shell-check.git
cd php2shell-check
```

Aucune dépendance à installer : ce sont des scripts Bash autonomes (`lib.sh` contient les fonctions communes).

## Utilisation

Chaque ligne de résultat commence par un état :

| Marqueur | Sens |
|---|---|
| `[OK]` | Version corrigée (ou changelog qui cite les CVE). |
| `[VULN]` | Version vulnérable, pré-version ou branche en fin de vie. |
| `[??]` | Indéterminé : release pas encore publiée, socket Docker inaccessible, PHP introuvable... |

### check.sh : cet hôte

```bash
./check.sh
sudo ./check.sh   # si le socket Docker demande des droits
```

Contrôle les paquets deb, rpm et apk, les binaires hors paquet (compilation, `/opt`, asdf, Homebrew...) et les conteneurs en cours d'exécution. Code de sortie `0` si tout est patché, `1` si au moins un runtime est vulnérable ou inconnu.

### apply.sh : appliquer le correctif sur cet hôte

```bash
./apply.sh
```

Met à jour les paquets PHP (apt, dnf/yum, apk), redémarre les services PHP et serveur web, liste les conteneurs à reconstruire, puis lance `check.sh` (dont le code de sortie est repris). Utilise `sudo` si vous n'êtes pas root. Les images Docker ne sont pas reconstruites ici.

### servers-check.sh : serveurs distants

```bash
cp servers.txt.example servers.txt   # une cible SSH par ligne
./servers-check.sh                   # tous les serveurs de servers.txt
./servers-check.sh web-01 ops@203.0.113.10   # ou des hôtes explicites
```

Envoie `probe.sh` (lecture seule, POSIX sh) en SSH sur chaque cible et juge ce qu'il trouve : binaires, paquets, conteneurs. Rien n'est installé à distance. Pour un paquet de distribution, la version upstream peut masquer un rétroportage : le script affiche alors `[??]` et vous invite à lancer `check.sh` sur l'hôte.

Codes de sortie : `0` tout est patché, `1` au moins un serveur injoignable, vulnérable ou inconnu, `2` si `servers.txt` est absent (et qu'aucun hôte n'est passé en argument).

Le compte SSH doit pouvoir exécuter `sudo -n docker` pour voir les conteneurs.

### docker-scan.sh : Dockerfiles et compose

```bash
./docker-scan.sh ~/code
NO_PULL=1 ./docker-scan.sh ~/code    # sans télécharger les images
```

Liste les images PHP de base des Dockerfiles et fichiers compose du dossier (courant par défaut), résout les `ARG` par défaut, classe chaque référence (`pin`, `exact`, `rolling`, `frozen(Nj)`) et lit la version PHP de l'image. Code de sortie `0` ou `1` comme `check.sh`.

### docker-bump.sh : ré-épingler les digests

```bash
DRY_RUN=1 ./docker-bump.sh path/to/Dockerfile   # affiche seulement
./docker-bump.sh path/to/Dockerfile
```

Remplace chaque `image@sha256:` par le digest actuel du tag, **seulement si** l'image contient la version corrigée. Sinon l'ancien pin est conservé et le code de sortie est `1`.

### frankenphp-selfbuild.sh : FrankenPHP sans attendre

```bash
./frankenphp-selfbuild.sh 8.4.27 trixie v1.13.1
SHIP_TO=user@node ./frankenphp-selfbuild.sh 8.4.27   # docker load sur un nœud distant
```

Solution provisoire : construit une image FrankenPHP sur `php:X.Y.Z-zts` corrigé, sans attendre le rebuild quotidien amont (04:00 UTC). Arguments : `PHP_VERSION [OS] [FRANKENPHP_TAG]`. Lance un vrai build multi-étapes (clone de `php/frankenphp` dans `build/`, `docker buildx bake`). Code de sortie `1` si la version demandée n'est pas la version corrigée ou si l'image officielle n'est pas encore sur Docker Hub.

### watch.sh : mode observation

```bash
./watch.sh
INTERVAL=5 ./watch.sh
```

Boucle jusqu'à interruption (Ctrl+C) et affiche une ligne `ALERT` quand un shell ou un outil réseau (`sh`, `bash`, `python`, `perl`, `curl`, `wget`, `nc`, `socat`...) est lancé par un process PHP ou serveur web.

## Variables d'environnement

| Variable | Scripts | Rôle |
|---|---|---|
| `RELEASE_DATE` | tous (via `lib.sh`) | Date de la release de sécurité portant le fix. Défaut : `2026-10-21`. |
| `CVES` | tous (via `lib.sh`) | CVE que doit citer un changelog de distribution. Défaut : `CVE-2026-109618 CVE-2026-109619`. À changer si l'avis officiel évolue. |
| `NO_COLOR` | tous (via `lib.sh`) | Si définie, désactive les couleurs. |
| `NO_PULL` | `docker-scan.sh` | Si définie, ne télécharge pas les images et ne lit pas leur version PHP. |
| `STALE_DAYS` | `docker-scan.sh` | Âge en jours au-delà duquel un tag Docker Hub est dit figé. Défaut : `30`. |
| `DRY_RUN` | `docker-bump.sh` | Si définie, affiche les changements sans modifier les fichiers. |
| `SHIP_TO` | `frankenphp-selfbuild.sh` | Cible SSH (`user@node`) où charger l'image construite avec `docker load`. |
| `INTERVAL` | `watch.sh` | Secondes entre deux relevés. Défaut : `2`. |

## Pièges rencontrés

- **Un `docker restart` ne patche rien** : il faut reconstruire avec `--pull` puis redéployer.
- **FrankenPHP embarque PHP** dans l'image et dans le binaire statique. Mettre à jour le PHP de l'hôte n'y change rien.
- **Les tags mineurs FrankenPHP se figent** : `1.9-php8.4` est resté en PHP 8.4.15. Préférer `1-phpX.Y`.
- **Un digest épinglé sans propriétaire dérive** : confiez-le à Renovate ou Dependabot.

## Limites

- Linux uniquement (GNU `date`, bash 4+, `curl`). Testé sur Ubuntu, Debian 13, Alpine et Rocky Linux 9. Pas testé sur macOS.
- `frankenphp-selfbuild.sh` lance un vrai build multi-étapes : relisez-le avant usage.
- Les identifiants CVE viennent des chercheurs et du CERT-EU, pas de l'annonce PHP. Vérifiez l'avis officiel sur php.net après la publication.
- Fourni tel quel, sans garantie. Testez d'abord en préproduction.

## Sécurité

- Les scripts sont en **lecture seule**, sauf `apply.sh` (met à jour les paquets et redémarre des services), `docker-bump.sh` (réécrit vos fichiers) et `frankenphp-selfbuild.sh` (construit et peut charger une image sur un nœud distant).
- `probe.sh` n'installe rien sur les serveurs : il liste seulement les runtimes PHP visibles.
- Relisez un script avant de le lancer en root.
- `servers.txt` (votre inventaire réel) est ignoré par Git : ne le committez jamais.

## Contribuer

Les issues et les pull requests sont les bienvenues. Avant d'ouvrir une PR, vérifiez la syntaxe de chaque script :

```bash
for f in *.sh; do bash -n "$f"; done
sh -n probe.sh
```

## Sources

- https://www.php.net/archive/2026.php#2026-10-20-1
- https://sansec.io/research/php2shell
- https://www.huntress.com/blog/php2shell-leaked-critical-php-vulnerabilities

## Licence

Licence : pas encore définie.
