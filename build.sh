#!/usr/bin/env bash
set -euo pipefail

# 다이나믹레이크 빌드 (SwiftPM, 비샌드박스, ad-hoc 서명)
#   ./build.sh           → build/DynamicLake.app 생성
#   ./build.sh install   → 빌드 후 /Applications 로 설치

BIN="DynamicLake"          # SwiftPM product / 실행 파일명 (불변 — 번들 ID·프로세스명 유지)
APP="Halo"                 # 앱 번들 표시명
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
BUNDLE="$BUILD/$APP.app"
CONTENTS="$BUNDLE/Contents"

echo "▶ swift build (release)…"
swift build -c release --product "$BIN"
BINPATH="$(swift build -c release --product "$BIN" --show-bin-path)/$BIN"

rm -rf "$BUILD"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINPATH" "$CONTENTS/MacOS/$BIN"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

echo "▶ ad-hoc 서명…"
codesign --force --sign - "$BUNDLE"
echo "✅ 빌드 완료: $BUNDLE"

if [[ "${1:-}" == "install" ]]; then
    DEST="/Applications/$APP.app"
    # 이미 떠 있으면 종료 후 교체
    pkill -x "$BIN" 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$BUNDLE" "$DEST"
    codesign --force --sign - "$DEST"
    echo "✅ 설치 완료: $DEST"
    echo "   실행:  open \"$DEST\""
else
    echo "   실행:  open \"$BUNDLE\""
    echo "   설치:  $0 install"
fi
