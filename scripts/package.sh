#!/usr/bin/env bash
# Yeniden derleme: build/extract + packaging/control -> build/*.deb
#
# Kullanım:
#   ./scripts/package.sh [--rootful|--rootless] [--backend manual|dpkg-deb]
#                        [--compress xz|gzip|zstd] [-o DIR]
#
# Varyantlar:
#   rootful  (varsayılan): orijinal yerleşim, Architecture=iphoneos-arm
#   rootless: /Applications /Library /usr -> /var/jb/..., Architecture=iphoneos-arm64
#             (+ loader symlink hedefi yeni konuma göre düzeltilir)
#
# Backend'ler:
#   manual   (varsayılan): GNU ar+tar ile upstream ile birebir arşiv
#            (debian-binary + control.tar.gz + data.tar.lzma, sahip root:0).
#            fakeroot gerektirmez (--owner/--group ile).
#   dpkg-deb sistem dpkg-deb'i ile derler (sahiplik o anki kullanıcı olur,
#            fakeroot varsa root:0 yapılır).
set -euo pipefail

source "$(dirname "$0")/lib.sh"

VARIANT="rootful"
BACKEND="manual"
COMPRESS="xz"
OUTDIR="$BUILD_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootful) VARIANT="rootful"; shift ;;
    --rootless) VARIANT="rootless"; shift ;;
    --backend) BACKEND="${2:?--backend değeri gerekli}"; shift 2 ;;
    --compress|-Z) COMPRESS="${2:?--compress değeri gerekli}"; shift 2 ;;
    -o|--output) OUTDIR="${2:?-o değeri gerekli}"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) die "Bilinmeyen argüman: $1" ;;
  esac
done

[[ "$BACKEND" == "manual" || "$BACKEND" == "dpkg-deb" ]] || die "backend manual|dpkg-deb olmalı"

if [[ ! -d "$EXTRACT_DIR" ]]; then
  log_info "build/extract yok, önce açılıyor..."
  "$PROJECT_ROOT/scripts/extract.sh"
fi

VERSION="$(read_version)"
if [[ "$VARIANT" == "rootless" ]]; then
  ARCH="iphoneos-arm64"
  STAGE="$BUILD_DIR/stage-rootless"
else
  ARCH="iphoneos-arm"
  STAGE="$BUILD_DIR/stage-rootful"
fi
OUT="$OUTDIR/com.gamegod.igg_${VERSION}_${ARCH}.deb"

log_info "Derleniyor: varyant=$VARIANT backend=$BACKEND arch=$ARCH"

# --- 1) stage hazırla ---
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$OUTDIR"
cp -a "$EXTRACT_DIR/." "$STAGE/"

if [[ "$VARIANT" == "rootless" ]]; then
  mkdir -p "$STAGE/var/jb"
  chmod 755 "$STAGE/var/jb" # umask'tan bağımsız, deterministik kip
  for d in Applications Library usr; do
    [[ -e "$STAGE/$d" ]] && mv "$STAGE/$d" "$STAGE/var/jb/$d"
  done
  # Loader symlink'i: var/jb/Library/MobileSubstrate/DynamicLibraries/ konumundan
  # /var/mobile/Library/iGameGod/substrate.plist'e göreli hedefi düzelt.
  DL="$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
  if [[ -L "$DL/iGameGodLoader.plist" ]]; then
    ln -sfn ../../../../mobile/Library/iGameGod/substrate.plist "$DL/iGameGodLoader.plist"
  fi
  log_info "rootless yerleşim uygulandı (/var/jb)"
fi

# --- 2) control dosyaları ---
cp -f "$PROJECT_ROOT"/packaging/control/* "$STAGE/DEBIAN/"
CTRL_VER="$(awk -F': *' '/^Version:/ {print $2}' "$STAGE/DEBIAN/control")"
[[ "$CTRL_VER" == "$VERSION" ]] || die "Sürüm uyuşmazlığı: packaging/control/control=$CTRL_VER, VERSION=$VERSION"

if [[ "$VARIANT" == "rootless" ]]; then
  sed -i 's/^Architecture:.*/Architecture: iphoneos-arm64/' "$STAGE/DEBIAN/control"
fi
# Installed-Size = data boyutu (KB, DEBIAN hariç)
TOTAL_KB="$(du -sk "$STAGE" | cut -f1)"
DEB_KB="$(du -sk "$STAGE/DEBIAN" | cut -f1)"
INSTALLED_KB=$(( TOTAL_KB - DEB_KB ))
sed -i "s/^Installed-Size:.*/Installed-Size: $INSTALLED_KB/" "$STAGE/DEBIAN/control"
chmod 644 "$STAGE/DEBIAN/control"
chmod 755 "$STAGE/DEBIAN"/preinst "$STAGE/DEBIAN"/postinst "$STAGE/DEBIAN"/prerm "$STAGE/DEBIAN"/postrm

# --- 3) arşivle ---
if [[ "$BACKEND" == "manual" ]]; then
  require_cmd tar; require_cmd xz; require_cmd ar
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  printf '2.0\n' > "$TMPD/debian-binary"
  ( cd "$STAGE/DEBIAN" && tar --sort=name --owner=0 --group=0 --numeric-owner \
      -czf "$TMPD/control.tar.gz" ./control ./preinst ./postinst ./prerm ./postrm )
  mv "$STAGE/DEBIAN" "$TMPD/DEBIAN"
  ( cd "$STAGE" && tar --sort=name --owner=0 --group=0 --numeric-owner -c . \
      | xz --format=lzma -c > "$TMPD/data.tar.lzma" )
  mv "$TMPD/DEBIAN" "$STAGE/DEBIAN"
  rm -f "$OUT"
  ( cd "$TMPD" && ar rc "$OUT" debian-binary control.tar.gz data.tar.lzma )
else
  require_cmd dpkg-deb
  if command -v fakeroot >/dev/null 2>&1; then
    fakeroot bash -c "chown -R 0:0 '$STAGE' && dpkg-deb -Z'$COMPRESS' -b '$STAGE' '$OUT'"
  else
    log_warn "fakeroot yok: sahiplik o anki kullanıcı olarak yazılacak (işlevsel, ama ideal değil)."
    dpkg-deb -Z"$COMPRESS" -b "$STAGE" "$OUT"
  fi
fi

log_ok "Derlendi: $OUT"
ls -la "$OUT"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$OUT"
fi
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb -f "$OUT" Package Version Architecture Installed-Size
fi
