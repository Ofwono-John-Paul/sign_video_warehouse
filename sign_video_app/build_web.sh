#!/usr/bin/env bash
set -e

FLUTTER_DIR="$HOME/flutter"

# Install Flutter SDK if not already present
if [ ! -d "$FLUTTER_DIR" ]; then
  echo ">>> Installing Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

export PATH="$PATH:$FLUTTER_DIR/bin"

echo ">>> Flutter version:"
flutter --version

echo ">>> Getting dependencies..."
flutter pub get

echo ">>> Building Flutter web..."
flutter build web \
  --release \
  --dart-define=API_BASE_URL=https://sign-video-backend-7o9n.onrender.com

echo ">>> Build complete. Output is in build/web/"
