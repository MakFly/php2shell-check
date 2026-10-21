#!/usr/bin/env bash
# Observe mode: print shells or network tools spawned by a PHP or web server
# process (the exploitation pattern Huntress expects for php2shell).
set -uo pipefail
PARENTS='php|php-fpm|php-cgi|apache2|httpd|nginx|frankenphp'
CHILDREN='sh|bash|dash|zsh|python[0-9.]*|perl|curl|wget|nc|ncat|socat'

while true; do
  ps -eo pid=,ppid=,user=,comm=,args= | while read -r pid ppid user comm args; do
    [[ "$comm" =~ ^($CHILDREN)$ ]] || continue
    pcomm=$(ps -o comm= -p "$ppid" 2>/dev/null) || continue
    [[ "$pcomm" =~ ^($PARENTS) ]] || continue
    echo "$(date -u +%FT%TZ) ALERT parent=$pcomm($ppid) child=$comm($pid) user=$user args=$args"
  done
  sleep "${INTERVAL:-2}"
done
