# Pure Voice PRD: Persona Voice Polish

## Vision

Pure Voice is a lightweight, always-on macOS app that turns raw spoken thoughts into polished text ready to paste into any app. The user speaks naturally, selects a communication persona, and receives concise, context-appropriate text shaped by local transcription and a configurable local LLM endpoint.

## Core Problem

Adrian often thinks aloud in verbose, stream-of-consciousness form, but wants written output that is precise, audience-aware, and fast to send. The app removes the friction of manually refactoring spoken thoughts into finished communication.

## Phase 1 MVP

### Product Goal

Deliver a reliable macOS record -> transcribe -> polish -> paste loop with local inference, five default personas, selectable speech-to-text engine, and selectable polishing model from an OpenAI-compatible endpoint.

### Primary Workflow

1. User presses the global hotkey.
2. Recording indicator appears.
3. User speaks naturally.
4. User presses the hotkey again or clicks stop.
5. App transcribes the audio using the selected STT engine.
6. App sends the transcript to the selected local OpenAI-compatible LLM endpoint with the active persona prompt.
7. App pastes the polished text into the active text field when safe.
8. If paste fails, app copies the polished text to the clipboard and shows a clear copied state.

### MVP Scope

- Native macOS app.
- Menu bar app with optional compact floating HUD.
- Global hotkey to start and stop recording.
- System default microphone capture.
- Batch transcription after recording stops.
- Local transcription only.
- Local LLM polishing through OpenAI-compatible API.
- Five built-in personas.
- Persona selector in the main UI.
- Transcript preview for feedback.
- Local transcript history and run metadata.
- Paste to active field with clipboard fallback.

### Explicitly Out Of Scope For Phase 1

- Streaming transcription.
- Streaming polishing.
- Mobile apps.
- Browser extension.
- Cloud fallback.
- Translation mode.
- Custom persona creation.
- Full benchmarking dashboard.
- Fine-tuning pipeline.
- Calendar/contact-aware persona selection.

## Input And Recording

### Hotkey

- Default hotkey: Control+Option+Space.
- User can start and stop recording with the same hotkey.
- Hotkey customization is deferred to Phase 2 unless trivial to expose safely.

### Recording Feedback

- Menu bar icon reflects status: idle, recording, processing, error.
- Floating HUD shows:
  - Active persona.
  - Recording state.
  - Audio level meter or pulsing indicator.
  - Current processing stage.

### Audio Requirements

- Use the system default microphone.
- Record until the user stops.
- No automatic timeout in MVP.
- Store raw audio only as needed for processing.
- Delete raw audio after successful transcription unless debug retention is enabled.

## Speech-To-Text

### Engines

Phase 1 includes a selectable STT engine:

- Whisper
- Parakeet

Whisper is the required baseline and default engine. Parakeet is a first-class selectable engine, but it may be marked unavailable if its local runtime, model files, or hardware requirements are not configured.

### Whisper Adapter

- Support a local Whisper implementation suitable for macOS.
- Acceptable implementation options:
  - whisper.cpp
  - faster-whisper
  - another local adapter if it exposes equivalent behavior
- Default target: high-accuracy local model with acceptable latency on Adrian's machine.

### Parakeet Adapter

- Support NVIDIA Parakeet through a local adapter when available.
- The app must health-check Parakeet availability before allowing selection.
- If unavailable, the UI should explain the missing runtime, model, or hardware requirement.

### STT Logging

Each run logs:

- STT engine
- STT model identifier
- Transcription latency
- Transcription status
- Any error message

## Text Polishing

### Endpoint Standard

Phase 1 standardizes on Adrian's local OLMX OpenAI-compatible chat-completions endpoint.

The app calls:

- `GET /health` to check server availability.
- `GET /v1/models` to discover available polishing models.
- `POST /v1/chat/completions` to polish text.
- `/v1/*` requests include the user's API key as a Bearer token.

