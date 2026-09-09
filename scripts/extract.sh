#!/usr/bin/env bash
# Upstream .deb'i açar:
#   upstream/*.deb  ->  build/extract      (data arşivi)
#                   ->  build/control-orig (control arşivi, referans)
#
# Kullanım: ./scripts/extract.sh [--force]
set -euo pipefail

source "$(dirname "$0")/lib.sh"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      echo "Kullanım: $0 [--force]"
      echo "  --force   build/extract varsa bile baştan aç"
      exit 0 ;;
    *) die "Bilinmeyen argüman: $arg" ;;
  esac
done

require_cmd dpkg-deb
DEB="$(upstream_deb)"
VERSION="$(read_version)"

if [[ -d "$EXTRACT_DIR" && "$FORCE" -eq 0 ]]; then
  log_info "build/extract zaten var, atlanıyor (baştan açmak için --force)."
  exit 0
fi

log_info "Açılıyor: $DEB"
rm -rf "$EXTRACT_DIR" "$CONTROL_ORIG_DIR"
mkdir -p "$EXTRACT_DIR" "$CONTROL_ORIG_DIR"

dpkg-deb -e "$DEB" "$CONTROL_ORIG_DIR"
dpkg-deb -x "$DEB" "$EXTRACT_DIR"

log_info "Upstream control dosyaları:"
ls -la "$CONTROL_ORIG_DIR"
NFILES="$(find "$EXTRACT_DIR" -mindepth 1 | wc -l)"
SIZE="$(du -sh "$EXTRACT_DIR" | cut -f1)"
log_ok "Extract tamam: $NFILES kayıt, $SIZE -> $EXTRACT_DIR"
log_info "Proje sürümü (VERSION): $VERSION"
