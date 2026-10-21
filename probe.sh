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
