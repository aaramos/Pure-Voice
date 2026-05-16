#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


APP_SUPPORT = Path.home() / "Library" / "Application Support" / "Pure Voice"
STT_DIR = APP_SUPPORT / "STT"
VENV_PYTHON = STT_DIR / ".venv" / "bin" / "python"
WHISPER_CPP_MODEL = APP_SUPPORT / "Models" / "whisper.cpp" / "ggml-base.en.bin"
MPLCONFIG_DIR = STT_DIR / "matplotlib"

try:
    MPLCONFIG_DIR.mkdir(parents=True, exist_ok=True)
    os.environ["MPLCONFIGDIR"] = str(MPLCONFIG_DIR)
except Exception:
    pass


def maybe_reexec_venv():
    if os.environ.get("PURE_VOICE_NO_VENV_REEXEC") == "1":
        return
    if os.environ.get("VIRTUAL_ENV"):
        return
    if VENV_PYTHON.exists() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), __file__, *sys.argv[1:]])


def emit(payload, exit_code=0):
    print(json.dumps(payload, ensure_ascii=False))
    raise SystemExit(exit_code)


def find_executable(*names):
    for name in names:
        if os.path.isabs(name) and Path(name).exists():
            return name
        found = shutil.which(name)
        if found:
            return found
    return None


def import_faster_whisper():
    try:
        from faster_whisper import WhisperModel  # type: ignore
        return WhisperModel
    except Exception:
        return None


def import_nemo_asr():
    try:
        import nemo.collections.asr as nemo_asr  # type: ignore
        return nemo_asr
    except Exception:
        return None


def whisper_health():
    if os.environ.get("PURE_VOICE_STT_STUB_TEXT"):
        return {
            "engine": "whisper",
            "available": True,
            "message": "Stub transcript configured",
            "model": "stub",
        }

    if import_faster_whisper() is not None:
        return {
            "engine": "whisper",
            "available": True,
            "message": "faster-whisper ready",
            "model": os.environ.get("PURE_VOICE_WHISPER_MODEL", "base.en"),
        }

    whisper_cli = find_executable(
        os.environ.get("PURE_VOICE_WHISPER_CLI", ""),
        "whisper-cli",
        "main",
    )
    if whisper_cli and WHISPER_CPP_MODEL.exists():
        return {
            "engine": "whisper",
            "available": True,
            "message": "whisper.cpp ready",
            "model": str(WHISPER_CPP_MODEL),
        }
    if whisper_cli:
        return {
            "engine": "whisper",
            "available": False,
            "message": "whisper.cpp found; model missing",
            "model": None,
        }

    return {
        "engine": "whisper",
        "available": False,
        "message": "Run script/setup_stt.sh",
        "model": None,
    }


def parakeet_health():
    if os.environ.get("PURE_VOICE_PARAKEET_STUB_TEXT"):
        return {
            "engine": "parakeet",
            "available": True,
            "message": "Stub transcript configured",
            "model": "stub",
        }

    if import_nemo_asr() is not None:
        return {
            "engine": "parakeet",
            "available": True,
            "message": "NeMo ASR ready",
            "model": os.environ.get("PURE_VOICE_PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3"),
        }

    return {
        "engine": "parakeet",
        "available": False,
        "message": "Run script/setup_parakeet.sh",
        "model": None,
    }


def transcribe_with_faster_whisper(audio_path, model_name):
    WhisperModel = import_faster_whisper()
    if WhisperModel is None:
        raise RuntimeError("faster-whisper is not installed")

    model_id = model_name or os.environ.get("PURE_VOICE_WHISPER_MODEL", "base.en")
    compute_type = os.environ.get("PURE_VOICE_WHISPER_COMPUTE_TYPE", "int8")
    model = WhisperModel(model_id, device="auto", compute_type=compute_type)
    segments, _info = model.transcribe(audio_path, vad_filter=True)
    text = " ".join(segment.text.strip() for segment in segments).strip()
    return text, model_id


