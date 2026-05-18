# Changelog

## Unreleased

- Added `PasteDeliveryStatus` for honest paste delivery outcomes, including confirmed AX insertion, confirmed or unconfirmed paste events, copied-only fallback, target activation failures, missing focus targets, Accessibility denial, and targets that did not accept paste.
- Added the `transcripts.paste_fallback_reason` SQLite column for structured per-attempt diagnostics. Existing `paste_status` rows are preserved; new rows store the precise `PasteDeliveryStatus` raw value in the existing text column.
