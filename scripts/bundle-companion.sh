#!/usr/bin/env bash
# Companion'i ana iGameGod deb'ine gomer: tek kurulumluk tum-bir-arada deb.
#
# Kullanim:
#   ./scripts/bundle-companion.sh --igg <igg.deb> --tweak <tweak.deb> --output <dosya|dizin>
#
# - Tweak .deb'indeki DynamicLibraries/*.dylib + *.plist ana pakete kopyalanir.
#   Yalnizca bu 2 dosya alinir; baska dosya varsa bilerek gormezden gelinir.
# - Varyantlar eslesmeli: rootful+rootful veya rootless+rootless.
# - Cikti surumu: <igg>+companion<tweak> (orn. 0.8.9.2-1+companion0.3.0).
# - Arsiv bicimi manual backend ile aynidir (control.tar.gz + data.tar.lzma).
set -euo pipefail

source "$(dirname "$0")/lib.sh"

IGG=""
TWEAK=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --igg) IGG="${2:---igg degeri gerekli}"; shift 2 ;;
    --tweak) TWEAK="${2:---tweak degeri gerekli}"; shift 2 ;;
    -o|--output) OUT="${2:?-o degeri gerekli}"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) die "Bilinmeyen arguman: $1" ;;
  esac
done

[[ -n "$IGG" && -n "$TWEAK" && -n "$OUT" ]] || die "Kullanim: $0 --igg <deb> --tweak <deb> --output <dosya|dizin>"
[[ -f "$IGG" ]] || die "igg deb bulunamadi: $IGG"
[[ -f "$TWEAK" ]] || die "tweak deb bulunamadi: $TWEAK"
require_cmd dpkg-deb
require_cmd tar
require_cmd xz
require_cmd ar

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/igg" "$WORK/tweak" "$WORK/debian"
dpkg-deb -x "$IGG" "$WORK/igg"
dpkg-deb -e "$IGG" "$WORK/debian"
dpkg-deb -x "$TWEAK" "$WORK/tweak"

DYLIB="$(find "$WORK/tweak" -path '*DynamicLibraries/*.dylib' | head -n 1)"
PLIST="$(find "$WORK/tweak" -path '*DynamicLibraries/*.plist' | head -n 1)"
[[ -n "$DYLIB" && -n "$PLIST" ]] || die "tweak deb'inde DynamicLibraries dylib+plist bulunamadi"

TWEAK_RL=0
[[ "$DYLIB" == *"/var/jb/"* ]] && TWEAK_RL=1
IGG_RL=0
[[ -d "$WORK/igg/var/jb" ]] && IGG_RL=1
[[ "$TWEAK_RL" == "$IGG_RL" ]] || die "varyant uyusmazligi: igg rootless=$IGG_RL, tweak rootless=$TWEAK_RL"

for src in "$DYLIB" "$PLIST"; do
  rel="${src#$WORK/tweak/}"
  mkdir -p "$WORK/igg/$(dirname "$rel")"
  cp -p "$src" "$WORK/igg/$rel"
  log_info "gomuldu: $rel"
done

IGG_VER="$(dpkg-deb -f "$IGG" Version)"
TW_VER="$(dpkg-deb -f "$TWEAK" Version)"
ARCH="$(dpkg-deb -f "$IGG" Architecture)"
NEW_VER="${IGG_VER}+companion${TW_VER}"
sed -i "s/^Version:.*/Version: $NEW_VER/" "$WORK/debian/control"
INSTALLED_KB="$(du -sk "$WORK/igg" | cut -f1)"
sed -i "s/^Installed-Size:.*/Installed-Size: $INSTALLED_KB/" "$WORK/debian/control"
chmod 644 "$WORK/debian/control"
for s in preinst postinst prerm postrm; do
  [[ -f "$WORK/debian/$s" ]] && chmod 755 "$WORK/debian/$s"
done

if [[ -d "$OUT" ]]; then
  OUT="$OUT/com.gamegod.igg_${NEW_VER}_${ARCH}.deb"
else
  mkdir -p "$(dirname "$OUT")"
fi

TMPD="$(mktemp -d)"
printf '2.0\n' > "$TMPD/debian-binary"
( cd "$WORK/debian" && tar --sort=name --owner=0 --group=0 --numeric-owner \
    -czf "$TMPD/control.tar.gz" ./control ./preinst ./postinst ./prerm ./postrm )
( cd "$WORK/igg" && tar --sort=name --owner=0 --group=0 --numeric-owner -c . \
    | xz --format=lzma -c > "$TMPD/data.tar.lzma" )
rm -f "$OUT"
( cd "$TMPD" && ar rc "$OUT" debian-binary control.tar.gz data.tar.lzma )
rm -rf "$TMPD"

log_ok "Birlesik deb: $OUT"
ls -la "$OUT"
dpkg-deb -f "$OUT" Package Version Architecture Installed-Size
