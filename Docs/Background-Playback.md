# Background audio playback

Already-started system TTS, neural TTS, and saved-recording playback may continue after the app backgrounds or the screen locks. The app does not start or resume playback without a user action. Background transitions cancel active model generation, transcription, enhancement, and downloads; an active microphone recording is closed and its file is retained. Audio interruptions and loss of the active output route stop playback.

The iOS target declares the audio background mode. GitHub macOS CI builds and launches the Simulator app, but does not establish lock-screen behavior or system audio-session policy on iPhone. Verify system and neural TTS plus saved-recording playback across app switching and screen lock, then verify that phone/audio interruptions and route changes stop playback and that returning to the app does not resume it automatically. Results depend on iOS and the active audio route.
