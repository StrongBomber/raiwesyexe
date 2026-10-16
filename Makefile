# Android bundle helpers.
#
#   make fetch-apk   URL='https://data.winudf.com/XAPK/....'   # download into apk/
#   make install-apk [XAPK=apk/Foo.xapk] [SERIAL=emulator-5554]
#   make check-apk                                             # is the bundle present & LFS-tracked?
#
APK_DIR  ?= apk
PKG      ?= com.monkeyibrow.worldsoccerchamps
TOOL     := tools/install-xapk.sh

.PHONY: help fetch-apk install-apk check-apk

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
