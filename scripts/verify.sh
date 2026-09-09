#!/usr/bin/env bash
# Derlenen .deb'leri doğrular:
#  - control alanlari (Package/Version/Architecture) + VERSION tutarliligi
#  - data icerigi: rootful birebir upstream ile ayni olmali (SHA256 manifest)
#  - rootless: /var/jb cevirisi + duzeltilmis symlink hedefi
#  - control uyelerinin kip (mode) ve sozdizimi denetimi
#
# Kullanim: ./scripts/verify.sh [deb ...]   (argumansiz: build/*.deb)
set -uo pipefail

source "$(dirname "$0")/lib.sh"

PASS=0
FAIL=0
vpass() { PASS=$((PASS + 1)); log_ok "$*"; }
vfail() { FAIL=$((FAIL + 1)); log_err "$*"; }

require_cmd dpkg-deb
require_cmd ar
require_cmd tar

# --- tasinabilir yardimcilar ---
if stat -c %a . >/dev/null 2>&1; then
  stat_mode() { stat -c %a "$1"; }   # GNU
else
  stat_mode() { stat -f %Lp "$1"; }  # BSD/macOS
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | awk '{print $1}'; }
else
  require_cmd shasum
  sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

# $1: dizin -> manifest satirlari:
#   D <kip> <yol> | F <kip> <sha256> <yol> | L <hedef> <yol>
manifest_of_tree() {
  ( cd "$1" || exit 1
    find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r p; do
      if [[ -L $p ]]; then
        printf 'L %s %s\n' "$(readlink "$p")" "$p"
      elif [[ -d $p ]]; then
        printf 'D %s %s\n' "$(stat_mode "$p")" "$p"
      elif [[ -f $p ]]; then
        printf 'F %s %s %s\n' "$(stat_mode "$p")" "$(sha256_of "$p")" "$p"
      else
        printf '? %s\n' "$p"
      fi
    done )
}

# Upstream manifestini rootless yerlesime cevirir.
# (Acik kurallar; karmasik regex kullanilmaz. Noktalar kasten kacsizdir:
# baglam geregi yalnizca gercek './Dizin' yollari eslesir.)
to_rootless_manifest() {
  sed -e 's| ./Applications/| ./var/jb/Applications/|' \
      -e 's| ./Applications$| ./var/jb/Applications|' \
      -e 's| ./Library/| ./var/jb/Library/|' \
      -e 's| ./Library$| ./var/jb/Library|' \
      -e 's| ./usr/| ./var/jb/usr/|' \
      -e 's| ./usr$| ./var/jb/usr|' \
      -e 's|^L ../../../var/mobile/|L ../../../../mobile/|'
}

# Manifest satirlarini YOLA gore siralar (karsilastirma icin kanonik duzen).
# Yollar bosluk icermez, o yuzden $NF her zaman yoldur.
by_path() {
  awk '{print $NF " " $0}' | LC_ALL=C sort -k1,1 | cut -d' ' -f2-
}

# Bundled deb'lerdeki companion dosyalarini dogrula (dylib Mach-O + plist gecerli).
check_companion_files() {
  local dylib plist
  dylib="$(find "$WORK/data" -path '*DynamicLibraries/IGGCompanion.dylib' | head -n 1)"
  plist="$(find "$WORK/data" -path '*DynamicLibraries/IGGCompanion.plist' | head -n 1)"
  if [[ -z "$dylib" || -z "$plist" ]]; then
    vfail "bundled: companion dosyalari bulunamadi"; return 0
  fi
  vpass "bundled: companion dosyalari mevcut"
  local magic
  magic="$(od -A n -t x1 -N 4 "$dylib" 2>/dev/null | tr -d ' \n')"
  if [[ "$magic" == "cffaedfe" || "$magic" == "cafebabe" ]]; then
    vpass "bundled: dylib Mach-O ($magic)"
  else
    vfail "bundled: dylib sihri yanlis: $magic"
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],"rb"))' "$plist" 2>/dev/null       && vpass "bundled: plist gecerli" || vfail "bundled: plist BOZUK"
  else
    [[ -s "$plist" ]] && vpass "bundled: plist mevcut (icerik atlandi)"                      || vfail "bundled: plist BOS"
  fi
}

