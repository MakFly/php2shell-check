# Shared helpers for php2shell-check. Source it, do not run it.
# Override from the environment if the advisory changes:
#   RELEASE_DATE  date of the PHP security release carrying the fix
#   CVES          CVE identifiers a distro changelog must cite
RELEASE_DATE="${RELEASE_DATE:-2026-10-21}"
CVES="${CVES:-CVE-2026-109618 CVE-2026-109619}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  red()    { printf '\033[31m%s\033[0m\n' "$*"; }
  green()  { printf '\033[32m%s\033[0m\n' "$*"; }
  yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
else
  red() { echo "$*"; }; green() { echo "$*"; }; yellow() { echo "$*"; }
fi

# Load into FIXED[branch] the latest upstream release of a branch (8.4...),
# only if published on or after RELEASE_DATE. Returns 1 while the fix is not
# out, or for an EOL branch. Call it directly (not in $(...)) to keep the cache.
declare -A FIXED
upstream_fixed() {
  local branch="$1" json ver date
  if [[ -z "${FIXED[$branch]+x}" ]]; then
    FIXED[$branch]=""
    if json=$(curl -fsS --max-time 15 "https://www.php.net/releases/index.php?json&version=${branch}"); then
      ver=$(sed -n 's/.*"version":"\([0-9.]*\)".*/\1/p' <<<"$json")
      date=$(grep -o '"date":"[^"]*"' <<<"$json" | head -1 | cut -d'"' -f4)   # top-level date comes first
      if [[ -n "$ver" && -n "$date" ]] && [[ $(date -d "$date" +%s) -ge $(date -d "$RELEASE_DATE" +%s) ]]; then
        FIXED[$branch]=$ver
      fi
    fi
  fi
  [[ -n "${FIXED[$branch]}" ]]
}

# True when php.net still supports the branch (fetched once per run).
SUPPORTED=""
branch_supported() {
  [[ -n "$SUPPORTED" ]] || SUPPORTED=$(curl -fsS --max-time 15 'https://www.php.net/releases/index.php?json&version=8' |
    grep -o '"supported_versions":\[[^]]*\]' | grep -oE '[0-9]+\.[0-9]+' | tr '\n' ' ')
  [[ " $SUPPORTED " == *" $1 "* ]]
}

# Upstream part of a version string: 8.4.27-1+deb13u1 -> 8.4.27, 2:8.3.6-0ubuntu -> 8.3.6
upstream_of() { sed -E 's/^[0-9]+://; s/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<<"$1"; }

# ver_ge A B: true when A >= B (RC builds count as older than the release).
ver_ge() { [[ "$1" != *RC* && $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1) == "$2" ]]; }

# verdict LABEL VERSION: prints OK / VULN / ?? and returns 1 unless OK.
verdict() {
  local label="$1" ver="$2" branch fixed
  branch=$(cut -d. -f1,2 <<<"$ver")
  upstream_fixed "$branch"; fixed=${FIXED[$branch]}
  if [[ -z "$fixed" ]] && ! branch_supported "$branch"; then
    red    "[VULN] $label $ver (branche $branch en fin de vie : aucun fix officiel, migrer vers une branche supportée)"
    return 1
  elif [[ -z "$fixed" ]]; then
    yellow "[??]   $label $ver (pas encore de release $branch >= $RELEASE_DATE sur php.net : relancer après la publication)"
    return 1
  elif [[ "$ver" == *RC* ]]; then
    red    "[VULN] $label $ver (pré-version, pas une release corrigée)"
    return 1
  elif ver_ge "$ver" "$fixed"; then
    green  "[OK]   $label $ver (>= $fixed)"
  else
    red    "[VULN] $label $ver (< $fixed)"
    return 1
  fi
}

# changelog_cites TEXT: true when every CVE of $CVES appears in TEXT.
changelog_cites() { local c; for c in $CVES; do grep -q "$c" <<<"$1" || return 1; done; }

# A distro package is patched if its changelog cites the CVEs (backport, the
# Debian/Ubuntu/RHEL way) or if its upstream version is the fixed release
# (Alpine, Sury, Remi, Homebrew).
verdict_pkg() {
  local label="$1" ver="$2" changelog="$3" up
  if changelog_cites "$changelog"; then
    green "[OK]   $label $ver (changelog cite $CVES)"; return 0
  fi
  up=$(upstream_of "$ver")
  verdict "$label" "$up" && return 0
  red "       ni le changelog ni la version upstream ne portent le fix : mettre à jour le paquet"
  return 1
}

# True when PATH belongs to a distro package (then the package check covers it).
pkg_owned() {
  local f; f=$(readlink -f "$1")
  { command -v dpkg >/dev/null && dpkg -S "$f" >/dev/null 2>&1; } ||
  { command -v rpm  >/dev/null && rpm -qf "$f" >/dev/null 2>&1; } ||
  { command -v apk  >/dev/null && apk info --who-owns "$f" 2>/dev/null | grep -q 'owned by'; }
}