### Supported Endpoint Presets

- OLMX default: `http://127.0.0.1:8000`
- Optional future presets: Ollama, LM Studio, oMLX / MLX server, or a custom OpenAI-compatible endpoint.

### Model Selection

- User enters the OLMX API key on first launch.
- API key is stored in macOS Keychain, never SQLite or plain config.
- User can refresh the model list from authenticated `/v1/models`.
- User can select any suitable listed chat or instruct model.
- User can manually enter a model name if discovery fails.
- Selected endpoint URL and model persist across restarts.
- The app must not hardcode one required polishing model in Phase 1.

### Prompt Contract

The polishing request should use:

- System message: active persona prompt.
- User message: raw transcript plus concise output instructions.

The model should return only the final polished text. No commentary, alternatives, markdown wrapper, or explanation unless the persona explicitly requires it.

### Recommended Generation Defaults

- Temperature: 0.2-0.4.
- Max output tokens: sized to the transcript length, with a reasonable minimum.
- Streaming: optional for internal progress display, not required for MVP.

## Personas

### Default Personas

Pure Voice ships with five built-in personas:

1. Default
2. Professional
3. Casual Friend
4. Boss
5. Technical

### Persona Requirements

- Personas are selectable from the main UI.
- Active persona persists across restarts.
- System prompts are human-readable and stored locally.
- Built-in personas can be reset to defaults.
- Prompt editing and custom personas are Phase 2.

### Persona Prompt Behavior

All personas must preserve the user's intent and facts. They should remove filler, repetition, false starts, and unnecessary hedging without inventing content.

#### Default

Balanced tone, moderate formality, general-purpose clarity.

#### Professional

Business-appropriate, polished, clear, and respectful. Removes filler and rambling while preserving nuance.

#### Casual Friend

Warm, conversational, and natural. Allows light informality while keeping the message coherent.

#### Boss

Concise, direct, action-oriented, and highly respectful. Prioritizes decisions, blockers, asks, and next steps.

#### Technical

Precise, structured, and domain-aware. Keeps technical details, removes non-technical noise, and avoids oversimplifying.

## Output And Paste

### Paste Behavior

- App captures the active app and focused target context at recording start.
- App attempts to paste only if the target still appears valid at completion.
- If target focus is lost or paste fails, app copies the polished output to clipboard.
- UI shows whether text was pasted or copied.

### Clipboard Handling

- Clipboard fallback is required.
- If possible, preserve and restore the previous clipboard after paste.
- If clipboard restoration is unsafe or unsupported, prioritize not losing the polished text.

## Data Storage

Use local SQLite for MVP data.

### personas

- id primary key
- name text
- system_prompt text
- is_builtin boolean
- is_default boolean
- created_at timestamp
- updated_at timestamp

### transcripts

- id primary key
- raw_text text
- polished_text text
- persona_id foreign key
- stt_engine text
- stt_model text
- llm_endpoint_url text
- llm_model text
- transcription_latency_ms integer
- polishing_latency_ms integer
- end_to_end_latency_ms integer
- paste_status text
- error_message text nullable
- rating integer nullable
- created_at timestamp

### app_config

- key text primary key
- value_json text
- updated_at timestamp

### model_cache

- id primary key
- endpoint_url text
- model_id text
- display_name text nullable
- provider text nullable
- last_seen_at timestamp

## Settings

### MVP Settings

- Active persona.
- STT engine.
- STT model or adapter settings.
- LLM endpoint preset.
- Custom endpoint URL.
- Polishing model.
- Refresh models button.
- Health check status for STT and LLM.
- History retention option.

### Health Checks

The app should clearly report:

- Microphone permission missing.
- Accessibility permission missing.
- LLM endpoint unreachable.
- `/v1/models` unavailable.
- Selected LLM model unavailable.
- Whisper unavailable.
- Parakeet unavailable.
- No speech detected.
- Paste failed and copied instead.

