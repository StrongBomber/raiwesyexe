# raiwesyexe — iGameGod paketleme + geliştirme projesi

VERSION := $(shell cat VERSION 2>/dev/null)
ROOTFUL_DEB := build/com.gamegod.igg_$(VERSION)_iphoneos-arm.deb
ROOTLESS_DEB := build/com.gamegod.igg_$(VERSION)_iphoneos-arm64.deb

.PHONY: help extract package package-rootless verify test repo bundle clean all

all: extract package package-rootless verify test ## Tam hat: aç, derle (2 varyant), doğrula, test et

help: ## Bu yardım
	@echo "Hedefler:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

extract: ## Upstream .deb'i build/extract altına aç
	./scripts/extract.sh

package: extract ## Rootful .deb'i yeniden derle -> $(ROOTFUL_DEB)
	./scripts/package.sh

package-rootless: extract ## Rootless (/var/jb) .deb'i derle -> $(ROOTLESS_DEB)
	./scripts/package.sh --rootless

verify: ## Derlenen .deb'leri upstream ile karşılaştırıp doğrula
	./scripts/verify.sh

test: ## Kurulum scriptlerini mock-kök üzerinde test et (rootful+rootless)
	./tests/test-packaging.sh

repo: package package-rootless ## Cydia/Sileo APT deposu üret (build/repo)
	./scripts/make-repo.sh

clean: ## build/ dizinini temizle
	rm -rf build

bundle: ## Companion gomulu tum-bir-arada deb'leri uret (tweak deb'leri build/dl/ altinda olmali)
	./scripts/bundle-companion.sh --igg "$$(ls build/com.gamegod.igg_*_iphoneos-arm.deb 2>/dev/null | head -1)" --tweak "$$(ls build/dl/*_iphoneos-arm.rootful.deb 2>/dev/null | head -1)" --output build/
	./scripts/bundle-companion.sh --igg "$$(ls build/com.gamegod.igg_*_iphoneos-arm64.deb 2>/dev/null | head -1)" --tweak "$$(ls build/dl/*_iphoneos-arm64.rootless.deb 2>/dev/null | head -1)" --output build/
