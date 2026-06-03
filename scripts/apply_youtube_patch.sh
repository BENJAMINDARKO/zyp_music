#!/bin/bash
# Apply youtube_explode_dart InnerTube client patch
# This fixes the VideoUnavailableException by forcing the clientName to WEB

echo "Patching youtube_explode_dart..."
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
FILE_PATH="$PUB_CACHE_DIR/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/reverse_engineering/youtube_http_client.dart"

if [ -f "$FILE_PATH" ]; then
    sed -i '' 's/"clientName": "ANDROID"/"clientName": "WEB"/g' "$FILE_PATH"
    sed -i '' 's/"clientVersion": ".*"/"clientVersion": "2.20250601.00.00"/g' "$FILE_PATH"
    echo "Patch applied successfully to $FILE_PATH"
else
    echo "Error: youtube_explode_dart-3.1.0 not found in pub cache."
    exit 1
fi
