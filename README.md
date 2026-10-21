# php2shell-check

Check, then apply, the **php2shell** fix on your PHP runtimes: system packages, standalone binaries, Docker containers (FrankenPHP included) and remote servers over SSH.

![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational?logo=linux&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-yellow)
![CVE-2026-109618](https://img.shields.io/badge/CVE-2026--109618-critical-red)
![CVE-2026-109619](https://img.shields.io/badge/CVE-2026--109619-critical-red)

```bash
git clone https://github.com/MakFly/php2shell-check.git
cd php2shell-check
./check.sh                          # this host: packages, binaries, containers
./servers-check.sh                  # every SSH target listed in servers.txt
./docker-scan.sh ~/code             # Dockerfiles and compose files of a folder
```

> Script output is in French. The status markers (`[OK]`, `[VULN]`, `[??]`) and exit codes are language-neutral.

## Why

**php2shell** is the name given to two remote code execution flaws in PHP core: **CVE-2026-109618** and **CVE-2026-109619** (CVSS v4.0 9.2). The fix ships in the PHP security release of **October 21, 2026, 14:00 UTC** (16:00 in Paris, CEST).

No configuration workaround is confirmed: **only upgrading PHP fixes it**. These scripts answer three questions: what is still vulnerable, how to fix it, and what to watch in the meantime.

## Features

Nothing is hardcoded for a given environment:

- **Fixed version**: read live from php.net, per branch (8.2 to 8.5). Until the release is out, the scripts answer `[??]`, never `[OK]`.
- **End-of-life branches** (7.x, 8.0, 8.1): detected through php.net's `supported_versions` list and reported `[VULN]`, since they will get no fix.
- **Distro packages**: Debian/Ubuntu and RHEL backport fixes without bumping the version number. A package is therefore judged on its changelog (CVEs cited) **or** on its upstream version (Alpine, Sury, Remi).
- **Docker**: `php` and FrankenPHP containers, plus frozen tags spotted from their last push date on Docker Hub.
- **Strict mode**: once the official advisory is out, `FIXED_VERSIONS` pins the exact fixed releases, so no heuristic is involved.
- **Fix actually loaded**: an upgraded package protects nothing until PHP restarts. Each PHP process (php-fpm, Apache, FrankenPHP, long-lived CLI workers) is checked through `/proc`: a process still mapping a replaced binary or `libphp` is reported `[VULN]`.
- **Deployment converged**: for Docker Swarm services running PHP, every running task must use the service image, and an update that is still running, paused or rolled back is reported `[VULN]`.

## Requirements

- Linux, with GNU `date`, bash 4+ and `curl`.
- `docker`: optional, only needed for containers and images.
- `ssh` for `servers-check.sh`.
- Tested on Ubuntu, Debian 13, Alpine and Rocky Linux 9. **Not tested on macOS.**

## Installation

```bash
git clone https://github.com/MakFly/php2shell-check.git
cd php2shell-check
```

Nothing to install: these are standalone Bash scripts (`lib.sh` holds the shared functions).

## Usage

Each result line starts with a status:

| Marker | Meaning |
|---|---|
| `[OK]` | Fixed version (or a changelog citing the CVEs). |
| `[VULN]` | Vulnerable version, pre-release, or end-of-life branch. |
| `[??]` | Unknown: release not published yet, Docker socket not reachable, PHP not found... |

### check.sh: this host

```bash
./check.sh
sudo ./check.sh   # if the Docker socket requires privileges
```

Checks deb, rpm and apk packages, binaries outside any package (source builds, `/opt`, asdf, Homebrew...), PHP processes still running an old binary, running containers, and Swarm convergence of PHP services. Run it with `sudo` to read every process in `/proc`. Exit code `0` if everything is patched, `1` if at least one runtime is vulnerable or unknown.

### apply.sh: apply the fix on this host

```bash
./apply.sh
```

Upgrades PHP packages (apt, dnf/yum, apk), restarts PHP and web server services, lists the containers to rebuild, then runs `check.sh` (and returns its exit code). Uses `sudo` when not run as root. Docker images are not rebuilt here.

### servers-check.sh: remote servers

```bash
cp servers.txt.example servers.txt   # one SSH target per line
./servers-check.sh                   # every server in servers.txt
./servers-check.sh web-01 ops@203.0.113.10   # or explicit hosts
```

Pipes `probe.sh` (read-only, POSIX sh) to each target over SSH and judges what it finds: binaries, packages, containers, PHP processes not restarted since the upgrade, Swarm services not converged. Nothing is installed remotely. For a distro package, the upstream version may hide a backport: the script then prints `[??]` and asks you to run `check.sh` on that host.

Exit codes: `0` everything is patched, `1` at least one server is unreachable, vulnerable or unknown, `2` if `servers.txt` is missing (and no host is passed as an argument).

The SSH account must be able to run `sudo -n docker` to see containers.

### docker-scan.sh: Dockerfiles and compose files

```bash
./docker-scan.sh ~/code
NO_PULL=1 ./docker-scan.sh ~/code    # without pulling images
```

Lists the PHP base images referenced by the Dockerfiles and compose files of a folder (current directory by default), resolves `ARG` defaults, classifies each reference (`pin`, `exact`, `rolling`, `frozen(Nj)`, where `j` stands for days) and reads the PHP version inside the image. Exit code `0` or `1`, like `check.sh`.

### docker-bump.sh: re-pin digests

```bash
DRY_RUN=1 ./docker-bump.sh path/to/Dockerfile   # print only
./docker-bump.sh path/to/Dockerfile
```

Replaces each `image@sha256:` with the current digest of its tag, **only if** that image ships the fixed version. Otherwise the old pin is kept and the exit code is `1`.

### frankenphp-selfbuild.sh: FrankenPHP without waiting

```bash
./frankenphp-selfbuild.sh 8.4.27 trixie v1.13.1
SHIP_TO=user@node ./frankenphp-selfbuild.sh 8.4.27   # docker load on a remote node
```

Stopgap: builds a FrankenPHP image on the fixed `php:X.Y.Z-zts` image, without waiting for the upstream daily rebuild (04:00 UTC, 06:00 in Paris). Arguments: `PHP_VERSION [OS] [FRANKENPHP_TAG]`. Runs a real multi-stage build (clones `php/frankenphp` into `build/`, then `docker buildx bake`). Exit code `1` if the requested version is not the fixed one, or if the official image is not on Docker Hub yet.

### watch.sh: observe mode

```bash
./watch.sh
INTERVAL=5 ./watch.sh
```

Loops until interrupted (Ctrl+C) and prints an `ALERT` line whenever a shell or a network tool (`sh`, `bash`, `python`, `perl`, `curl`, `wget`, `nc`, `socat`...) is spawned by a PHP or web server process.

## Environment variables

| Variable | Scripts | Purpose |
|---|---|---|
| `RELEASE_DATE` | all (through `lib.sh`) | Date of the security release carrying the fix. Default: `2026-10-21`. |
| `CVES` | all (through `lib.sh`) | CVEs a distro changelog must cite. Default: `CVE-2026-109618 CVE-2026-109619`. Change it if the official advisory differs. |
| `FIXED_VERSIONS` | all (through `lib.sh`) | Strict mode: fixed releases of the official advisory, e.g. `"8.2.35 8.3.36 8.4.27 8.5.12"`. php.net is not queried, and a branch missing from the list has no fix. |
| `NO_COLOR` | all (through `lib.sh`) | When set, disables colors. |
| `NO_PULL` | `docker-scan.sh` | When set, does not pull images nor read their PHP version. |
| `STALE_DAYS` | `docker-scan.sh` | Age in days after which a Docker Hub tag counts as frozen. Default: `30`. |
| `DRY_RUN` | `docker-bump.sh` | When set, prints the changes without editing files. |
| `SHIP_TO` | `frankenphp-selfbuild.sh` | SSH target (`user@node`) where the built image is loaded with `docker load`. |
| `INTERVAL` | `watch.sh` | Seconds between two scans. Default: `2`. |

## Pitfalls we hit

- **A `docker restart` patches nothing**: rebuild with `--pull`, then redeploy.
- **FrankenPHP embeds PHP** in its image and in its static binary. Upgrading the host's PHP changes nothing for it.
- **FrankenPHP minor tags freeze**: `1.9-php8.4` stayed on PHP 8.4.15. Prefer `1-phpX.Y`.
- **A pinned digest nobody owns drifts**: hand it to Renovate or Dependabot.

## Limitations

- Linux only (GNU `date`, bash 4+, `curl`). Tested on Ubuntu, Debian 13, Alpine and Rocky Linux 9. Not tested on macOS.
- `frankenphp-selfbuild.sh` runs a real multi-stage build: read it before use.
- The CVE identifiers come from researchers and CERT-EU, not from the PHP announcement. Check the official advisory on php.net once it is published.
- Provided as is, without warranty. Test in staging first.

## Security

- The scripts are **read-only**, except `apply.sh` (upgrades packages and restarts services), `docker-bump.sh` (rewrites your files) and `frankenphp-selfbuild.sh` (builds an image and can load it on a remote node).
- `probe.sh` installs nothing on servers: it only lists the PHP runtimes it can see.
- Read a script before running it as root.
- `servers.txt` (your real inventory) is ignored by Git: never commit it.

## Contributing

Issues and pull requests are welcome. Before opening a PR, check the syntax of every script:

```bash
for f in *.sh; do bash -n "$f"; done
sh -n probe.sh
```

## Sources

- https://www.php.net/archive/2026.php#2026-10-20-1
- https://sansec.io/research/php2shell
- https://www.huntress.com/blog/php2shell-leaked-critical-php-vulnerabilities

## License

[MIT](LICENSE) © 2026 MakFly
