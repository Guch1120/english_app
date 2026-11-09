# Background audio playback

Already-started system TTS, neural TTS, and saved-recording playback may continue after the app backgrounds or the screen locks. The app does not start or resume playback without a user action. Background transitions cancel active model generation, transcription, enhancement, and downloads; an active microphone recording is closed and its file is retained. Audio interruptions and loss of the active output route stop playback.

The iOS target declares the audio background mode. GitHub macOS CI builds and launches the Simulator app, but does not establish lock-screen behavior or system audio-session policy on iPhone. Verify each case on an iPhone:

1. Start system TTS, neural TTS, and saved-recording playback separately. For each, switch apps and lock the screen; confirm the current item continues.
2. While playback is active, trigger a phone call or another audio interruption, then disconnect the active output route. Confirm playback stops in both cases.
3. Start model generation, transcription, enhancement, and a model download separately, then background the app. Confirm each operation is cancelled and that any source recording remains available.
4. Start microphone recording and background the app. Confirm recording closes, the file remains available, and returning to the app does not resume capture or playback automatically.

Results depend on iOS and the active audio route. Record the iOS version and route for any failure; Simulator results do not substitute for these checks.
