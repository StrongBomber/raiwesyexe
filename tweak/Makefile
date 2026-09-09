# IGGCompanion — Theos tweak derleme dosyası.
# Gereken: macOS + Xcode CLT + Theos ($THEOS tanımlı olmalı).
#
#   make package                                  # rootful .deb
#   THEOS_PACKAGE_SCHEME=rootless make package    # rootless .deb

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0

TWEAK_NAME = IGGCompanion
IGGCompanion_FILES = Tweak.x
IGGCompanion_CFLAGS = -fobjc-arc -Wall

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk
