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
VENV_DIR = STT_DIR / ".venv"
VENV_PYTHON = VENV_DIR / "bin" / "python"
WHISPER_CPP_MODEL = APP_SUPPORT / "Models" / "whisper.cpp" / "ggml-base.en.bin"
MPLCONFIG_DIR = STT_DIR / "matplotlib"
PARAKEET_MODEL = "mlx-community/parakeet-tdt-0.6b-v2"

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


def emit_progress(message):
    print(json.dumps({"progress": message}, ensure_ascii=False), file=sys.stderr, flush=True)


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


def parakeet_cli_path():
    return VENV_DIR / "bin" / "parakeet-mlx"


def find_parakeet_cli():
    return find_executable(str(parakeet_cli_path()), "parakeet-mlx")


def run_checked(command, description, cwd=None):
    try:
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=cwd,
        )
        return result
    except FileNotFoundError as exc:
        raise RuntimeError(f"{description} failed because {command[0]} was not found") from exc
    except subprocess.CalledProcessError as exc:
        output = "\n".join(part for part in [exc.stdout, exc.stderr] if part).strip()
        if len(output) > 4000:
            output = output[-4000:]
        raise RuntimeError(f"{description} failed: {output or exc}") from exc


def create_or_reuse_venv():
    STT_DIR.mkdir(parents=True, exist_ok=True)
    MPLCONFIG_DIR.mkdir(parents=True, exist_ok=True)
    prepare_venv_dir()

    if VENV_PYTHON.exists():
        return

    uv = find_executable("uv")
    if uv:
        run_checked([uv, "venv", str(VENV_DIR), "--python", "python3.12"], "Creating STT Python environment")
        return

    python_bin = find_executable("python3.12", "python3.11", "python3")
    if not python_bin:
        raise RuntimeError("Python 3 was not found. Install Python 3, then reopen Pure Voice.")
    run_checked([python_bin, "-m", "venv", str(VENV_DIR)], "Creating STT Python environment")
    run_checked([str(VENV_PYTHON), "-m", "pip", "install", "--upgrade", "pip"], "Updating pip")


