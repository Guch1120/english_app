# iPhone 16 build 145.1 acceptance observations

2026-11-09 JST: TestFlight workflow [42628402118](https://github.com/Guch1120/english_app/actions/runs/42628402118) completed successfully and archived/uploaded 0.1.0 (145.1). The user updated the iPhone. USB confirmed `iPhone17,3`, iOS 26.4.2 and installed build 145.1; upload and installation are separate observations.

After the user accepted the device's automation prompt, the existing WDA runner reported ready. An app session displayed the learning home and previously saved lessons. Settings showed 145.1. The library opened, category selection changed from all to word and was restored, and its include-hidden switch changed from 0 to 1 and back to 0 by interacting with the switch control. An accessibility-element tap on the switch label did not change it; a coordinate gesture on the control succeeded. A sample lesson opened from the library, the action menu displayed edit/report/hide, and the edit sheet opened and was cancelled without saving. The WDA runner was stopped afterwards.

These observations establish launch, navigation and the specific control states only. They do not establish saving an edit, quiz answering, persistence after restart, audio output, recognition, offline use, or inference performance. No screenshots, user learning contents, recordings or transcripts are included in this document.
