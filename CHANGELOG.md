# Changelog

## v1.1.7 - 2026-08-01

- Added an on-device live transcript preview and expanded recording controls for Stop and Cancel.
- Added the Speech Recognition usage description and onboarding permission flow required by the live preview.
- Prevented Push to Talk from starting after its shortcut has already been released.
- Prevented the status panel from reclaiming focus after output delivery.
- Ensured temporary recordings are deleted after failed as well as successful processing attempts.
- Corrected the Parakeet model download estimate and made live preview follow the user's current locale.
- Strengthened the Brief persona and made its live behavior test use the same shared guardrail as production.

## v1.1.6 - 2026-05-19

- Strengthened polishing instructions so question-like dictation is edited as copy, not answered as a chat prompt.
- Added explicit guardrails to keep questions as questions and prevent the model from role-playing or referring to itself.
- Added regression coverage for prompts such as "what model are you."

## v1.1.5 - 2026-05-19

- Fixed Push to Talk restarting after Pure Voice pasted polished text.
- Restricted modifier-only shortcut activation to real modifier-change events so synthetic Command-V paste events cannot trigger a new recording.
- Added regression coverage for modifier-only hotkeys versus key chord hotkeys.

## v1.1.4 - 2026-05-19

- Fixed Push to Talk and Push to Record start shortcuts when existing local settings still had legacy Command-Option bindings.
- Persisted migrated hotkey defaults so Right Command remains the Start shortcut after restart.
- Treated silent recordings as a graceful no-output stop instead of a Needs Attention error.
- Added regression coverage for hotkey migration, modifier matching, and empty transcript handling.

## v1.1.0 - 2026-05-19

- Added first-launch onboarding with permission checks, guided speech-to-text engine choice, and a shared install screen.
- Added on-demand speech-to-text install from Settings with inline confirmation, cancel-to-Whisper fallback, calmer install status, sanitized user-facing errors, and technical details disclosure.
- Added a more reactive flowing waveform that responds to live recording levels and uses a calmer processing animation.
- Added configurable system-wide hotkeys with capture mode, side-specific modifier detection, persisted bindings, mouse-button support, and conflict warnings.
- Added Push to Record and Push to Talk recording modes, with Push to Talk tied to a long press of the Start shortcut.
- Added opt-in Parakeet speech-to-text support with user-controlled install prompts, install progress messaging, and temporary Whisper fallback when Parakeet is unavailable.
- Replaced the default persona set with Polish, Brief, Rewrite, and Caveman. Polish remains the default.
- Added editable persona prompts with auto-save, customized indicators, per-persona restore controls, and a locked shared guardrail appended at runtime.
- Added a Persona Preview tab that runs saved personas from a Preview button, shows per-persona loading/results/errors, marks stale outputs, and supports restore-default from preview.
- Fixed custom persona prompts so Preview and live polish treat the saved persona directive as authoritative while scoping transcript-injection protection to transcript content.
- Fixed Settings window ordering, minimize, zoom, and Preview dictation targeting.
