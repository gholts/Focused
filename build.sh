#!/bin/sh
set -eu

cd "$(dirname "$0")"
mkdir -p build
xcrun --sdk iphoneos clang \
  -arch arm64e -miphoneos-version-min=14.0 -fobjc-arc \
  -Wall -Wextra -Werror -fvisibility=hidden -dynamiclib \
  -install_name @rpath/WeChatFocused.dylib \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -framework Foundation -framework UIKit -framework Photos \
  -framework ImageIO -framework CoreGraphics \
  -weak_framework PhotosUI -weak_framework UniformTypeIdentifiers \
  -o build/WeChatFocused.dylib src/Entry.m src/MomentsTab.m src/NativePicker.m
