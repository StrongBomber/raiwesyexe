#!/usr/bin/env bash
# Sürüm yükseltir: VERSION + packaging/control/control + CHANGELOG iskeleti.
#
# Kullanım: ./scripts/bump-version.sh <yeni-sürüm>
# Örnek:    ./scripts/bump-version.sh 0.8.9.2-2
set -euo pipefail

source "$(dirname "$0")/lib.sh"
require_cmd python3

NEW="${1:-}"
[[ -n "$NEW" ]] || die "Kullanım: $0 <yeni-sürüm>  (örn. $0 0.8.9.2-2)"
[[ "$NEW" =~ ^[0-9][A-Za-z0-9.+~:-]*$ ]] || die "Geçersiz Debian sürüm biçimi: $NEW"

OLD="$(read_version)"
[[ "$NEW" != "$OLD" ]] || die "Yeni sürüm eskisiyle aynı: $OLD"

echo "$NEW" > "$VERSION_FILE"
sed -i "s/^Version: .*/Version: $NEW/" "$PROJECT_ROOT/packaging/control/control"

TODAY="$(date +%F)"
python3 - "$PROJECT_ROOT/CHANGELOG.md" "$NEW" "$TODAY" <<'EOF'
import sys
path, new, today = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
anchor = "## [Unreleased]\n"
entry = anchor + f"\n## [{new}] - {today}\n\n### Değişen\n\n- (değişiklikleri buraya yazın)\n"
assert anchor in text, "CHANGELOG'da '## [Unreleased]' bulunamadı"
with open(path, "w") as f:
    f.write(text.replace(anchor, entry, 1))
EOF

log_ok "Sürüm: $OLD -> $NEW"
log_info "CHANGELOG'a değişiklikleri işlemeyi unutmayın, sonra: make all"
