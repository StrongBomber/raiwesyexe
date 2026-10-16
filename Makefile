# Android bundle helpers.
#
#   make fetch-apk   URL='https://data.winudf.com/XAPK/....'   # download into apk/
#   make install-apk [XAPK=apk/Foo.xapk] [SERIAL=emulator-5554]
#   make check-apk                                             # is the bundle present & LFS-tracked?
#   make fetch-ci SOURCE='<drive link or id>' [KIND=drive|url]  # let a GitHub runner fetch it
#
APK_DIR  ?= apk
PKG      ?= com.monkeyibrow.worldsoccerchamps
TOOL     := tools/install-xapk.sh

.PHONY: help fetch-apk install-apk check-apk fetch-ci

help:
	@sed -n '1,6p' Makefile | sed 's/^# \{0,1\}//'

fetch-apk:
	@test -n "$(URL)" || { echo "usage: make fetch-apk URL='https://...'"; exit 1; }
	DIST_DIR=$(APK_DIR) bash $(TOOL) "$(URL)" --fetch-only
	@echo
	@echo "Downloaded into $(APK_DIR)/. To commit it:"
	@git lfs version >/dev/null 2>&1 || echo "  git lfs install   # git-lfs is not installed on this machine"
	@echo "  git add $(APK_DIR) .gitattributes && git commit -m 'Add $(PKG) bundle' && git push"

install-apk:
	@test -n "$(XAPK)" || { echo "usage: make install-apk XAPK=$(APK_DIR)/WorldSoccerChamps.xapk"; exit 1; }
	DIST_DIR=$(APK_DIR) bash $(TOOL) "$(XAPK)" $(if $(SERIAL),--serial $(SERIAL),)

check-apk:
	@echo "apk/ contents:"
	@ls -la $(APK_DIR) 2>/dev/null || { echo "  (directory missing)"; exit 0; }
	@for f in $(APK_DIR)/*.xapk $(APK_DIR)/*.apk; do \
	  [ -e "$$f" ] || continue; \
	  size=$$(wc -c < "$$f"); \
	  if [ "$$size" -lt 1000 ] && head -c 100 "$$f" | grep -q 'git-lfs'; then \
	    echo "  $$f: LFS pointer ($$size bytes) - run 'git lfs pull' to materialise"; \
	  else \
	    echo "  $$f: real file, $$size bytes"; \
	  fi; \
	done

# The agent sandbox caps workspace files at 100 MiB and cannot reach
# drive.google.com, so a >100 MiB bundle has to be fetched by a CI runner.
# Requires: gh CLI, and a Drive file readable by "anyone with the link".
KIND     ?= drive
FILENAME ?= WorldSoccerChamps.xapk

fetch-ci:
	@test -n "$(SOURCE)" || { echo "usage: make fetch-ci SOURCE='https://drive.google.com/file/d/<ID>/view'"; exit 1; }
	@command -v gh >/dev/null 2>&1 || { echo "gh CLI not found"; exit 1; }
	gh workflow run fetch-bundle.yml \
	  -f source='$(SOURCE)' \
	  -f source_kind=$(KIND) \
	  -f filename=$(FILENAME) \
	  -f commit=true
	@echo "Triggered. Watch it with: gh run watch"
