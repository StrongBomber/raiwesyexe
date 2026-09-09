#!/usr/bin/env bash
# Cydia/Sileo/Zebra APT deposu üretir:
#   build/repo/
#     debs/*.deb  Packages[.gz|.bz2|.xz]  Release  index.html
#
# Kullanım: ./scripts/make-repo.sh [-o DIR] [--base-url URL]
# Yayınlama: build/repo içeriğini GitHub Pages vb. bir statik hosta koyun.
set -euo pipefail

source "$(dirname "$0")/lib.sh"

OUT="$BUILD_DIR/repo"
BASE_URL="https://example.com/igg-repo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUT="${2:?-o değeri gerekli}"; shift 2 ;;
    --base-url) BASE_URL="${2:---base-url değeri gerekli}"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) die "Bilinmeyen argüman: $1" ;;
  esac
done

require_cmd dpkg-deb

DEBS=( "$BUILD_DIR"/com.gamegod.igg_*_iphoneos-arm*.deb )
[[ -e "${DEBS[0]}" ]] || die "build/ altında derlenmiş .deb yok. Önce: make package package-rootless"

# taşınabilir hash/boyut yardımcıları
if command -v md5sum >/dev/null 2>&1; then
  md5_of() { md5sum "$1" | awk '{print $1}'; }
else
  require_cmd md5; md5_of() { md5 -q "$1"; }
fi
if command -v sha1sum >/dev/null 2>&1; then
  sha1_of() { sha1sum "$1" | awk '{print $1}'; }
else
  require_cmd shasum; sha1_of() { shasum -a 1 "$1" | awk '{print $1}'; }
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | awk '{print $1}'; }
else
  sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
fi
fsize() { wc -c < "$1" | tr -d ' '; }
field() { dpkg-deb -f "$1" "$2" 2>/dev/null || true; }

rm -rf "$OUT"
mkdir -p "$OUT/debs"
cp -f "${DEBS[@]}" "$OUT/debs/"

# --- Packages ---
: > "$OUT/Packages"
for deb in "$OUT"/debs/*.deb; do
  {
    echo "Package: $(field "$deb" Package)"
    echo "Name: $(field "$deb" Name)"
    echo "Version: $(field "$deb" Version)"
    echo "Architecture: $(field "$deb" Architecture)"
    echo "Depends: $(field "$deb" Depends)"
    echo "Section: $(field "$deb" Section)"
    echo "Author: $(field "$deb" Author)"
    echo "Maintainer: $(field "$deb" Maintainer)"
    echo "Installed-Size: $(field "$deb" Installed-Size)"
    echo "Description: $(field "$deb" Description)"
    echo "Filename: debs/$(basename "$deb")"
    echo "Size: $(fsize "$deb")"
    echo "MD5sum: $(md5_of "$deb")"
    echo "SHA1: $(sha1_of "$deb")"
    echo "SHA256: $(sha256_of "$deb")"
    echo
  } >> "$OUT/Packages"
done

( cd "$OUT" && gzip -k -9 Packages )
command -v bzip2 >/dev/null 2>&1 && ( cd "$OUT" && bzip2 -k -9 Packages ) || log_warn "bzip2 yok, Packages.bz2 atlandı"
command -v xz >/dev/null 2>&1 && ( cd "$OUT" && xz -k -9 Packages ) || log_warn "xz yok, Packages.xz atlandı"

# --- Release ---
EXTRA_PKGS=""
command -v bzip2 >/dev/null 2>&1 && EXTRA_PKGS="$EXTRA_PKGS Packages.bz2"
command -v xz >/dev/null 2>&1 && EXTRA_PKGS="$EXTRA_PKGS Packages.xz"
{
  echo "Origin: raiwesyexe"
  echo "Label: raiwesyexe"
  echo "Suite: stable"
  echo "Codename: ios"
  echo "Date: $(date -u +"%a, %d %b %Y %T UTC")"
  echo "Architectures: iphoneos-arm iphoneos-arm64"
  echo "Components: main"
  echo "Description: raiwesyexe iGameGod paket deposu"
  for algo in MD5Sum SHA1 SHA256; do
    echo "$algo:"
    # EXTRA_PKGS kasten tirnaksiz: kelime bolme isteniyor (glob icermez).
    ( cd "$OUT" && for f in debs/*.deb Packages Packages.gz $EXTRA_PKGS; do
        case "$algo" in
          MD5Sum) h="$(md5_of "$f")" ;;
          SHA1)   h="$(sha1_of "$f")" ;;
          SHA256) h="$(sha256_of "$f")" ;;
        esac
        printf ' %s %16s %s\n' "$h" "$(fsize "$f")" "$f"
      done )
  done
} > "$OUT/Release"

# --- index.html ---
cat > "$OUT/index.html" <<HTML
<!DOCTYPE html>
<html lang="tr">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>raiwesyexe APT Deposu</title>
<style>body{font-family:-apple-system,sans-serif;max-width:640px;margin:2em auto;padding:0 1em}
a.btn{display:inline-block;margin:.3em .3em .3em 0;padding:.6em 1em;border:1px solid #888;border-radius:8px;text-decoration:none}</style>
</head>
<body>
<h1>raiwesyexe APT Deposu</h1>
<p>iGameGod (yeniden paketlenmiş) deposu. Paket yöneticinize şu adresi ekleyin:</p>
<p><code>$BASE_URL</code></p>
<p>
<a class="btn" href="sileo://source/$BASE_URL">Sileo'da Aç</a>
<a class="btn" href="zebra://sources/add/$BASE_URL">Zebra'da Aç</a>
<a class="btn" href="cydia://url/https://cydia.saurik.com/api/share#?source=$BASE_URL">Cydia'da Aç</a>
</p>
<h2>Paketler</h2>
<ul>
HTML
for deb in "$OUT"/debs/*.deb; do
  echo "<li><a href=\"debs/$(basename "$deb")\">$(basename "$deb")</a> ($(field "$deb" Version), $(field "$deb" Architecture))</li>" >> "$OUT/index.html"
done
echo "</ul></body></html>" >> "$OUT/index.html"

log_ok "Repo hazır: $OUT"
find "$OUT" -type f | LC_ALL=C sort
