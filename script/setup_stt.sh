#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/Pure Voice"
STT_DIR="$APP_SUPPORT/STT"
VENV_DIR="$STT_DIR/.venv"

mkdir -p "$STT_DIR"

if command -v uv >/dev/null 2>&1; then
  uv venv "$VENV_DIR" --python python3.12
  uv pip install --python "$VENV_DIR/bin/python" faster-whisper
else
  PYTHON_BIN="$(command -v python3.12 || command -v python3.11 || command -v python3)"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip
  "$VENV_DIR/bin/python" -m pip install faster-whisper
fi

"$VENV_DIR/bin/python" "$ROOT_DIR/Sources/PureVoiceApp/Resources/stt_helper.py" health --engine whisper

cat <<EOF

Pure Voice STT setup complete.

Whisper uses faster-whisper from:
  $VENV_DIR

The first transcription may download the selected Whisper model into the local
Hugging Face cache. Inference remains local after the model is available.
EOF
