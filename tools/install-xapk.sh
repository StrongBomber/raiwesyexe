#!/usr/bin/env bash
#
# install-xapk.sh — download an .xapk bundle and sideload it onto an Android device.
#
# An .xapk is a plain ZIP that contains:
#   * base.apk
#   * one or more split_*.apk (arch / density / language splits)
#   * optionally *.obb expansion files that must be pushed to /sdcard/Android/obb/<package>/
#
# Usage:
#   tools/install-xapk.sh <url-or-local-file> [--serial <device>] [--package <pkg>] [--keep] [--dry-run]
#
# Examples:
#   tools/install-xapk.sh https://data.winudf.com/XAPK/....xapk
#   tools/install-xapk.sh ~/Downloads/WorldSoccerChamps.xapk --serial emulator-5554
#
set -euo pipefail

DIST_DIR="${DIST_DIR:-dist}"
SERIAL=""
PACKAGE=""
KEEP=0
DRY_RUN=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: %s\n' "$*" >&2
  else
    "$@"
  fi
}

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --serial)  SERIAL="${2:-}";  shift 2 ;;
    --package) PACKAGE="${2:-}"; shift 2 ;;
    --keep)    KEEP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    -*)        die "unknown option: $1 (try --help)" ;;
    *)         INPUT="$1"; shift ;;
  esac
done

[ -n "${INPUT:-}" ] || usage 1

command -v unzip >/dev/null 2>&1 || die "unzip is required but not installed"

# --- 1. Obtain the .xapk -----------------------------------------------------
if [ -f "$INPUT" ]; then
  XAPK="$INPUT"
  info "using local file: $XAPK"
else
  case "$INPUT" in
    http://*|https://*) ;;
    *) die "not a readable file and not an http(s) URL: $INPUT" ;;
  esac
  command -v curl >/dev/null 2>&1 || die "curl is required to download a URL"
  mkdir -p "$DIST_DIR"
  XAPK="$DIST_DIR/$(basename "${INPUT%%\?*}")"
  info "downloading to $XAPK (resume-safe, use Ctrl-C to abort)"
  # -L follow redirects, -C - resume, --fail on HTTP errors.
  # A stale signed URL returns HTTP 403 -> retry by copying a fresh link from the site.
  curl -fL -C - --retry 3 --retry-delay 2 -o "$XAPK" "$INPUT" \
    || die "download failed. If the URL is signed it may have expired; copy a fresh link."
fi

unzip -tq "$XAPK" >/dev/null 2>&1 || die "$XAPK is not a valid ZIP/XAPK archive (partial download?)"
info "archive ok: $(du -h "$XAPK" | cut -f1)"

# --- 2. Unpack ---------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/xapk.XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT
unzip -q "$XAPK" -d "$WORK"

# --- 3. Discover the APK splits ---------------------------------------------
APKS="$(find "$WORK" -maxdepth 1 -name '*.apk' | sort)"
[ -n "$APKS" ] || die "no .apk found at the archive root — is this really an XAPK?"

# base.apk must come first for `adb install-multiple`
BASE="$(printf '%s\n' "$APKS" | grep -E '/(base\.apk|[^/]*\.apk)$' | grep '/base.apk$' | head -1 || true)"
if [ -n "$BASE" ]; then
  APKS="$(printf '%s\n%s\n' "$BASE" "$(printf '%s\n' "$APKS" | grep -v -F "$BASE")" | sed '/^$/d')"
fi
APK_COUNT="$(printf '%s\n' "$APKS" | grep -c .)"
info "found $APK_COUNT apk(s):"
printf '%s\n' "$APKS" | sed 's#.*/#    #' >&2

# --- 4. Resolve the package name --------------------------------------------
MANIFEST="$WORK/manifest.json"
if [ -z "$PACKAGE" ] && [ -f "$MANIFEST" ] && command -v python3 >/dev/null 2>&1; then
  PACKAGE="$(python3 - "$MANIFEST" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("package_name", ""))
except Exception:
    pass
PY
)"
fi
[ -n "$PACKAGE" ] || die "could not determine package name; pass --package com.example.app"
info "package: $PACKAGE"

# --- 5. Find a device --------------------------------------------------------
command -v adb >/dev/null 2>&1 || die "adb not found. Install Android platform-tools, or push the .apk to the phone manually."

if [ -z "$SERIAL" ]; then
  DEVICES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
  NDEV="$(printf '%s' "$DEVICES" | grep -c . || true)"
  if [ "${NDEV:-0}" -eq 0 ]; then
    die "no authorized device. Enable USB debugging, accept the RSA prompt, then re-run."
  elif [ "${NDEV:-0}" -gt 1 ]; then
    die "multiple devices attached; re-run with --serial one of: $(printf '%s' "$DEVICES" | tr '\n' ' ')"
  fi
  SERIAL="$DEVICES"
fi
info "device: $SERIAL"

# --- 6. Install --------------------------------------------------------------
if [ "$APK_COUNT" -eq 1 ]; then
  run adb -s "$SERIAL" install -r -d "$APKS"
else
  # shellcheck disable=SC2086  # word splitting is intentional
  run adb -s "$SERIAL" install-multiple -r -d $APKS
fi

# --- 7. Push OBB expansion files, if any ------------------------------------
OBBS="$(find "$WORK" -name '*.obb' | sort)"
if [ -n "$OBBS" ]; then
  DEST="/sdcard/Android/obb/$PACKAGE"
  info "pushing $(printf '%s\n' "$OBBS" | grep -c .) obb file(s) to $DEST"
  run adb -s "$SERIAL" shell mkdir -p "$DEST"
  # shellcheck disable=SC2086
  run adb -s "$SERIAL" push $OBBS "$DEST/"
else
  info "no .obb files in archive — nothing to push"
fi

info "done. Launch with: adb -s $SERIAL shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1"
[ "$KEEP" -eq 1 ] && info "unpacked files kept at: $WORK"
exit 0
