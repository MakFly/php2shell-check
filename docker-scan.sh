#!/usr/bin/env bash
# List every PHP base image referenced by Dockerfiles and compose files under
# the given directories (default: current directory), resolve ARG defaults, pull each image
# and report whether the PHP it ships carries the php2shell fix.
# Usage: ./docker-scan.sh [DIR...]    NO_PULL=1 to skip the PHP version probe.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
PHP_IMAGES='(^|/)(php|frankenphp|adminer|wordpress|drupal|joomla|nextcloud|matomo|phpmyadmin|laravelsail/[a-z0-9.-]*)([:@]|$)'
status=0

# Print "ref" for each FROM / image: line, with ${ARG} replaced by its default.
refs_of() {
  awk '
    /^[[:space:]]*ARG[[:space:]]+[A-Za-z_]+=/ { split($2, kv, "="); args[kv[1]] = kv[2] }
    /^[[:space:]]*(FROM|image:)/ {
      ref = ($1 == "image:") ? $2 : $2
      if ($1 ~ /^FROM$/ && $2 ~ /^--/) ref = $3
      while (match(ref, /\$\{[A-Za-z_]+\}/)) {
        name = substr(ref, RSTART + 2, RLENGTH - 3)
        ref = substr(ref, 1, RSTART - 1) args[name] substr(ref, RSTART + RLENGTH)
      }
      gsub(/"/, "", ref); print ref
    }' "$1"
}

php_version_of() {
  docker run --rm --pull "${PULL:-missing}" --entrypoint php "$1" -r 'echo PHP_VERSION;' 2>/dev/null
}

# Days since Docker Hub last pushed this tag, empty for other registries.
# A tag nobody rebuilds (old FrankenPHP minor, old Adminer...) never gets the fix.
hub_age_days() {
  local ref="${1%@*}" repo tag updated
  [[ "$ref" == *:* ]] && tag=${ref##*:} repo=${ref%:*} || { tag=latest; repo=$ref; }
  [[ "$repo" == */*.*/* || "$repo" == *.*/* ]] && return 0   # ghcr.io/..., registry:5000/...
  [[ "$repo" == */* ]] || repo="library/$repo"
  updated=$(curl -fsS --max-time 10 "https://hub.docker.com/v2/repositories/$repo/tags/$tag" 2>/dev/null |
    sed -n 's/.*"last_updated":"\([^"]*\)".*/\1/p') || return 0
  [[ -n "$updated" ]] && echo $(( ($(date +%s) - $(date -d "$updated" +%s)) / 86400 ))
}

STALE_DAYS=${STALE_DAYS:-30}
kind_of() {
  local age
  case "$1" in
    *@sha256:*) echo "pin"; return ;;
    *:[0-9]*.[0-9]*.[0-9]*) [[ "${1##*:}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && { echo "exact"; return; } ;;
  esac
  age=$(hub_age_days "$1")
  if [[ -n "$age" && "$age" -gt "$STALE_DAYS" ]]; then echo "frozen(${age}j)"; else echo "rolling"; fi
}

mapfile -t files < <(find "${@:-.}" \( -name node_modules -o -name vendor -o -name .git \) -prune -o \
  -type f \( -name 'Dockerfile*' -o -name '*.Dockerfile' -o -name '*compose*.y*ml' -o -name 'docker-stack*.y*ml' \) -print 2>/dev/null)

declare -A seen
for f in "${files[@]}"; do
  while read -r ref; do
    [[ "$ref" =~ $PHP_IMAGES ]] || continue
    [[ "$ref" == *'$'* ]] && { yellow "[??]   $f : $ref (variable non résolue)"; continue; }
    kind=$(kind_of "$ref")
    printf '%-7s %s\n        %s\n' "$kind" "$ref" "$f"
    [[ -n "${NO_PULL:-}" ]] && continue
    if [[ -z "${seen[$ref]:-}" ]]; then
      PULL=$([[ $kind == pin || $kind == exact ]] && echo missing || echo always) seen[$ref]=$(php_version_of "$ref" || echo none)
    fi
    [[ "${seen[$ref]}" == none ]] && { yellow "        [??] php introuvable dans l'image"; continue; }
    verdict "        ->" "${seen[$ref]}" || status=1
  done < <(refs_of "$f")
done
exit $status