# $1: deb -> control uyelerinin "kip ad" listesi.
# Not: pipe uzerinden okurken bazi tar surumleri sikistirmayi otomatik
# algilamaz; uye uzantisina gore acik bayrak verilir.
ctrl_modes() {
  local deb="$1" member
  member="$(ar t "$deb" | grep '^control.tar' | head -n 1)"
  if [[ -z "$member" ]]; then echo "CONTROL-UYE-YOK"; return 1; fi
  case "$member" in
    *.gz)   ar p "$deb" "$member" | tar tzvf - 2>/dev/null ;;
    *.xz)   ar p "$deb" "$member" | tar tJvf - 2>/dev/null ;;
    *.lzma) ar p "$deb" "$member" | tar --lzma -tvf - 2>/dev/null ;;
    *.zst*) ar p "$deb" "$member" | tar --zstd -tvf - 2>/dev/null ;;
    *.bz2)  ar p "$deb" "$member" | tar tjvf - 2>/dev/null ;;
    *)      ar p "$deb" "$member" | tar tvf - 2>/dev/null ;;
  esac | awk '{sub(/^[.][/]/, "", $6); print $1, $6}'
}

DEBS=()
if [[ $# -gt 0 ]]; then
  DEBS=( "$@" )
else
  for d in "$BUILD_DIR"/com.gamegod.igg_*_iphoneos-arm.deb \
           "$BUILD_DIR"/com.gamegod.igg_*_iphoneos-arm64.deb; do
    [[ -e "$d" ]] && DEBS+=( "$d" )
  done
  [[ "${#DEBS[@]}" -gt 0 ]] || die "build/ altinda derlenmis .deb yok. Once: make package package-rootless"
fi

if [[ ! -d "$EXTRACT_DIR" ]]; then
  log_info "build/extract yok, once aciliyor..."
  "$PROJECT_ROOT/scripts/extract.sh"
fi

VERSION="$(read_version)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
manifest_of_tree "$EXTRACT_DIR" > "$WORK/upstream.manifest"

for deb in "${DEBS[@]}"; do
  log_info "Denetleniyor: $deb"
  [[ -f "$deb" ]] || { vfail "dosya yok: $deb"; continue; }

  PKG="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"
  VER="$(dpkg-deb -f "$deb" Version 2>/dev/null || true)"
  ARCH="$(dpkg-deb -f "$deb" Architecture 2>/dev/null || true)"
  [[ "$PKG" == "com.gamegod.igg" ]] && vpass "Package = $PKG" || vfail "Package yanlis: '$PKG'"
  BUNDLED=0
  [[ "$VER" == *"+companion"* ]] && BUNDLED=1
  if [[ "$BUNDLED" -eq 1 ]]; then
    [[ "$VER" == "$VERSION"* ]] && vpass "Version = $VER (bundled, VERSION tabanli)" \
                               || vfail "Version uyusmazligi: deb=$VER, beklenen $VERSION+..."
  else
    [[ "$VER" == "$VERSION" ]] && vpass "Version = $VER (VERSION ile tutarli)" \
                               || vfail "Version uyusmazligi: deb=$VER, VERSION=$VERSION"
  fi

  VARIANT="rootful"
  [[ "$deb" == *iphoneos-arm64.deb ]] && VARIANT="rootless"
  if [[ "$VARIANT" == "rootless" ]]; then
    [[ "$ARCH" == "iphoneos-arm64" ]] && vpass "Architecture = $ARCH" || vfail "Architecture yanlis: '$ARCH'"
  else
    [[ "$ARCH" == "iphoneos-arm" ]] && vpass "Architecture = $ARCH" || vfail "Architecture yanlis: '$ARCH'"
  fi
  [[ -n "$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)" ]] \
    && vpass "Depends alani dolu" || vfail "Depends alani bos"

  # data manifest karsilastirmasi
  rm -rf "$WORK/data" && mkdir -p "$WORK/data"
  dpkg-deb -x "$deb" "$WORK/data"
  manifest_of_tree "$WORK/data" > "$WORK/actual.manifest"
  if [[ "$VARIANT" == "rootless" ]]; then
    { to_rootless_manifest < "$WORK/upstream.manifest"
      echo "D 755 ./var/jb"; } | LC_ALL=C sort > "$WORK/expected.manifest"
    if grep -Eq ' ./(Applications|Library|usr)/' "$WORK/actual.manifest"; then
      vfail "rootless: cevrilmemis kok yolu var (Applications/Library/usr)"
    else
      vpass "rootless: tum kok yollari /var/jb altinda"
    fi
  else
    cp "$WORK/upstream.manifest" "$WORK/expected.manifest"
  fi
  if [[ "$BUNDLED" -eq 1 ]]; then
    grep -v 'IGGCompanion' "$WORK/actual.manifest" > "$WORK/actual.nocompanion"
    by_path < "$WORK/expected.manifest" > "$WORK/expected.sorted"
    by_path < "$WORK/actual.nocompanion" > "$WORK/actual.sorted"
  else
    by_path < "$WORK/expected.manifest" > "$WORK/expected.sorted"
    by_path < "$WORK/actual.manifest" > "$WORK/actual.sorted"
  fi
  if diff -u "$WORK/expected.sorted" "$WORK/actual.sorted" > "$WORK/manifest.diff"; then
    vpass "data manifesti beklenenle birebir ayni ($(wc -l < "$WORK/actual.sorted" | tr -d ' ') kayit)"
  else
    vfail "data manifesti farkli (ilk 20 satir):"
    head -20 "$WORK/manifest.diff" >&2
  fi

  if [[ "$BUNDLED" -eq 1 ]]; then
    check_companion_files
  fi

  # symlink hedefi
  if [[ "$VARIANT" == "rootless" ]]; then
    grep -q 'L ../../../../mobile/Library/iGameGod/substrate.plist ./var/jb/Library/MobileSubstrate/DynamicLibraries/iGameGodLoader.plist' "$WORK/actual.manifest" \
      && vpass "rootless: loader symlink hedefi dogru" \
      || vfail "rootless: loader symlink hedefi YANLIS"
  else
    grep -q 'L ../../../var/mobile/Library/iGameGod/substrate.plist ./Library/MobileSubstrate/DynamicLibraries/iGameGodLoader.plist' "$WORK/actual.manifest" \
      && vpass "rootful: loader symlink hedefi korunmus" \
      || vfail "rootful: loader symlink hedefi BOZULMUS"
  fi

  # control uyeleri: kip + sozdizimi + icerik
  MODES="$(ctrl_modes "$deb")"
  echo "$MODES" | grep -q -- '-rw-r--r-- control' \
    && vpass "control kipi 644" || vfail "control kipi yanlis: [$MODES]"
  for s in preinst postinst prerm postrm; do
    echo "$MODES" | grep -q -- "-rwxr-xr-x $s" \
      && vpass "$s kipi 755" || vfail "$s kipi yanlis"
  done
  rm -rf "$WORK/ctrl" && mkdir -p "$WORK/ctrl"
  dpkg-deb -e "$deb" "$WORK/ctrl"
  SYNTAX_OK=1
  for s in preinst postinst prerm postrm; do
    bash -n "$WORK/ctrl/$s" || { vfail "$s sozdizimi hatasi"; SYNTAX_OK=0; }
  done
  [[ "$SYNTAX_OK" -eq 1 ]] && vpass "control scriptleri bash -n'den gecti"
  grep -q 'backups/preinst-' "$WORK/ctrl/preinst" \
    && vpass "preinst: zaman damgali yedek mantigi mevcut" \
    || vfail "preinst: yedek mantigi BULUNAMADI"
  grep -q 'chmod 6775' "$WORK/ctrl/postinst" \
    && vpass "postinst: cmnd setuid adimi mevcut" \
    || vfail "postinst: cmnd setuid adimi YOK"
  grep -q 'uicache' "$WORK/ctrl/postinst" \
    && vpass "postinst: uicache adimi mevcut" \
    || vfail "postinst: uicache adimi YOK"
done

echo
log_info "Sonuc: $PASS gecti, $FAIL kaldi"
[[ "$FAIL" -eq 0 ]] || die "$FAIL dogrulama basarisiz"
log_ok "Tum dogrulamalar gecti"
