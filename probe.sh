#!/bin/sh
# Read-only probe, piped to a remote host by servers-check.sh: lists every PHP
# runtime it can see. POSIX sh, nothing to install on the server.
echo "host $(hostname) os=$(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
for b in /usr/bin/php* /usr/sbin/php-fpm* /usr/local/bin/php* /usr/local/sbin/php-fpm* /usr/local/bin/frankenphp /opt/*/bin/php; do
  [ -x "$b" ] || continue
  case "$b" in *-config|*ize|*.dpkg-*) continue;; esac
  case "$b" in *frankenphp) v=$("$b" php-cli -r 'echo PHP_VERSION;' 2>/dev/null) ;; *) v=$("$b" -r 'echo PHP_VERSION;' 2>/dev/null) ;; esac
  [ -n "$v" ] && echo "bin $b $v"
done
command -v dpkg-query >/dev/null && dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 'php*-common' 2>/dev/null | awk '$1=="ii" && $2!="php-common" {print "pkg deb",$2,$3}'
command -v rpm >/dev/null && rpm -qa --qf 'pkg rpm %{NAME} %{VERSION}-%{RELEASE}\n' 'php*-common' 2>/dev/null
command -v apk >/dev/null && apk info -v 2>/dev/null | sed -nE 's/^(php[0-9]*-common)-([0-9].*)$/pkg apk \1 \2/p'
D=docker; $D ps >/dev/null 2>&1 || D="sudo -n docker"
if command -v docker >/dev/null && ! $D ps >/dev/null 2>&1; then echo "nodocker socket inaccessible (ni accès direct ni sudo -n)"; fi
$D ps --format '{{.Names}}|{{.Image}}' 2>/dev/null | while IFS='|' read -r n i; do
  v=$($D exec "$n" php -r 'echo PHP_VERSION;' 2>/dev/null) || v=$($D exec "$n" frankenphp php-cli -r 'echo PHP_VERSION;' 2>/dev/null) || continue
  echo "ctr $n $v $i"
done
S=""; [ "$(id -u)" = 0 ] || S="sudo -n"
ps -eo pid=,ppid=,comm= | while read -r pid ppid comm; do
  case "$comm" in php|php[0-9]*|php-fpm*|php-cgi*|apache2|httpd|frankenphp) ;; *) continue ;; esac
  [ "$(ps -o comm= -p "$ppid" 2>/dev/null)" = "$comm" ] && continue
  exe=$($S readlink "/proc/$pid/exe" 2>/dev/null) || { echo "proc unreadable $pid $comm"; continue; }
  if echo "$exe" | grep -q ' (deleted)$' || $S grep -qE 'php[^ ]* \(deleted\)$' "/proc/$pid/maps" 2>/dev/null; then
    echo "proc stale $pid $comm"
  else
    echo "proc fresh $pid $comm"
  fi
done
# Swarm convergence, only for services whose tasks run PHP on this node.
if [ "$($D info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}' 2>/dev/null)" = "active true" ]; then
  for svc in $($D ps --format '{{.Names}}' | grep -E '^[^.]+\.[0-9]+\.' | cut -d. -f1 | sort -u); do
    $D exec "$($D ps -q -f "name=^$svc\." | head -1)" sh -c 'command -v php || command -v frankenphp' >/dev/null 2>&1 || continue
    spec=$($D service inspect -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$svc")
    state=$($D service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}' "$svc")
    old=""
    for img in $($D service ps "$svc" --filter desired-state=running --format '{{.Image}}'); do
      case "$img@$spec" in
        *@sha256:*@*@sha256:*) [ "${img#*@}" = "${spec#*@}" ] || old=$img ;;
        *) [ "${img%@*}" = "${spec%@*}" ] || old=$img ;;
      esac
    done
    echo "swarm $svc ${state:-none} ${old:-converged}"
  done
fi
