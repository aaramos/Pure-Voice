# Pure Voice

Pure Voice is a native macOS menu bar app for turning dictated thoughts into polished text. The Phase 1 loop is:

1. Press `Control Option Space` to start recording.
2. Press `Control Option Space` again to stop.
3. Transcribe locally through the app-owned STT helper.
4. Polish through the OLMX OpenAI-compatible endpoint at `http://127.0.0.1:8000`.
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

3. In the Pure Voice window, enter the OLMX API key. It is stored in macOS Keychain.
4. Click `Refresh Models`, then select the model to use for polishing.

## Build And Test

```bash
swift test
./script/build_and_run.sh --verify
./script/build_dmg.sh
```

The DMG is created at `dist/PureVoice-0.1.0.dmg`.

## Phase 1 Notes

- Whisper is the required working STT engine for Phase 1.
- Parakeet is present in settings and health checks, but remains setup-gated until a local runtime is configured.
- Transcript history is stored locally in SQLite under Application Support.
- Raw audio is temporary and is deleted after successful transcription.
- The current DMG is ad-hoc signed for local use. Developer ID signing and notarization require installing Apple signing credentials and are intentionally left as a follow-up.
