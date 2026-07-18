#!/usr/bin/env bash
# Build a distributable Seyeon.app (+ zip / dmg) for macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACAPP="$ROOT/MacApp"
DIST="$ROOT/dist"
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || date +%Y%m%d)"
PRODUCT_NAME="Seyeon"
SCHEME="LocalAgent"

echo "==> Cleaning dist"
rm -rf "$DIST"
mkdir -p "$DIST/DerivedData"

echo "==> Generating Xcode project"
cd "$MACAPP"
command -v xcodegen >/dev/null || { echo "xcodegen required (brew install xcodegen)"; exit 1; }
xcodegen generate

echo "==> Building Release $PRODUCT_NAME.app"
xcodebuild \
  -project LocalAgent.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DIST/DerivedData" \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_SRC="$(find "$DIST/DerivedData/Build/Products/Release" -maxdepth 1 -name "${PRODUCT_NAME}.app" -type d | head -1)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "ERROR: ${PRODUCT_NAME}.app not found under Release products"
  find "$DIST/DerivedData/Build/Products" -name "*.app" 2>/dev/null || true
  exit 1
fi

echo "==> Copying app → dist/${PRODUCT_NAME}.app"
rm -rf "$DIST/${PRODUCT_NAME}.app"
cp -R "$APP_SRC" "$DIST/${PRODUCT_NAME}.app"

# Ad-hoc sign so Gatekeeper is a bit happier for local distribution
if command -v codesign >/dev/null; then
  echo "==> Ad-hoc codesign"
  codesign --force --deep --sign - "$DIST/${PRODUCT_NAME}.app" || true
fi

ZIP_NAME="${PRODUCT_NAME}-${VERSION}-macos.zip"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-macos.dmg"

echo "==> Creating $ZIP_NAME"
(
  cd "$DIST"
  ditto -c -k --sequesterRsrc --keepParent "${PRODUCT_NAME}.app" "$ZIP_NAME"
)

if command -v hdiutil >/dev/null; then
  echo "==> Creating $DMG_NAME"
  STAGE="$DIST/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$DIST/${PRODUCT_NAME}.app" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  # Short README for recipients
  cat > "$STAGE/README.txt" <<EOF
Seyeon (local-agent)

1. Seyeon.app을 Applications로 드래그하거나 실행하세요.
2. 이 Mac에 local-agent 저장소가 있어야 합니다 (Python 백엔드).
   기본 경로 예: ~/Documents/src/local-agent
3. 경로가 다르면 앱 Settings에서 Repo root를 지정하세요.
4. 최초 1회: cd local-agent && pip install -r requirements.txt
   그리고 application/config.json 을 설정하세요.
EOF
  hdiutil create \
    -volname "$PRODUCT_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DIST/$DMG_NAME"
  rm -rf "$STAGE"
fi

# Drop heavy DerivedData from dist (keep only shippable artifacts)
rm -rf "$DIST/DerivedData"

echo ""
echo "Done. Artifacts:"
ls -lh "$DIST"
echo ""
echo "Install: open $DIST/$DMG_NAME"
echo "Or run:  open $DIST/${PRODUCT_NAME}.app"
