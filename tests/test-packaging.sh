#!/usr/bin/env bash
# Kurulum scriptleri (preinst/postinst/prerm/postrm) için mock-kök testleri.
# Cihaz gerekmez: IGG_ROOT ile sahte bir dosya sistemi kurulur, hem rootful
# hem rootless yerleşimleri denenir.
#
# Kullanım: ./tests/test-packaging.sh
set -u

source "$(dirname "$0")/../scripts/lib.sh"

PASS=0
FAIL=0
tpass() { PASS=$((PASS + 1)); log_ok "$*"; }
tfail() { FAIL=$((FAIL + 1)); log_err "$*"; }

check_bash_syntax() {
  log_info "1) bash sözdizimi denetimi"
  local f ok=1
  for f in packaging/control/preinst packaging/control/postinst \
           packaging/control/prerm packaging/control/postrm \
           scripts/*.sh tests/*.sh; do
    if bash -n "$f"; then
      : # sessiz geç
    else
      tfail "sözdizimi hatası: $f"; ok=0
    fi
  done
  [[ "$ok" -eq 1 ]] && tpass "tüm scriptler bash -n'den geçti"
}

# $1: etiket (rootful|rootless), $2: mock kök dizini
run_install_cycle() {
  local label="$1" mock="$2"
  log_info "2) kurulum döngüsü testi [$label] (mock: $mock)"

  local dylib
  if [[ "$label" == "rootless" ]]; then
    dylib="$mock/var/jb/Library/MobileSubstrate/DynamicLibraries"
    mkdir -p "$dylib" "$mock/var/mobile/Library/iGameGod"
  else
    dylib="$mock/Library/MobileSubstrate/DynamicLibraries"
    mkdir -p "$dylib" "$mock/var/mobile/Library/iGameGod"
  fi

  # 1. aşama: "kurulu" eski filtreler
  echo "LOADER-FILTRE-v1" > "$mock/var/mobile/Library/iGameGod/substrate.plist"
  echo "BF-v1"            > "$dylib/bfdecrypttweak.plist"
  echo "SPOOF-v1"         > "$dylib/iGSpoof.plist"

  # 2. aşama: preinst (IGG_PREFIX boş -> otomatik tespit sınanır)
  if ! env IGG_ROOT="$mock" IGG_PREFIX="" bash packaging/control/preinst >/dev/null 2>&1; then
    tfail "[$label] preinst çıkış kodu != 0"; return 1
  fi
  local bdir
  bdir="$(ls -dt "$mock"/var/mobile/Library/iGameGod/backups/preinst-* 2>/dev/null | head -n 1)"
  if [[ -z "$bdir" ]]; then
    tfail "[$label] preinst yedek dizini oluşturmadı"; return 1
  fi
  tpass "[$label] preinst yedek dizini oluşturdu"
  for f in iGameGodLoader.plist bfdecrypttweak.plist iGSpoof.plist; do
    [[ -f "$bdir/$f" ]] && tpass "[$label] yedekte var: $f" \
                          || tfail "[$label] yedekte YOK: $f"
  done
  [[ -f "$mock/var/mobile/Library/iGameGod/install.log" ]] \
    && tpass "[$label] install.log yazıldı" || tfail "[$label] install.log YOK"

  # 3. aşama: dpkg "yükseltmesi" simülasyonu — yeni boş filtreler gelir
  echo "BOS" > "$dylib/bfdecrypttweak.plist"
  echo "BOS" > "$dylib/iGSpoof.plist"
  echo "BOS" > "$mock/var/mobile/Library/iGameGod/substrate.plist"

  # 4. aşama: postinst geri yüklemeli
  if ! env IGG_ROOT="$mock" IGG_PREFIX="" bash packaging/control/postinst >/dev/null 2>&1; then
    tfail "[$label] postinst çıkış kodu != 0"; return 1
  fi
  [[ "$(cat "$dylib/bfdecrypttweak.plist")" == "BF-v1" ]] \
    && tpass "[$label] bfdecrypt filtresi geri yüklendi" \
    || tfail "[$label] bfdecrypt filtresi geri YÜKLENMEDİ"
  [[ "$(cat "$dylib/iGSpoof.plist")" == "SPOOF-v1" ]] \
    && tpass "[$label] iGSpoof filtresi geri yüklendi" \
    || tfail "[$label] iGSpoof filtresi geri YÜKLENMEDİ"
  [[ "$(cat "$mock/var/mobile/Library/iGameGod/substrate.plist")" == "LOADER-FILTRE-v1" ]] \
    && tpass "[$label] loader filtresi geri yüklendi" \
    || tfail "[$label] loader filtresi geri YÜKLENMEDİ"
  [[ -d "$mock/var/mobile/Documents/Decrypted" ]] \
    && tpass "[$label] Decrypted dizini oluşturuldu" \
    || tfail "[$label] Decrypted dizini YOK"

  # rootless tespitinin gerçekten çalıştığını doğrula (dylib yolu /var/jb altında olmalı)
  if [[ "$label" == "rootless" ]]; then
    grep -q "IGG_PREFIX='/var/jb'" "$mock/var/mobile/Library/iGameGod/install.log" \
      && tpass "[$label] /var/jb öneki otomatik tespit edildi" \
      || tfail "[$label] /var/jb öneki tespit EDİLEMEDİ"
  fi

  # 5. aşama: prerm + postrm patlamamalı
  env IGG_ROOT="$mock" bash packaging/control/prerm >/dev/null 2>&1 \
    && tpass "[$label] prerm temiz çıktı" || tfail "[$label] prerm hata verdi"
  env IGG_ROOT="$mock" bash packaging/control/postrm remove >/dev/null 2>&1 \
    && tpass "[$label] postrm (remove) temiz çıktı" || tfail "[$label] postrm hata verdi"
  # purge: yedek+günlük gider, kullanıcı filtresi kalır
  env IGG_ROOT="$mock" bash packaging/control/postrm purge >/dev/null 2>&1
  if [[ ! -e "$mock/var/mobile/Library/iGameGod/backups" && \
        ! -e "$mock/var/mobile/Library/iGameGod/install.log" && \
        -f "$mock/var/mobile/Library/iGameGod/substrate.plist" ]]; then
    tpass "[$label] purge: günlük/yedek silindi, kullanıcı filtresi korundu"
  else
    tfail "[$label] purge davranışı yanlış"
  fi
}

main() {
  cd "$PROJECT_ROOT"
  check_bash_syntax

  local m1 m2
  m1="$(mktemp -d)"; m2="$(mktemp -d)"
  run_install_cycle rootful "$m1"
  run_install_cycle rootless "$m2"
  rm -rf "$m1" "$m2"

  echo
  log_info "Sonuç: $PASS geçti, $FAIL kaldı"
  [[ "$FAIL" -eq 0 ]] || die "$FAIL test başarısız"
  log_ok "Tüm paketleme testleri geçti"
}

main "$@"
