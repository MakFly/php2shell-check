#!/usr/bin/env bash
# Pipe probe.sh (read-only) to every host of servers.txt over SSH and judge
# each PHP runtime found (binary, distro package, container).
# Distro packages are reported for a check on the host (backports keep the
# old upstream version): run check.sh there to read the changelog.
# Usage: ./servers-check.sh [HOST...]     (default: servers.txt)
set -uo pipefail
cd "$(dirname "$0")"
source ./lib.sh
status=0
hosts=("$@")
if [[ ${#hosts[@]} -eq 0 ]]; then
  [[ -f servers.txt ]] || { echo "servers.txt manquant : cp servers.txt.example servers.txt" >&2; exit 2; }
  mapfile -t hosts < <(grep -vE '^\s*(#|$)' servers.txt | awk '{print $1}')
fi

for h in "${hosts[@]}"; do
  echo "######## $h"
  if ! out=$(timeout 90 ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" sh -s < probe.sh 2>&1); then
    red "[ERR]  $h injoignable : $(tail -1 <<<"$out")"; status=1; continue
  fi
  found=0
  while read -r kind a b c; do
    case "$kind" in
      host)     echo "  $a $b $c" ;;
      bin)      found=1; verdict "  bin $a" "$b" || status=1 ;;
      ctr)      found=1; verdict "  conteneur $a ($c)" "$b" || status=1 ;;
      pkg)      found=1; up=$(upstream_of "$c")
                verdict "  $a $b $c" "$up" >/dev/null && green "  [OK]   $a $b $c" \
                  || { yellow "  [??]   $a $b $c : version upstream $up, lancer check.sh sur l'hôte (backport ?)"; status=1; } ;;
      nodocker) yellow "  [??]   docker $a $b $c"; status=1 ;;
    esac
  done <<<"$(grep -vE '^\*\*|post-quantum|store now' <<<"$out")"
  [[ $found -eq 1 ]] || echo "  aucun PHP visible"
done
exit $status