def transcribe_with_whisper_cpp(audio_path, model_name):
    whisper_cli = find_executable(
        os.environ.get("PURE_VOICE_WHISPER_CLI", ""),
        "whisper-cli",
        "main",
    )
    if not whisper_cli:
        raise RuntimeError("whisper.cpp CLI is not installed")

    model_path = Path(model_name or os.environ.get("PURE_VOICE_WHISPER_CPP_MODEL", str(WHISPER_CPP_MODEL)))
    if not model_path.exists():
        raise RuntimeError(f"whisper.cpp model missing at {model_path}")

    with tempfile.TemporaryDirectory(prefix="pure-voice-whisper-") as temp_dir:
        output_prefix = Path(temp_dir) / "transcript"
        command = [
            whisper_cli,
            "-m",
            str(model_path),
            "-f",
            audio_path,
            "-otxt",
            "-of",
            str(output_prefix),
            "-np",
        ]
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output_file = output_prefix.with_suffix(".txt")
        return output_file.read_text(encoding="utf-8").strip(), str(model_path)


def transcribe_whisper(audio_path, model_name):
    stub = os.environ.get("PURE_VOICE_STT_STUB_TEXT")
    if stub:
        return stub, "stub"

    try:
        return transcribe_with_faster_whisper(audio_path, model_name)
    except Exception as faster_error:
        try:
            return transcribe_with_whisper_cpp(audio_path, model_name)
        except Exception as cpp_error:
            raise RuntimeError(f"Whisper unavailable. faster-whisper: {faster_error}; whisper.cpp: {cpp_error}")


def extract_transcription_text(output):
    if isinstance(output, (list, tuple)):
        if not output:
            return ""
        return extract_transcription_text(output[0])
    if isinstance(output, dict):
        return str(output.get("text") or output.get("transcript") or "").strip()
    if hasattr(output, "text"):
        return str(output.text).strip()
    return str(output).strip()


def transcribe_parakeet(audio_path, model_name):
    stub = os.environ.get("PURE_VOICE_PARAKEET_STUB_TEXT")
    if stub:
        return stub, "stub"

    model_id = model_name or os.environ.get("PURE_VOICE_PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3")
    device = os.environ.get("PURE_VOICE_PARAKEET_DEVICE", "cpu")
    if device == "cpu":
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

    nemo_asr = import_nemo_asr()
    if nemo_asr is None:
        raise RuntimeError("Parakeet requires NeMo ASR. Run script/setup_parakeet.sh.")

    asr_model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_id)
    if hasattr(asr_model, "eval"):
        asr_model.eval()

    if device:
        try:
            asr_model.to(device)
        except Exception as device_error:
            if device == "cpu":
                raise
            asr_model.to("cpu")
            print(f"Fell back to CPU for Parakeet after device error: {device_error}", file=sys.stderr)

    output = asr_model.transcribe([audio_path])
    return extract_transcription_text(output), model_id


def handle_health(args):
    if args.engine == "whisper":
        emit(whisper_health())
    if args.engine == "parakeet":
        emit(parakeet_health())
    emit({"engine": args.engine, "available": False, "message": "Unknown STT engine", "model": None}, 2)


def handle_transcribe(args):
    started = time.monotonic()
    try:
        if args.engine == "whisper":
            raw_text, model = transcribe_whisper(args.audio, args.model)
        elif args.engine == "parakeet":
            raw_text, model = transcribe_parakeet(args.audio, args.model)
        else:
            raise RuntimeError(f"Unknown STT engine: {args.engine}")

        emit(
            {
                "engine": args.engine,
                "model": model,
                "raw_text": raw_text,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "status": "ok",
                "error_message": None,
            }
        )
    except Exception as exc:
        emit(
            {
                "engine": args.engine,
                "model": args.model or "",
                "raw_text": "",
                "latency_ms": int((time.monotonic() - started) * 1000),
                "status": "error",
                "error_message": str(exc),
            },
            1,
        )


def main():
    maybe_reexec_venv()

    parser = argparse.ArgumentParser(description="Pure Voice STT helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    health = subparsers.add_parser("health")
    health.add_argument("--engine", required=True, choices=["whisper", "parakeet"])
    health.set_defaults(func=handle_health)

    transcribe = subparsers.add_parser("transcribe")
    transcribe.add_argument("--engine", required=True, choices=["whisper", "parakeet"])
    transcribe.add_argument("--audio", required=True)
    transcribe.add_argument("--model", default=None)
    transcribe.set_defaults(func=handle_transcribe)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
