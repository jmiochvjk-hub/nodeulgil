#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BUILD_TOOLS="$SDK_DIR/build-tools/36.1.0"
ANDROID_JAR="$SDK_DIR/platforms/android-35/android.jar"
JAVA_HOME_DIR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
OUT_DIR="$PROJECT_DIR/build"
KEYSTORE="$OUT_DIR/pickedule-debug.keystore"

export JAVA_HOME="$JAVA_HOME_DIR"
export PATH="$JAVA_HOME_DIR/bin:$PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/compiled" "$OUT_DIR/gen" "$OUT_DIR/classes" "$OUT_DIR/dex" "$OUT_DIR/dist"

"$BUILD_TOOLS/aapt2" compile --dir "$PROJECT_DIR/res" -o "$OUT_DIR/compiled/res.zip"
"$BUILD_TOOLS/aapt2" link \
  -o "$OUT_DIR/base.apk" \
  -I "$ANDROID_JAR" \
  --manifest "$PROJECT_DIR/AndroidManifest.xml" \
  --java "$OUT_DIR/gen" \
  --min-sdk-version 23 \
  --target-sdk-version 35 \
  "$OUT_DIR/compiled/res.zip"

"$JAVA_HOME_DIR/bin/javac" \
  -classpath "$ANDROID_JAR" \
  -source 17 \
  -target 17 \
  -d "$OUT_DIR/classes" \
  $(find "$PROJECT_DIR/src" "$OUT_DIR/gen" -name '*.java')

"$BUILD_TOOLS/d8" \
  --lib "$ANDROID_JAR" \
  --output "$OUT_DIR/dex" \
  $(find "$OUT_DIR/classes" -name '*.class')

cp "$OUT_DIR/base.apk" "$OUT_DIR/unsigned.apk"
(cd "$OUT_DIR/dex" && zip -q -r "$OUT_DIR/unsigned.apk" classes.dex)

"$BUILD_TOOLS/zipalign" -f -p 4 "$OUT_DIR/unsigned.apk" "$OUT_DIR/aligned.apk"

"$JAVA_HOME_DIR/bin/keytool" \
  -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -storepass android \
  -alias pickedule \
  -keypass android \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=pickedule,O=pickedule,C=KR" >/dev/null

"$BUILD_TOOLS/apksigner" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias pickedule \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$OUT_DIR/dist/pickedule-debug.apk" \
  "$OUT_DIR/aligned.apk"

"$BUILD_TOOLS/apksigner" verify "$OUT_DIR/dist/pickedule-debug.apk"
echo "$OUT_DIR/dist/pickedule-debug.apk"
