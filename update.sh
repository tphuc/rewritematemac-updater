#!/bin/bash
set -e
# ---------- CONFIG ----------
APP_NAME="RewriteMateMac.app"
APP_PATH="$HOME/Documents/RewriteMate/RewriteMateMac.app"
UPDATER_DIR="$HOME/Documents/RewriteMate/rewritematemac-updater"
DMG_NAME="RewriteMateMac.dmg"
APPCAST="appcast.xml"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/RewriteMateMac-bgbdnfzaosjqudcupgcykynqpgoh/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
GITHUB_BASE_URL="https://github.com/tphuc/rewritematemac-updater/releases/download"
# ----------------------------
VERSION="$1"
if [[ -z "$VERSION" ]]; then
  echo "❌ Usage: ./update.sh <version> (e.g. 1.0.2)"
  exit 1
fi
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')
echo "🚀 Releasing RewriteMate $VERSION ($BUILD_NUMBER)"

cd "$UPDATER_DIR"

echo "🔍 Current directory: $(pwd)"
echo "🔍 Appcast file exists? $( [ -f "$APPCAST" ] && echo Yes || echo No )"

# ---------- CREATE TEMP FOLDER FOR DMG CONTENTS ----------
echo "🗂️ Preparing DMG contents..."
TEMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TEMP_DIR/"
ln -s /Applications "$TEMP_DIR/Applications" # Optional: nice drag-to-install shortcut

# ---------- CREATE DMG ----------
echo "📦 Creating DMG..."
rm -f "$DMG_NAME"
hdiutil create -srcfolder "$TEMP_DIR" -volname "RewriteMate $VERSION" \
  -fs HFS+ -format UDZO "$DMG_NAME"

# Clean up temp folder
rm -rf "$TEMP_DIR"

FILE_SIZE=$(stat -f%z "$DMG_NAME")
echo "📏 DMG size: $FILE_SIZE bytes"

# ---------- GITHUB RELEASE ----------
echo "🚀 Uploading DMG to GitHub Release..."
gh release create "v$VERSION" "$DMG_NAME" \
  --title "RewriteMate $VERSION" \
  --notes "Improvements and bug fixes" \
  || gh release upload "v$VERSION" "$DMG_NAME" --clobber

# ---------- SPARKLE SIGN ----------
echo "🔐 Generating Sparkle signature..."
SIGN_OUTPUT=$("$SPARKLE_BIN" "$DMG_NAME")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
echo "🔑 Extracted signature: $ED_SIGNATURE"

# ---------- XML ITEM ----------
ITEM=$(cat <<EOF
  <item>
    <title>Version $VERSION</title>
    <sparkle:version>$BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
    <enclosure
      url="$GITHUB_BASE_URL/v$VERSION/$DMG_NAME"
      length="$FILE_SIZE"
      type="application/octet-stream"
      sparkle:edSignature="$ED_SIGNATURE"
    />
    <description><![CDATA[
      - Improvements
      - Bug fixes
    ]]></description>
  </item>
EOF
)

echo "🧩 New item XML:"
echo "$ITEM"

# ---------- UPDATE APPCAST (FIXED + DEBUG) ----------
echo "🧠 Updating appcast.xml..."

# Show before state
echo "📄 appcast.xml before update (first 20 lines):"
head -20 "$APPCAST"

# Backup
cp "$APPCAST" "$APPCAST.bak"
echo "💾 Backup created: $APPCAST.bak"

# Insert new item as FIRST inside <channel>
perl -0777 -i -pe '
  s|(<channel\b[^>]*>)|$1\n    '"$ITEM"'|i
' "$APPCAST"

# Show after state
echo "📄 appcast.xml after update (first 30 lines):"
head -30 "$APPCAST"

echo "✅ appcast.xml updated (new item inserted as first)"

# ---------- GIT ----------
echo "📤 Committing appcast..."
git add "$APPCAST"
git commit -m "Release v$VERSION"
git push

echo "✅ Release v$VERSION (DMG) completed successfully"