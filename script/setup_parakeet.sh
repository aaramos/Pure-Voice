#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/Pure Voice"
STT_DIR="$APP_SUPPORT/STT"
VENV_DIR="$STT_DIR/.venv"
PYTHON="$VENV_DIR/bin/python"
export MPLCONFIGDIR="$STT_DIR/matplotlib"

mkdir -p "$STT_DIR"
mkdir -p "$MPLCONFIGDIR"

if [[ ! -x "$PYTHON" ]]; then
  "$ROOT_DIR/script/setup_stt.sh"
fi

if command -v uv >/dev/null 2>&1; then
  uv pip install --python "$PYTHON" --upgrade torch torchaudio soundfile "nemo_toolkit[asr]"
else
  "$PYTHON" -m pip install --upgrade pip
  "$PYTHON" -m pip install --upgrade torch torchaudio soundfile "nemo_toolkit[asr]"
fi

"$PYTHON" "$ROOT_DIR/Sources/PureVoiceApp/Resources/stt_helper.py" health --engine parakeet

cat <<EOF

Pure Voice Parakeet setup complete.

Parakeet uses NVIDIA NeMo ASR from:
  $VENV_DIR

Default model:
  nvidia/parakeet-tdt-0.6b-v3

The first Parakeet transcription may download the model into the local cache.
Inference remains local after the model is available.
EOF
