#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/Pure Voice"
STT_DIR="$APP_SUPPORT/STT"
export MPLCONFIGDIR="$STT_DIR/matplotlib"

mkdir -p "$STT_DIR"
mkdir -p "$MPLCONFIGDIR"

python3 "$ROOT_DIR/Sources/PureVoiceApp/Resources/stt_helper.py" install --engine whisper

cat <<EOF

Pure Voice STT setup complete.

Whisper uses faster-whisper from:
  $STT_DIR/.venv

The first transcription may download the selected Whisper model into the local
Hugging Face cache. Inference remains local after the model is available.
EOF