## Privacy And Local-First Requirements

- Phase 1 uses local inference only.
- No telemetry.
- No cloud calls.
- Transcript history stays local.
- Raw audio is deleted after successful transcription by default.
- User can disable transcript history.
- Future API keys must be stored in macOS Keychain.

## Non-Functional Requirements

### Performance

- MVP target: under 15 seconds end-to-end for a typical short message.
- Phase 2 target: under 10 seconds end-to-end.
- App logs transcription, polishing, and total latency for every run.

### Reliability

- No silent failure.
- Failed paste still leaves the final text on clipboard.
- Crashes must not corrupt the local database.
- Recording must stop cleanly even if downstream inference fails.

### Accessibility

- App guides user through microphone and Accessibility permissions.
- Status is visible in menu bar and HUD.
- Keyboard-first workflow is supported.

## Phase 1 Acceptance Criteria

- User can install and launch the app on macOS.
- User can grant microphone and Accessibility permissions.
- User can record from the global hotkey.
- User can select Whisper or Parakeet, with unavailable engines clearly disabled or explained.
- User can configure the OLMX endpoint URL and securely save the OLMX API key.
- App can refresh available models from `/v1/models`.
- User can select or manually enter a polishing model.
- User can select one of five default personas.
- 15-30 seconds of spoken input becomes polished text.
- Output is pasted into TextEdit, Notes, browser text fields, and common compose fields when safe.
- If paste fails, output is copied to clipboard.
- Each run logs raw text, polished text, persona, STT engine, STT model, LLM endpoint, LLM model, latency, paste status, and error state.
- App works offline after local models are installed.

## Phase 2: Admin Panel And Experimentation

### Advanced Settings

Activated through settings or a hidden shortcut.

### Features

- Edit persona prompts.
- Create custom personas.
- Export and import persona sets.
- Manage STT model paths and parameters.
- Manage LLM endpoint parameters.
- Compare polishing models.
- Rate output quality.
- Search and filter transcript history.
- Export experiment logs to CSV.
- Show latency trends by STT engine, LLM model, and persona.

### Benchmarking

Phase 2 should make model selection empirical. The app should help identify the best quality/speed tradeoff for Adrian's voice, hardware, and communication contexts.

## Phase 3: Mobile, Cloud Fallback, And Browser Integration

- iOS companion app.
- iOS keyboard extension.
- Chrome extension.
- Local network routing to the Mac backend.
- Optional cloud fallback when away from the local machine.
- Network status indicator.
- Sync persona definitions across devices.

Cloud fallback must be explicit, configurable, and off by default.

## Phase 4: Translation And Multilingual Mode

- Input language detection.
- Target language selector.
- Translate polished output.
- Optional target-language text-to-speech.
- Reverse conversation mode.
- Bilingual conversation history.

## Phase 5: WatchOS And Restricted Windows Workflows

- watchOS voice capture.
- Route audio to Mac or cloud backend.
- Return polished text to watch where possible.
- Phone-as-microphone workflow for locked-down Windows environments.
- Mac processes speech and returns text or audio without requiring Windows software installation.

## Backlog

- Multi-turn conversation mode.
- Tone intensity slider.
- Custom audience profiles.
- Calendar/contact-based persona selection.
- Quality benchmarking dashboard.
- Fine-tuning pipeline from corrected outputs.
- Streaming real-time polishing.
- Keyboard shortcut customization.
- Multiple hotkey profiles.

## Implementation Notes

Build Phase 1 first. The architecture should make STT engines and LLM endpoints pluggable, but the user experience should stay simple: choose persona, choose STT engine, choose local LLM model, speak, paste.

The OpenAI-compatible endpoint is the right abstraction boundary for polishing. Phase 1 defaults to OLMX at `http://127.0.0.1:8000`; other local or private endpoints can be added later without rewriting the persona-polishing pipeline.