def verify_venv_whisper_health():
    if not VENV_PYTHON.exists():
        return {
            "engine": "whisper",
            "available": False,
            "message": f"Python environment missing at {VENV_PYTHON}",
            "model": None,
        }

    result = run_checked(
        [str(VENV_PYTHON), __file__, "health", "--engine", "whisper"],
        "Whisper health verification",
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Whisper health verification returned invalid output: {result.stdout}") from exc


def prepare_venv_dir():
    if VENV_DIR.exists() and not VENV_PYTHON.exists():
        shutil.rmtree(VENV_DIR)


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
    if os.environ.get("PURE_VOICE_STT_STUB_TEXT"):
        return {
            "engine": "parakeet",
            "available": True,
            "message": "Stub transcript configured",
            "model": "stub",
        }

    if find_parakeet_cli():
        return {
            "engine": "parakeet",
            "available": True,
            "message": "parakeet-mlx ready",
            "model": os.environ.get("PURE_VOICE_PARAKEET_MODEL", PARAKEET_MODEL),
        }

    return {
        "engine": "parakeet",
        "available": False,
        "message": "Parakeet is not installed",
        "model": None,
    }


def install_whisper():
    current_health = whisper_health()
    if current_health.get("available"):
        return current_health

    create_or_reuse_venv()

    uv = find_executable("uv")
    if uv:
        run_checked(
            [uv, "pip", "install", "--python", str(VENV_PYTHON), "faster-whisper"],
            "Installing faster-whisper",
        )
    else:
        run_checked([str(VENV_PYTHON), "-m", "pip", "install", "faster-whisper"], "Installing faster-whisper")

    health = verify_venv_whisper_health()
    if health.get("available"):
        health["message"] = "faster-whisper installed"
    return health


def install_parakeet():
    current_health = parakeet_health()
    if current_health.get("available"):
        return current_health

    emit_progress("Preparing Parakeet environment...")
    create_or_reuse_venv()

    emit_progress("Installing parakeet-mlx...")
    uv = find_executable("uv")
    if uv:
        run_checked(
            [uv, "pip", "install", "--python", str(VENV_PYTHON), "-U", "parakeet-mlx"],
            "Installing parakeet-mlx",
        )
    else:
        run_checked([str(VENV_PYTHON), "-m", "pip", "install", "-U", "parakeet-mlx"], "Installing parakeet-mlx")

    emit_progress("Checking Parakeet...")
    health = parakeet_health()
    if health.get("available"):
        health["message"] = "parakeet-mlx installed"
    return health


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


def clean_caption_text(raw_text):
    lines = []
    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.upper() == "WEBVTT":
            continue
        if line.isdigit():
            continue
        if "-->" in line:
            continue
        if line.startswith("NOTE"):
            continue
        lines.append(line)
    return " ".join(lines).strip()


def text_from_json(raw_text):
    try:
        payload = json.loads(raw_text)
    except json.JSONDecodeError:
        return None

    if isinstance(payload, dict):
        for key in ("text", "raw_text", "transcript"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        segments = payload.get("segments")
        if isinstance(segments, list):
            parts = []
            for segment in segments:
                if isinstance(segment, dict) and isinstance(segment.get("text"), str):
                    parts.append(segment["text"].strip())
            if parts:
                return " ".join(parts).strip()
    return None


def text_from_transcript_file(path):
    raw_text = path.read_text(encoding="utf-8", errors="replace").strip()
    if not raw_text:
        return None
    if path.suffix.lower() == ".json":
        return text_from_json(raw_text)
    if path.suffix.lower() in {".srt", ".vtt"}:
        return clean_caption_text(raw_text)
    return raw_text


def parakeet_status_only(text):
    lowered = text.lower()
    status_fragments = [
        "transcription complete",
        "outputs saved",
        "error writing output file",
    ]
    return any(fragment in lowered for fragment in status_fragments)


def read_parakeet_transcript(output_dir, stdout_text):
    suffix_order = [".txt", ".srt", ".vtt", ".json"]
    for suffix in suffix_order:
        for path in sorted(output_dir.glob(f"*{suffix}")):
            text = text_from_transcript_file(path)
            if text:
                return text

    text = stdout_text.strip()
    if text.startswith("{"):
        parsed = text_from_json(text)
        if parsed:
            return parsed
    if text and not parakeet_status_only(text):
        return text
    return ""


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


def transcribe_parakeet(audio_path, model_name):
    stub = os.environ.get("PURE_VOICE_STT_STUB_TEXT")
    if stub:
        return stub, "stub"

    cli = find_parakeet_cli()
    if not cli:
        raise RuntimeError("parakeet-mlx is not installed")

    model_id = model_name or os.environ.get("PURE_VOICE_PARAKEET_MODEL", PARAKEET_MODEL)
    absolute_audio_path = str(Path(audio_path).resolve())
    with tempfile.TemporaryDirectory(prefix="pure-voice-parakeet-") as temp_dir:
        output_dir = Path(temp_dir)
        result = run_checked(
            [cli, absolute_audio_path, "--model", model_id],
            "Parakeet transcription",
            cwd=temp_dir,
        )
        text = read_parakeet_transcript(output_dir, result.stdout)
        if not text:
            raise RuntimeError("Parakeet finished without a readable transcript.")
        return text.strip(), model_id


def handle_health(args):
    if args.engine == "whisper":
        emit(whisper_health())
    if args.engine == "parakeet":
        emit(parakeet_health())
    emit({"engine": args.engine, "available": False, "message": "Unknown STT engine", "model": None}, 2)


def handle_install(args):
    try:
        if args.engine == "whisper":
            health = install_whisper()
        elif args.engine == "parakeet":
            health = install_parakeet()
        else:
            raise RuntimeError(f"Unknown STT engine: {args.engine}")

        emit(health, 0 if health.get("available") else 1)
    except Exception as exc:
        emit(
            {
                "engine": args.engine,
                "available": False,
                "message": str(exc),
                "model": None,
            },
            1,
        )


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

    install = subparsers.add_parser("install")
    install.add_argument("--engine", required=True, choices=["whisper", "parakeet"])
    install.set_defaults(func=handle_install)

    transcribe = subparsers.add_parser("transcribe")
    transcribe.add_argument("--engine", required=True, choices=["whisper", "parakeet"])
    transcribe.add_argument("--audio", required=True)
    transcribe.add_argument("--model", default=None)
    transcribe.set_defaults(func=handle_transcribe)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
