# Pure Voice

Pure Voice is a native macOS menu bar app for turning dictated thoughts into polished text. The v1 loop is:

1. Press `right Command + right Option` to start recording.
2. Press `right Option` to stop.
3. Transcribe locally through the app-owned STT helper.
4. Polish on-device with Apple Foundation Models.
5. Paste into the original app when safe, otherwise copy to clipboard.

## First Run

1. Install the local Whisper helper environment:

   ```bash
   ./script/setup_stt.sh
   ```

2. Run the app:

   ```bash
   ./script/build_and_run.sh
   ```

3. Confirm Apple Intelligence is enabled in System Settings.

## Build And Test

```bash
swift test
./script/build_and_run.sh --verify
./script/build_dmg.sh
```

The DMG is created at `dist/PureVoice-1.0.0.dmg`.

## v1 Notes

- Whisper is the v1 speech-to-text engine.
- v1 includes two personas: Clarity and Ultra Concise.
- Polishing uses Apple Foundation Models and requires macOS 26 with Apple Intelligence available.
- The global recording gesture is `right Command + right Option` to start and `right Option` to stop.
- Transcript history is stored locally in SQLite under Application Support.
- Raw audio is temporary and is deleted after successful transcription.
- The current DMG is ad-hoc signed for local use. Developer ID signing and notarization require installing Apple signing credentials and are intentionally left as a follow-up.
