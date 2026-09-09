#!/usr/bin/env bash
# raiwesyexe ortak yardımcıları.
# Kullanım: source "$(dirname "$0")/lib.sh"
set -u

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"
BUILD_DIR="$PROJECT_ROOT/build"
UPSTREAM_DIR="$PROJECT_ROOT/upstream"
EXTRACT_DIR="$BUILD_DIR/extract"
CONTROL_ORIG_DIR="$BUILD_DIR/control-orig"

# Renkler (terminal değilse boş).
if [[ -t 1 ]]; then
  _C_OK=$'\e[32m'; _C_INFO=$'\e[36m'; _C_WARN=$'\e[33m'; _C_ERR=$'\e[31m'; _C_OFF=$'\e[0m'
else
  _C_OK=''; _C_INFO=''; _C_WARN=''; _C_ERR=''; _C_OFF=''
fi

log_info() { echo "${_C_INFO}[..]${_C_OFF} $*"; }
log_ok()   { echo "${_C_OK}[OK]${_C_OFF} $*"; }
log_warn() { echo "${_C_WARN}[!!]${_C_OFF} $*" >&2; }
log_err()  { echo "${_C_ERR}[HATA]${_C_OFF} $*" >&2; }
die()      { log_err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' gerekli ama bulunamadı. Kurup tekrar deneyin."
}

# VERSION dosyasını okur (örn. 0.8.9.2-1).
read_version() {
  [[ -f "$VERSION_FILE" ]] || die "VERSION dosyası yok: $VERSION_FILE"
  local v
  v="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
  [[ -n "$v" ]] || die "VERSION dosyası boş"
  echo "$v"
}

# upstream/*.deb yolunu döndürür (tek dosya olmalı).
upstream_deb() {
  local files=( "$UPSTREAM_DIR"/*.deb )
  [[ -e "${files[0]}" ]] || die "upstream/ altında .deb bulunamadı"
  [[ "${#files[@]}" -eq 1 ]] || die "upstream/ altında birden fazla .deb var: ${files[*]}"
  echo "${files[0]}"
}
