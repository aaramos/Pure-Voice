# Pure Voice

Pure Voice is a native macOS menu bar app for turning dictated thoughts into polished text. The v1 loop is:

1. Press `right Command` to start recording.
2. Press `right Command + right Option` to stop.
3. Transcribe locally through the app-owned STT helper.
4. Polish on-device with Apple Foundation Models.
5. Paste into the original app when safe, otherwise copy to clipboard.

## First Run

1. Run the app:

   ```bash
   ./script/build_and_run.sh
   ```

2. Follow onboarding to grant microphone access and install the default Whisper transcription engine.
3. Grant Accessibility when prompted if you want Pure Voice to paste into the active app automatically. Without it, Pure Voice copies the result to the clipboard.
4. Confirm Apple Intelligence is enabled in System Settings for on-device polishing.

## Build And Test

```bash
swift test
./script/build_and_run.sh --verify
./script/build_dmg.sh
```

The DMG is created at `dist/PureVoice-1.1.2.dmg`.

## Backlog

The v1.x backlog lives in [docs/backlog.md](docs/backlog.md).

## v1.1 Notes

- Whisper is the default speech-to-text engine. Parakeet is available as an opt-in install from onboarding or Settings.
- v1.1 includes four personas: Polish, Brief, Rewrite, and Caveman. Polish is the default.
- Polishing uses Apple Foundation Models and requires macOS 26 with Apple Intelligence available.
- The default Push to Record gesture is `right Command` to start and `right Command + right Option` to stop. Push to Talk uses a 1.5-second long press of the Start shortcut.
- Transcript history is stored locally in SQLite under Application Support.
- Raw audio is temporary and is deleted after successful transcription.
- The current DMG is signed with the local Pure Voice development identity. Developer ID signing and notarization require Apple distribution credentials and are intentionally left as a follow-up.
