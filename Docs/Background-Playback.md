# Background audio playback

Already-started system TTS, neural TTS, and saved-recording playback may continue after the app backgrounds or the screen locks. The app does not start or resume playback without a user action. Background transitions cancel active model generation, transcription, enhancement, and downloads; an active microphone recording is closed and its file is retained. Audio interruptions and loss of the active output route stop playback.

The iOS target declares the audio background mode. GitHub macOS CI builds and launches the Simulator app, but does not establish lock-screen behavior or system audio-session policy on iPhone. Verify each case on an iPhone:

1. Start system TTS, neural TTS, and saved-recording playback separately. For each, switch apps and lock the screen; confirm the current item continues.
2. While playback is active, trigger a phone call or another audio interruption, then disconnect the active output route. Confirm playback stops in both cases.
3. Start model generation, transcription, enhancement, and a model download separately, then background the app. Confirm each operation is cancelled and that any source recording remains available.
4. Start microphone recording and background the app. Confirm recording closes, the file remains available, and returning to the app does not resume capture or playback automatically.

Results depend on iOS and the active audio route. Record the iOS version and route for any failure; Simulator results do not substitute for these checks.

## Physical-device evidence

On 2026-11-11, the user confirmed repeat-enabled Kokoro neural TTS continued audibly after physically locking an iPhone 16 / iOS 26.4.2 running TestFlight 208.1 and after returning to the Home screen. The user also confirmed Apple US English lesson TTS continued after locking the same device, and a saved 3.9-second recording continued after locking. WDA later showed the saved recording idle, with Kokoro selected and repeat OFF. No transcript was accessed or saved recording changed or deleted. These cover one Kokoro Home and lock case, one Apple TTS lock case, and one saved-recording lock case. Saved-recording Home behavior, Apple TTS Home behavior, interruptions, route loss, and long-duration behavior remain unverified.

Further checks on the same device/build confirmed repeat-enabled Apple US English lesson TTS continued after returning Home, with repeat audibly heard (cycle count not measured), and the saved 3.9-second recording continued after returning Home. During active playback on Bluetooth headphones, disconnecting Bluetooth stopped app playback and did not route audio to the phone speaker. The user accepted this route-loss behavior. Playing audio from another app stopped Kokoro playback, which did not resume when the other app's audio ended. The check covered that interruption only; calls and other interruption types were not tested. In a retention OFF relaunch check, the saved recording was removed as configured; retention was restored ON afterward. The test intentionally replaced the prior saved recording, and no transcript was accessed.
