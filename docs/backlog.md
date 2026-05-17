# Pure Voice Backlog

This backlog starts from the v1 baseline: Whisper speech-to-text, Apple Foundation Models polishing, and six active writing modes. Items below are candidates for v1.x unless promoted into a release plan.

## Priorities

### P0 - Restore Strong Alternate STT With Parakeet MLX

**Goal:** Add Parakeet back through MLX instead of the earlier NeMo path.

**Reference:** https://github.com/senstella/parakeet-mlx

**Scope:**
- Add a setup path for `senstella/parakeet-mlx`.
- Add a helper engine behind an internal feature flag first.
- Keep Whisper as the default until Parakeet MLX passes end-to-end recording smoke tests.
- Report Parakeet MLX health separately from import availability.
- Avoid startup chatter breaking the JSON helper contract.

**Acceptance:**
- Helper health returns clean JSON with no non-JSON preamble.
- Recording through Parakeet MLX produces text through the same app pipeline as Whisper.
- The UI only exposes Parakeet MLX after setup and health are valid.
- A real record-to-paste smoke test passes before the engine becomes selectable.

### P0 - UI Polish

**Goal:** Make the app feel complete and reduce uncertainty when paste, clipboard, microphone, or model availability changes.

**Scope:**
- Tighten menu bar status language.
- Improve the recording/status modal layout and visual hierarchy.
- Make output destination unmistakable: pasted, copied, raw transcript fallback, or failed.
- Keep permission recovery actionable with direct next steps.
- Review light/dark mode and spacing across the menu, settings, and modal.

**Acceptance:**
- A user can tell where their text went without opening logs.
- Permission warnings state the exact permission and why it is needed.
- Status modal corners, background, text, and waveform look native and intentional.
- No clipped text at common desktop widths.

### P1 - Add More Persona Modes

**Goal:** Add focused writing modes beyond the Polish default plus the Apple-style Rewrite, Proofread, Concise, Clarity, and Ultra Concise set while keeping the persona list small enough to scan.

**New modes:**
- Professional
- Executive Summary
- Plain English

**Scope:**
- Add prompts in `PersonaDefaults`.
- Migrate existing databases to insert these modes without duplicating them.
- Keep Polish as the default.
- Add tests for the full default persona set and default selection.

**Acceptance:**
- Settings and menu bar show Polish, Rewrite, Proofread, Concise, Clarity, Ultra Concise, Professional, Executive Summary, and Plain English.
- Polish remains the single default on fresh install and migration.
- Each prompt includes the no-preamble/no-reasoning instruction.

### P1 - Advanced Persona Prompt Tuning

**Goal:** Let advanced users tune the prompt behind each writing persona from inside the app without cluttering the default recording workflow.

**Scope:**
- Add an Advanced drawer or disclosure section in Settings.
- The drawer opens a persona editor with a dropdown for all personas.
- Show whether each persona is included in the menu/persona picker.
- Allow included personas to be toggled on or off without deleting their saved prompt.
- Allow editing the prompt text for each persona.
- Provide a Restore Defaults action for the selected persona.
- Provide a Restore All Defaults action for all personas.
- Keep at least one included persona at all times.
- Keep one default persona selected at all times; if the default is excluded, choose Polish or the first included persona.
- Persist custom prompts and inclusion state in SQLite.
- Preserve bundled defaults so restore actions can recover the shipped prompts.

**Acceptance:**
- Settings exposes the persona editor only through an Advanced drawer/disclosure.
- The persona dropdown includes every bundled persona.
- Editing a prompt changes the prompt used on the next polishing request.
- Excluding a persona removes it from normal persona selection without losing its custom prompt.
- Restore Defaults resets the selected persona prompt and inclusion state to the bundled default.
- Restore All Defaults resets every persona prompt, inclusion state, and the default persona back to bundled defaults.
- Tests cover prompt editing, include/exclude persistence, default fallback, and restore behavior.

### P1 - Audio File To Text

**Goal:** Let users transcribe an existing audio file without recording live.

**Scope:**
- Add an import action for local audio files.
- Reuse the same STT, persona, polishing, history, and paste/clipboard pipeline.
- Support common macOS audio formats that AVFoundation can read.
- Show progress and errors in the same status surface used for live recording.

**Acceptance:**
- Selecting an audio file produces polished text.
- Output can be pasted, copied, and saved to history like live recordings.
- Unsupported file formats show a clear error.
- Temporary converted files are cleaned up.

### P2 - Optional OpenAI-Compatible LLM Backend

**Goal:** Add a configurable cloud/local OpenAI-compatible polishing backend without making it part of the default v1 experience.

**Scope:**
- Add an optional backend provider setting.
- Support OpenAI-compatible base URL, model, and API key.
- Store API keys securely and never touch that keychain item unless the backend is selected.
- Preserve Apple Foundation Models as the default.
- Include deterministic response sanitization and no-reasoning prompts.

**Acceptance:**
- Apple Foundation Models remains the default and works with no API key prompts.
- OpenAI-compatible backend can be enabled manually.
- Keychain access happens only after the backend is enabled.
- Backend errors do not paste or copy bad output.
- Switching back to Apple disables OpenAI endpoint health checks and keychain reads.

## Release Notes

- Treat Parakeet MLX and OpenAI-compatible LLM support as opt-in until their end-to-end paths are boring and reliable.
- Keep the main UI focused on recording, polishing, and output delivery; advanced backend configuration should stay out of the default path.
