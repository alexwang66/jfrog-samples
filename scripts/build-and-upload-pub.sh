#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../pub-samples" && pwd)"
SERVER_ID="${JFROG_SERVER_ID:-solenglatest}"
PUB_REPO="${JFROG_PUB_REPO:-pub-samples-local}"
BUILD_NAME="${JFROG_BUILD_NAME:-jfrog-pub-sample}"
VERSION="$(awk '$1 == "version:" {print $2; exit}' "$PROJECT_DIR/pubspec.yaml")"
BUILD_NUMBER="${JFROG_BUILD_NUMBER:-$VERSION}"
ARCHIVE_DIR="$PROJECT_DIR/build/pub/jfrog_pub_sample"
ARCHIVE="$ARCHIVE_DIR/jfrog_pub_sample-$VERSION.tar.gz"

command -v dart >/dev/null || { echo "dart is required; install Dart or Flutter first" >&2; exit 1; }
command -v jf >/dev/null || { echo "jf is required; install JFrog CLI first" >&2; exit 1; }

cd "$PROJECT_DIR"
dart pub get
dart test
dart pub publish --dry-run

rm -rf "$PROJECT_DIR/build/pub"
mkdir -p "$ARCHIVE_DIR"
tar -czf "$ARCHIVE" --exclude='.dart_tool' --exclude='build' --exclude='test' --exclude='pubspec.lock' --exclude='repo-template.json' -C "$PROJECT_DIR" .

jf rt upload "$ARCHIVE" "$PUB_REPO/jfrog_pub_sample/jfrog_pub_sample-$VERSION.tar.gz" \
  --server-id="$SERVER_ID" --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER" --detailed-summary
jf rt build-add-git "$BUILD_NAME" "$BUILD_NUMBER" \
  --server-id="$SERVER_ID" --dot-git-path="$(dirname "$PROJECT_DIR")"
jf rt build-publish "$BUILD_NAME" "$BUILD_NUMBER" --server-id="$SERVER_ID" --detailed-summary

echo "Published $ARCHIVE to $PUB_REPO as build $BUILD_NAME/$BUILD_NUMBER"
