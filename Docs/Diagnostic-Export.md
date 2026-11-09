# Diagnostic export

Settings can prepare a JSON report from the bounded local event log. Sharing requires an explicit tap and selection in the system share sheet; preparing the report does not send it. The export contains only fixed subsystem, action, model, outcome and thermal enums and numeric durations and resource measurements. It omits event IDs, timestamps, app/user identifiers, prompts, lesson text, transcripts, recordings and error descriptions. Event order and measurements can still reveal usage patterns, so users should choose recipients carefully.

The report is an in-memory snapshot and is discarded when Settings closes or the diagnostic log is cleared. It does not create an export file. Format version 1 allows future changes to be interpreted explicitly. A fresh snapshot is produced when the user taps the preparation button again.

Docker tests verify the schema and omission of identifiers and timestamps, as well as the existing bounded-log behavior. The iOS share sheet and actual sharing need GitHub macOS CI and physical-device verification.
